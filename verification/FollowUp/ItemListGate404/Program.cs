using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using Emby.YouTubePlugin;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Controller.Security;
using MediaBrowser.Model.Querying;

// Calls the production prefix and coverage class directly. Authorization,
// authentication storage, library and DTO registration are adapters; no
// server, Harmony patch, native token validation or HTTP status is involved.
var assembly = typeof(Plugin).Assembly;
var gate = assembly.GetType("Emby.YouTubePlugin.PersonalYouTubeItemListGate", true)!;
var flags = BindingFlags.Static | BindingFlags.NonPublic;
var subjects = gate.GetField("_subjectDtos", flags)!;
var authorization = gate.GetField("_authorization", flags)!;
var authentications = gate.GetField("_authentications", flags)!;
var library = gate.GetField("_library", flags)!;
var access = gate.GetField("_access", flags)!;
var previousAccess = access.GetValue(null);
var accessDirectory = Directory.CreateTempSubdirectory("item-list-gate-probe-").FullName;
var current = gate.GetField("Current", flags)!;
var previousSubjects = subjects.GetValue(null);
var previousAuthorization = authorization.GetValue(null);
var previousAuthentications = authentications.GetValue(null);
var previousLibrary = library.GetValue(null);
var observations = new List<object>();
void Check(string name, bool reproduced)
{
    observations.Add(new { Name = name, Reproduced = reproduced });
    if (!reproduced) throw new InvalidOperationException(name);
}
async Task<bool> GenericNotFound(object? task)
{
    try { await (Task<object>)task!; return false; }
    catch (Exception error) when (error.GetType().Name == "ResourceNotFoundException") { return error.Message == "Items not found."; }
}
(bool Proceed, object? State, object? Result) Run()
{
    object?[] arguments = { new ProbeDto(), null, null, null };
    var proceed = (bool)gate.GetMethod("BeforeService", flags)!.Invoke(null, arguments)!;
    var asyncLocal = current.GetValue(null)!;
    asyncLocal.GetType().GetProperty("Value")!.SetValue(asyncLocal, null);
    return (proceed, arguments[3], arguments[2]);
}
try
{
    subjects.SetValue(null, new Dictionary<Type, PropertyInfo?> { [typeof(ProbeDto)] = null });
    var adapter = DispatchProxy.Create<IAuthorizationContext, AuthorizationAdapter>();
    authorization.SetValue(null, adapter);
    var libraryAdapter = DispatchProxy.Create<ILibraryManager, LibraryAdapter>();
    library.SetValue(null, libraryAdapter);
    // Production resolver over an empty private data directory: no ledger,
    // journal or profile exists, so the empty inventory has nothing to deny.
    access.SetValue(null, Activator.CreateInstance(assembly.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeAccess", true)!,
        BindingFlags.Instance | BindingFlags.NonPublic, null, new object[] { accessDirectory, libraryAdapter }, null));

    // Original incident: null User without any verifiable key.
    var denied = Run();
    Check("Null-user authorization without a verified key suppresses the native service", !denied.Proceed);
    Check("Denial happens before a request scope is created", denied.State == null);
    Check("Null-user result is the reported generic not-found exception", await GenericNotFound(denied.Result));
    Check("Authorization adapter returned a non-null info object with null User", ((AuthorizationAdapter)adapter).ReturnedNullUser);

    var store = DispatchProxy.Create<IAuthenticationRepository, AuthenticationAdapter>();
    authentications.SetValue(null, store);
    AuthenticationAdapter.Records = new[] { new AuthenticationInfo { AccessToken = "server-key", UserId = 0, IsActive = true, AppName = "probe" } };

    AuthorizationAdapter.Token = "";
    Check("Empty token with null User is still rejected", !Run().Proceed);
    AuthorizationAdapter.Token = "unknown-key";
    Check("Unknown token with null User is still rejected", !Run().Proceed);
    AuthorizationAdapter.Token = "user-token";
    AuthenticationAdapter.Records = new[] { new AuthenticationInfo { AccessToken = "user-token", UserId = 7, IsActive = true } };
    Check("Account token resolving to null User is not treated as a server key", !Run().Proceed);
    AuthenticationAdapter.Records = new[] { new AuthenticationInfo { AccessToken = "server-key", UserId = 0, IsActive = false } };
    AuthorizationAdapter.Token = "server-key";
    Check("Inactive server key is rejected", !Run().Proceed);

    AuthenticationAdapter.Records = new[] { new AuthenticationInfo { AccessToken = "server-key", UserId = 0, IsActive = true } };
    var allowed = Run();
    Check("Verified active server key reaches the native service", allowed.Proceed);
    var scope = allowed.State?.GetType().GetProperty("Created")!.GetValue(allowed.State);
    var scopeType = scope?.GetType();
    Check("Server-key scope carries no account", scope != null && scopeType!.GetField("User", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(scope) == null);
    Check("Server-key scope is re-verifiable by its token", (string?)scopeType!.GetField("ServiceToken", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(scope) == "server-key");
    var stillAuthorized = gate.GetMethod("StillAuthorized", flags)!;
    Check("Server-key result remains authorized while the key is active", (bool)stillAuthorized.Invoke(null, new[] { scope })!);
    AuthenticationAdapter.Records = Array.Empty<AuthenticationInfo>();
    Check("Revoked server key fails the result/writer recheck", !(bool)stillAuthorized.Invoke(null, new[] { scope })!);

    var coverageType = assembly.GetType("Emby.YouTubePlugin.PersonalYouTubeQueryCoverage", true)!;
    var instanceFlags = BindingFlags.Instance | BindingFlags.NonPublic;
    var coverage = Activator.CreateInstance(coverageType, instanceFlags, null, new object[] { Array.Empty<long>() }, null)!;
    var covers = coverageType.GetMethod("Covers", instanceFlags)!;
    Check("No source record rejects even an empty denial set", !(bool)covers.Invoke(coverage, new object[] { Array.Empty<long>() })!);
    coverageType.GetMethod("Record", instanceFlags)!.Invoke(coverage, new object[] { Array.Empty<long>() });
    Check("Recorded empty source accepts an empty denial set", (bool)covers.Invoke(coverage, new object[] { Array.Empty<long>() })!);
    Check("New unexcluded denial rejects that same source", !(bool)covers.Invoke(coverage, new object[] { new long[] { 42 } })!);
}
finally
{
    subjects.SetValue(null, previousSubjects);
    authorization.SetValue(null, previousAuthorization);
    authentications.SetValue(null, previousAuthentications);
    library.SetValue(null, previousLibrary);
    access.SetValue(null, previousAccess);
    Directory.Delete(accessDirectory, true);
}
Console.WriteLine(JsonSerializer.Serialize(new {
    ProductionDLLSHA256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(assembly.Location))),
    Observations = observations,
    Limit = "Production component check with adapters and an empty library; no native HTTP, real API-key store, personal inventory, Linux runtime or latency measurement. Not a product acceptance result."
}, new JsonSerializerOptions { WriteIndented = true }));

