using MediaBrowser.Common.Configuration;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;

namespace Emby.YouTubePlugin;

[Route("/YouTubePlugin/MyProfile", "GET")]
[Authenticated]
public sealed class GetPersonalYouTubeProfile : IReturn<PersonalYouTubeProfileView> { }

[Route("/YouTubePlugin/MyJob", "GET")]
[Authenticated]
public sealed class GetPersonalYouTubeJob : IReturn<PersonalYouTubeJobView> { }

[Route("/YouTubePlugin/PersonalServerStatus", "GET")]
[Authenticated]
public sealed class GetPersonalYouTubeServerStatus { }

[Route("/YouTubePlugin/MyProfile", "POST")]
[Authenticated]
public sealed class SavePersonalYouTubeProfile : IRequiresRequestStream, IReturn<PersonalYouTubeProfileView>
{
    public Stream RequestStream { get; set; } = null!;
}

[Route("/YouTubePlugin/MyProfile/Delete", "POST")]
[Authenticated]
public sealed class DeletePersonalYouTubeProfile : IRequiresRequestStream, IReturn<PersonalYouTubeProfileView>
{
    public Stream RequestStream { get; set; } = null!;
}

public sealed class PersonalYouTubeProfileView
{
    public Guid OwnerUserId { get; set; }
    public Guid CollectionId { get; set; }
    public Guid GenerationId { get; set; }
    public long Revision { get; set; }
    public long KeyRevision { get; set; }
    public string State { get; set; } = "Absent";
    public string[] Channels { get; set; } = Array.Empty<string>();
    public bool HasApiKey { get; set; }
}

