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
internal sealed partial class PersonalYouTubeNativeAccess
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
    private readonly string _directory;
    private readonly PersonalYouTubePublicationJournal _journal;
    internal PersonalYouTubeNativeAccess(string directory, ILibraryManager library)
    { _directory = Path.GetFullPath(directory); _library = library; _journal = new(directory); }
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
        => DecideOrdinaryItem(item, authenticatedUser, _library.GetItemById, FolderLocations(_library.GetVirtualFolders()), _journal.ReadSnapshot());
    // Native virtual-folder locations by root InternalId, in native order.
    private static Dictionary<long, string[]> FolderLocations(IEnumerable<MediaBrowser.Model.Entities.VirtualFolderInfo> folders)
        => folders.Select(folder => (Parsed: long.TryParse(folder.ItemId, out var id), Id: id, Locations: (IEnumerable<string>?)folder.Locations ?? Array.Empty<string>()))
            .Where(folder => folder.Parsed).GroupBy(folder => folder.Id)
            .ToDictionary(group => group.Key, group => group.SelectMany(folder => folder.Locations).ToArray());
    private Access DecideOrdinaryItem(BaseItem item, User? authenticatedUser, Func<long, BaseItem?> parentById,
        Dictionary<long, string[]> folderLocations, PersonalYouTubePublicationJournal.Snapshot snapshot)
    {
        var owner = authenticatedUser == null || authenticatedUser.Policy.IsDisabled ? Guid.Empty : authenticatedUser.Id;
        var roots = _library.GetCollectionFolders(item).Where(root => root.InternalId != item.InternalId).Cast<BaseItem>().ToList();
        var visited = new HashSet<long> { item.InternalId };
        var current = item;
        while (current.ParentId != 0)
        {
            if (!visited.Add(current.ParentId) || visited.Count > 513) return Access.Denied;
            current = parentById(current.ParentId);
            if (current == null) return Access.Denied;
            roots.Add(current);
        }
        var groups = roots.GroupBy(parent => parent.InternalId).ToArray();
        if (groups.Any(group => group.Select(parent => parent.Id).Distinct().Count() != 1)) return Access.Denied;
        var parents = groups.Select(group => group.First()).ToArray();
        if (parents.Length > 512) return Access.Denied;
        var rootIds = parents.Select(parent => parent.InternalId).Append(item.InternalId).ToHashSet();
        var sources = rootIds.SelectMany(id => folderLocations.TryGetValue(id, out var locations) ? locations : Array.Empty<string>())
            .Concat(parents.Select(parent => parent.Path ?? ""))
            .Append(item.Path ?? "").ToArray();
        NativeItem Pair(BaseItem value) => new(value.InternalId, value.Id);
        return snapshot.DecideSources(Pair(item), parents.Select(Pair).ToArray(), owner, sources);
    }
    // Request-scoped decisions for one list request: ledger, journal, profile
    // and virtual folders are read once; parents come from the same inventory.
    // Every item still gets the complete ordinary decision; metadata index
    // objects are decided in bulk with the same source/link rule as DecideItem.
    internal ListContext CreateListContext(User? authenticatedUser, IReadOnlyDictionary<long, BaseItem> inventory)
        => new(this, authenticatedUser, inventory);
    internal ListContext CreateListContext(User? authenticatedUser, SourceInventory inventory)
        => new(this, authenticatedUser, inventory.ById, inventory);
    internal sealed class ListContext
    {
        private readonly PersonalYouTubeNativeAccess _access;
        private readonly User? _user;
        private readonly IReadOnlyDictionary<long, BaseItem> _inventory;
        private readonly Dictionary<long, string[]> _folders;
        private readonly PersonalYouTubePublicationJournal.Snapshot _snapshot;
        private readonly Dictionary<long, Access> _ordinary = new();
        private readonly SourceInventory? _sources;
        private readonly HashSet<long>? _potential;
        private readonly string _authorityStamp;
        internal bool AuthorityCurrent() => _authorityStamp == PersonalYouTubeSourceAuthorityStamp.Read(_access._directory, _user?.Id);
        // Sanitized counters for the gate's slow-request diagnostics.
        internal double MetadataQueryMs, MetadataLinkMs; internal int MetadataSources, MetadataLinkReads;
        internal ListContext(PersonalYouTubeNativeAccess access, User? user, IReadOnlyDictionary<long, BaseItem> inventory, SourceInventory? sources = null)
        {
            _access = access; _user = user; _inventory = inventory;
            // Migration may append the independent scope document once. Retry
            // that change, but never bless a snapshot read across changing files.
            var before = PersonalYouTubeSourceAuthorityStamp.Read(access._directory, user?.Id);
            _snapshot = access._journal.ReadSnapshot();
            _authorityStamp = PersonalYouTubeSourceAuthorityStamp.Read(access._directory, user?.Id);
            if (before != _authorityStamp)
            {
                before = _authorityStamp;
                _snapshot = access._journal.ReadSnapshot();
                _authorityStamp = PersonalYouTubeSourceAuthorityStamp.Read(access._directory, user?.Id);
                if (before != _authorityStamp) throw new InvalidDataException("Private source authority changed during capture.");
            }
            _sources = sources; _potential = sources?.Candidates(_snapshot);
            _folders = FolderLocations(access._library.GetVirtualFolders());
        }
        private BaseItem? Parent(long id) => _inventory.TryGetValue(id, out var item) ? item : _access._library.GetItemById(id);
        internal static bool IsMetadata(BaseItem item) => MetadataLink(item).HasValue;
        internal HashSet<long> DeniedSourceIds() => _potential!.Where(id => DecideOrdinary(_inventory[id]) == Access.Denied).ToHashSet();
        internal Access DecideOrdinary(BaseItem item)
        {
            if (_ordinary.TryGetValue(item.InternalId, out var known)) return known;
            var decision = _sources != null && _inventory.ContainsKey(item.InternalId)
                ? _potential!.Contains(item.InternalId) ? _sources.Decide(item.InternalId, _user == null || _user.Policy.IsDisabled ? Guid.Empty : _user.Id, _snapshot) : Access.Unknown
                : _access.DecideOrdinaryItem(item, _user, Parent, _folders, _snapshot);
            _ordinary[item.InternalId] = decision;
            return decision;
        }
        // Returns metadata index IDs that DecideItem would deny: a Genre,
        // Studio or Tag is allowed only through a currently visible native
        // source that is not itself metadata, is not denied, and actually
        // links that ID. One source query per link type and chunk replaces
        // one query per index object; links are verified per source.
        internal HashSet<long> DeniedMetadata(IEnumerable<BaseItem> metadata, CancellationToken cancellationToken,
            IDictionary<long, long>? witnesses = null, IReadOnlyCollection<long>? preferredSources = null)
        {
            var groups = metadata.GroupBy(item => MetadataLink(item)!.Value).ToArray();
            var denied = groups.SelectMany(group => group.Select(item => item.InternalId)).ToHashSet();
            if (_user == null || _user.Policy.IsDisabled) return denied;
            // One read context and one link read per source for all three
            // types. A type is still credited only from sources returned by
            // that type's own query, exactly as in the per-object rule.
            var allTypes = new List<ItemLinkType> { ItemLinkType.Genres, ItemLinkType.Studios, ItemLinkType.Tags };
            var links = new Dictionary<long, List<(ItemLinkType, string, long)>?>();
            using var data = _access._library.GetReadDataContext(cancellationToken);
            foreach (var group in groups)
            {
                var link = group.Key;
                var pending = group.Select(item => item.InternalId).ToHashSet();
                var checkedSources = new HashSet<long>();
                foreach (var chunk in pending.ToArray().Chunk(500))
                {
                    if (!chunk.Any(pending.Contains)) continue;
                    // Previous witnesses are search hints, never authorization.
                    // Requery their current native visibility and recheck their
                    // ownership, parents, journal and links in this new context.
                    // If a witness disappeared, search all sources as before.
                    foreach (var preferred in preferredSources is { Count: > 0 } ? new[] { true, false } : new[] { false })
                    {
                        if (!chunk.Any(pending.Contains)) break;
                        var query = new InternalItemsQuery { User = _user, Recursive = true };
                        if (preferred) query.ItemIds = preferredSources!.ToArray();
                        if (link == ItemLinkType.Genres) query.GenreIds = chunk;
                        else if (link == ItemLinkType.Studios) query.StudioIds = chunk;
                        else query.TagIds = chunk;
                        // Same native normalization and SQL filter as GetItemList
                        // (LibraryManager.SetUserAndParents + QueryItemsInTransaction),
                        // selecting only Id. Sources resolve from this request's
                        // inventory; an ID GetItemList could not materialize is skipped.
                        var queryStarted = System.Diagnostics.Stopwatch.GetTimestamp();
                        var sources = _access._library.GetInternalItemIds(query, data, cancellationToken);
                        MetadataQueryMs += (System.Diagnostics.Stopwatch.GetTimestamp() - queryStarted) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
                        MetadataSources += sources.Length;
                        var linkStarted = System.Diagnostics.Stopwatch.GetTimestamp();
                        foreach (var sourceId in sources)
                        {
                            if (pending.Count == 0) break;
                            if (!checkedSources.Add(sourceId)) continue;
                            if (!links.TryGetValue(sourceId, out var sourceLinks))
                            {
                                var source = Parent(sourceId);
                                sourceLinks = source == null || source.InternalId != sourceId || IsMetadata(source) || DecideOrdinary(source) == Access.Denied ? null
                                    : _access._library.GetItemLinks(sourceId, allTypes, data, cancellationToken);
                                if (sourceLinks != null) MetadataLinkReads++;
                                links[sourceId] = sourceLinks;
                            }
                            if (sourceLinks == null) continue;
                            foreach (var value in sourceLinks)
                                if (value.Item1 == link && pending.Remove(value.Item3))
                                {
                                    denied.Remove(value.Item3);
                                    if (witnesses != null) witnesses[value.Item3] = sourceId;
                                }
                        }
                        MetadataLinkMs += (System.Diagnostics.Stopwatch.GetTimestamp() - linkStarted) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
                        if (pending.Count == 0) break;
                    }
                }
            }
            return denied;
        }
    }
}
