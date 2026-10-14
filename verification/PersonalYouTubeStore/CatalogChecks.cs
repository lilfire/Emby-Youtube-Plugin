using Emby.YouTubePlugin;
using System.Net;
using System.Text.Json;

internal static class CatalogChecks
{
    internal static async Task Run(string directory, Action<string, bool> check)
    {
        var store = new PersonalYouTubeStore(directory);
        var a = Guid.NewGuid(); var b = Guid.NewGuid();
        var ca = "UC" + new string('a', 22); var cb = "UC" + new string('b', 22);
        store.Save(a, 0, new[] { ca }, "synthetic-a", false);
        store.Save(b, 0, new[] { cb }, "synthetic-b", false);
        var requests = new List<(string Path, string Key, string Channel)>();
        var mode = "ok";
        using var client = new HttpClient(new Handler(async request =>
        {
            var uri = request.RequestUri!;
            var args = uri.Query.TrimStart('?').Split('&').Select(value => value.Split('=', 2))
                .ToDictionary(value => value[0], value => Uri.UnescapeDataString(value[1]));
            var channel = args.TryGetValue("id", out var id) ? id : "UC" + args["playlistId"][2..];
            requests.Add((uri.AbsolutePath, args["key"], channel));
            if (mode == "http-error") throw new HttpRequestException(uri.ToString());
            if (mode is "quota" or "key-rejected") return new HttpResponseMessage(HttpStatusCode.Forbidden) {
                Content = new StringContent(JsonSerializer.Serialize(new { error = new { message = "request with synthetic-a credential", errors = new[] { new { reason = mode == "quota" ? "quotaExceeded" : "keyInvalid" } } } }))
            };
            if(mode == "modern-key-rejected") return new HttpResponseMessage(HttpStatusCode.BadRequest) {
                Content = new StringContent(JsonSerializer.Serialize(new { error = new { status = "INVALID_ARGUMENT", errors = new[] { new { reason = "badRequest" } }, details = new[] { new { reason = "API_KEY_INVALID" } } } }))
            };
            if (mode == "delete") { var view = store.Read(a); store.Delete(a, view.Revision); }
            await Task.Yield();
            object body = uri.AbsolutePath.EndsWith("/channels")
                ? new { items = new[] { new { id = channel, contentDetails = new { relatedPlaylists = new { uploads = "UU" + channel[2..] } } } } }
                : new { items = new[] { new { contentDetails = new { videoId = "abcdefghijk" }, snippet = new { channelId = channel, title = args["key"] == "synthetic-a" ? "A video" : "B video", description = "fixture" } } }, nextPageToken = "page+two" };
            if (mode == "rotate-on-last-page" && uri.AbsolutePath.EndsWith("/playlistItems"))
            { var view = store.Read(b); store.Save(b, view.Revision, new[] { cb }, "rotated-b", false); }
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(body)) };
        }));
        var catalog = new PersonalYouTubeCatalog(store, client);
        var snapshot = store.Prepare(a);
        var ap = await catalog.ReadPageAsync(snapshot, ca, null, CancellationToken.None);
        var bp = await catalog.ReadPageAsync(store.Prepare(b), cb, null, CancellationToken.None);
        check("Catalog uses each owner's stored key and channel", requests.Count == 4
            && requests.Take(2).All(r => r.Key == "synthetic-a" && r.Channel == ca)
            && requests.Skip(2).All(r => r.Key == "synthetic-b" && r.Channel == cb));
        check("Catalog retains publisher ownership and paging without returning keys", ap.OwnerUserId == a
            && bp.OwnerUserId == b && ap.CollectionId != bp.CollectionId && ap.NextPageToken == "page+two"
            && ap.Videos.Single().Title == "A video" && bp.Videos.Single().Title == "B video"
            && !JsonSerializer.Serialize(ap).Contains("synthetic-a"));
        var before = requests.Count;
        await Reject<InvalidOperationException>(() => catalog.ReadPageAsync(snapshot, cb, null, CancellationToken.None));
        await Reject<InvalidOperationException>(() => catalog.ReadPageAsync(snapshot with { ApiKey = "forged" }, ca, null, CancellationToken.None));
        check("Foreign channel and substituted key rejected before HTTP", requests.Count == before);
        mode = "http-error";
        var failure = await Reject<InvalidDataException>(() => catalog.ReadPageAsync(snapshot, ca, null, CancellationToken.None));
        check("Transport failure does not disclose request URL or key", !failure.ToString().Contains("synthetic-a")
            && !failure.ToString().Contains("googleapis"));
        mode = "quota";
        var quota = await Reject<PersonalYouTubeJobFailure>(() => catalog.ReadPageAsync(snapshot, ca, null, CancellationToken.None));
        check("Quota failure reports a safe reason with no fallback catalog", quota.Code == "YouTubeQuotaExceeded" && !quota.ToString().Contains("synthetic-a"));
        mode = "key-rejected";
        var rejected = await Reject<PersonalYouTubeJobFailure>(() => catalog.ReadPageAsync(snapshot, ca, null, CancellationToken.None));
        check("Rejected personal key has an actionable sanitized code", rejected.Code == "YouTubeKeyRejected" && !rejected.ToString().Contains("synthetic-a"));
        mode = "modern-key-rejected";
        var modern = await Reject<PersonalYouTubeJobFailure>(() => catalog.ReadPageAsync(snapshot, ca, null, CancellationToken.None));
        check("Actual Google ErrorInfo invalid-key shape remains actionable", modern.Code == "YouTubeKeyRejected");
        mode = "delete"; before = requests.Count;
        await Reject<InvalidOperationException>(() => catalog.ReadPageAsync(snapshot, ca, null, CancellationToken.None));
        check("Profile deletion during retrieval stops before the next request", requests.Count == before + 1);
        mode = "ok";
        var reread = await catalog.ReadPageAsync(store.Prepare(b), cb, null, CancellationToken.None);
        check("Deleting A leaves B catalog usable", reread.OwnerUserId == b && reread.Videos.Single().Title == "B video");
        mode = "rotate-on-last-page";
        await Reject<InvalidOperationException>(() => catalog.ReadPageAsync(store.Prepare(b), cb, null, CancellationToken.None));
        check("Key rotation during the final response discards the completed page", true);
        mode = "ok";
        var noKey = store.Read(b);
        store.Save(b, noKey.Revision, new[] { cb }, null, true);
        before = requests.Count;
        await Reject<InvalidOperationException>(() => catalog.ReadPageAsync(store.Prepare(b), cb, null, CancellationToken.None));
        check("Missing personal key never falls back to global configuration", requests.Count == before);
    }
    private static async Task<T> Reject<T>(Func<Task<PersonalYouTubeCatalog.Page>> action) where T : Exception
    { try { await action(); } catch (T error) { return error; } throw new Exception("Expected " + typeof(T).Name); }
    private sealed class Handler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, Task<HttpResponseMessage>> _send;
        internal Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) => _send = send;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => _send(request);
    }
}