public sealed class PersonalYouTubeService : IService, IRequiresRequest
{
    private readonly IAuthorizationContext _authorization;
    private readonly PersonalYouTubeStore _store;
    private readonly IHttpResultFactory _results;
    public IRequest Request { get; set; } = null!;
    public PersonalYouTubeService(IAuthorizationContext authorization, IApplicationPaths paths, IHttpResultFactory results)
    {
        _authorization = authorization;
        _store = new(Path.Combine(paths.DataPath, "youtube-personal"));
        _results = results;
    }
    private sealed class ProfileFailure : Exception
    {
        internal HttpStatusCode Status { get; }
        internal string Code { get; }
        internal ProfileFailure(HttpStatusCode status, string code, string message) : base(message)
        { Status = status; Code = code; }
    }
    private static Exception Error(HttpStatusCode status, string code, string message) => new ProfileFailure(status, code, message);
    private async Task<object> Respond(Func<Task<PersonalYouTubeProfileView>> action)
    {
        object payload; var status = HttpStatusCode.OK;
        try { payload = await action().ConfigureAwait(false); }
        catch (ProfileFailure failure)
        { status = failure.Status; payload = new { ErrorCode = failure.Code, Message = failure.Message }; }
        var result = _results.GetResult(Request, JsonSerializer.SerializeToUtf8Bytes(payload), "application/json",
            new Dictionary<string, string> { ["Cache-Control"] = "no-store, private" });
        Request.Response.StatusCode = (int)status;
        return result;
    }
    private Guid Owner()
    {
        var user = _authorization.GetAuthorizationInfo(Request).User;
        if (user == null || user.Policy.IsDisabled || user.Id == Guid.Empty)
            throw Error(HttpStatusCode.Unauthorized, "AuthenticationRequired", "Authentication required.");
        return user.Id;
    }
    private static PersonalYouTubeProfileView View(PersonalYouTubeStore.View value) => new()
    {
        OwnerUserId = value.OwnerUserId, CollectionId = value.CollectionId, GenerationId = value.GenerationId,
        Revision = value.Revision, KeyRevision = value.KeyRevision, State = value.State,
        Channels = value.Channels, HasApiKey = value.HasApiKey
    };
    private static PersonalYouTubeProfileView Execute(Func<PersonalYouTubeStore.View> action)
    {
        try { return View(action()); }
        catch (ArgumentException) { throw Error(HttpStatusCode.BadRequest, "InvalidProfile", "Invalid profile update."); }
        catch (InvalidOperationException) { throw Error(HttpStatusCode.Conflict, "ProfileConflict", "Profile revision changed or profile unavailable."); }
        catch (Exception error) when (error is IOException or InvalidDataException or CryptographicException or UnauthorizedAccessException)
        { throw Error(HttpStatusCode.ServiceUnavailable, "ProfileUnavailable", "Personal profile storage unavailable."); }
    }
    public Task<object> Get(GetPersonalYouTubeProfile request) => Respond(() => {
        var owner = Owner();
        return Task.FromResult(Execute(() => _store.Read(owner)));
    });
    public object Get(GetPersonalYouTubeJob request)
    {
        var owner = Owner();
        PersonalYouTubeJobView view;
        try { view = PersonalYouTubeJobs.Current?.Read(owner) ?? new() { OwnerUserId = owner, State = "Disabled" }; }
        catch(Exception error) when(error is IOException or InvalidDataException or UnauthorizedAccessException)
        { view = new() { OwnerUserId = owner, State = "Failed", ErrorCode = "StatusUnavailable" }; }
        return _results.GetResult(Request, JsonSerializer.SerializeToUtf8Bytes(view), "application/json",
            new Dictionary<string, string> { ["Cache-Control"] = "no-store, private" });
    }
    public object Get(GetPersonalYouTubeServerStatus request)
    {
        var user = _authorization.GetAuthorizationInfo(Request).User;
        if(user == null || user.Policy.IsDisabled || !user.Policy.IsAdministrator)
        {
            Request.Response.StatusCode = (int)HttpStatusCode.Forbidden;
            return _results.GetResult(Request, JsonSerializer.SerializeToUtf8Bytes(new { ErrorCode = "AdministratorRequired" }), "application/json",
                new Dictionary<string, string> { ["Cache-Control"] = "no-store, private" });
        }
        var options = Plugin.Instance?.Options;
        return _results.GetResult(Request, JsonSerializer.SerializeToUtf8Bytes(new {
            AlphaEnabled = options?.PersonalYouTubeAlphaEnabled == true,
            WorkerRunning = PersonalYouTubeJobs.Current != null,
            Creation = PersonalYouTubeNativeCreationHook.Snapshot(),
            References = PersonalYouTubeServiceReferenceGate.Snapshot(),
            Lists = PersonalYouTubeItemListGate.Snapshot(),
            MediaToolsAvailable = options != null && new[] { options.PersonalYouTubeDownloaderPath, options.PersonalYouTubeFfmpegPath, options.PersonalYouTubeNodePath }
                .All(path => Path.IsPathRooted(path) && File.Exists(path))
        }), "application/json", new Dictionary<string, string> { ["Cache-Control"] = "no-store, private" });
    }
    private sealed class Input
    {
        public long? ExpectedRevision { get; set; }
        public string[]? Channels { get; set; }
        public string? ApiKey { get; set; }
        public bool ClearApiKey { get; set; }
    }
    private static async Task<Input> ReadInput(Stream stream, bool deletion)
    {
        if (stream == null) throw Error(HttpStatusCode.BadRequest, "InvalidProfile", "Profile body required.");
        using var buffer = new MemoryStream();
        var bytes = new byte[4096];
        while (true)
        {
            var count = await stream.ReadAsync(bytes.AsMemory()).ConfigureAwait(false);
            if (count == 0) break;
            if (buffer.Length + count > 32768)
                throw Error(HttpStatusCode.RequestEntityTooLarge, "ProfileTooLarge", "Profile body too large.");
            buffer.Write(bytes, 0, count);
        }
        try
        {
            using var doc = JsonDocument.Parse(buffer.ToArray());
            if (doc.RootElement.ValueKind != JsonValueKind.Object) throw new JsonException();
            var allowed = deletion ? new[] { "ExpectedRevision" } : new[] { "ExpectedRevision", "Channels", "ApiKey", "ClearApiKey" };
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in doc.RootElement.EnumerateObject())
                if (!allowed.Contains(property.Name, StringComparer.OrdinalIgnoreCase) || !seen.Add(property.Name))
                    throw new JsonException();
            var input = JsonSerializer.Deserialize<Input>(doc.RootElement.GetRawText(), new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (input?.ExpectedRevision == null || input.ExpectedRevision < 0 || !deletion && input.Channels == null)
                throw new JsonException();
            return input;
        }
        catch (JsonException) { throw Error(HttpStatusCode.BadRequest, "InvalidProfile", "Invalid profile body."); }
    }
    public Task<object> Post(SavePersonalYouTubeProfile request) => Respond(async () => {
        var owner = Owner();
        var input = await ReadInput(request.RequestStream, false).ConfigureAwait(false);
        var view = Execute(() => PersonalYouTubeJobs.Current == null
            ? _store.Save(owner, input.ExpectedRevision!.Value, input.Channels!, input.ApiKey, input.ClearApiKey)
            : _store.SaveForRefresh(owner, input.ExpectedRevision!.Value, input.Channels!, input.ApiKey, input.ClearApiKey));
        PersonalYouTubeJobs.Current?.Notify(owner);
        return view;
    });
    public Task<object> Post(DeletePersonalYouTubeProfile request) => Respond(async () => {
        var owner = Owner();
        var input = await ReadInput(request.RequestStream, true).ConfigureAwait(false);
        var view = Execute(() => _store.Delete(owner, input.ExpectedRevision!.Value));
        PersonalYouTubeJobs.Current?.Notify(owner);
        return view;
    });
}
