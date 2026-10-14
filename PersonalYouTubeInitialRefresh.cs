using System.Collections.Concurrent;
using MediaBrowser.Model.IO;
using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;

namespace Emby.YouTubePlugin;

// First publication orchestration. Scheduling, replacement of an active
// collection and crash recovery remain separate lifecycle work.
internal sealed class PersonalYouTubeInitialRefresh
{
    internal sealed record Result(NativeItem Root, NativeItem[] Videos, long ProfileRevision);
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Jobs = new(StringComparer.Ordinal);
    private readonly string _directory;
    private readonly PersonalYouTubeCatalog _catalog;
    private readonly PersonalYouTubeVideoBuffer _buffer;
    private readonly PersonalYouTubeNativePublisher _publisher;
    private readonly IFileSystem _files;
    internal Action<string, int, int>? Progress { get; set; }
    internal PersonalYouTubeInitialRefresh(string directory, PersonalYouTubeCatalog catalog,
        PersonalYouTubeVideoBuffer buffer, PersonalYouTubeNativePublisher publisher, IFileSystem files)
    { _directory = Path.GetFullPath(directory); _catalog = catalog; _buffer = buffer; _publisher = publisher; _files = files; }

    internal Task<Result> RunAsync(Guid owner, int maxVideos, long maxVideoBytes, long maxTotalBytes,
        PersonalYouTubeNativePublisher.PreparingLibrary? preparing, CancellationToken cancellationToken)
        => RunCoreAsync(owner, maxVideos, maxVideoBytes, maxTotalBytes, preparing, null, cancellationToken);
    internal Task<Result> RunPreparedAsync(PersonalYouTubeStore.Prepared snapshot, int maxVideos, long maxVideoBytes, long maxTotalBytes,
        PersonalYouTubeNativePublisher.PreparingLibrary? preparing, CancellationToken cancellationToken)
        => RunCoreAsync(snapshot.OwnerUserId, maxVideos, maxVideoBytes, maxTotalBytes, preparing, snapshot, cancellationToken);
    private async Task<Result> RunCoreAsync(Guid owner, int maxVideos, long maxVideoBytes, long maxTotalBytes,
        PersonalYouTubeNativePublisher.PreparingLibrary? preparing, PersonalYouTubeStore.Prepared? expected, CancellationToken cancellationToken)
    {
        if (owner == Guid.Empty || maxVideos is < 1 or > 10000 || maxTotalBytes < maxVideoBytes)
            throw new ArgumentException("Invalid personal refresh budget.");
        var gate = Jobs.GetOrAdd(_directory + "|" + owner.ToString("N"), _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        var buffered = new List<PersonalYouTubeVideoBuffer.BufferedVideo>();
        try
        {
            var store = new PersonalYouTubeStore(_directory);
            var snapshot = expected ?? store.Prepare(owner);
            if(!store.IsCurrent(snapshot)) throw new OperationCanceledException("Personal refresh profile changed.");
            if (snapshot.Channels.Length == 0 || string.IsNullOrWhiteSpace(snapshot.ApiKey))
                throw new InvalidOperationException("Personal channels and API key required.");
            if(snapshot.Channels.Length > maxVideos) throw new InvalidOperationException("Video budget must allow at least one video per channel.");
            var perChannelLimit = Math.Max(1, maxVideos / snapshot.Channels.Length);
            var selected = new Dictionary<string, PersonalYouTubeCatalog.Page>(StringComparer.Ordinal);
            Progress?.Invoke("Fetching", 0, 0);
            // Select a bounded recent window from every configured channel
            // before creating a library or downloading any media. A large
            // channel must not require buffering its entire upload history.
            foreach (var channel in snapshot.Channels)
            {
                var tokens = new HashSet<string>(StringComparer.Ordinal);
                var channelVideos = new HashSet<string>(StringComparer.Ordinal);
                string? token = null;
                do
                {
                    if (!tokens.Add(token ?? "")) throw new InvalidDataException("Repeated personal YouTube page token.");
                    var page = await _catalog.ReadPageAsync(snapshot, channel, token, cancellationToken).ConfigureAwait(false);
                    foreach (var video in page.Videos)
                    {
                        if(channelVideos.Count >= perChannelLimit) break;
                        channelVideos.Add(video.Id);
                        selected.TryAdd(video.Id, page);
                    }
                    token = channelVideos.Count >= perChannelLimit ? null : page.NextPageToken;
                } while (token != null);
            }
            if (selected.Count == 0) throw new InvalidOperationException("Personal YouTube catalog has no videos.");
            long total = 0;
            var downloaded = 0;
            foreach (var pair in selected)
            {
                var remaining = Math.Min(maxVideoBytes, maxTotalBytes - total);
                Progress?.Invoke("Buffering", downloaded, selected.Count);
                if (remaining < 1024) throw new InvalidDataException("Personal YouTube buffer budget exceeded.");
                var video = await _buffer.DownloadAsync(snapshot, pair.Value, pair.Key, remaining, cancellationToken).ConfigureAwait(false);
                buffered.Add(video); total = checked(total + video.Bytes);
                downloaded++;
            }
            if (!store.IsCurrent(snapshot)) throw new InvalidOperationException("Personal refresh profile changed.");
            Progress?.Invoke("Publishing", downloaded, selected.Count);
            _publisher.Metadata = selected.ToDictionary(pair => pair.Key, pair => pair.Value.Videos.Single(video => video.Id == pair.Key), StringComparer.Ordinal);
            preparing ??= _publisher.CreatePreparingLibrary(snapshot, "YouTube " + snapshot.GenerationId.ToString("N"));
            var ids = await _publisher.PublishInitialVideosAsync(snapshot, preparing, buffered.ToArray(), _files, cancellationToken).ConfigureAwait(false);
            return new(preparing.Root, ids, snapshot.Revision);
        }
        finally
        {
            try { foreach (var video in buffered) _buffer.Release(video); }
            finally { gate.Release(); }
        }
    }
}
