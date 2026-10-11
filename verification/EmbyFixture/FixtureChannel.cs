using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Controller.Channels;
using MediaBrowser.Controller.Net;
using MediaBrowser.Controller.Providers;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Channels;
using MediaBrowser.Model.Dto;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.MediaInfo;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;
using MediaBrowser.Model.Services;

namespace WatchStateFixture;

// Only installed into the isolated server's plugin directory. It materializes
// deterministic channel items without any YouTube requests or video downloads.
public sealed class FixturePlugin : BasePlugin<BasePluginConfiguration>
{
    public static string? DataPath;
    public FixturePlugin(IApplicationPaths paths, IXmlSerializer serializer) : base(paths, serializer)
        => DataPath = paths.DataPath;
    public override string Name => "Watch State Fixture";
    public override Guid Id => Guid.Parse("119d2fcf-b8a5-4c86-96e3-38d2c61c8832");
}

public sealed class FixtureChannel : IChannel
{
    public string Name => "Watch State Fixture";
    public string Description => "Isolated watched-folder regression fixture";
    private static bool HasFlag(string name) => File.Exists(Path.Combine(FixturePlugin.DataPath!, name));
    public string DataVersion => HasFlag("fixture-empty") ? "empty" : HasFlag("fixture-third-video") ? "three" : "two";
    public ChannelParentalRating ParentalRating => ChannelParentalRating.GeneralAudience;
    public bool IsEnabledByDefault => true;
    public string Id => "watch_state_fixture";
    public ChannelFeatures GetChannelFeatures() => new();
    public IEnumerable<ImageType> GetSupportedChannelImages() => Array.Empty<ImageType>();
    public Task<DynamicImageResponse> GetChannelImage(ImageType type, CancellationToken ct) => Task.FromResult(new DynamicImageResponse());
    public Task<ChannelItemResult> GetChannelItems(InternalChannelItemQuery query, CancellationToken ct)
    {
            ct.ThrowIfCancellationRequested();
            var items = new List<ChannelItemInfo>();
            if (string.IsNullOrEmpty(query.FolderId))
            {
                items.Add(new ChannelItemInfo { Id = "channel_x_fixture", Name = "Fixture Channel", Type = ChannelItemType.Folder,
                    FolderType = ChannelFolderType.Container, MediaType = ChannelMediaType.Video,
                    ProviderIds = new ProviderIdDictionary { ["YouTubeChannel"] = "youtube_channel_10" } });
            }
            else if (query.FolderId == "channel_x_fixture")
            {
                var count = HasFlag("fixture-empty") ? 0 : HasFlag("fixture-third-video") ? 3 : 2;
                for (var index = 1; index <= count; index++)
                {
                    var id = "fixture000" + index;
                    var path = "https://www.youtube.com/watch?v=" + id;
                    items.Add(new ChannelItemInfo { Id = id, Name = "Fixture Video " + index,
                        Type = ChannelItemType.Media, MediaType = ChannelMediaType.Video,
                        ContentType = ChannelMediaContentType.Clip,
                        ProviderIds = new ProviderIdDictionary { ["YouTube"] = id },
                        MediaSources = new List<MediaSourceInfo> { new() { Id = id, Path = path, Protocol = MediaProtocol.Http,
                            IsRemote = true, SupportsDirectPlay = true, SupportsDirectStream = false, SupportsTranscoding = false } } });
                }
            }
            return Task.FromResult(new ChannelItemResult { Items = items, TotalRecordCount = items.Count });
    }
}

[Route("/WatchStateFixture/Refresh", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class RefreshFixture : IReturnVoid { }

public sealed class FixtureService : IService
{
    private readonly IChannelManager _channels;
    private readonly ILibraryManager _library;
    private readonly IUserManager _users;
    private readonly IUserDataManager _data;
    public FixtureService(IChannelManager channels, ILibraryManager library, IUserManager users, IUserDataManager data)
        { _channels = channels; _library = library; _users = users; _data = data; }
    public Task Post(RefreshFixture request) => _channels.RefreshChannelContent(
        _channels.GetChannel<FixtureChannel>(), 3, null, CancellationToken.None);
    public object Get(FixtureDiagnostic request)
    {
        var user = _users.GetUserById(request.UserId);
        var folder = _library.GetItemList(new InternalItemsQuery { ExternalId = "channel_x_fixture", IsFolder = true }).Single();
        var scopedFolder = _library.GetItemList(new InternalItemsQuery(user) { ItemIds = new[] { folder.InternalId }, EnforceShareLevel = true, EnforceContentRestriction = true });
        var marked = _library.GetItemList(new InternalItemsQuery(user) { IsFolder = true, HasAnyProviderId = new[] { "YouTubeChannel" }, Recursive = true, EnforceShareLevel = true, EnforceContentRestriction = true });
        var children = _library.GetItemList(new InternalItemsQuery(user) { AncestorIds = new[] { folder.InternalId }, Recursive = true, EnforceShareLevel = true, EnforceContentRestriction = true });
        return new { ScopedFolders = scopedFolder.Length, MarkedFolders = marked.Length, FolderPlayed = _data.GetUserData(user, folder).Played,
            FolderKey = folder.UserDataKey, folder.ExternalId,
            Videos = children.OfType<Video>().Select(i => new { i.InternalId, i.ExternalId, i.Path, i.ParentId, Played = _data.GetUserData(user, i).Played }).ToArray() };
    }
}

[Route("/WatchStateFixture/Diagnostic", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class FixtureDiagnostic : IReturn<object> { public string UserId { get; set; } = ""; }
