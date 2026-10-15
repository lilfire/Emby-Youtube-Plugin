using MediaBrowser.Controller.Entities;
using Access = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Access;
using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;

namespace Emby.YouTubePlugin;

internal sealed partial class PersonalYouTubeNativeAccess
{
    // Native objects are retained solely as change sentinels. Decisions use
    // copied, canonical identities/sources, never mutable cached authorization.
    internal sealed class SourceInventory
    {
        private sealed record Fingerprint(BaseItem Item, long Number, Guid Guid, long Parent, string? Path, string? Name)
        {
            internal bool Current => Item.InternalId == Number && Item.Id == Guid && Item.ParentId == Parent && Item.Path == Path && Item.Name == Name;
        }
        private sealed record Source(NativeItem Item, NativeItem[] Parents, string[] Paths, bool Invalid);
        private readonly Dictionary<long, Source> _sources = new();
        private readonly Dictionary<long, HashSet<long>> _numbers = new();
        private readonly Dictionary<Guid, HashSet<long>> _guids = new();
        private readonly HashSet<long> _privatePaths = new(), _invalid = new();
        private readonly Fingerprint[] _fingerprints;
        private readonly string _folders;
        internal readonly BaseItem[] Items;
        internal readonly IReadOnlyDictionary<long, BaseItem> ById;
        internal readonly long Version;
        internal readonly BaseItem[] Metadata;
        internal SourceInventory(PersonalYouTubeNativeAccess access, BaseItem[] items, long version)
        {
            Items = items; Version = version; Metadata = items.Where(ListContext.IsMetadata).ToArray();
            ById = items.ToDictionary(item => item.InternalId);
            var folders = access._library.GetVirtualFolders();
            _folders = FolderKey(folders);
            var locations = FolderLocations(folders);
            var dependencies = new Dictionary<BaseItem, Fingerprint>(ReferenceEqualityComparer.Instance);
            void Observe(BaseItem item) => dependencies.TryAdd(item, new(item, item.InternalId, item.Id, item.ParentId, item.Path, item.Name));
            BaseItem? Parent(long id)
            {
                var item = ById.TryGetValue(id, out var found) ? found : access._library.GetItemById(id);
                if (item != null) Observe(item);
                return item;
            }
            void Index<TKey>(Dictionary<TKey, HashSet<long>> index, TKey key, long id) where TKey : notnull
            {
                if (!index.TryGetValue(key, out var ids)) index[key] = ids = new();
                ids.Add(id);
            }
            foreach (var item in items)
            {
                Observe(item);
                if (ListContext.IsMetadata(item)) continue;
                try
                {
                    if (item.InternalId <= 0 || item.Id == Guid.Empty) throw new InvalidDataException();
                    var parents = access._library.GetCollectionFolders(item).Where(root => root.InternalId != item.InternalId).Cast<BaseItem>().ToList();
                    foreach (var parent in parents) Observe(parent);
                    var visited = new HashSet<long> { item.InternalId };
                    var current = item;
                    while (current.ParentId != 0)
                    {
                        if (!visited.Add(current.ParentId) || visited.Count > 513) throw new InvalidDataException();
                        current = Parent(current.ParentId) ?? throw new InvalidDataException();
                        parents.Add(current);
                    }
                    var groups = parents.GroupBy(parent => parent.InternalId).ToArray();
                    if (groups.Length > 512 || groups.Any(group => group.Select(parent => parent.Id).Distinct().Count() != 1)) throw new InvalidDataException();
                    var pairs = groups.Select(group => new NativeItem(group.Key, group.First().Id)).ToArray();
                    if (pairs.Any(pair => pair.InternalId <= 0 || pair.ItemId == Guid.Empty)) throw new InvalidDataException();
                    var paths = pairs.Select(pair => pair.InternalId).Append(item.InternalId).Distinct()
                        .SelectMany(id => locations.TryGetValue(id, out var paths) ? paths : Array.Empty<string>())
                        .Concat(groups.Select(group => group.First().Path ?? ""))
                        .Append(item.Path ?? "").Where(path => !string.IsNullOrEmpty(path)).Select(Path.GetFullPath).ToArray();
                    if (paths.Length > 512) throw new InvalidDataException();
                    _sources[item.InternalId] = new(new(item.InternalId, item.Id), pairs, paths, false);
                    if (paths.Any(access._journal.IsPrivatePath)) _privatePaths.Add(item.InternalId);
                    foreach (var pair in pairs.Append(new(item.InternalId, item.Id)))
                    { Index(_numbers, pair.InternalId, item.InternalId); Index(_guids, pair.ItemId, item.InternalId); }
                }
                catch (Exception error) when (error is IOException or InvalidDataException or ArgumentException or UnauthorizedAccessException)
                {
                    _invalid.Add(item.InternalId);
                    _sources[item.InternalId] = new(new(item.InternalId, item.Id), Array.Empty<NativeItem>(), Array.Empty<string>(), true);
                }
            }
            _fingerprints = dependencies.Values.ToArray();
        }
        private static string FolderKey(IEnumerable<MediaBrowser.Model.Entities.VirtualFolderInfo> folders)
            => System.Text.Json.JsonSerializer.Serialize(folders.Select(folder => new { folder.ItemId, folder.Locations }).OrderBy(folder => folder.ItemId));
        internal bool Current(PersonalYouTubeNativeAccess access, bool readFolders)
            => PersonalYouTubeNativeSourceBarrier.IsCurrent(Version) && _fingerprints.All(value => value.Current)
                && (!readFolders || _folders == FolderKey(access._library.GetVirtualFolders()))
                && PersonalYouTubeNativeSourceBarrier.IsCurrent(Version);
        internal bool ObjectsCurrent => _fingerprints.All(value => value.Current);
        internal HashSet<long> Candidates(PersonalYouTubePublicationJournal.Snapshot snapshot)
        {
            var ids = new HashSet<long>(_privatePaths); ids.UnionWith(_invalid);
            foreach (var number in snapshot.PrivateNumbers) if (_numbers.TryGetValue(number, out var values)) ids.UnionWith(values);
            foreach (var guid in snapshot.PrivateGuids) if (_guids.TryGetValue(guid, out var values)) ids.UnionWith(values);
            return ids;
        }
        internal Access Decide(long id, Guid owner, PersonalYouTubePublicationJournal.Snapshot snapshot)
        {
            var source = _sources[id];
            return source.Invalid ? Access.Denied : snapshot.DecideSources(source.Item, source.Parents, owner, source.Paths);
        }
    }
    private readonly object _inventoryGate = new();
    private SourceInventory? _inventory;
    internal long InventoryBuilds, InventoryHits;
    internal SourceInventory? ReadSourceInventory()
    {
        if (!PersonalYouTubeNativeSourceBarrier.Snapshot().Installed) return null;
        lock (_inventoryGate)
        {
            if (_inventory?.Current(this, true) == true) { Interlocked.Increment(ref InventoryHits); return _inventory; }
            var state = PersonalYouTubeNativeSourceBarrier.Snapshot();
            if (state.Writers != 0) throw new InvalidDataException("Native source mutation in progress.");
            var next = new SourceInventory(this, PersonalYouTubeItemListGate.NativeScan(_library, new() { Recursive = true }), state.Version);
            if (!next.Current(this, true)) throw new InvalidDataException("Native source inventory changed during capture.");
            Interlocked.Increment(ref InventoryBuilds);
            return _inventory = next;
        }
    }
}
