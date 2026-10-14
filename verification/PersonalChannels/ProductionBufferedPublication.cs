using System.Reflection;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.IO;

namespace PersonalChannelsFixture;

internal static class ProductionBufferedPublication
{
    private static IDisposable? _jobs;
    private static HttpClient? _jobHttp;
    internal static object StartJobs(ILibraryManager library, IFileSystem files, IUserManager users)
    {
        if(_jobs != null) throw new InvalidOperationException("Isolated personal jobs already started.");
        var directory = Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal");
        var configuration = Create("PluginConfiguration");
        void Set(string name, object value) => configuration.GetType().GetProperty(name)!.SetValue(configuration, value);
        Set("PersonalYouTubeDownloaderPath", "C:/git/Emby-Youtube-Plugin/verification/PersonalChannels/bin/media-tools/yt-dlp.exe");
        Set("PersonalYouTubeFfmpegPath", Path.GetFullPath(Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "../../server/system/ffmpeg.exe")));
        Set("PersonalYouTubeNodePath", "C:/Program Files/nodejs/node.exe");
        Set("PersonalYouTubeMaxVideos", 1); Set("PersonalYouTubeMaxVideoBytes", 64L * 1024 * 1024); Set("PersonalYouTubeMaxCollectionBytes", 64L * 1024 * 1024);
        _jobHttp = new HttpClient(new CatalogHandler("UC" + new string('a', 22), "synthetic-alpha-personal-key", true));
        var runtime = Type("PersonalYouTubeJobRuntime");
        _jobs = (IDisposable)runtime.GetMethod("Start", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, new[] { directory, (object)library, files, configuration, _jobHttp, users })!;
        return new { Started = true, CatalogTransport = "Controlled synthetic key/channel; real media extraction" };
    }
    internal static async Task<object> StopJobs()
    {
        if(_jobs == null) return new { Stopped = true };
        var jobs = _jobs; jobs.Dispose();
        await (Task)Call(jobs, "DrainAsync");
        _jobs = null; _jobHttp?.Dispose(); _jobHttp = null;
        return new { Stopped = true };
    }
    private static readonly BindingFlags Flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;
    private static Type Type(string name) => AppDomain.CurrentDomain.GetAssemblies().Single(assembly => assembly.GetName().Name == "Emby.YouTubePlugin")
        .GetType("Emby.YouTubePlugin." + name, true)!;
    private static object Create(string name, params object[] args) => Activator.CreateInstance(Type(name), Flags, null, args, null)!;
    private static object Call(object value, string name, params object[] args) => value.GetType().GetMethod(name, Flags)!.Invoke(value, args)!;
    private static object Property(object value, string name) => value.GetType().GetProperty(name, Flags)!.GetValue(value)!;
    private static async Task<object> Result(object value) { await (Task)value; return Property(value, "Result"); }
    internal static async Task<object> Run(ILibraryManager library, IUserManager users,
        IFileSystem files, string ownerId, long rootId)
    {
        var owner = users.GetUserById(ownerId);
        if (owner == null || owner.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator)
            throw new ArgumentException("Controlled synthetic A only.");
        var directory = Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal");
        var snapshot = Call(Create("PersonalYouTubeStore", directory), "Prepare", owner.Id);
        var generation = (Guid)Property(snapshot, "GenerationId");
        var root = library.GetItemById(rootId);
        if (root == null || root.Name != "JournalPending_" + generation.ToString("N"))
            throw new ArgumentException("Controlled preparing root only.");
        var journal = Create("PersonalYouTubePublicationJournal", directory);
        var preparingEntry = ((System.Collections.IEnumerable)Call(journal, "Pending")).Cast<object>()
            .Single(entry => (Guid)Property(entry, "GenerationId") == generation);
        var pair = Activator.CreateInstance(Type("PersonalYouTubeNativeBindings").GetNestedType("NativeItem", BindingFlags.NonPublic)!, root.InternalId, root.Id)!;
        var preparing = Activator.CreateInstance(Type("PersonalYouTubeNativePublisher").GetNestedType("PreparingLibrary", BindingFlags.NonPublic)!, pair, Call(journal, "MediaPath", preparingEntry))!;
        var channel = ((string[])Property(snapshot, "Channels")).Single();
        var key = (string)Property(snapshot, "ApiKey");
        var handler = new CatalogHandler(channel, key);
        using var http = new HttpClient(handler);
        var catalog = Create("PersonalYouTubeCatalog", Create("PersonalYouTubeStore", directory), http);
        var buffer = Create("PersonalYouTubeVideoBuffer", directory,
            "C:/git/Emby-Youtube-Plugin/verification/PersonalChannels/bin/media-tools/yt-dlp.exe",
            Path.GetFullPath(Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "../../server/system/ffmpeg.exe")),
            "C:/Program Files/nodejs/node.exe");
        var job = Create("PersonalYouTubeInitialRefresh", directory, catalog, buffer,
            Create("PersonalYouTubeNativePublisher", directory, library), files);
        var result = await Result(Call(job, "RunAsync", owner.Id, 10, 64L * 1024 * 1024, 64L * 1024 * 1024, preparing, CancellationToken.None));
        var ids = (Array)Property(result, "Videos");
        var published = ids.Cast<object>().Single();
        var item = library.GetItemById((long)Property(published, "InternalId"));
        using var input = File.OpenRead(item.Path); using var sha = SHA256.Create();
        return new { Published = true, VideoId = Property(published, "InternalId").ToString(),
            VideoGuid = ((Guid)Property(published, "ItemId")).ToString("N"), SHA256 = Convert.ToHexString(sha.ComputeHash(input)), Bytes = input.Length,
            PersonalCatalogCalls = handler.Calls, StagingReleased = !Directory.EnumerateFiles(Path.Combine(directory, "buffer"), "*.mp4", SearchOption.AllDirectories).Any() };
    }
    private sealed class CatalogHandler : HttpMessageHandler
    {
        private readonly string _channel, _key;
        private readonly bool _boundedSample;
        internal int Calls;
        internal CatalogHandler(string channel, string key, bool boundedSample = false) { _channel = channel; _key = key; _boundedSample = boundedSample; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri!;
            var args = uri.Query.TrimStart('?').Split('&').Select(part => part.Split('=', 2))
                .ToDictionary(part => part[0], part => Uri.UnescapeDataString(part[1]));
            if (uri.Host != "www.googleapis.com")
                throw new InvalidOperationException("Unexpected personal catalog host.");
            if (_boundedSample && args["key"] == "synthetic-alpha-quota-key")
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden) {
                    Content = new StringContent(JsonSerializer.Serialize(new {
                        error = new { errors = new[] { new { reason = "quotaExceeded" } } }
                    }))
                });
            if (args["key"] != _key)
                throw new InvalidOperationException("Personal catalog request did not use the saved owner key.");
            if(_boundedSample && args.ContainsKey("pageToken")) throw new InvalidOperationException("Recent selection must not fetch full upload history.");
            Calls++;
            object data;
            var channel = _boundedSample && (args.GetValueOrDefault("id") == "UC" + new string('b', 22) || args.GetValueOrDefault("playlistId") == "UU" + new string('b', 22)) ? "UC" + new string('b', 22) : _channel;
            if (uri.AbsolutePath.EndsWith("/channels") && args["id"] == channel)
                data = new { items = new[] { new { id = channel, contentDetails = new { relatedPlaylists = new { uploads = "UU" + channel[2..] } } } } };
            else if (uri.AbsolutePath.EndsWith("/playlistItems") && args["playlistId"] == "UU" + channel[2..])
            {
                var first = new { contentDetails = new { videoId = "DTi8wZ1a1TA" }, snippet = new { channelId = channel, title = "Public upstream test video", description = "<b>Untrusted catalog description</b>" } };
                data = _boundedSample
                    ? new { items = new[] { first }.Concat(Enumerable.Range(0, 9).Select(index => new { contentDetails = new { videoId = "ABCDEF0000" + index }, snippet = new { channelId = channel, title = "Unselected older video", description = "<b>Untrusted catalog description</b>" } })).ToArray(), nextPageToken = "must-not-fetch-full-history" }
                    : (object)new { items = new[] { first } };
            }
            else throw new InvalidOperationException("Unexpected personal catalog request.");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(data)) });
        }
    }
}
