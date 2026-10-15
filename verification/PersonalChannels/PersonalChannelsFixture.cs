using System.Reflection;
using System.Text.Json;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Controller.Channels;
using MediaBrowser.Controller.Net;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Plugins;
using MediaBrowser.Controller.Providers;
using MediaBrowser.Model.Channels;
using MediaBrowser.Model.Drawing;
using MediaBrowser.Model.Dto;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.MediaInfo;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

// Synthetic, isolated-server-only fixture. Never contacts YouTube or uses real keys.
public sealed class FixturePlugin : BasePlugin<BasePluginConfiguration>
{
    internal static string StatePath = "";
    public FixturePlugin(IApplicationPaths paths, IXmlSerializer serializer, IHttpServer http) : base(paths, serializer)
    {
        StatePath = Path.Combine(paths.DataPath, "personal-channels-fixture.json");
        PrivacyGuard.Prepare(http, File.Exists(StatePath + ".guard.json"));
    }
    public override string Name => "Personal Channels Fixture";
    public override Guid Id => Guid.Parse("fd19a58d-b512-4f93-84c0-d019f555819a");
}

public sealed class Profile
{
    public string Owner { get; set; } = "";
    public int Revision { get; set; } = 1;
    public string? Label { get; set; }
    public bool LocalMedia { get; set; }
}

internal static class Registry
{
    internal static readonly SemaphoreSlim Gate = new(1, 1);
    internal static PersonalChannel[] Personal = Array.Empty<PersonalChannel>();
    internal static bool Initialized;

    internal static IChannel[] Channels(IChannelManager manager)
    {
        // Inspect the installed server's registry; do not assume AddParts appends.
        for (var type = manager.GetType(); type != null; type = type.BaseType)
        foreach (var field in type.GetFields(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.DeclaredOnly))
        {
            if (field.GetValue(manager) is IEnumerable<IChannel> channels)
                return channels.ToArray();
        }
        throw new InvalidOperationException("No readable IChannel registry found.");
    }

    internal static async Task Initialize(IChannelManager manager)
    {
        await Gate.WaitAsync();
        try
        {
            if (Initialized) return;
            if (File.Exists(FixturePlugin.StatePath))
                Replace(manager, JsonSerializer.Deserialize<Profile[]>(File.ReadAllText(FixturePlugin.StatePath))!);
            Initialized = true;
        }
        finally { Gate.Release(); }
    }

    internal static void Replace(IChannelManager manager, Profile[] profiles)
    {
        var originals = Channels(manager).Where(channel => channel is not PersonalChannel).ToArray();
        Personal = profiles.Select(profile => new PersonalChannel(profile)).ToArray();
        manager.AddParts(originals.Concat(Personal));
    }
}

public sealed class EntryPoint : IServerEntryPoint
{
    private readonly IChannelManager _manager;
    private readonly IHttpServer _http;
    private readonly IAuthorizationContext _authorization;
    private readonly ILibraryManager _library;
    private readonly IUserManager _users;
    private readonly MediaBrowser.Controller.Session.ISessionManager _sessions;
    public EntryPoint(IChannelManager manager, IHttpServer http, IAuthorizationContext authorization, ILibraryManager library, IUserManager users, MediaBrowser.Controller.Session.ISessionManager sessions)
        { _manager = manager; _http = http; _authorization = authorization; _library = library; _users = users; _sessions = sessions; }
    public void Run()
    {
        if (File.Exists(FixturePlugin.StatePath + ".delay")) Thread.Sleep(4000);
        if (File.Exists(FixturePlugin.StatePath + ".guard.json"))
        {
            var json = File.ReadAllText(FixturePlugin.StatePath + ".guard.json");
            var state = json.TrimStart().StartsWith('"') ? new EnablePrivacyGuard { OwnerUserId = JsonSerializer.Deserialize<string>(json)! }
                : JsonSerializer.Deserialize<EnablePrivacyGuard>(json)!;
            PrivacyGuard.Enable(_http, _authorization, _library, _users, _sessions, state.OwnerUserId, state.OwnerUserIds, state.RootOwnerUserIds);
        }
        Registry.Initialize(_manager).GetAwaiter().GetResult();
    }
    public void Dispose() { }
}

public sealed class PersonalChannel : IChannel
{
    private readonly Profile _profile;
    // Emby also discovers an empty template through DI; Replace removes that instance.
    public PersonalChannel(Profile profile) => _profile = profile;
    public string Name => "Personal Fixture " + (_profile.Label ?? _profile.Owner);
    public string Description => "Synthetic per-owner channel lifecycle test";
    public string Id => "personal_fixture_" + _profile.Owner;
    public string DataVersion => _profile.Revision.ToString();
    public ChannelParentalRating ParentalRating => ChannelParentalRating.GeneralAudience;
    public bool IsEnabledByDefault => false;
    public ChannelFeatures GetChannelFeatures() => new();
    public IEnumerable<ImageType> GetSupportedChannelImages() => Array.Empty<ImageType>();
    public Task<DynamicImageResponse> GetChannelImage(ImageType type, CancellationToken ct)
        => Task.FromResult(new DynamicImageResponse());
    internal readonly List<long> ObservedUserIds = new();
    internal string? SelectedCredentialOwner;

    public Task<ChannelItemResult> GetChannelItems(InternalChannelItemQuery query, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        lock (ObservedUserIds) ObservedUserIds.Add(query.UserId);
        SelectedCredentialOwner = _profile.Owner; // Simulates owner-bound credential resolution.
        var items = new List<ChannelItemInfo>();
        if (string.IsNullOrEmpty(query.FolderId))
            items.Add(new ChannelItemInfo { Id = "root", Name = Name + " Root", Type = ChannelItemType.Folder,
                FolderType = ChannelFolderType.Container, MediaType = ChannelMediaType.Video });
        else if (query.FolderId == "root")
        {
            var ids = new[] { "shared00001", "unique_" + _profile.Owner };
            if (_profile.Revision > 1) ids = ids.Append("added_" + _profile.Owner).ToArray();
            foreach (var id in ids)
                items.Add(new ChannelItemInfo { Id = id, Name = "Personal Video " + id,
                    Type = ChannelItemType.Media, MediaType = ChannelMediaType.Video, ContentType = ChannelMediaContentType.Clip,
                    ProviderIds = new ProviderIdDictionary { ["YouTube"] = id },
                    Genres = new List<string> { "PrivateFixtureGenre_" + _profile.Owner, "SharedFixtureGenre" },
                    Studios = new List<string> { "PrivateFixtureStudio_" + _profile.Owner, "SharedFixtureStudio" },
                    Tags = new List<string> { "PrivateFixtureTag_" + _profile.Owner, "SharedFixtureTag" },
                    MediaSources = new List<MediaSourceInfo> { new() { Id = id,
                        Path = _profile.LocalMedia ? Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "personal-fixture.mp4") : "https://www.youtube.com/watch?v=" + id,
                        Protocol = _profile.LocalMedia ? MediaProtocol.File : MediaProtocol.Http,
                        Container = _profile.LocalMedia ? "mp4" : null,
                        IsRemote = !_profile.LocalMedia, SupportsDirectPlay = true,
                        SupportsDirectStream = _profile.LocalMedia, SupportsTranscoding = _profile.LocalMedia,
                        RunTimeTicks = _profile.LocalMedia ? TimeSpan.FromSeconds(6).Ticks : null,
                        MediaStreams = _profile.LocalMedia ? new List<MediaStream> {
                            new() { Type = MediaStreamType.Video, Codec = "h264", Index = 0, Width = 160, Height = 90, BitRate = 100000 },
                            new() { Type = MediaStreamType.Audio, Codec = "aac", Index = 1, Channels = 2, SampleRate = 44100, BitRate = 64000 }
                        } : new List<MediaStream>() } } });
        }
        return Task.FromResult(new ChannelItemResult { Items = items, TotalRecordCount = items.Count });
    }
}

