using System.Reflection;
using HarmonyLib;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;

namespace PersonalChannelsFixture;

// Timing-only isolated experiment. Never changes native item/status/path values.
internal static class NativeSyncWriteGate
{
    private static readonly object GateLock = new();
    private static readonly ManualResetEventSlim ReleaseSignal = new(false);
    private static bool Installed, Armed, Reached, Active, TimedOut, Released, OutputExists, OutputMatches;
    private static long SourceKey, JobKey, ItemKey;
    private static string ExpectedPath = "";
    private static bool Converted;
    private static string CapturedOutputPath = "", CapturedOutputHash = "";
    private static long CapturedOutputBytes;
    internal static object Arm(ILibraryManager library, long sourceKey, bool converted = false)
    {
        var source = library.GetItemById(sourceKey);
        var suffix = string.Join(Path.DirectorySeparatorChar, "verification", "PersonalChannels", "bin", "native-client", "a", "PrivateNativeVideo_a_client.mp4");
        if (source is not Video || source.Name != "PrivateNativeVideo_a_client" || !File.Exists(source.Path)
            || !Path.GetFullPath(source.Path).EndsWith(Path.DirectorySeparatorChar + suffix, StringComparison.OrdinalIgnoreCase)
            || !library.GetCollectionFolders(source).Any(root => root.Name == "Private Native Fixture a"))
            throw new ArgumentException("Only the isolated native A source");
        lock (GateLock)
        {
            if (Active) throw new InvalidOperationException("Gate already active");
            if (!Installed)
            {
                var type = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Sync.SyncManager")).First(type => type != null)!;
                var method = type.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                    .Single(method => method.Name == "UpdateSyncJobItemInternal" && method.GetParameters().Length == 1);
                new Harmony("isolated-native-sync-write-gate").Patch(method, prefix: new HarmonyMethod(typeof(NativeSyncWriteGate), nameof(BeforeWrite)));
                Installed = true;
            }
            SourceKey = sourceKey; ExpectedPath = Path.GetFullPath(source.Path);
            Converted = converted; CapturedOutputPath = CapturedOutputHash = ""; CapturedOutputBytes = 0;
            Armed = true; Reached = Active = TimedOut = Released = OutputExists = OutputMatches = false;
            JobKey = ItemKey = 0; ReleaseSignal.Reset();
            return Snapshot();
        }
    }
    private static void BeforeWrite(object __0)
    {
        lock (GateLock)
        {
            if (!Armed || Reached || Convert.ToInt64(__0.GetType().GetProperty("ItemId")!.GetValue(__0)) != SourceKey
                || __0.GetType().GetProperty("Status")!.GetValue(__0)?.ToString() != "ReadyToTransfer") return;
            var output = __0.GetType().GetProperty("OutputPath")!.GetValue(__0) as string;
            OutputExists = !string.IsNullOrEmpty(output) && File.Exists(output);
            OutputMatches = OutputExists && Path.GetFullPath(output!) == ExpectedPath;
            if (Converted && OutputExists) {
                var syncFolder = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(Path.GetDirectoryName(FixturePlugin.StatePath))!, "sync")) + Path.DirectorySeparatorChar;
                OutputMatches = Path.GetFullPath(output!).StartsWith(syncFolder, StringComparison.OrdinalIgnoreCase)
                    && Path.GetFullPath(output!) != ExpectedPath && Path.GetExtension(output!).Equals(".mp4", StringComparison.OrdinalIgnoreCase);
            }
            if (!OutputMatches) return;
            CapturedOutputPath = Path.GetFullPath(output!);
            CapturedOutputHash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(output!)));
            CapturedOutputBytes = new FileInfo(output!).Length;
            JobKey = Convert.ToInt64(__0.GetType().GetProperty("JobId")!.GetValue(__0));
            ItemKey = Convert.ToInt64(__0.GetType().GetProperty("Id")!.GetValue(__0));
            Reached = Active = true;
        }
        // No guard lock, repository operation, or native mutation during pause.
        var released = ReleaseSignal.Wait(TimeSpan.FromSeconds(25));
        lock (GateLock) { TimedOut = !released; Active = false; Armed = false; }
    }
    internal static object Release()
    {
        lock (GateLock) { Released = true; ReleaseSignal.Set(); return Snapshot(); }
    }
    internal static object Snapshot()
    {
        lock (GateLock) return new { Installed, Armed, Reached, Active, TimedOut, Released,
            NativeOutputFileExists = OutputExists, OutputMatchesExpectedFixture = OutputMatches, Converted,
            CapturedOutputPath, CapturedOutputHash, CapturedOutputBytes, JobKey, ItemKey };
    }
}
