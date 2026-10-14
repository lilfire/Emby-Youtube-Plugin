using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Dto;
using MediaBrowser.Model.MediaInfo;
using System.Reflection;

namespace PersonalChannelsFixture;

internal static class FixtureLiveActivity {
    internal static readonly System.Collections.Concurrent.ConcurrentDictionary<string, int> Opens = new();
    internal static readonly System.Collections.Concurrent.ConcurrentDictionary<string, int> Closes = new();
    internal static readonly System.Collections.Concurrent.ConcurrentDictionary<string, int> SourceDenials = new();
    internal static int ProbeDelayMs;
    private static readonly object ProbeLock = new();
    private static readonly Dictionary<long, long> Active = new();
    private static readonly HashSet<long> Subjects = new();
    private static long Sequence, Overlaps;
    private static int Maximum;
    internal static long Begin(long? subject) {
        if (ProbeDelayMs == 0 || !subject.HasValue) return 0;
        lock (ProbeLock) {
            var id = ++Sequence;
            if (Active.Values.Any(value => value != subject.Value)) Overlaps++;
            Active[id] = subject.Value; Subjects.Add(subject.Value); Maximum = Math.Max(Maximum, Active.Count);
            return id;
        }
    }
    internal static void End(long id) { lock (ProbeLock) Active.Remove(id); }
    internal static object Probe(bool reset = false, int delay = 0) {
        lock (ProbeLock) {
            if (reset) { if (Active.Count != 0) throw new InvalidOperationException("Active native probe."); Sequence = Overlaps = 0; Maximum = 0; Subjects.Clear(); ProbeDelayMs = delay; }
            return new { NativeOpenCalls = Sequence, CrossSubjectOverlapEvents = Overlaps, MaximumActive = Maximum, ActiveCalls = Active.Count, DistinctSubjects = Subjects.Count, ProbeDelayMs };
        }
    }
}

// Disposable local provider. Only journaled synthetic fixture videos qualify.
public sealed class FixtureLiveSourceProvider
{
    private readonly ILibraryManager _library;
    public FixtureLiveSourceProvider(ILibraryManager library) { _library = library; }
    private static bool IsFixture(BaseItem item) => item is Video
        && item.Name is "PrivateNativeVideo_a_client" or "PrivateNativeVideo_b_client" or "PrivateNativeVideo_a_grown"
        && File.Exists(item.Path)
        && Path.GetFullPath(item.Path).Contains(Path.Combine("verification", "PersonalChannels", "bin", "native-client") + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static MediaSourceInfo Source(BaseItem item) => new() {
        Id = "fixture-live-source-" + item.InternalId,
        Name = item.Name,
        Path = item.Path,
        Protocol = MediaProtocol.File,
        Container = "mp4",
        SupportsDirectPlay = true,
        SupportsDirectStream = true,
        SupportsTranscoding = true,
        RequiresOpening = true,
        RequiresClosing = true,
        OpenToken = item.InternalId.ToString(),
        MediaStreams = new(),
    };
    public Task<List<MediaSourceInfo>> GetMediaSources(BaseItem item, CancellationToken cancellationToken) =>
        Task.FromResult(IsFixture(item) ? new List<MediaSourceInfo> { Source(item) } : new());
    public async Task<ILiveStream> OpenMediaSource(string openToken, string consumerId, List<ILiveStream> currentStreams, CancellationToken cancellationToken) {
        if (!long.TryParse(openToken, out var id)) throw new ArgumentException("Invalid fixture source.");
        var item = _library.GetItemById(id);
        if (item == null || !IsFixture(item)) throw new ArgumentException("Not a fixture source.");
        if (FixtureLiveActivity.ProbeDelayMs > 0) await Task.Delay(FixtureLiveActivity.ProbeDelayMs, cancellationToken).ConfigureAwait(false);
        PrivacyGuard.AuthorizeFixtureStream(item);
        FixtureLiveActivity.Opens.AddOrUpdate(item.Name, 1, (_, count) => count + 1);
        ILiveStream stream = DispatchProxy.Create<ILiveStream, FixtureLiveStream>();
        var openedSource = Source(item);
        openedSource.LiveStreamId = "fixture-live-" + Guid.NewGuid().ToString("N");
        ((FixtureLiveStream)(object)stream).Source = openedSource;
        typeof(ILiveStream).GetMethod("AddConsumer")!.Invoke(stream, new object[] { consumerId });
        return stream;
    }
    public Task<ILiveStream> OpenMediaSource(string openToken, List<ILiveStream> currentStreams, CancellationToken cancellationToken) =>
        OpenMediaSource(openToken, "fixture-sdk-consumer", currentStreams, cancellationToken);
}

// Implement the installed server's interface at runtime: its OpenMediaSource
// contract differs from the compilation SDK. This is only a test adapter.
public class FixtureLiveProviderProxy : DispatchProxy
{
    internal FixtureLiveSourceProvider Provider = null!;
    protected override object? Invoke(MethodInfo? method, object?[]? args) => method?.Name switch {
        "GetMediaSources" => Provider.GetMediaSources((BaseItem)args![0]!, (CancellationToken)args[1]!),
        "OpenMediaSource" when args!.Length == 4 => Provider.OpenMediaSource((string)args[0]!, (string)args[1]!, (List<ILiveStream>)args[2]!, (CancellationToken)args[3]!),
        _ => throw new NotSupportedException("Only installed-server fixture provider methods are supported.")
    };
}

public class FixtureLiveStream : DispatchProxy
{
    private readonly HashSet<string> _consumers = new(StringComparer.Ordinal);
    internal MediaSourceInfo Source = null!;
    private string _original = "";
    private readonly string _unique = Guid.NewGuid().ToString("N");
    private readonly DateTimeOffset _opened = DateTimeOffset.UtcNow;
    protected override object? Invoke(MethodInfo? method, object?[]? args) {
        lock (_consumers) {
            switch (method?.Name) {
                case "get_MediaSource": return Source;
                case "set_MediaSource": Source = (MediaSourceInfo)args![0]!; return null;
                case "get_OriginalStreamId": return _original;
                case "set_OriginalStreamId": _original = (string)args![0]!; return null;
                case "get_UniqueId": return _unique;
                case "get_DateOpened": return _opened;
                case "get_TunerHostId": return "";
                case "get_EnableStreamSharing": case "get_SupportsCopyTo": return false;
                case "get_ConsumerCount": return _consumers.Count;
                case "set_ConsumerCount": throw new NotSupportedException("Old SDK consumer setter is not part of this server test.");
                case "AddConsumer": _consumers.Add((string)args![0]!); return null;
                case "RemoveConsumer": _consumers.Remove((string)args![0]!); return null;
                case "Open": return Task.CompletedTask;
                case "Close": FixtureLiveActivity.Closes.AddOrUpdate(Source.Name, 1, (_, count) => count + 1); _consumers.Clear(); return Task.CompletedTask;
                default: throw new NotSupportedException("Only fixture metadata/open/close are supported.");
            }
        }
    }
}
