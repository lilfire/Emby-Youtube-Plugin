using Emby.YouTubePlugin;
using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;

// Synthetic executable transport, deliberately not yt-dlp/Node/FFmpeg.
if(args.FirstOrDefault() == "--child") { await Task.Delay(60000); return; }
if(args.FirstOrDefault() == "--ignore-config")
{
    var mode = Environment.GetEnvironmentVariable("YT_G_MODE");
    var output = args[Array.IndexOf(args, "--output") + 1].Replace("%(ext)s", "mp4");
    if(mode is "hang" or "orphan")
    {
        using var child = Process.Start(new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true, ArgumentList = { "--child" } })!;
        File.WriteAllText(Environment.GetEnvironmentVariable("YT_G_PIDS")!, JsonSerializer.Serialize(new[] { Environment.ProcessId, child.Id }));
        if(mode == "hang") await child.WaitForExitAsync();
    }
    else if(mode == "fail") { Console.Error.WriteLine("synthetic-private-provider-detail"); Environment.ExitCode = 1; }
    else File.WriteAllBytes(output, new byte[mode == "oversize" ? 8192 : 1024]);
    return;
}
var outDir = Path.GetFullPath(args.FirstOrDefault() ?? "verification/FollowUp/G");
Directory.CreateDirectory(outDir);
var root = Path.Combine(Path.GetTempPath(), "youtube-followup-g-" + Guid.NewGuid().ToString("N"));
var rows = new List<object>();
var processIds = new List<int>();
void Check(string label, bool observed, bool requirementMet = true)
{
    rows.Add(new { Label = label, Reproduced = observed, RequirementMet = requirementMet });
    if(!observed) throw new Exception("Observation failed: " + label);
}
async Task<Exception> Failure(Func<Task> action)
{
    try { await action(); } catch(Exception ex) { return ex; }
    throw new Exception("Expected failure");
}
HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(value)) };
var channel = "UC" + new string('a', 22);
object Channel() => new { items = new[] { new { id = channel, contentDetails = new { relatedPlaylists = new { uploads = "UU" + channel[2..] } } } } };
object Videos(int count = 1) => new { items = Enumerable.Range(0, count).Select(_ => new { contentDetails = new { videoId = "abcdefghijk" }, snippet = new { channelId = channel, title = "fixture", description = "fixture" } }).ToArray() };
bool Alive(int pid) { try { using var p = Process.GetProcessById(pid); return !p.HasExited; } catch(ArgumentException) { return false; } }
bool complete = false;
try
{
    var store = new PersonalYouTubeStore(root);
    var a = Guid.NewGuid(); var b = Guid.NewGuid();
    store.Save(a, 0, new[] { channel }, "synthetic-shared-key", false);
    store.Save(b, 0, new[] { channel }, "synthetic-shared-key", false);
    var snapshot = store.Prepare(a);
    int calls = 0;
    using var good = new HttpClient(new Handler((r, t) => { Interlocked.Increment(ref calls); return Task.FromResult(Json(r.RequestUri!.AbsolutePath.EndsWith("channels") ? Channel() : Videos())); }));
    var catalog = new PersonalYouTubeCatalog(store, good);
    var page = await catalog.ReadPageAsync(snapshot, channel, null, default);
    var bp = await catalog.ReadPageAsync(store.Prepare(b), channel, null, default);
    Check("A/B positive catalog controls; shared key does not coalesce requests", calls == 4 && page.OwnerUserId == a && bp.OwnerUserId == b && page.GenerationId != bp.GenerationId);
    var copied = snapshot with { OwnerUserId = b };
    var denied = await Failure(() => catalog.ReadPageAsync(copied, channel, null, default));
    Check("Forged B owner on A snapshot denied before transport", denied is InvalidOperationException && calls == 4);
    foreach(var scenario in new[] { "quotaExceeded", "rateLimitExceeded", "keyInvalid", "API_KEY_INVALID", "unknown", "html", "timeout", "network", "missing", "oversized", "cancel" })
    {
        using var cts = new CancellationTokenSource();
        using var http = new HttpClient(new Handler((r, t) => {
            if(scenario == "timeout") throw new TaskCanceledException("synthetic-private-provider-detail");
            if(scenario == "network") throw new HttpRequestException("synthetic-private-provider-detail");
            if(scenario == "cancel") { cts.Cancel(); throw new OperationCanceledException(cts.Token); }
            if(scenario == "missing") return Task.FromResult(Json(new { items = Array.Empty<object>() }));
            var content = scenario == "html" ? "<html>synthetic-private-provider-detail</html>" : scenario == "oversized" ? new string('x', 4 * 1024 * 1024 + 1) : JsonSerializer.Serialize(new { error = new { errors = new[] { new { reason = scenario, message = "synthetic-private-provider-detail" } } } });
            return Task.FromResult(new HttpResponseMessage((HttpStatusCode)429) { Content = new StringContent(content) });
        }));
        var ex = await Failure(() => new PersonalYouTubeCatalog(store, http).ReadPageAsync(snapshot, channel, null, cts.Token));
        var expected = scenario is "quotaExceeded" or "rateLimitExceeded" ? "YouTubeQuotaExceeded" : scenario is "keyInvalid" or "API_KEY_INVALID" ? "YouTubeKeyRejected" : scenario == "unknown" ? "YouTubeRequestFailed" : null;
        Check("Sanitized catalog failure: " + scenario, !ex.ToString().Contains("synthetic-private-provider-detail") && (expected == null || ex is PersonalYouTubeJobFailure f && f.Code == expected) && (scenario != "cancel" || ex is OperationCanceledException));
    }
    using(var cts = new CancellationTokenSource())
    using(var http = new HttpClient(new Handler((r, t) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(new StalledStream()) }))) { Timeout = TimeSpan.FromMilliseconds(100) })
    {
        var pending = new PersonalYouTubeCatalog(store, http).ReadPageAsync(snapshot, channel, null, cts.Token);
        await Task.Delay(350);
        Check("ResponseHeadersRead body stall outlives HttpClient timeout", !pending.IsCompleted, false);
        cts.Cancel();
        Check("Explicit cancellation terminates stalled catalog body", await Failure(async () => await pending.WaitAsync(TimeSpan.FromSeconds(3))) is OperationCanceledException);
    }
    var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    using(var slow = new HttpClient(new Handler(async (r, t) => {
        if(r.RequestUri!.AbsolutePath.EndsWith("playlistItems")) { entered.TrySetResult(); await release.Task.WaitAsync(t); }
        return Json(r.RequestUri!.AbsolutePath.EndsWith("channels") ? Channel() : Videos());
    })))
    {
        var pending = new PersonalYouTubeCatalog(store, slow).ReadPageAsync(snapshot, channel, null, default);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        store.Save(a, snapshot.Revision, snapshot.Channels, "synthetic-rotated", false);
        release.SetResult();
        Check("Late A response rejected after key rotation", await Failure(() => pending) is InvalidOperationException);
        Check("B catalog remains functional after A rotation", (await catalog.ReadPageAsync(store.Prepare(b), channel, null, default)).OwnerUserId == b);
    }
    snapshot = store.Prepare(a); page = await catalog.ReadPageAsync(snapshot, channel, null, default);
    var exe = Environment.ProcessPath!;
    var buffer = new PersonalYouTubeVideoBuffer(root, exe, exe, exe);
    Environment.SetEnvironmentVariable("YT_G_MODE", "success");
    var video = await buffer.DownloadAsync(snapshot, page, "abcdefghijk", 4096, default);
    Check("Buffer positive owner control and SHA256", video.OwnerUserId == a && video.Bytes == 1024 && video.SHA256 == Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(video.Path))));
    Check("Non-media MP4-named bytes accepted without track validation", File.ReadAllBytes(video.Path).All(x => x == 0), false);
    Check("Foreign page denied for B buffer", await Failure(() => buffer.DownloadAsync(store.Prepare(b), page, "abcdefghijk", 4096, default)) is InvalidOperationException);
    var bv = await buffer.DownloadAsync(store.Prepare(b), bp, "abcdefghijk", 4096, default);
    using(var locked = new FileStream(video.Path, FileMode.Open, FileAccess.Read, FileShare.None))
        Check("Locked staging release reports disk error and preserves B", await Failure(() => { buffer.Release(video); return Task.CompletedTask; }) is IOException && File.Exists(bv.Path));
    buffer.Release(video); Check("A release leaves B buffered file intact", !File.Exists(video.Path) && File.Exists(bv.Path)); buffer.Release(bv);
    foreach(var mode in new[] { "fail", "oversize" })
    {
        Environment.SetEnvironmentVariable("YT_G_MODE", mode);
        var ex = await Failure(() => buffer.DownloadAsync(snapshot, page, "abcdefghijk", 4096, default));
        Check("Downloader " + mode + " fails sanitized and removes staging", ex is InvalidDataException && !ex.ToString().Contains("synthetic-private-provider-detail") && !Directory.EnumerateFiles(Path.Combine(root, "buffer"), "*", SearchOption.AllDirectories).Any());
    }
    foreach(var mutation in new[] { "cancel", "profile" })
    {
        Environment.SetEnvironmentVariable("YT_G_MODE", "hang");
        var pidFile = Path.Combine(root, "pids.json"); File.Delete(pidFile);
        Environment.SetEnvironmentVariable("YT_G_PIDS", pidFile);
        using var cts = new CancellationTokenSource();
        var pending = buffer.DownloadAsync(snapshot, page, "abcdefghijk", 4096, cts.Token);
        var watch = Stopwatch.StartNew();
        while(!File.Exists(pidFile) && watch.Elapsed < TimeSpan.FromSeconds(5)) await Task.Delay(25);
        var pids = JsonSerializer.Deserialize<int[]>(File.ReadAllText(pidFile))!; processIds.AddRange(pids);
        if(mutation == "cancel") cts.Cancel(); else store.Save(a, snapshot.Revision, snapshot.Channels, "synthetic-next", false);
        var ex = await Failure(async () => await pending.WaitAsync(TimeSpan.FromSeconds(10)));
        Check("Synthetic parent/child killed on " + mutation, (ex is OperationCanceledException or InvalidOperationException) && pids.All(pid => !Alive(pid)));
        Check("Staging cleaned on " + mutation, !Directory.EnumerateFiles(Path.Combine(root, "buffer"), "*.mp4", SearchOption.AllDirectories).Any());
        snapshot = store.Prepare(a); page = await catalog.ReadPageAsync(snapshot, channel, null, default);
    }
    Environment.SetEnvironmentVariable("YT_G_MODE", "orphan");
    var orphanFile = Path.Combine(root, "orphan-pids.json");
    Environment.SetEnvironmentVariable("YT_G_PIDS", orphanFile);
    using(var cts = new CancellationTokenSource())
    {
        var pending = buffer.DownloadAsync(snapshot, page, "abcdefghijk", 4096, cts.Token);
        var watch = Stopwatch.StartNew();
        while(!File.Exists(orphanFile) && watch.Elapsed < TimeSpan.FromSeconds(5)) await Task.Delay(25);
        var pids = JsonSerializer.Deserialize<int[]>(File.ReadAllText(orphanFile))!; processIds.AddRange(pids);
        while(Alive(pids[0]) && watch.Elapsed < TimeSpan.FromSeconds(5)) await Task.Delay(25);
        cts.Cancel(); await Task.Delay(500);
        Check("Exited downloader with child-held output pipes ignores cancellation", !Alive(pids[0]) && Alive(pids[1]) && !pending.IsCompleted, false);
        using(var child = Process.GetProcessById(pids[1])) { child.Kill(true); await child.WaitForExitAsync(); }
        await Failure(async () => await pending.WaitAsync(TimeSpan.FromSeconds(5)));
        Check("Orphan test recovers after explicit fixture child kill", pids.All(pid => !Alive(pid)));
    }
    Environment.SetEnvironmentVariable("YT_G_MODE", "success");
    using(var budget = await PersonalYouTubeStorageBudget.EnterAsync(root, default))
    {
        Check("Empty budget reserves staging plus native copy", budget.DownloadAllowance(8192, 8192) == 4096);
        var media = Path.Combine(root, "media"); Directory.CreateDirectory(media); File.WriteAllBytes(Path.Combine(media, "external"), new byte[4096]);
        Check("External plugin-tree growth is counted at next allowance", budget.DownloadAllowance(8192, 8192) == 2048);
        File.WriteAllBytes(Path.Combine(media, "external"), new byte[8192]);
        Check("Exhausted budget produces bounded error code", await Failure(() => Task.FromResult(budget.DownloadAllowance(8192, 8192))) is PersonalYouTubeJobFailure { Code: "StorageBudgetExceeded" });
        File.Delete(Path.Combine(media, "external"));
        File.WriteAllBytes(Path.Combine(root, "unrelated"), new byte[8192]);
        Check("Storage outside media/buffer ignored; no physical free-space reservation", budget.DownloadAllowance(8192, 8192) == 4096, false);
        Directory.Delete(media);
        Check("Disappeared media directory treated as zero usage", budget.DownloadAllowance(8192, 8192) == 4096, false);
        using var wait = new CancellationTokenSource(100);
        Check("Blocked budget waiter cancels", await Failure(async () => { using var other = await PersonalYouTubeStorageBudget.EnterAsync(root, wait.Token); }) is OperationCanceledException);
    }
    // Duplicate metadata fails before native publisher use: no native adapter required.
    using(var dup = new HttpClient(new Handler((r, t) => Task.FromResult(Json(r.RequestUri!.AbsolutePath.EndsWith("channels") ? Channel() : Videos(2))))))
    {
        var refresh = new PersonalYouTubeInitialRefresh(root, new(store, dup), buffer, null!, null!);
        var ex = await Failure(() => refresh.RunPreparedAsync(snapshot, 1, 4096, 4096, null, default));
        Check("Same-page duplicate survives selection and crashes metadata Single", ex is InvalidOperationException && ex.Message.Contains("more than one"), false);
        Check("Duplicate failure releases downloaded staging", !Directory.EnumerateFiles(Path.Combine(root, "buffer"), "*.mp4", SearchOption.AllDirectories).Any());
    }
    // Distinct empty page tokens bypass repeated-token detection until cancellation.
    int pages = 0;
    using(var cts = new CancellationTokenSource())
    using(var empty = new HttpClient(new Handler((r, t) => {
        t.ThrowIfCancellationRequested();
        if(r.RequestUri!.AbsolutePath.EndsWith("channels")) return Task.FromResult(Json(Channel()));
        if(++pages == 150) cts.Cancel();
        return Task.FromResult(Json(new { items = Array.Empty<object>(), nextPageToken = "page-" + pages }));
    })))
    {
        var refresh = new PersonalYouTubeInitialRefresh(root, new(store, empty), buffer, null!, null!);
        Check("Selection has no page/request ceiling for changing empty tokens", await Failure(() => refresh.RunPreparedAsync(snapshot, 1, 4096, 4096, null, cts.Token)) is OperationCanceledException && pages == 150, false);
    }
    // Jobs uses real persisted status; executor is explicitly a test delegate.
    using(var jobs = new PersonalYouTubeJobs(root, (s, p, t) => throw new PersonalYouTubeJobFailure(s.OwnerUserId == a ? "YouTubeQuotaExceeded" : "YouTubeKeyRejected")))
    {
        jobs.Notify(a); jobs.Notify(b); await jobs.DrainAsync().WaitAsync(TimeSpan.FromSeconds(5));
        Check("Jobs failures persist correct owner-specific sanitized status", jobs.Read(a).ErrorCode == "YouTubeQuotaExceeded" && jobs.Read(b).ErrorCode == "YouTubeKeyRejected" && jobs.Read(a).OwnerUserId == a && jobs.Read(b).OwnerUserId == b);
        var text = string.Join("", Directory.EnumerateFiles(Path.Combine(root, "jobs")).Select(File.ReadAllText));
        Check("Persisted status excludes synthetic keys/channel/provider detail", !text.Contains("synthetic-") && !text.Contains(channel));
    }
    var running = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    var letOldFinish = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    using(var jobs = new PersonalYouTubeJobs(root, async (s, p, t) => {
        if(s.OwnerUserId == a && s.Revision == snapshot.Revision) { running.TrySetResult(); await letOldFinish.Task; p("Obsolete", 99, 99); }
        throw new PersonalYouTubeJobFailure(s.OwnerUserId == a ? "YouTubeRequestFailed" : "YouTubeKeyRejected");
    }))
    {
        jobs.Notify(a); await running.Task.WaitAsync(TimeSpan.FromSeconds(5));
        store.Save(a, snapshot.Revision, snapshot.Channels, "synthetic-replacement", false); jobs.Notify(a); jobs.Notify(b);
        await Task.Delay(100);
        Check("Replacement waits for predecessor; B executor can progress independently", jobs.Read(a).State == "Queued" && jobs.Read(b).State == "Failed");
        letOldFinish.SetResult(); await jobs.DrainAsync().WaitAsync(TimeSpan.FromSeconds(5));
        Check("Obsolete progress cannot overwrite new owner revision/status", jobs.Read(a).ProfileRevision == snapshot.Revision + 1 && jobs.Read(a).ErrorCode == "YouTubeRequestFailed" && jobs.Read(a).CompletedVideos == 0);
    }
    var acquired = new List<int>();
    var first = await PersonalYouTubeStorageBudget.EnterAsync(root, default);
    bool firstReleased = false;
    try
    {
        var waiting = Enumerable.Range(0, 32).Select(async i => { using var lease = await PersonalYouTubeStorageBudget.EnterAsync(root, default); lock(acquired) acquired.Add(i); }).ToArray();
        first.Dispose();
        firstReleased = true;
        await Task.WhenAll(waiting).WaitAsync(TimeSpan.FromSeconds(5));
        Check("32 bounded waiters all complete (no fairness guarantee)", acquired.Count == 32);
    }
    finally { if(!firstReleased) first.Dispose(); }
    complete = true;
}
finally
{
    foreach(var pid in processIds.Where(Alive)) { using var p = Process.GetProcessById(pid); p.Kill(true); p.WaitForExit(); }
    Environment.SetEnvironmentVariable("YT_G_MODE", null); Environment.SetEnvironmentVariable("YT_G_PIDS", null);
    // root is a unique, absolute test-owned directory under the OS temporary directory.
    if(!root.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(root).StartsWith("youtube-followup-g-")) throw new Exception("Unsafe fixture cleanup");
    if(Directory.Exists(root)) Directory.Delete(root, true);
    var sources = new[] { "Catalog", "VideoBuffer", "Jobs", "JobRuntime", "InitialRefresh", "StorageBudget" }.Select(n => "PersonalYouTube" + n + ".cs").ToDictionary(n => n, n => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(n))));
    File.WriteAllText(Path.Combine(outDir, "WINDOWS-EVIDENCE.json"), JsonSerializer.Serialize(new { Complete = complete, Runtime = Environment.Version.ToString(), Platform = System.Runtime.InteropServices.RuntimeInformation.OSDescription, ProductionDLLSHA256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(PersonalYouTubeStore).Assembly.Location))), TestDLLSHA256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(Handler).Assembly.Location))), Sources = sources, Transport = "Synthetic HttpMessageHandler and synthetic executable parent/child", Observations = rows, Cleanup = new { FixtureRemoved = !Directory.Exists(root), AllTrackedProcessesExited = processIds.All(pid => !Alive(pid)) } }, new JsonSerializerOptions { WriteIndented = true }));
}

sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> execute) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => execute(request, token);
}

sealed class StalledStream : Stream
{
    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => 0; set => throw new NotSupportedException(); }
    public override void Flush() => throw new NotSupportedException();
    public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default) { await Task.Delay(Timeout.Infinite, token); return 0; }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
}