public sealed class ProbeDto { }
public class AuthorizationAdapter : DispatchProxy
{
    public static string? Token;
    public bool ReturnedNullUser { get; private set; }
    protected override object? Invoke(MethodInfo? method, object?[]? args)
    {
        if (method?.Name != "GetAuthorizationInfo") throw new NotSupportedException();
        var info = (AuthorizationInfo)Activator.CreateInstance(method.ReturnType)!;
        info.Token = Token;
        ReturnedNullUser = info.User == null;
        return info;
    }
}
public class AuthenticationAdapter : DispatchProxy
{
    public static AuthenticationInfo[] Records = Array.Empty<AuthenticationInfo>();
    protected override object? Invoke(MethodInfo? method, object?[]? args)
    {
        if (method?.Name != "Get") throw new NotSupportedException();
        var query = (AuthenticationInfoQuery)args![0]!;
        // Like the native store, filter by the requested token/user/active state.
        var items = Records.Where(record => record.AccessToken == query.AccessToken
            && (query.HasUser != false || record.UserId == 0)
            && (query.IsActive == null || record.IsActive == query.IsActive)).ToArray();
        return new QueryResult<AuthenticationInfo> { Items = items, TotalRecordCount = items.Length };
    }
}
public class LibraryAdapter : DispatchProxy
{
    protected override object? Invoke(MethodInfo? method, object?[]? args)
        => method?.Name switch {
            "GetItemList" => Array.Empty<BaseItem>(),
            "GetVirtualFolders" => new List<MediaBrowser.Model.Entities.VirtualFolderInfo>(),
            _ => throw new NotSupportedException()
        };
}
