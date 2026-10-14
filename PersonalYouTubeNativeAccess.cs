using System.Globalization;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using MediaBrowser.Model.Dto;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;
using Access = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Access;
using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;

namespace Emby.YouTubePlugin;

// Server-context resolver. Native boundary hooks must supply the actual
// authenticated User, not a request UserId, DeviceId or claimed owner.
internal sealed class PersonalYouTubeNativeAccess
{
    private static readonly MethodInfo? SourceItems = typeof(BaseItem).GetMethod("GetAllItemsForMediaSources", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
        null, new[] { typeof(User), typeof(bool) }, null);
    internal static bool StaticVideoSourceContractVerified()
    {
        try
        {
            string Hash(MethodInfo method) => Convert.ToHexString(SHA256.HashData(method.GetMethodBody()!.GetILAsByteArray()!));
            var progressive = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.MediaEncoding.Api.Progressive.BaseProgressiveStreamingService"))
                .Single(type => type != null)!;
            var process = progressive.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                .Single(method => method.Name == "ProcessRequest" && method.GetParameters().Length == 2);
            var state = process.GetCustomAttribute<AsyncStateMachineAttribute>()!.StateMachineType;
            var move = state.GetMethod("MoveNext", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)!;
            return SourceItems?.ReturnType == typeof(List<Tuple<BaseItem, MediaSourceType>>)
                && Hash(SourceItems) == "D5DB52411B126F017217D8D1CE66E60A324D522F2F33D5B6FF0F4BA01D486E81"
                && Hash(typeof(BaseItem).GetMethod("GetDefaultMediaSourceId")!) == "CD50AC8D2CB3110C3F0E52B356F4CAA4E6CE3422F3BF34E3042FE6A522C6DB22"
                && Hash(move) == "63B25855AF2D4B9E471FD2583870FA79CAAC2E9E07880CEA7A8CAA241CB7D3B6";
        }
        catch (Exception) { return false; }
    }
    // The audited native ProcessRequest normalizes original.* to Static=true
    // after ServiceController.Execute. Match that normalization before access
    // checks; source membership and the actual file reader remain protected.
    internal static bool IsOriginalStaticStream(string? streamFileName)
        => !string.IsNullOrEmpty(streamFileName)
            && string.Equals(Path.GetFileNameWithoutExtension(streamFileName), "original", StringComparison.OrdinalIgnoreCase);
    private readonly ILibraryManager _library;
    private readonly PersonalYouTubePublicationJournal _journal;
    internal PersonalYouTubeNativeAccess(string directory, ILibraryManager library)
    { _library = library; _journal = new(directory); }
    internal Access DecideRequest(IRequest request, IAuthorizationContext authorization, string reference)
        => DecideReference(reference, authorization.GetAuthorizationInfo(request).User);
    internal long[] DeniedRegisteredIds(User? authenticatedUser)
        => _journal.DeniedRegisteredIds(authenticatedUser == null || authenticatedUser.Policy.IsDisabled ? Guid.Empty : authenticatedUser.Id);
    internal Access DecideReference(string reference, User? authenticatedUser)
    {
        var item = Resolve(reference);
        return item == null ? _journal.DecideAbsentReference(reference) : DecideItem(item, authenticatedUser);
    }
    internal bool ReferenceExists(string reference) => Resolve(reference) != null;
    private BaseItem? Resolve(string reference)
    {
        BaseItem? item = null;
        if (long.TryParse(reference, NumberStyles.Integer, CultureInfo.InvariantCulture, out var numeric) && numeric > 0)
            item = _library.GetItemById(numeric);
        else if (Guid.TryParse(reference, out var guid) && guid != Guid.Empty)
            item = _library.GetItemById(guid);
        return item;
    }
    // Static native video sources only. Dynamic/live/transcoded provenance
    // needs its own audited resolver; do not treat a claimed source ID as an
    // authorization token for a private item.
    internal Access DecideStaticVideoSource(string reference, User user, bool isStatic, string sourceId, string liveStreamId)
    {
        var item = Resolve(reference);
        var decision = item == null ? _journal.DecideAbsentReference(reference) : DecideItem(item, user);
        if (decision != Access.Allowed) return decision;
        if (!isStatic || !string.IsNullOrEmpty(liveStreamId)) return Access.Denied;
        var candidates = (List<Tuple<BaseItem, MediaSourceType>>)SourceItems!.Invoke(item, new object[] { user, false })!;
        if (candidates.Count == 0 || candidates.Count > 128) return Access.Denied;
        var matching = candidates.Where(candidate => string.IsNullOrEmpty(sourceId)
            || string.Equals(candidate.Item1.GetDefaultMediaSourceId(), sourceId, StringComparison.Ordinal)).ToArray();
        if (matching.Length == 0 || matching.Any(candidate => DecideItem(candidate.Item1, user) != Access.Allowed)) return Access.Denied;
        return Access.Allowed;
    }
    internal bool StaticVideoPathAllowed(string reference, User user, string sourceId, string path)
    {
        if (DecideStaticVideoSource(reference, user, true, sourceId, "") != Access.Allowed) return false;
        var item = Resolve(reference)!;
        var candidates = (List<Tuple<BaseItem, MediaSourceType>>)SourceItems!.Invoke(item, new object[] { user, false })!;
        var canonical = Path.GetFullPath(path);
        return candidates.Any(candidate => (string.IsNullOrEmpty(sourceId)
                || string.Equals(candidate.Item1.GetDefaultMediaSourceId(), sourceId, StringComparison.Ordinal))
            && !string.IsNullOrEmpty(candidate.Item1.Path)
            && string.Equals(Path.GetFullPath(candidate.Item1.Path), canonical, StringComparison.OrdinalIgnoreCase)
            && DecideItem(candidate.Item1, user) == Access.Allowed);
    }
    internal bool AssetImageInputAllowed(string reference, User user, MediaBrowser.Model.Entities.ImageType type, int index,
        long itemId, string path)
    {
        if (DecideReference(reference, user) != Access.Allowed) return false;
        var item = _library.GetItemById(itemId);
        return item != null && DecideItem(item, user) == Access.Allowed
            && SameSourcePath(item.GetImageInfo(type, index)?.Path, path);
    }
    internal bool AssetSubtitleInputAllowed(string reference, User user, string sourceId, int index, string inputPath, string streamPath)
    {
        if (DecideStaticVideoSource(reference, user, true, sourceId, "") != Access.Allowed) return false;
        var candidates = (List<Tuple<BaseItem, MediaSourceType>>)SourceItems!.Invoke(Resolve(reference)!, new object[] { user, false })!;
        return candidates.Where(candidate => string.IsNullOrEmpty(sourceId) || candidate.Item1.GetDefaultMediaSourceId() == sourceId)
            .Any(candidate => SameSourcePath(candidate.Item1.Path, inputPath)
                && candidate.Item1.GetMediaStreams().Any(stream => stream.Type == MediaBrowser.Model.Entities.MediaStreamType.Subtitle
                    && stream.Index == index && SameSourcePath(stream.Path, streamPath, true)));
    }
    internal bool AssetDirectPathAllowed(string reference, User user, string sourceId, bool image,
        MediaBrowser.Model.Entities.ImageType type, int index, string path)
    {
        var item = Resolve(reference);
        if (item == null || DecideItem(item, user) != Access.Allowed) return false;
        if (image) return SameSourcePath(item.GetImageInfo(type, index)?.Path, path);
        if (DecideStaticVideoSource(reference, user, true, sourceId, "") != Access.Allowed) return false;
        var candidates = (List<Tuple<BaseItem, MediaSourceType>>)SourceItems!.Invoke(item, new object[] { user, false })!;
        return candidates.Where(candidate => string.IsNullOrEmpty(sourceId) || candidate.Item1.GetDefaultMediaSourceId() == sourceId)
            .Any(candidate => candidate.Item1.GetMediaStreams().Any(stream => stream.Index == index
                && stream.Type == MediaBrowser.Model.Entities.MediaStreamType.Subtitle && stream.IsExternal && SameSourcePath(stream.Path, path)));
    }
    private static bool SameSourcePath(string? first, string? second, bool emptyAllowed = false)
    {
        if (string.IsNullOrEmpty(first) || string.IsNullOrEmpty(second)) return emptyAllowed && string.IsNullOrEmpty(first) && string.IsNullOrEmpty(second);
        if (Uri.TryCreate(first, UriKind.Absolute, out var uri) && !uri.IsFile) return string.Equals(first, second, StringComparison.Ordinal);
        return string.Equals(Path.GetFullPath(first), Path.GetFullPath(second), OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
    }
    internal Access DecideItem(BaseItem item, User? authenticatedUser)
    {
        var link = MetadataLink(item);
        if(!link.HasValue) return DecideOrdinaryItem(item, authenticatedUser);
        if(authenticatedUser == null || authenticatedUser.Policy.IsDisabled) return Access.Denied;
        // Index objects have no private collection parent. Authorization
        // comes from a currently visible, permitted native content source,
        // not from the globally cached index object or its known ID.
        var query = new InternalItemsQuery { User = authenticatedUser, Recursive = true };
        if(link == ItemLinkType.Genres) query.GenreIds = new[] { item.InternalId };
        else if(link == ItemLinkType.Studios) query.StudioIds = new[] { item.InternalId };
        else query.TagIds = new[] { item.InternalId };
        var sources = PersonalYouTubeItemListGate.NativeScan(_library, query);
        return sources.Where(source => !MetadataLink(source).HasValue
                && DecideOrdinaryItem(source, authenticatedUser) != Access.Denied)
            .Any(source => _library.GetItemLinks(source.InternalId, new List<ItemLinkType> { link.Value }, CancellationToken.None)
                .Any(value => value.Item3 == item.InternalId)) ? Access.Allowed : Access.Denied;
    }
    private static ItemLinkType? MetadataLink(BaseItem item) => item.GetType().FullName switch {
        "MediaBrowser.Controller.Entities.Genre" => ItemLinkType.Genres,
        "MediaBrowser.Controller.Entities.Studio" => ItemLinkType.Studios,
        "MediaBrowser.Controller.Entities.Tag" => ItemLinkType.Tags,
        _ => null
    };
    internal string ResolveMetadataName(string dto, string name)
    {
        var kind = dto == "Emby.Api.UserLibrary.GetGenre" ? "Genre" : "Studio";
        var candidates = PersonalYouTubeItemListGate.NativeScan(_library, new InternalItemsQuery {
            IncludeItemTypes = new[] { kind }, Name = name, AllowGlobalLists = true, Recursive = true
        }).Where(item => item.GetType().Name == kind && string.Equals(item.Name, name, StringComparison.OrdinalIgnoreCase)).ToArray();
        if(candidates.Length != 1) throw new InvalidDataException("Metadata name not uniquely resolved.");
        return candidates[0].InternalId.ToString(CultureInfo.InvariantCulture);
    }
    private Access DecideOrdinaryItem(BaseItem item, User? authenticatedUser)
    {
        var owner = authenticatedUser == null || authenticatedUser.Policy.IsDisabled ? Guid.Empty : authenticatedUser.Id;
        var roots = _library.GetCollectionFolders(item).Where(root => root.InternalId != item.InternalId).Cast<BaseItem>().ToList();
        var visited = new HashSet<long> { item.InternalId };
        var current = item;
        while (current.ParentId != 0)
        {
            if (!visited.Add(current.ParentId) || visited.Count > 513) return Access.Denied;
            current = _library.GetItemById(current.ParentId);
            if (current == null) return Access.Denied;
            roots.Add(current);
        }
        var groups = roots.GroupBy(parent => parent.InternalId).ToArray();
        if (groups.Any(group => group.Select(parent => parent.Id).Distinct().Count() != 1)) return Access.Denied;
        var parents = groups.Select(group => group.First()).ToArray();
        if (parents.Length > 512) return Access.Denied;
        var rootIds = parents.Select(parent => parent.InternalId).Append(item.InternalId).ToHashSet();
        var sources = _library.GetVirtualFolders().Where(folder => long.TryParse(folder.ItemId, out var id) && rootIds.Contains(id))
            .SelectMany(folder => (IEnumerable<string>?)folder.Locations ?? Array.Empty<string>()).Append(item.Path ?? "").ToArray();
        NativeItem Pair(BaseItem value) => new(value.InternalId, value.Id);
        return _journal.DecideSources(Pair(item), parents.Select(Pair), owner, sources);
    }
}
