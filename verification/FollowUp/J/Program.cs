using Emby.YouTubePlugin;
using HarmonyLib;
using MediaBrowser.Controller.Library;
using System.Diagnostics;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

// External executable adapter: no Google, yt-dlp or native publication.
if (args.FirstOrDefault() == "--ignore-config")
{
    var output = args[Array.IndexOf(args, "--output") + 1].Replace("%(ext)s", "mp4");
    if (Environment.GetEnvironmentVariable("YT_J_MODE") == "wait") {
        File.WriteAllText(Path.Combine(Path.GetDirectoryName(output)!, "started"), "started");
        await Task.Delay(60000); return;
    }
    File.WriteAllText(output, JsonSerializer.Serialize(new {
        LD_LIBRARY_PATH = Environment.GetEnvironmentVariable("LD_LIBRARY_PATH"),
        LD_PRELOAD = Environment.GetEnvironmentVariable("LD_PRELOAD") }));
    using var file = File.OpenWrite(output); file.SetLength(1024);
    return;
}
if (args.FirstOrDefault() == "inventory")
{
    var expected = new HashSet<string>(Directory.GetFiles(args[1], "PersonalYouTube*.cs")
        .SelectMany(p => Regex.Matches(File.ReadAllText(p), "\"([A-F0-9]{64})\"").Select(m => m.Groups[1].Value)));
    var assemblies = new List<object>();
    foreach (var path in Directory.GetFiles(args[2], "*.dll"))
    {
        using var stream = File.OpenRead(path); using var pe = new PEReader(stream);
        if (!pe.HasMetadata) continue;
        var md = pe.GetMetadataReader(); if (!md.IsAssembly) continue;
        var assembly = md.GetAssemblyDefinition(); var matches = new List<object>();
        foreach (var handle in md.TypeDefinitions)
        {
            var type = md.GetTypeDefinition(handle);
            foreach (var mh in type.GetMethods())
            {
                var method = md.GetMethodDefinition(mh);
                if (method.RelativeVirtualAddress == 0 || (method.ImplAttributes & MethodImplAttributes.CodeTypeMask) != MethodImplAttributes.IL) continue;
                var hash = Convert.ToHexString(SHA256.HashData(pe.GetMethodBody(method.RelativeVirtualAddress).GetILBytes()!));
                if (expected.Contains(hash)) matches.Add(new { Type = md.GetString(type.Namespace) + "." + md.GetString(type.Name), Method = md.GetString(method.Name), ILHash = hash });
            }
        }
        if (matches.Count > 0 || md.GetString(assembly.Name).StartsWith("Emby")) assemblies.Add(new {
            Name = md.GetString(assembly.Name), Version = assembly.Version.ToString(), SHA256 = Hash(path), Matches = matches });
    }
    File.WriteAllText(args[3], JsonSerializer.Serialize(new { ExpectedDistinctHashes = expected.Count, Assemblies = assemblies,
        Limitation = "Offline raw IL hash inventory; neither complete contract match nor runtime support proof" }, new JsonSerializerOptions { WriteIndented = true }));
    return;
}
var evidence = Path.GetFullPath(args.FirstOrDefault() ?? "verification/FollowUp/J/WINDOWS-EVIDENCE.json");
var root = Path.Combine(Path.GetTempPath(), "youtube-followup-j-" + Guid.NewGuid().ToString("N"));
var rows = new List<object>(); bool completed = false;
void Check(string label, bool observed, bool requirementMet = true) {
    rows.Add(new { Label = label, Observed = observed, RequirementMet = requirementMet });
    if (!observed) throw new Exception("Observation failed: " + label);
}
try
{
    var unsupported = DispatchProxy.Create<ILibraryManager, UnsupportedLibrary>();
    var unsupportedState = PersonalYouTubeNativeCreationHook.Install(unsupported);
    Check("Production creation hook rejects unsupported concrete library contract", !unsupportedState.ContractMatched && !unsupportedState.Installed && unsupportedState.Error == "UnsupportedNativeContract");
    try { PersonalYouTubeNativeCreationHook.RequireAvailable(unsupported); throw new Exception("Unsupported contract accepted"); }
    catch (InvalidOperationException) { Check("Unsupported contract cannot pass creation availability check", true); }
    var own = new Harmony("youtube.followup.j.guard"); var other = new Harmony("youtube.followup.j.other");
    var native = typeof(PatchTarget).GetMethod(nameof(PatchTarget.Read))!;
    var guard = typeof(PatchTarget).GetMethod(nameof(PatchTarget.Guard))!;
    bool HasGuard() => Harmony.GetPatchInfo(native)?.Prefixes.Any(p => p.owner == own.Id && p.PatchMethod == guard) == true;
    try {
        own.Patch(native, prefix: new HarmonyMethod(guard) { priority = 800 });
        Check("Harmony baseline owner positive, foreign negative", PatchTarget.Read(true) == "private" && PatchTarget.Read(false) == "denied" && HasGuard());
        other.Patch(native, prefix: new HarmonyMethod(typeof(PatchTarget).GetMethod(nameof(PatchTarget.Bypass))!) { priority = 900 });
        Check("Foreign higher-priority prefix can skip guard while metadata remains", HasGuard() && PatchTarget.Read(false) == "other-plugin-result", false);
        other.UnpatchAll(other.Id);
        Check("Removing conflicting prefix restores actual guard", PatchTarget.Read(true) == "private" && PatchTarget.Read(false) == "denied");
        own.Unpatch(native, guard);
        Check("Patch removal detectable through metadata, actual guard gone", !HasGuard() && PatchTarget.Read(false) == "private", false);
        own.Patch(native, prefix: new HarmonyMethod(guard) { priority = 800 });
        Check("Reinstall restores owner and foreign behavior", HasGuard() && PatchTarget.Read(true) == "private" && PatchTarget.Read(false) == "denied");
        Check("Production loader reuses loaded Harmony assembly", EmbeddedDependencyLoader.LoadHarmonyAssembly() == typeof(Harmony).Assembly);
    } finally { other.UnpatchAll(other.Id); own.UnpatchAll(own.Id); }
    Check("All J Harmony patches removed", Harmony.GetPatchInfo(native) == null || Harmony.GetPatchInfo(native)!.Owners.Count == 0);

    var store = new PersonalYouTubeStore(root); var a = Guid.NewGuid(); var b = Guid.NewGuid(); var channel = "UC" + new string('a', 22);
    store.Save(a, 0, new[] { channel }, "synthetic-j-key", false); store.Save(b, 0, new[] { channel }, "synthetic-j-key", false);
    var snapshot = store.Prepare(a); var videoId = "abcdefghijk";
    var page = new PersonalYouTubeCatalog.Page(a, snapshot.CollectionId, snapshot.GenerationId, snapshot.Revision, snapshot.KeyRevision, channel,
        new[] { new PersonalYouTubeCatalog.Video(videoId, "Synthetic", "Synthetic") }, null);
    var executable = Environment.ProcessPath!;
    if (OperatingSystem.IsLinux()) {
        // The image's glibc .NET apphost needs /system in LD_LIBRARY_PATH.
        // Use an explicit shell transport adapter to observe production stripping.
        executable = Path.Combine(root, "j-downloader");
        File.WriteAllText(executable, """
#!/bin/sh
set -eu
while [ "$1" != --output ]; do shift; done
output=$(printf '%s' "$2" | sed 's/%(ext)s/mp4/')
test -z "${LD_LIBRARY_PATH+x}"
test -z "${LD_PRELOAD+x}"
if [ "$YT_J_MODE" = wait ]; then
  dirname "$output" | xargs -I{} touch {}/started
  sleep 60
else
  printf '{"LD_LIBRARY_PATH":null,"LD_PRELOAD":null}' > "$output"
  truncate -s 1024 "$output"
fi
""");
        File.SetUnixFileMode(executable, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }
    var buffer = new PersonalYouTubeVideoBuffer(root, executable, executable, executable);
    Environment.SetEnvironmentVariable("YT_J_MODE", "ok");
    var video = await buffer.DownloadAsync(snapshot, page, videoId, 4096, default);
    Check("Production buffer positive owner with executable adapter", video.OwnerUserId == a && video.Bytes == 1024 && video.SHA256 == Hash(video.Path));
    var bp = store.Prepare(b);
    try { await buffer.DownloadAsync(bp, page, videoId, 4096, default); throw new Exception("Foreign accepted"); }
    catch (InvalidOperationException) { Check("Production buffer rejects B using A page", true); }
    if (OperatingSystem.IsLinux()) {
        var environment = File.ReadAllText(video.Path).TrimEnd('\0');
        Check("Production Linux child environment strips both LD variables", environment.Contains("\"LD_LIBRARY_PATH\":null") && environment.Contains("\"LD_PRELOAD\":null"));
    }
    buffer.Release(video);
    Environment.SetEnvironmentVariable("YT_J_MODE", "wait");
    using var cancel = new CancellationTokenSource();
    var download = buffer.DownloadAsync(snapshot, page, videoId, 4096, cancel.Token);
    var deadline = DateTime.UtcNow.AddSeconds(10);
    while (!Directory.EnumerateFiles(root, "started", SearchOption.AllDirectories).Any() && DateTime.UtcNow < deadline) await Task.Delay(25);
    Check("Buffering adapter reaches actual child process before cancellation", Directory.EnumerateFiles(root, "started", SearchOption.AllDirectories).Any());
    cancel.Cancel();
    try { await download.WaitAsync(TimeSpan.FromSeconds(10)); throw new Exception("Cancellation ignored"); }
    catch (OperationCanceledException) { Check("Production Buffering cancellation completes", true); }
    Check("Cancelled staging physically removed", !Directory.EnumerateFiles(Path.Combine(root, "buffer"), "*", SearchOption.AllDirectories).Any());
    Check("A cancellation preserves current B profile", store.IsCurrent(bp));
    Environment.SetEnvironmentVariable("YT_J_MODE", "ok");
    var bpage = page with { OwnerUserId = b, CollectionId = bp.CollectionId, GenerationId = bp.GenerationId, Revision = bp.Revision, KeyRevision = bp.KeyRevision };
    var bv = await buffer.DownloadAsync(bp, bpage, videoId, 4096, default); buffer.Release(bv);
    Check("B positive buffer after A cancellation", bv.OwnerUserId == b);
    var invalidTool = Path.Combine(root, "invalid-tool"); File.WriteAllText(invalidTool, "not an executable");
    var invalidBuffer = new PersonalYouTubeVideoBuffer(root, invalidTool, executable, executable);
    try { await invalidBuffer.DownloadAsync(snapshot, page, videoId, 4096, default); throw new Exception("Invalid tool accepted"); }
    catch (System.ComponentModel.Win32Exception) { Check("Existing but non-executable tool fails only at process launch", true, false); }
    Check("Invalid executable launch leaves no staging files", !Directory.EnumerateFiles(Path.Combine(root, "buffer"), "*", SearchOption.AllDirectories).Any());
    completed = true;
}
finally
{
    Environment.SetEnvironmentVariable("YT_J_MODE", null);
    if (Directory.Exists(root)) Directory.Delete(root, true);
    Directory.CreateDirectory(Path.GetDirectoryName(evidence)!);
    File.WriteAllText(evidence, JsonSerializer.Serialize(new {
        Completed = completed, Runtime = Environment.Version.ToString(), OS = System.Runtime.InteropServices.RuntimeInformation.OSDescription,
        Architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),
        PluginSHA256 = Hash(typeof(PersonalYouTubeStore).Assembly.Location), HarmonyVersion = typeof(Harmony).Assembly.GetName().Version!.ToString(),
        Entry = "Production Store/VideoBuffer; synthetic executable downloader; synthetic Harmony target, no Emby server or Google",
        Observations = rows, Cleanup = new { TestDataGone = !Directory.Exists(root) }
    }, new JsonSerializerOptions { WriteIndented = true }));
}
static string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
public static class PatchTarget
{
    [MethodImpl(MethodImplOptions.NoInlining)] public static string Read(bool owner) => "private";
    public static bool Guard(bool owner, ref string __result) { if (owner) return true; __result = "denied"; return false; }
    public static bool Bypass(ref string __result) { __result = "other-plugin-result"; return false; }
}
public class UnsupportedLibrary : DispatchProxy
{
    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args) => throw new NotSupportedException("No native library execution in J adapter");
}
