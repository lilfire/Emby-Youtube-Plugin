using Emby.YouTubePlugin;
using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

if(args.Length > 0 && args[0] == "child")
{
    var childStore = new PersonalYouTubeStore(args[1]);
    var owner = Guid.Parse(args[2]);
    var view = childStore.Read(owner);
    childStore.Save(owner, view.Revision, view.Channels, "synthetic-rotated-child", false);
    return;
}
var artifact = Path.GetFullPath("verification/FollowUp/F/bin");
Directory.CreateDirectory(artifact);
var root = Path.Combine(artifact, "store-" + Guid.NewGuid().ToString("N"));
var rows = new List<object>();
bool complete = false;
void Check(string name, bool pass) { rows.Add(new { Label = name, Passed = pass }); if(!pass) throw new Exception(name); }
void Reject(string name, Action action)
{
    try { action(); } catch(Exception ex) when(ex is InvalidDataException or CryptographicException or InvalidOperationException)
    { Check(name, true); return; }
    Check(name, false);
}
try
{
    var store = new PersonalYouTubeStore(root);
    var a = Guid.NewGuid(); var b = Guid.NewGuid();
    var channel = "UC" + new string('a', 22);
    store.Save(a, 0, new[] { channel }, "synthetic-shared", false);
    store.Save(b, 0, new[] { channel }, "synthetic-shared", false);
    var aPath = Path.Combine(root, a.ToString("N") + ".json");
    var bPath = Path.Combine(root, b.ToString("N") + ".json");
    var keyPath = Path.Combine(root, "encryption.key");
    var aOriginal = File.ReadAllText(aPath); var bOriginal = File.ReadAllText(bPath); var key = File.ReadAllBytes(keyPath);
    if(!OperatingSystem.IsWindows())
    {
        rows.Add(new { Label = "Production-created Unix permissions", DirectoryMode = File.GetUnixFileMode(root).ToString(), KeyMode = File.GetUnixFileMode(keyPath).ToString(), ProfileMode = File.GetUnixFileMode(aPath).ToString(), Classification = "Measured permissions; no hardening assertion" });
    }
    Check("Identical secret has randomized ciphertext and distinct collection", JsonNode.Parse(aOriginal)!["Current"]!["EncryptedApiKey"]!.ToString() != JsonNode.Parse(bOriginal)!["Current"]!["EncryptedApiKey"]!.ToString() && store.Read(a).CollectionId != store.Read(b).CollectionId);
    var corrupt = JsonNode.Parse(aOriginal)!;
    var encrypted = Convert.FromBase64String(corrupt["Current"]!["EncryptedApiKey"]!.GetValue<string>());
    encrypted[^1] ^= 1; corrupt["Current"]!["EncryptedApiKey"] = Convert.ToBase64String(encrypted);
    File.WriteAllText(aPath, corrupt.ToJsonString());
    Reject("Corrupt ciphertext fails authenticated decryption", () => store.Prepare(a));
    Check("Corrupt A does not affect B", store.Prepare(b).ApiKey == "synthetic-shared" && File.ReadAllText(bPath) == bOriginal);
    File.WriteAllText(aPath, aOriginal);
    foreach(var replacement in new[] { Array.Empty<byte>(), RandomNumberGenerator.GetBytes(32) })
    {
        File.WriteAllBytes(keyPath, replacement);
        Reject("Invalid or replaced server key denies prepared secret", () => store.Prepare(a));
        Check("Key failure preserves both profile files", File.ReadAllText(aPath) == aOriginal && File.ReadAllText(bPath) == bOriginal);
    }
    File.Delete(keyPath);
    Reject("Missing server key denies secret retrieval", () => store.Prepare(a));
    Reject("Missing key cannot silently regenerate for existing profiles", () => store.Save(a, store.Read(a).Revision, new[] { channel }, "synthetic-new", false));
    Check("Missing key leaves files unchanged and remains missing", !File.Exists(keyPath) && File.ReadAllText(aPath) == aOriginal && File.ReadAllText(bPath) == bOriginal);
    File.WriteAllBytes(keyPath, key);
    Check("Matching backup key recovers both secrets", store.Prepare(a).ApiKey == "synthetic-shared" && store.Prepare(b).ApiKey == "synthetic-shared");
    var old = store.Prepare(a);
    var rotated = store.Save(a, old.Revision, old.Channels, "synthetic-rotated", false);
    Check("Owner key rotation invalidates old snapshot and preserves B", !store.IsCurrent(old) && rotated.KeyRevision == old.KeyRevision + 1 && store.Prepare(a).ApiKey == "synthetic-rotated" && File.ReadAllText(bPath) == bOriginal);
    File.WriteAllText(aPath, aOriginal);
    Check("Restoring old matching profile and key revives old snapshot at store layer", store.IsCurrent(old) && store.Prepare(a).ApiKey == "synthetic-shared");

    foreach(var mutation in new[] { "key", "channels", "delete" })
    {
        store.Save(a, store.Read(a).Revision, new[] { channel }, "synthetic-shared", false);
        var before = store.Prepare(a);
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var http = new HttpClient(new Handler(async request => {
            if(request.RequestUri!.AbsolutePath.EndsWith("playlistItems"))
            { entered.TrySetResult(); await release.Task.WaitAsync(TimeSpan.FromSeconds(10)); }
            object payload = request.RequestUri!.AbsolutePath.EndsWith("channels")
                ? new { items = new[] { new { id = channel, contentDetails = new { relatedPlaylists = new { uploads = "UU" + channel[2..] } } } } }
                : (object)new { items = new[] { new { contentDetails = new { videoId = "abcdefghijk" }, snippet = new { channelId = channel, title = "fixture", description = "fixture" } } } };
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(payload)) };
        }));
        var request = new PersonalYouTubeCatalog(store, http).ReadPageAsync(before, channel, null, CancellationToken.None);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
        var second = new PersonalYouTubeStore(root);
        if(mutation == "delete") second.Delete(a, before.Revision);
        else second.Save(a, before.Revision, mutation == "channels" ? new[] { "UC" + new string('b', 22) } : before.Channels, mutation == "key" ? "synthetic-replacement" : null, false);
        release.TrySetResult();
        bool denied = false;
        try { await request; } catch(InvalidOperationException) { denied = true; }
        bool published = false;
        Check("Delayed real catalog response rejected after " + mutation, denied && !store.PublishIfCurrent(before, () => published = true) && !published);
        Check("Delayed A response mutation leaves B key and file unchanged", store.Prepare(b).ApiKey == "synthetic-shared" && File.ReadAllText(bPath) == bOriginal);
    }
    store.Save(a, store.Read(a).Revision, new[] { channel }, "synthetic-shared", false);
    var prepared = store.Prepare(a);
    bool childChanged = false;
    var publication = store.PublishIfCurrent(prepared, () => {
        var executable = Environment.ProcessPath!;
        var info = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        if(Path.GetFileNameWithoutExtension(executable) == "dotnet") info.ArgumentList.Add(typeof(Handler).Assembly.Location);
        info.ArgumentList.Add("child"); info.ArgumentList.Add(root); info.ArgumentList.Add(a.ToString());
        using var process = Process.Start(info)!;
        if(!process.WaitForExit(10000)) { process.Kill(true); throw new Exception("Child timeout"); }
        childChanged = process.ExitCode == 0;
    });
    Check("Separate process can save while parent publication holds process-local gate", publication && childChanged && !store.IsCurrent(prepared));
    Check("Separate process A write preserves B", File.ReadAllText(bPath) == bOriginal);
    CryptographicOperations.ZeroMemory(key);
    complete = true;
}
finally
{
    if(Directory.Exists(root)) Directory.Delete(root, true);
    File.WriteAllText(Path.Combine(artifact, "store-results.json"), JsonSerializer.Serialize(new { Completed = complete, TestDataGone = !Directory.Exists(root), Observations = rows }, new JsonSerializerOptions { WriteIndented = true }));
}
Console.WriteLine("F store/catalog checks: " + rows.Count);
sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> response) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => response(request);
}