[Route("/PersonalChannelsFixture/State", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class GetState : IReturn<object> { }

[Route("/PersonalChannelsFixture/Configure", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class Configure : IReturn<object>
{
    public Profile[] Profiles { get; set; } = Array.Empty<Profile>();
    public bool Prune { get; set; }
}

[Route("/PersonalChannelsFixture/Surface", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class Surface : IReturn<object> { }

[Route("/PersonalChannelsFixture/LiveStreamSurface", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class LiveStreamSurface : IReturn<object> { }

[Route("/PersonalChannelsFixture/NativeFixtureDynamicSource", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeFixtureDynamicSource : IReturn<object> { public long ItemKey { get; set; } }

[Route("/PersonalChannelsFixture/NativeFixtureStreamActivity", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeFixtureStreamActivity : IReturn<object> { }

[Route("/PersonalChannelsFixture/NativeReferenceStatus", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeReferenceStatus : IReturn<object> { public string Candidate { get; set; } = ""; }

[Route("/PersonalChannelsFixture/ApproveFixtureRootDeletion", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class ApproveFixtureRootDeletion : IReturn<object> { public long RootKey { get; set; } }

[Route("/PersonalChannelsFixture/DeleteGrownFixtureVideo", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class DeleteGrownFixtureVideo : IReturn<object> { public long ItemKey { get; set; } }

[Route("/PersonalChannelsFixture/NativeFixtureStreamProbe", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeFixtureStreamProbe : IReturn<object> { public int DelayMs { get; set; } }

[Route("/PersonalChannelsFixture/NativeRootProbe", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeRootProbe : IReturn<object> { }

[Route("/PersonalChannelsFixture/NativeRecreatedRootProbe", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeRecreatedRootProbe : IReturn<object> { }

[Route("/PersonalChannelsFixture/NativeSyncJobProbe", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeSyncJobProbe : IReturn<object> { public long JobKey { get; set; } }

[Route("/PersonalChannelsFixture/NativeSyncItemProbe", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeSyncItemProbe : IReturn<object> { public long JobKey { get; set; } public long ItemKey { get; set; } }

[Route("/PersonalChannelsFixture/NativeSyncWriteGate", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeSyncWriteGateRequest : IReturn<object> { public long SourceKey { get; set; } public bool Release { get; set; } public bool Converted { get; set; } }

[Route("/PersonalChannelsFixture/NativeVideoAliases", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeVideoAliases : IReturn<object> { public long ItemKey { get; set; } }
[Route("/PersonalChannelsFixture/NativeSyncInputTrace", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeSyncInputTrace : IReturn<object> { }
[Route("/PersonalChannelsFixture/NativeVisibilityTrace", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeVisibilityTrace : IReturn<object> {
    public bool Reset { get; set; }
    public long ItemKey { get; set; }
    public string UserKey { get; set; } = "";
}
[Route("/PersonalChannelsFixture/NativeJobsSnapshot", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeJobsSnapshot : IReturn<object> { public string UserKey { get; set; } = ""; }

[Route("/PersonalChannelsFixture/NotifyNative", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class NotifyNative : IReturn<object> {
    public string UserA { get; set; } = "";
    public string UserB { get; set; } = "";
    public string Stamp { get; set; } = "";
}

[Route("/PersonalChannelsFixture/DenyShares", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class DenyShares : IReturn<object> { public string UserId { get; set; } = ""; }

[Route("/PersonalChannelsFixture/Notify", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class NotifyFixture : IReturn<object> {
    public string OtherUserId { get; set; } = "";
    public string OwnerUserId { get; set; } = "";
}

[Route("/PersonalChannelsFixture/StreamedMetadata", "GET")]
[Authenticated]
public sealed class StreamedMetadata : IReturn<object> { public string Style { get; set; } = "json"; }

[Route("/PersonalChannelsFixture/Subject", "GET")]
[Authenticated]
public sealed class SubjectProbe : IReturn<object> { }

[Route("/PersonalChannelsFixture/YouTubeSourceNormalization", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class YouTubeSourceNormalizationProbe : IReturn<object> { }

[Route("/PersonalChannelsFixture/NewRootIdentity", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NewRootIdentityProbe : IReturn<object> { public string Name { get; set; } = ""; }

[Route("/PersonalChannelsFixture/NativeCreationInspection", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeCreationInspectionProbe : IReturn<object> { }

[Route("/PersonalChannelsFixture/NativeAssetProcessingInspection", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeAssetProcessingInspectionProbe : IReturn<object> { public bool Counts { get; set; } public bool Metadata { get; set; } public bool Search { get; set; } public bool History { get; set; } public bool Libraries { get; set; } public bool Videos { get; set; } }

[Route("/PersonalChannelsFixture/NativeImageProducerProbe", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeImageProducerProbeRequest : IReturn<object>
{
    public bool CachePathFault { get; set; }
    public string OwnerUserId { get; set; } = "";
    public string ForeignOwnerUserId { get; set; } = "";
    public long ItemId { get; set; }
    public long ForeignItemId { get; set; }
}

[Route("/PersonalChannelsFixture/NativeBoundaryInspection", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeBoundaryInspectionProbe : IReturn<object> { }

[Route("/PersonalChannelsFixture/ProductionServiceGate", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class ProductionServiceGateProbe : IReturn<object> { public bool DisableExperimentalGuard { get; set; } }

[Route("/PersonalChannelsFixture/ProductionItemList", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class ProductionItemListProbe : IReturn<object> { public bool RemoveForNativeBaseline { get; set; } }

[Route("/PersonalChannelsFixture/TransferLease", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class TransferLeaseProbe : IReturn<object> { public Guid OwnerUserId { get; set; } }

[Route("/PersonalChannelsFixture/NativeReferenceWriteGate", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeReferenceWriteGateProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; public bool Release { get; set; } public bool Playback { get; set; } public bool Download { get; set; } public bool Video { get; set; } public string Asset { get; set; } = ""; public bool AfterCheck { get; set; } }

[Route("/PersonalChannelsFixture/NativeStaticFactoryTrace", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeStaticFactoryTraceProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; public long ItemId { get; set; } public long ForeignItemId { get; set; } public string Asset { get; set; } = ""; }

[Route("/PersonalChannelsFixture/NativeListInventoryGate", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeListInventoryGateProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; public bool Release { get; set; } }

[Route("/PersonalChannelsFixture/NativeListResultGate", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeListResultGateProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; public bool Release { get; set; } }

[Route("/PersonalChannelsFixture/NativeListWriteGate", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeListWriteGateProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; public bool Release { get; set; } public bool AfterCheck { get; set; } }

[Route("/PersonalChannelsFixture/ProductionCreationGuard", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class ProductionCreationGuardProbe : IReturn<object> { public bool RemovePrefix { get; set; } public string OwnerUserId { get; set; } = ""; }

[Route("/PersonalChannelsFixture/NativeAccessDecision", "GET")]
public sealed class NativeAccessDecisionProbe : IReturn<object> { public string Reference { get; set; } = ""; }

[Route("/PersonalChannelsFixture/NativeAbsentSubjectDecision", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeAbsentSubjectDecisionProbe : IReturn<object> { public string Reference { get; set; } = ""; }

[Route("/PersonalChannelsFixture/NativeContextCreate", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeContextCreateProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; public string Name { get; set; } = ""; }

[Route("/PersonalChannelsFixture/NativeCreationGate", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeCreationGateProbe : IReturn<object> { public string Name { get; set; } = ""; public bool Release { get; set; } public bool ReserveIdentity { get; set; } }

[Route("/PersonalChannelsFixture/ProductionNativeBindings", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class ProductionNativeBindingsProbe : IReturn<object>
{
    public long RootKey { get; set; }
    public string OwnerUserId { get; set; } = "";
    public bool Enable { get; set; }
    public string JournalAction { get; set; } = "";
}

[Route("/PersonalChannelsFixture/NativeSearchHistory", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeSearchHistoryProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; }

[Route("/PersonalChannelsFixture/NativeUserData", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class NativeUserDataProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; public long ItemId { get; set; } }

[Route("/PersonalChannelsFixture/NativeSearchMutationGate", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeSearchMutationGateProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; public bool Release { get; set; } public bool AfterCheck { get; set; } }

[Route("/PersonalChannelsFixture/BufferedPublication", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class BufferedPublicationProbe : IReturn<object> { public string OwnerUserId { get; set; } = ""; public long RootKey { get; set; } }

[Route("/PersonalChannelsFixture/PersonalJobs", "POST,DELETE")]
[Authenticated(Roles = "Admin")]
public sealed class PersonalJobsProbe : IReturn<object> { }

public sealed partial class FixtureService : IService, IRequiresRequest
{
    public object Post(PersonalJobsProbe request) => ProductionBufferedPublication.StartJobs(_library, _files, _users);
    public Task<object> Delete(PersonalJobsProbe request) => ProductionBufferedPublication.StopJobs();
    public object Get(NativeUserDataProbe request)
    {
        var user = _users.GetUserById(request.OwnerUserId);
        var item = _library.GetItemById(request.ItemId);
        if(user == null || user.Policy.IsAdministrator || user.Name is not ("native-privacy-fixture-a" or "native-privacy-fixture-b")
            || item == null || Path.GetFileName(item.Path) != "DTi8wZ1a1TA.mp4"
            || !Path.GetFullPath(item.Path).StartsWith(Path.GetFullPath(Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal", "media")) + Path.DirectorySeparatorChar))
            throw new ArgumentException("Synthetic published video state only");
        var getter = typeof(IUserDataManager).GetMethods().Single(method => method.Name == "GetUserData"
            && method.GetParameters().Select(parameter => parameter.ParameterType).SequenceEqual(new[] { typeof(User), typeof(BaseItem), typeof(CancellationToken) }));
        var data = getter.Invoke(_historyData, new object[] { user, item, CancellationToken.None })!;
        object? Field(string name) => data.GetType().GetProperty(name)!.GetValue(data);
        return new { Played = Field("Played"), PlayCount = Field("PlayCount"), PlaybackPositionTicks = Field("PlaybackPositionTicks"), IsFavorite = Field("IsFavorite") };
    }
    public Task<object> Post(BufferedPublicationProbe request) => ProductionBufferedPublication.Run(_library, _users, _files, request.OwnerUserId, request.RootKey);
    public object Get(NativeSearchMutationGateProbe request) => NativeSearchMutationGate.Snapshot();
    public object Post(NativeSearchMutationGateProbe request) => request.Release ? NativeSearchMutationGate.Release()
        : NativeSearchMutationGate.Arm(_users, _authorization, _http, request.OwnerUserId, request.AfterCheck);
    public object Get(NativeSearchHistoryProbe request)
    {
        var user = _users.GetUserById(request.OwnerUserId);
        if(user == null || user.Policy.IsAdministrator || user.Name is not ("native-privacy-fixture-a" or "native-privacy-fixture-b"))
            throw new ArgumentException("Synthetic history subjects only");
        var query = new InternalItemsQuery { User = user, Recursive = true, IncludeItemTypes = new[] { "Video" } };
        var searched = typeof(InternalItemsQuery).GetProperty("WasSearched");
        if(searched == null || searched.PropertyType != typeof(bool?) || !searched.CanWrite)
            throw new InvalidOperationException("Native WasSearched query contract missing");
        searched.SetValue(query, true);
        var items = _library.GetItemList(query);
        if(items.Any(item => item.Name is not ("PrivateNativeVideo_a_client" or "PrivateNativeVideo_b_client")))
            throw new InvalidOperationException("Unexpected history fixture item");
        var getter = typeof(IUserDataManager).GetMethods().Single(method => method.Name == "GetUserData"
            && method.GetParameters().Select(parameter => parameter.ParameterType).SequenceEqual(new[] { typeof(User), typeof(BaseItem), typeof(CancellationToken) }));
        var date = getter.ReturnType.GetProperty("DateLastSearched");
        if(date?.PropertyType != typeof(DateTimeOffset?)) throw new InvalidOperationException("Native search date contract missing");
        var entries = items.OrderBy(item => item.InternalId).Select(item => {
            var value = getter.Invoke(_historyData, new object[] { user, item, CancellationToken.None })!;
            return new { Id = item.InternalId.ToString(System.Globalization.CultureInfo.InvariantCulture), Date = ((DateTimeOffset?)date.GetValue(value))?.ToString("o") ?? "" };
        }).ToArray();
        return new { UserId = user.Id.ToString("N"), Ids = entries.Select(entry => entry.Id).ToArray(), Entries = entries };
    }
    public object Get(NativeCreationInspectionProbe request) => NativeCreationInspection.Read(_library);
    public object Get(NativeAssetProcessingInspectionProbe request)
    {
        try { return NativeAssetProcessingInspection.Read(request.Counts, request.Metadata, request.Search, request.History, request.Libraries, request.Videos); }
        catch(Exception error) { return new { InspectionError = error.GetType().FullName, StaticStack = error.StackTrace }; }
    }
    public object Get(NativeImageProducerProbeRequest request) => NativeImageProducerProbe.Snapshot();
    public object Post(NativeImageProducerProbeRequest request) => NativeImageProducerProbe.Arm(_users, _library, _authorization, _http,
        request.OwnerUserId, request.ForeignOwnerUserId, request.ItemId, request.ForeignItemId, request.CachePathFault);
    public object Get(NativeBoundaryInspectionProbe request) => NativeBoundaryInspection.Read(_http, _library, Request.Response, _results);
    public object Get(NativeListWriteGateProbe request) => NativeListWriteGate.Snapshot();
    public object Post(NativeListWriteGateProbe request) => request.Release ? NativeListWriteGate.Release() : NativeListWriteGate.Arm(_users, request.OwnerUserId, request.AfterCheck);
    public object Get(ProductionServiceGateProbe request) => ProductionBindingBridge.ServiceGateStatus();
    public object Get(ProductionItemListProbe request) => ProductionBindingBridge.ItemListStatus();
    public object Get(TransferLeaseProbe request) => ProductionBindingBridge.TransferStatus(request.OwnerUserId);
    public object Get(NativeReferenceWriteGateProbe request) => NativeReferenceWriteGate.Snapshot();
    public object Get(NativeStaticFactoryTraceProbe request) => NativeStaticFactoryTrace.Snapshot();
    public object Post(NativeStaticFactoryTraceProbe request) => NativeStaticFactoryTrace.Arm(_users, _library, _authorization, _results, request.OwnerUserId, request.ItemId, request.ForeignItemId, request.Asset);
    public object Post(NativeReferenceWriteGateProbe request) => request.Release ? NativeReferenceWriteGate.Release() : NativeReferenceWriteGate.Arm(_users, _authorization, request.OwnerUserId, _http, request.Playback, request.Download, request.Video, request.Asset, request.AfterCheck);
    public object Get(NativeListInventoryGateProbe request) => NativeListInventoryGate.Snapshot();
    public object Get(NativeListResultGateProbe request) => NativeListResultGate.Snapshot();
    public object Post(NativeListResultGateProbe request) => request.Release ? NativeListResultGate.Release() : NativeListResultGate.Arm(_users, request.OwnerUserId);
    public object Post(NativeListInventoryGateProbe request) => request.Release ? NativeListInventoryGate.Release() : NativeListInventoryGate.Arm(_users, request.OwnerUserId);
    public object Post(ProductionItemListProbe request)
    {
        if (request.RemoveForNativeBaseline)
        {
            if (Directory.Exists(Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal")))
                throw new InvalidOperationException("Native baseline requires no private profiles or bindings");
            new HarmonyLib.Harmony("isolated-native-list-baseline").UnpatchAll("emby.youtubeplugin.personal-item-list");
        }
        return ProductionBindingBridge.ItemListStatus();
    }
    public object Post(ProductionServiceGateProbe request)
    {
        if (request.DisableExperimentalGuard) PrivacyGuard.DisableForProductionServiceVerification();
        return new { Production = ProductionBindingBridge.ServiceGateStatus(), ExperimentalEnabled = PrivacyGuard.Enabled };
    }
    public object Get(ProductionCreationGuardProbe request) => ProductionBindingBridge.CreationGuardStatus();
    public object Get(NativeAccessDecisionProbe request) => ProductionBindingBridge.DecideRequest(Request, _authorization, _library, request.Reference);
    public object Get(NativeAbsentSubjectDecisionProbe request) => ProductionBindingBridge.DecideWithoutUser(_library, request.Reference);
    public object Post(ProductionCreationGuardProbe request)
    {
        if (request.RemovePrefix)
        {
            var owner = _users.GetUserById(request.OwnerUserId);
            if (owner == null || owner.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator)
                throw new ArgumentException("Synthetic client fixture required");
            var create = _library.GetType().GetMethod("CreateItem", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                null, new[] { typeof(BaseItem), typeof(BaseItem), typeof(BaseItem[]) }, null)!;
            new HarmonyLib.Harmony("isolated-creation-hook-loss").Unpatch(create, HarmonyLib.HarmonyPatchType.Prefix,
                "emby.youtubeplugin.personal-native-creation");
        }
        return ProductionBindingBridge.VerifyCreationGuardRequirement(_library);
    }
    public object Post(NativeContextCreateProbe request) => ProductionBindingBridge.CreateNativeWithContext(_library, _users, request.OwnerUserId, request.Name);
    public object Get(NativeCreationGateProbe request) => NativeCreationGate.Snapshot(_library);
    public object Post(NativeCreationGateProbe request) => request.Release ? NativeCreationGate.Release() : NativeCreationGate.Arm(_library, request.Name, request.ReserveIdentity);
    public object Get(NewRootIdentityProbe request)
    {
        if (!request.Name.StartsWith("JournalPending_", StringComparison.Ordinal)
            || !Guid.TryParseExact(request.Name.Substring("JournalPending_".Length), "N", out _)) throw new ArgumentException("Only a controlled journal test root.");
        var folder = _library.GetVirtualFolders().SingleOrDefault(value => value.Name == request.Name);
        if (folder == null) return new { Exists = false };
        var native = _library.GetItemById(long.Parse(folder.ItemId))!;
        return new { Exists = true, InternalId = native.InternalId, Guid = native.Id.ToString("N"), Locations = folder.Locations };
    }
    public object Post(ProductionNativeBindingsProbe request) => request.Enable
        ? ProductionBindingBridge.Enable()
        : request.JournalAction.Length != 0 ? ProductionBindingBridge.Publication(_library, _users, request.RootKey, request.OwnerUserId, request.JournalAction)
        : ProductionBindingBridge.Register(_library, _users, request.RootKey, request.OwnerUserId);
    public object Get(NativeSyncWriteGateRequest request) => NativeSyncWriteGate.Snapshot();
    public object Post(NativeSyncWriteGateRequest request) => request.Release ? NativeSyncWriteGate.Release() : NativeSyncWriteGate.Arm(_library, request.SourceKey, request.Converted);
    public object Get(NativeReferenceStatus request) => PrivacyGuard.ReferenceStatus(request.Candidate);
    public object Post(ApproveFixtureRootDeletion request) => PrivacyGuard.ApproveFixtureRootDelete(request.RootKey);
    public object Post(DeleteGrownFixtureVideo request) {
        var item = _library.GetItemById(request.ItemKey);
        var suffix = string.Join(Path.DirectorySeparatorChar, "verification", "PersonalChannels", "bin", "native-client", "a", "PrivateNativeVideo_a_grown.mp4");
        if (item is not Video || item.Name != "PrivateNativeVideo_a_grown" || string.IsNullOrEmpty(item.Path)
            || !Path.GetFullPath(item.Path).EndsWith(Path.DirectorySeparatorChar + suffix, StringComparison.OrdinalIgnoreCase)
            || !_library.GetCollectionFolders(item).Any(root => root.Name == "Private Native Fixture a"))
            throw new ArgumentException("Only the isolated grown fixture video can be deleted");
        var file = item.Path;
        _library.DeleteItem(item, new DeleteOptions { DeleteFileLocation = true });
        return new { Deleted = true, NativeItemGone = _library.GetItemById(request.ItemKey) == null, MediaFileGone = !File.Exists(file), GuidReference = item.Id.ToString("N") };
    }
    private readonly IMediaSourceManager _mediaSources;
    public object Post(NativeFixtureStreamProbe request) {
        if (request.DelayMs < 0 || request.DelayMs > 1500) throw new ArgumentException("Invalid probe delay.");
        return FixtureLiveActivity.Probe(true, request.DelayMs);
    }
    public object Get(NativeFixtureStreamActivity request) {
        var field = _mediaSources.GetType().GetField("_openStreams", BindingFlags.Instance | BindingFlags.NonPublic)!;
        var table = (System.Collections.IEnumerable)field.GetValue(_mediaSources)!;
        var streams = table.Cast<object>().Select(entry => (ILiveStream)entry.GetType().GetProperty("Value")!.GetValue(entry)!)
            .Select(stream => stream.MediaSource.Name).Where(name => name is "PrivateNativeVideo_a_client" or "PrivateNativeVideo_b_client" or "PrivateNativeVideo_a_grown")
            .GroupBy(name => name).ToDictionary(group => group.Key, group => group.Count());
        return new { Probe = FixtureLiveActivity.Probe(), NativeOpenStreams = streams, ProviderOpenCalls = FixtureLiveActivity.Opens.ToArray().ToDictionary(pair => pair.Key, pair => pair.Value),
            ProviderCloseCalls = FixtureLiveActivity.Closes.ToArray().ToDictionary(pair => pair.Key, pair => pair.Value),
            SourceDeniedOpenCalls = FixtureLiveActivity.SourceDenials.ToArray().ToDictionary(pair => pair.Key, pair => pair.Value) };
    }
    private readonly IChannelManager _manager;
    private readonly ILibraryManager _library;
    private readonly IHttpServer _http;
    private readonly IUserManager _users;
    private readonly MediaBrowser.Controller.Session.ISessionManager _sessions;
    private readonly IHttpResultFactory _results;
    private readonly IAuthorizationContext _authorization;
    private readonly IUserDataManager _historyData;
    private readonly MediaBrowser.Model.IO.IFileSystem _files;
    public IRequest Request { get; set; } = null!;
    public FixtureService(IChannelManager manager, ILibraryManager library, IHttpServer http, IUserManager users,
        MediaBrowser.Controller.Session.ISessionManager sessions, IHttpResultFactory results, IAuthorizationContext authorization, IMediaSourceManager mediaSources, IUserDataManager historyData, MediaBrowser.Model.IO.IFileSystem files)
        { _manager = manager; _library = library; _http = http; _users = users; _sessions = sessions; _results = results; _authorization = authorization; _mediaSources = mediaSources; _historyData = historyData; _files = files; }
    public async Task<object> Get(NativeFixtureDynamicSource request) {
        var item = _library.GetItemById(request.ItemKey) ?? throw new ArgumentException("Missing fixture item.");
        var provider = DispatchProxy.Create<IMediaSourceProvider, FixtureLiveProviderProxy>();
        ((FixtureLiveProviderProxy)(object)provider).Provider = new FixtureLiveSourceProvider(_library);
        if ((await provider.GetMediaSources(item, CancellationToken.None)).Count != 1) throw new ArgumentException("Not a local fixture video.");
        var type = _mediaSources.GetType();
        var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        var providers = (IMediaSourceProvider[])type.GetField("_providers", flags)!.GetValue(_mediaSources)!;
        if (!providers.Any(part => part is FixtureLiveProviderProxy))
            type.GetMethod("AddParts", flags)!.Invoke(_mediaSources, new object[] {providers.Append(provider).ToArray()});
        var method = type.GetMethods(flags).Single(candidate => candidate.Name == "GetDynamicMediaSources"
            && candidate.GetParameters().Length == 3 && candidate.GetParameters()[1].ParameterType == typeof(IMediaSourceProvider));
        return (await (Task<IEnumerable<MediaSourceInfo>>)method.Invoke(_mediaSources, new object[] {item, provider, CancellationToken.None})!).ToArray();
    }
    public object Get(YouTubeSourceNormalizationProbe request) {
        // Invoke the loaded production methods on a synthetic source. No media
        // request, YouTube API call, configuration change or playback occurs.
        var assembly=AppDomain.CurrentDomain.GetAssemblies().Single(loaded => loaded.GetName().Name == "Emby.YouTubePlugin");
        var channelType=assembly.GetType("Emby.YouTubePlugin.YouTubeChannel",true)!;
        var flags=BindingFlags.Static | BindingFlags.NonPublic;
        var source=((IEnumerable<MediaSourceInfo>)channelType.GetMethod("MakeMediaSources",flags)!
            .Invoke(null,new object[] {"shared00001",false})!).Single();
        var interceptor=assembly.GetType("Emby.YouTubePlugin.PlaybackIntentInterceptor",true)!;
        var native=(bool)interceptor.GetMethod("IsLikelyNativeTheaterClient",flags)!
            .Invoke(null,new object[] {Request})!;
        var contextType=assembly.GetType("Emby.YouTubePlugin.PlaybackInfoPatchContext",true)!;
        var context=Activator.CreateInstance(contextType,new object[] {
            "synthetic-normalization",Request.Headers["X-Emby-Client"] ?? "",
            "Isolated probe",Request.UserAgent ?? "","127.0.0.1","",0L,false,true,false,false,native})!;
        var before=new {source.SupportsDirectPlay,source.SupportsDirectStream,source.SupportsTranscoding,source.RequiresOpening,source.RequiresClosing};
        interceptor.GetMethod("NormalizeYouTubeMediaSources",flags)!
            .Invoke(null,new object[] {new {MediaSources=new[] {source}},"shared00001",context});
        return new {NativeTheaterDetected=native,Before=before,After=new {
            source.SupportsDirectPlay,source.SupportsDirectStream,source.SupportsTranscoding,
            source.RequiresOpening,source.RequiresClosing,HasTranscodingUrl=!string.IsNullOrEmpty(source.TranscodingUrl),
            PathIsYouTubeWatchUrl=source.Path.StartsWith("https://www.youtube.com/watch",StringComparison.Ordinal),
            HasAnyAdvertisedNativePlayback=source.SupportsDirectPlay || source.SupportsDirectStream || source.SupportsTranscoding}};
    }
    public async Task<object> Post(NotifyNative request) {
        var a = _users.GetUserById(request.UserA);
        var b = _users.GetUserById(request.UserB);
        if (a.Name != "native-privacy-fixture-a" || b.Name != "native-privacy-fixture-b" || !Guid.TryParse(request.Stamp, out _))
            throw new ArgumentException("Only isolated native fixture subjects are permitted.");
        var roots = _library.GetItemList(new InternalItemsQuery { IsFolder = true, Recursive = true })
            .Where(item => item.Name.StartsWith("Private Native Fixture ", StringComparison.Ordinal)).ToArray();
        var videos = roots.SelectMany(root => _library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { root.InternalId }, Recursive = true }))
            .OfType<Video>().Select(video => video.InternalId.ToString()).Distinct().ToArray();
        await _sessions.SendMessageToUserSessions(new[] { a.InternalId, b.InternalId }, "LibraryChanged", new {
            ItemsAdded = videos.Concat(new[] { "25" }).ToArray(), ItemsUpdated = videos,
            FoldersAddedTo = roots.Select(root => root.InternalId.ToString()).ToArray(),
            FixtureControlStamp = request.Stamp
        }, CancellationToken.None);
        return new { Sent = true };
    }
    public object Get(NativeVideoAliases request) {
        var item = _library.GetItemById(request.ItemKey);
        if (item is not Video || item.Name is not ("PrivateNativeVideo_a_1" or "PrivateNativeVideo_b_1"))
            throw new ArgumentException("Only the synthetic native first videos are permitted.");
        return new { Numeric = item.InternalId.ToString(), GuidN = item.Id.ToString("N"), GuidD = item.Id.ToString("D") };
    }    public object Get(NativeSyncInputTrace request) => PrivacyGuard.NativeSyncInputSnapshot();
    public object Get(NativeVisibilityTrace request) {
        PrivacyGuard.NativeVisibilitySnapshot(request.Reset);
        if (request.ItemKey != 0) {
            var item=_library.GetItemById(request.ItemKey);
            var user=_users.GetUserById(request.UserKey);
            if (item is not Video || !item.Name.StartsWith("PrivateNativeVideo_", StringComparison.Ordinal)
                || user == null || !user.Name.StartsWith("native-privacy-fixture-", StringComparison.Ordinal))
                throw new ArgumentException("Only synthetic native fixture subjects are permitted.");
            var visible=item.IsVisible(user);
            var standalone=item.IsVisibleStandalone(user);
            return new { Visible=visible, Standalone=standalone, Trace=PrivacyGuard.NativeVisibilitySnapshot(false) };
        }
        return PrivacyGuard.NativeVisibilitySnapshot(false);
    }
    public object Get(NativeJobsSnapshot request) {
        var user = _users.GetUserById(request.UserKey);
        if (user.Name is not ("native-privacy-fixture-a" or "native-privacy-fixture-b")) throw new ArgumentException("Only isolated native fixture subjects are permitted.");
        var type = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Sync.SyncManager")).First(type => type != null)!;
        var manager = type.GetField("Current", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)!.GetValue(null);
        var jobsMethod = type.GetMethods().Single(method => method.Name == "GetJobs");
        var jobQuery = Activator.CreateInstance(jobsMethod.GetParameters()[0].ParameterType)!;
        var userFilter = jobQuery.GetType().GetProperty("UserId") ?? throw new InvalidOperationException("Native job user query missing.");
        userFilter.SetValue(jobQuery, Convert.ChangeType(user.InternalId, Nullable.GetUnderlyingType(userFilter.PropertyType) ?? userFilter.PropertyType, System.Globalization.CultureInfo.InvariantCulture));
        var result = jobsMethod.Invoke(manager, new[] { jobQuery, (object)CancellationToken.None })!;
        var jobs = ((System.Collections.IEnumerable)result.GetType().GetProperty("Items")!.GetValue(result)!).Cast<object>()
            .OrderBy(job => Convert.ToInt64(job.GetType().GetProperty("Id")!.GetValue(job))).ToArray();
        var state = new List<object>();
        var itemCount = 0;
        var itemsMethod = type.GetMethods().Single(method => method.Name == "GetJobItems");
        foreach (var job in jobs) {
            if (Convert.ToInt64(job.GetType().GetProperty("UserId")!.GetValue(job)) != user.InternalId) throw new InvalidOperationException("Native user query did not scope jobs.");
            var query = Activator.CreateInstance(itemsMethod.GetParameters()[0].ParameterType)!;
            var jobFilter = query.GetType().GetProperty("JobId") ?? throw new InvalidOperationException("Native item job query missing.");
            jobFilter.SetValue(query, job.GetType().GetProperty("Id")!.GetValue(job));
            var itemsResult = itemsMethod.Invoke(manager, new[] { query, (object)CancellationToken.None })!;
            var items = ((System.Collections.IEnumerable)itemsResult.GetType().GetProperty("Items")!.GetValue(itemsResult)!).Cast<object>()
                .OrderBy(item => Convert.ToInt64(item.GetType().GetProperty("Id")!.GetValue(item))).ToArray();
            itemCount += items.Length;
            state.Add(new { Job = JsonSerializer.Serialize(job, job.GetType()), Items = items.Select(item => JsonSerializer.Serialize(item, item.GetType())).ToArray() });
        }
        var bytes = System.Text.Encoding.UTF8.GetBytes(JsonSerializer.Serialize(state));
        return new { JobKeys = jobs.Select(job => job.GetType().GetProperty("Id")!.GetValue(job)!.ToString()).ToArray(), JobCount = jobs.Length, JobItemCount = itemCount, StateDigest = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)) };
    }
    public object Get(NativeSyncJobProbe request) {
        var type = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Sync.SyncManager")).First(type => type != null)!;
        var manager = type.GetField("Current", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)!.GetValue(null);
        var job = type.GetMethod("GetJob", new[] { typeof(long), typeof(CancellationToken) })!.Invoke(manager, new object[] { request.JobKey, CancellationToken.None });
        if (job == null) return new { Exists = false, SyntheticNameVerified = false };
        if (job.GetType().GetProperty("Name")?.GetValue(job)?.ToString() is not ("LibraryScanAddition_c_2" or "SyntheticMultiSourceJob_b" or "Private Native Fixture c" or "PrivateNativeVideo_a_client" or "PrivateNativeVideo_b_client"))
            throw new ArgumentException("Only the synthetic deletion job may be inspected.");
        var method = type.GetMethods().Single(candidate => candidate.Name == "GetJobItems");
        var query = Activator.CreateInstance(method.GetParameters()[0].ParameterType)!;
        query.GetType().GetProperty("JobId")!.SetValue(query, job.GetType().GetProperty("Id")!.GetValue(job));
        var result = method.Invoke(manager, new[] { query, (object)CancellationToken.None })!;
        var items = ((System.Collections.IEnumerable)result.GetType().GetProperty("Items")!.GetValue(result)!).Cast<object>().ToArray();
        var paths = items.SelectMany(item => item.GetType().GetProperties()
            .Where(property => property.PropertyType == typeof(string) && property.Name.Contains("Path", StringComparison.OrdinalIgnoreCase))
            .Select(property => property.GetValue(item) as string)
            .Append(item.GetType().GetProperty("MediaSource")?.GetValue(item)?.GetType().GetProperty("Path")?
                .GetValue(item.GetType().GetProperty("MediaSource")?.GetValue(item)) as string))
            .Where(path => !string.IsNullOrEmpty(path)
                && path.Contains(Path.Combine("verification", "PersonalChannels", "bin", "native-client") + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        return new { Exists = true, SyntheticNameVerified = true, NativeItemCount = items.Length,
            ReadyItemCount = items.Count(item => item.GetType().GetProperty("Status")?.GetValue(item)?.ToString() == "ReadyToTransfer"),
            ExistingSyntheticOutputFileCount = paths.Count(File.Exists) };
    }
    public object Get(NativeSyncItemProbe request) {
        var type = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Sync.SyncManager")).First(candidate => candidate != null)!;
        var manager = type.GetField("Current", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)!.GetValue(null);
        var item = type.GetMethod("GetJobItem", new[] { typeof(long), typeof(CancellationToken) })!
            .Invoke(manager, new object[] { request.ItemKey, CancellationToken.None });
        if (item == null) return new { Exists = false, ParentJobExists = false, ReadyToTransfer = false, KnownPrivateSourceVerified = false };
        var jobKey = Convert.ToInt64(item.GetType().GetProperty("JobId")!.GetValue(item));
        var source = item.GetType().GetProperty("ItemId")!.GetValue(item)?.ToString();
        if (jobKey != request.JobKey || source == null || !PrivacyGuard.IsKnownPrivateFixtureReference(source))
            throw new ArgumentException("Only the expected synthetic private Sync reference");
        var job = type.GetMethod("GetJob", new[] { typeof(long), typeof(CancellationToken) })!
            .Invoke(manager, new object[] { jobKey, CancellationToken.None });
        return new { Exists = true, ParentJobExists = job != null,
            ReadyToTransfer = item.GetType().GetProperty("Status")!.GetValue(item)?.ToString() == "ReadyToTransfer",
            NativeStatus = item.GetType().GetProperty("Status")!.GetValue(item)?.ToString(), KnownPrivateSourceVerified = true };
    }
    public object Get(NativeRootProbe request) {
        var root = _library.GetItemList(new InternalItemsQuery { IsFolder = true, Recursive = true })
            .SingleOrDefault(item => item.Name == "Private Native Fixture c");
        if (root == null) return new { RootKey = "", RootGuid = "", VideoKeys = Array.Empty<string>() };
        var videos = _library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { root.InternalId }, Recursive = true })
            .OfType<Video>().Select(item => item.InternalId.ToString()).ToArray();
        return new { RootKey = root.InternalId.ToString(), RootGuid = root.Id.ToString("N"), VideoKeys = videos };
    }
    public object Get(NativeRecreatedRootProbe request) {
        if (_authorization.GetAuthorizationInfo(Request).User?.Policy.IsAdministrator != true)
            throw new UnauthorizedAccessException();
        var root = _library.GetItemList(new InternalItemsQuery { IsFolder = true, Recursive = true })
            .SingleOrDefault(item => item.Name == "Private Native Fixture a");
        if (root == null) return new { Exists = false, RootKey = "", RootGuid = "", Videos = Array.Empty<object>() };
        var videos = _library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { root.InternalId }, Recursive = true })
            .OfType<Video>().Select(item => (object)new { Key = item.InternalId.ToString(), Guid = item.Id.ToString("N"), Name = item.Name,
                ParentKey = item.ParentId.ToString(), ParentGuid = _library.GetItemById(item.ParentId)?.Id.ToString("N"),
                CollectionRoots = _library.GetCollectionFolders(item).Select(folder => new { Key = folder.InternalId.ToString(), Guid = folder.Id.ToString("N"), Name = folder.Name }).ToArray() }).ToArray();
        var locationsProperty = root.GetType().GetProperty("PhysicalLocations", BindingFlags.Instance | BindingFlags.Public);
        var locations = locationsProperty?.GetValue(root) as IEnumerable<string>;
        var locationsMethod = root.GetType().GetMethod("GetPhysicalLocations", BindingFlags.Instance | BindingFlags.Public, null, Type.EmptyTypes, null);
        if (locations == null) locations = locationsMethod?.Invoke(root, null) as IEnumerable<string>;
        var nativeFolders = _library.GetVirtualFolders().Where(folder => folder.ItemId == root.InternalId.ToString()).ToArray();
        var configuredLocations = nativeFolders.SelectMany(folder => (IEnumerable<string>?)folder.Locations ?? Array.Empty<string>()).ToArray();
        return new { Exists = true, RootKey = root.InternalId.ToString(), RootGuid = root.Id.ToString("N"), Videos = videos,
            RootRuntimeType = root.GetType().FullName, RootPath = root.Path,
            PhysicalLocationsPropertyFound = locationsProperty != null, PhysicalLocationsMethodFound = locationsMethod != null,
            LocationMethodSignatures = root.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public).Where(method => method.Name.Contains("Location", StringComparison.Ordinal)).Select(method => method.ToString()).ToArray(),
            LibraryLocationMethodSignatures = _library.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public).Where(method => method.Name.Contains("VirtualFolder", StringComparison.Ordinal)).Select(method => method.ToString()).ToArray(),
            PhysicalLocations = locations?.ToArray() ?? Array.Empty<string>(), NativeVirtualFolderMatches = nativeFolders.Length, NativeConfiguredLocations = configuredLocations };
    }
    public object Get(SubjectProbe request) {
        var user = _authorization.GetAuthorizationInfo(Request).User;
        return new { UserId = user?.Id.ToString("N"), IsAdministrator = user?.Policy.IsAdministrator ?? false };
    }
    public object Get(StreamedMetadata request)
    {
        var root = _library.GetItemList(new InternalItemsQuery { IsFolder = true, Recursive = true }).OfType<Channel>()
            .Single(channel => channel.Name == "Personal Fixture a");
        var video = _library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { root.InternalId }, Recursive = true }).First(item => item is Video);
        var payload = request.Style == "xml"
            ? $"<QueryResult><Items><BaseItemDto><Id>{video.InternalId}</Id><Name>Personal Video Stream Control</Name></BaseItemDto><BaseItemDto><Id>25</Id><Name>Fixture Video 1</Name></BaseItemDto></Items><TotalRecordCount>2</TotalRecordCount></QueryResult>"
            : JsonSerializer.Serialize(new { Items = new[] { new { Id = video.InternalId.ToString(), Name = "Personal Video Stream Control" }, new { Id = "25", Name = "Fixture Video 1" } }, TotalRecordCount = 2 });
        if (request.Style == "soap") {
            var didl = $"<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><item id=\"{video.InternalId}\"><dc:title>Personal Video Stream Control</dc:title></item><item id=\"25\"><dc:title>Fixture Video 1</dc:title></item></DIDL-Lite>";
            payload = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:BrowseResponse xmlns:u=\"urn:schemas-upnp-org:service:ContentDirectory:1\"><Result>"
                + System.Security.SecurityElement.Escape(didl) + "</Result><NumberReturned>2</NumberReturned><TotalMatches>2</TotalMatches></u:BrowseResponse></s:Body></s:Envelope>";
        }
        var bytes = System.Text.Encoding.UTF8.GetBytes(payload);
        var result = _results.GetResult(Request, bytes, request.Style is "xml" or "soap" ? "application/xml" : "application/json", new Dictionary<string, string>());
        if (result.GetType().FullName != "Emby.Server.Implementations.HttpServer.StreamWriter") throw new InvalidOperationException("Unexpected streaming result shape.");
        result.GetType().GetField("SourceBytes", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)!.SetValue(result, ReadOnlyMemory<byte>.Empty);
        result.GetType().GetField("SourceStream", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)!.SetValue(result,
            new MediaBrowser.Model.IO.StreamHandler { Stream = new MemoryStream(bytes, false), Length = bytes.Length, TotalLength = bytes.Length });
        return result;
    }
    public async Task<object> Post(NotifyFixture request)
    {
        // Deterministic output-path test with the native LibraryChanged message shape.
        var channel = _library.GetItemList(new InternalItemsQuery { IsFolder = true, Recursive = true })
            .OfType<Channel>().Single(channel => channel.Name == "Personal Fixture a");
        var video = _library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { channel.InternalId }, Recursive = true })
            .First(item => item is Video);
        var publicVideo = _library.GetItemList(new InternalItemsQuery { Recursive = true, IncludeItemTypes = new[] { "Video" } })
            .First(item => item.Name.StartsWith("Fixture Video ", StringComparison.Ordinal));
        var recipient = _users.GetUserById(request.OtherUserId);
        if (recipient.Name != "fixture-second") throw new ArgumentException("Only the isolated fixture user is permitted.");
        var owner = _users.GetUserById(request.OwnerUserId);
        if (!owner.Policy.IsAdministrator) throw new ArgumentException("Only the isolated administrator is permitted.");
        var users = new[] { owner.InternalId, recipient.InternalId };
        var ids = new[] { video.InternalId.ToString(), publicVideo.InternalId.ToString() };
        await _sessions.SendMessageToUserSessions(users, "LibraryChanged", new {
            ItemsAdded = ids, ItemsUpdated = ids, ItemsRemoved = ids,
            FoldersAddedTo = new[] { channel.InternalId.ToString() },
            FoldersRemovedFrom = new[] { channel.InternalId.ToString() },
            CollectionFolders = new[] { channel.InternalId.ToString() }
        }, CancellationToken.None);
        return new { PrivateId = video.InternalId.ToString(), PrivateChannelId = channel.InternalId.ToString(), PublicId = publicVideo.InternalId.ToString() };
    }
    public object Post(DenyShares request)
    {
        var user = _users.GetUserById(request.UserId);
        var roots = _library.GetItemList(new InternalItemsQuery { IsFolder = true, Recursive = true })
            .OfType<Channel>().Where(channel => channel.Name.StartsWith("Personal Fixture ", StringComparison.Ordinal)).ToArray();
        var items = roots.SelectMany(root => _library.GetItemList(new InternalItemsQuery {
            AncestorIds = new[] { root.InternalId }, Recursive = true })).Concat(roots).DistinctBy(item => item.InternalId).ToArray();
        _library.SaveUserItemShares(items.Select(item => new UserItemShare {
            ItemId = item.InternalId, UserId = user.InternalId, ShareLevel = UserItemShareLevel.None }).ToArray());
        var levels = _library.GetShareLevels(new InternalItemsQuery(user) { ItemIds = items.Select(item => item.InternalId).ToArray() }, CancellationToken.None);
        return new { SavedItems = items.Length, ReadBackShareLevels = levels.Items };
    }
    public object Get(LiveStreamSurface request) {
        // Read-only method references, never instance fields, arguments, paths or tokens.
        var types = AppDomain.CurrentDomain.GetAssemblies()
            .Where(assembly => assembly.GetName().Name is "Emby.Server.MediaEncoding" or "Emby.Server.Implementations")
            .SelectMany(assembly => assembly.GetTypes())
            .Where(type => type.Name.Contains("MediaSourceManager", StringComparison.Ordinal)
                || type.Name.Contains("MediaInfoService", StringComparison.Ordinal)
                || type.DeclaringType?.Name.Contains("MediaSourceManager", StringComparison.Ordinal) == true
                || type.DeclaringType?.Name.Contains("MediaInfoService", StringComparison.Ordinal) == true)
            .Concat(new[] {typeof(IMediaSourceProvider), typeof(ILiveStream)});
        return types.Select(type => new {
            Type = type.FullName,
            Methods = type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
                .Select(method => new { Signature = method.ToString(), References = ReferencedMethods(method) }).ToArray()
        }).ToArray();
    }
    private static string[] ReferencedMethods(MethodInfo method, bool protocolConstants = false) {
        var bytes = method.GetMethodBody()?.GetILAsByteArray();
        if (bytes == null) return Array.Empty<string>();
        var codes = typeof(System.Reflection.Emit.OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static)
            .Where(field => field.FieldType == typeof(System.Reflection.Emit.OpCode)).Select(field => (System.Reflection.Emit.OpCode)field.GetValue(null)!)
            .ToDictionary(code => unchecked((ushort)code.Value));
        var result = new List<string>();
        for (var offset = 0; offset < bytes.Length;) {
            ushort key = bytes[offset++];
            if (key == 0xfe) key = (ushort)(0xfe00 | bytes[offset++]);
            var code = codes[key];
            var size = code.OperandType switch {
                System.Reflection.Emit.OperandType.InlineNone => 0,
                System.Reflection.Emit.OperandType.ShortInlineBrTarget or System.Reflection.Emit.OperandType.ShortInlineI or System.Reflection.Emit.OperandType.ShortInlineVar => 1,
                System.Reflection.Emit.OperandType.InlineVar => 2,
                System.Reflection.Emit.OperandType.InlineI8 or System.Reflection.Emit.OperandType.InlineR => 8,
                System.Reflection.Emit.OperandType.InlineSwitch => 4 + BitConverter.ToInt32(bytes, offset) * 4,
                _ => 4
            };
            if (code.OperandType is System.Reflection.Emit.OperandType.InlineMethod or System.Reflection.Emit.OperandType.InlineField) {
                try {
                    var member = method.Module.ResolveMember(BitConverter.ToInt32(bytes, offset), method.DeclaringType?.GetGenericArguments(), method.GetGenericArguments());
                    result.Add(offset + " " + code.Name + " " + member?.DeclaringType?.FullName + "::" + member);
                } catch { result.Add(offset + " unresolved " + code.Name); }
            }
            if (code.OperandType == System.Reflection.Emit.OperandType.InlineString) {
                var literal = method.Module.ResolveString(BitConverter.ToInt32(bytes, offset));
                if (System.Text.RegularExpressions.Regex.IsMatch(literal, "^[A-Za-z]{1,80}$")
                    && new[] { "Library", "Start", "Stop", "Sessions", "Change", "Refresh", "Scan" }.Any(word => literal.Contains(word, StringComparison.Ordinal)))
                    result.Add(offset + " literal " + literal);
                else if (protocolConstants && System.Text.RegularExpressions.Regex.IsMatch(literal, "^[A-Za-z0-9_{}:-]{1,80}$"))
                    result.Add(offset + " protocol literal " + literal);
            }
            if (code.Name == "ldc.i4") result.Add(offset + " integer " + BitConverter.ToInt32(bytes, offset));
            if (code.Name == "ldc.i4.s") result.Add(offset + " integer " + unchecked((sbyte)bytes[offset]));
            offset += size;
        }
        return result.ToArray();
    }
    private static object SyncSecuritySnapshot() {
        var type = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Sync.SyncManager")).FirstOrDefault(type => type != null);
        var manager = type?.GetField("Current", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(null);
        var security = type?.GetField("_securityManager", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(manager);
        if (security == null) return new { Available = false };
        return new { Available = true, Type = security.GetType().FullName, FeatureChecks = PrivacyGuard.ObserveSyncFeatures(security),
            Fields = security.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).Select(field => field.Name + ":" + field.FieldType.FullName).ToArray(),
            Properties = security.GetType().GetProperties().Select(property => property.Name + ":" + property.PropertyType.FullName).ToArray(),
            CachedRegistrationShapes = (security.GetType().GetField("_regRecordCache", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(security) as System.Collections.IDictionary)?
                .Values.Cast<object>().Select(record => new { Type = record.GetType().FullName,
                    Fields = record.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).Select(field => field.Name + ":" + field.FieldType.FullName).ToArray(),
                    Properties = record.GetType().GetProperties().Select(property => property.Name + ":" + property.PropertyType.FullName).ToArray() }).ToArray(),
            LocalFlags = security.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                .Where(field => field.FieldType == typeof(bool) || field.FieldType == typeof(bool?))
                .Select(field => new { field.Name, Value = field.GetValue(security) }).ToArray() };
    }
    public object Get(Surface request) => new {
        SyncSecurity = SyncSecuritySnapshot(),
        SyncTargetLookup = AppDomain.CurrentDomain.GetAssemblies().Where(assembly => assembly.GetName().Name == "Emby.Server.Sync")
            .SelectMany(assembly => assembly.GetTypes()).Where(type => type.Name == "SyncManager")
            .SelectMany(type => type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance))
            .Where(method => method.Name == "GetInternalTargetId")
            .Select(method => new { Signature = method.ToString(), Parameters = method.GetParameters().Select(parameter => parameter.Name + ":" + parameter.ParameterType.FullName).ToArray(), References = ReferencedMethods(method) }).ToArray(),
        NativeNotifications = AppDomain.CurrentDomain.GetAssemblies().Where(assembly => assembly.GetName().Name?.StartsWith("Emby.", StringComparison.Ordinal) == true)
            .SelectMany(assembly => assembly.GetTypes()).Where(type => type.Name.Contains("WebSocketListener")
                || type.FullName?.Contains("LibraryChangedNotifier") == true || type.Name.Contains("Library") && (type.Name.Contains("Changed") || type.Name.Contains("Notification")))
            .Select(type => new { type.FullName,
                Fields = type.GetFields(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic).Select(field => field.Name + ":" + field.FieldType.FullName).ToArray(),
                Methods = type.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
                    .Where(method => method.DeclaringType == type).Select(method => new { Signature = method.ToString(), References = ReferencedMethods(method) }).ToArray() }).ToArray(),
        SyncProtocolReferences = AppDomain.CurrentDomain.GetAssemblies().Where(assembly => assembly.GetName().Name == "Emby.Server.Sync")
            .SelectMany(assembly => assembly.GetTypes()).Where(type => type.Name == "SyncManager" || type.DeclaringType?.Name == "SyncManager")
            .SelectMany(type => type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            .Where(method => method.Name.Contains("SyncData", StringComparison.Ordinal) || method.Name == "GetJobItemInfo")
            .Select(method => new { Method = method.DeclaringType?.FullName + "::" + method, References = ReferencedMethods(method, true) }).ToArray(),        SyncCallReferences = AppDomain.CurrentDomain.GetAssemblies().Where(assembly => assembly.GetName().Name == "Emby.Server.Sync")
            .SelectMany(assembly => assembly.GetTypes()).Where(type => type.Name is "SyncManager" or "SyncJobProcessor" or "SyncService" || type.FullName?.Contains("SyncJobProcessor+<Sync>d__27") == true
                || type.FullName?.Contains("SyncJobProcessor+<SyncJobItems>") == true
                || type.FullName?.Contains("SyncJobProcessor+<ProcessJobItem>") == true
                || type.FullName?.Contains("SyncJobProcessor+<SyncVideo>") == true
                || type.GetInterfaces().Any(contract => contract.Name == "IScheduledTask")
                || type.DeclaringType?.GetInterfaces().Any(contract => contract.Name == "IScheduledTask") == true)
            .SelectMany(type => type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static))
            .Where(method => method.Name == "MoveNext" || method.Name is "ReportOfflineAction" or "ReportOfflinePlayedItem" or "Sync" or "Execute" or "SyncData" or "SyncDataUsingSyncJobItemIds"
                or "SetJobItemStatus" or "UpdateSyncJobItemInternal" or "OnItemReadyToTransfer"
                || method.DeclaringType?.Name == "SyncService" && method.Name is "Post" or "Get" && method.GetParameters().Any(parameter => parameter.ParameterType.Name is "GetSyncStatus" or "SyncData" or "GetReadySyncItems"))
            .Select(method => new { Method = method.DeclaringType?.FullName + "::" + method, References = ReferencedMethods(method) }).ToArray(),
        SyncModels = AppDomain.CurrentDomain.GetAssemblies().Where(assembly => assembly.GetName().Name is "Emby.Server.Sync" or "MediaBrowser.Model")
            .SelectMany(assembly => assembly.GetTypes()).Where(type => type.Name is "UserAction" or "SyncJobItem" or "SyncDataRequest" or "SyncDataResponse" or "SyncJobItemQuery" or "SyncJobQuery")
            .Select(type => new { type.FullName, Properties = type.GetProperties().Select(property => new {
                property.Name, Type = property.PropertyType.FullName,
                Values = property.PropertyType.IsEnum ? Enum.GetNames(property.PropertyType) : Array.Empty<string>() }).ToArray() }).ToArray(),
        SyncSurface = AppDomain.CurrentDomain.GetAssemblies().Where(assembly => assembly.GetName().Name == "Emby.Server.Sync")
            .SelectMany(assembly => assembly.GetTypes()).Where(type => type.Name.Contains("Manager") || type.Name.Contains("Processor") || type.Name.Contains("Repository") || type.Name == "SyncService")
            .Select(type => new { type.FullName,
                Constructors = type.GetConstructors().Select(ctor => ctor.ToString()).ToArray(),
                Methods = type.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
                    .Where(method => !method.IsSpecialName && method.DeclaringType == type).Select(method => method.ToString()).ToArray(),
                Fields = type.GetFields(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
                    .Select(field => field.Name + ":" + field.FieldType.FullName).ToArray() }).ToArray(),
        ApiRoutes = AppDomain.CurrentDomain.GetAssemblies().Where(assembly =>
                assembly.GetName().Name?.StartsWith("Emby.", StringComparison.Ordinal) == true
                || assembly.GetName().Name?.StartsWith("MediaBrowser.", StringComparison.Ordinal) == true
                || assembly.GetName().Name == "MultiMediaServices")
            .SelectMany(assembly => assembly.GetTypes())
            .SelectMany(type => type.CustomAttributes.Where(attribute => attribute.AttributeType.Name == "RouteAttribute")
                .Select(attribute => new {
                    Request = type.FullName,
                    Assembly = type.Assembly.GetName().Name,
                    Path = attribute.ConstructorArguments.FirstOrDefault().Value?.ToString(),
                    Verbs = attribute.ConstructorArguments.Skip(1).FirstOrDefault().Value?.ToString(),
                    Properties = type.GetProperties().Select(property => property.Name + ":" + property.PropertyType.FullName).ToArray(),
                    Contracts = type.GetInterfaces().Where(contract => contract.Name.StartsWith("IReturn")).Select(contract => contract.ToString()).ToArray()
                })).ToArray(),
        QueryMembers = typeof(InternalItemsQuery).GetProperties().Select(property => property.Name + ":" + property.PropertyType.FullName).ToArray(),
        CountMembers = typeof(MediaBrowser.Model.Dto.ItemCounts).GetMembers().Select(member => member.ToString()).ToArray(),
        LinkTypes = Enum.GetNames<MediaBrowser.Controller.Library.ItemLinkType>(),
        StreamMembers = typeof(MediaBrowser.Model.IO.StreamHandler).GetMembers().Select(member => member.ToString()).ToArray(),
        QueryHooks = _library.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            .Where(method => method.Name.Contains("Genre") || method.Name.Contains("Studio") || method.Name.Contains("Tag") || method.Name.StartsWith("GetItem"))
            .Select(method => method.ToString()).ToArray(),
        HttpType = _http.GetType().FullName,
        ServiceHooks = _http.GetType().Assembly.GetTypes().Where(type => type.Name is "ServiceController" or "ServiceHandler")
            .Select(type => new { type.FullName, Methods = type.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
                .Select(method => method.ToString()).ToArray() }).ToArray(),
        SocketHooks = _http.GetType().Assembly.GetTypes().Where(type => type.Name.Contains("WebSocketConnection") || type.Name == "SessionInfoWebSocketListener")
            .Select(type => new { type.FullName, Methods = type.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
                .Where(method => method.Name.Contains("Send") || method.Name.Contains("Data"))
                .Select(method => method.ToString()).ToArray() }).ToArray(),
        ResultHooks = _http.GetType().Assembly.GetTypes().Where(type => type.Name.Contains("ResultFactory") || type.Name == "StreamWriter")
            .Select(type => new { type.FullName, Methods = type.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
                .Where(method => method.Name.Contains("Result") || method.Name.Contains("Write"))
                .Select(method => method.ToString()).ToArray(), Fields = type.GetFields(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public).Select(field => field.ToString()).ToArray() }).ToArray(),
        HttpMembers = _http.GetType().GetMembers(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            .Where(member => member.Name.Contains("Filter") || member.Name.Contains("Request") || member.Name.Contains("Service") || member.Name.Contains("Handler"))
            .Select(member => member.ToString()).ToArray(),
        FilterMethod = typeof(AuthenticatedAttribute).GetMethod("RequestFilter")?.ToString(),
        LibraryMethods = _library.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            .Where(method => method.Name.Contains("Access") || method.Name.Contains("Share"))
            .Select(method => method.ToString()).ToArray(),
        ShareMembers = typeof(UserItemShare).GetMembers().Select(member => member.ToString()).ToArray(),
        ItemMembers = typeof(BaseItem).GetMembers().Where(member => member.Name.Contains("Share") || member.Name.Contains("Access"))
            .Select(member => member.ToString()).ToArray()
    };
    public async Task<object> Get(GetState request)
    {
        await Registry.Initialize(_manager);
        return State();
    }
    public async Task<object> Post(Configure request)
    {
        if (request.Profiles.Any(p => p.Owner is not ("a" or "b" or "c")))
            throw new ArgumentException("Only synthetic owners a, b and c are permitted.");
        await Registry.Initialize(_manager);
        await Registry.Gate.WaitAsync();
        try
        {
            Registry.Replace(_manager, request.Profiles);
            File.WriteAllText(FixturePlugin.StatePath, JsonSerializer.Serialize(request.Profiles));
            foreach (var channel in Registry.Personal)
                await _manager.RefreshChannelContent(channel, 3, null, CancellationToken.None);
            if (request.Prune)
            {
                var activeNames = Registry.Personal.Select(channel => channel.Name).ToHashSet();
                var stale = _library.GetItemList(new InternalItemsQuery { IsFolder = true, Recursive = true })
                    .OfType<Channel>()
                    .Where(channel => channel.Name.StartsWith("Personal Fixture ", StringComparison.Ordinal)
                        && !activeNames.Contains(channel.Name)).ToArray();
                foreach (var channel in stale)
                    _library.DeleteItem(channel, new DeleteOptions { DeleteFileLocation = false });
            }
            return State();
        }
        finally { Registry.Gate.Release(); }
    }
    private object State() => new
    {
        Registered = Registry.Channels(_manager).Select(channel => new {
            DeclaredId = channel.GetType().GetProperty("Id")?.GetValue(channel), channel.Name }).ToArray(),
        Profiles = Registry.Personal.Select(channel => new { channel.Id, channel.Name,
            channel.DataVersion, channel.SelectedCredentialOwner,
            ObservedUserIds = channel.ObservedUserIds.ToArray() }).ToArray()
    };
}
