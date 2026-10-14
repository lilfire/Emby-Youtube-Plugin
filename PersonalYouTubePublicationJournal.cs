using System.Collections.Concurrent;
using System.Text.Json;
using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;
using Access = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Access;

namespace Emby.YouTubePlugin;

// Records private creation before native indexing. This is not an Emby
// publisher or access hook. Consumers must use this combined decision rather
// than treating registered-but-preparing bindings as publishable.
internal sealed class PersonalYouTubePublicationJournal
{
    internal sealed record Entry(Guid OwnerUserId, Guid CollectionId, Guid GenerationId,
        long CreationRevision, string State, NativeItem? Root, Guid? ReservedRootId = null);
    private sealed record Document(int Version, Entry[] Entries);
    private static readonly ConcurrentDictionary<string, object> Gates = new(StringComparer.OrdinalIgnoreCase);
    private readonly string _path;
    private readonly string _marker;
    private readonly string _mediaRoot;
    private readonly object _gate;
    private readonly PersonalYouTubeStore _profiles;
    private readonly PersonalYouTubeNativeBindings _bindings;
    private static StringComparison PathComparison => OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
    internal PersonalYouTubePublicationJournal(string directory)
    {
        var root = Path.GetFullPath(directory);
        _path = Path.Combine(root, "publication-journal.json");
        _marker = Path.Combine(root, "publication-journal.required");
        _mediaRoot = Path.Combine(root, "media");
        _gate = Gates.GetOrAdd(root, _ => new object());
        _profiles = new(root); _bindings = new(root);
    }
    internal string MediaPath(Entry entry) => Path.Combine(_mediaRoot,
        entry.OwnerUserId.ToString("N"), entry.CollectionId.ToString("N"), entry.GenerationId.ToString("N"));
    internal Entry[] Pending()
    {
        lock (_gate) return Load().Entries.Where(entry => entry.State == "Preparing").ToArray();
    }
    internal Entry[] Entries() { lock(_gate) return Load().Entries.ToArray(); }
    private static bool Under(string path, string root) => path.Equals(root, PathComparison)
        || path.StartsWith(root + Path.DirectorySeparatorChar, PathComparison);
    private Document Load()
    {
        if (!File.Exists(_path))
        {
            if (File.Exists(_marker) || Directory.Exists(_mediaRoot)) throw new InvalidDataException("Required private publication journal unavailable.");
            return new(1, Array.Empty<Entry>());
        }
        if (!File.Exists(_marker)) throw new InvalidDataException("Private publication marker unavailable.");
        Document document;
        try { document = JsonSerializer.Deserialize<Document>(File.ReadAllText(_path)) ?? throw new InvalidDataException(); }
        catch (JsonException) { throw new InvalidDataException("Invalid private publication journal."); }
        if (document.Version != 1 || document.Entries == null
            || document.Entries.Any(entry => entry == null || entry.OwnerUserId == Guid.Empty || entry.CollectionId == Guid.Empty
                || entry.GenerationId == Guid.Empty || entry.CreationRevision <= 0 || entry.State is not ("Preparing" or "Active")
                || entry.State == "Preparing" && entry.Root.HasValue
                || entry.ReservedRootId == Guid.Empty
                || entry.State == "Active" && (!entry.Root.HasValue || entry.Root.Value.InternalId <= 0 || entry.Root.Value.ItemId == Guid.Empty
                    || entry.ReservedRootId.HasValue && entry.ReservedRootId != entry.Root.Value.ItemId))
            || document.Entries.Select(entry => entry.GenerationId).Distinct().Count() != document.Entries.Length
            || document.Entries.Where(entry => entry.ReservedRootId.HasValue).Select(entry => entry.ReservedRootId).Distinct().Count()
                != document.Entries.Count(entry => entry.ReservedRootId.HasValue))
            throw new InvalidDataException("Invalid private publication identity or state.");
        return document;
    }
    private void Persist(Document document)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        if (!File.Exists(_marker))
        {
            using var marker = new FileStream(_marker, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            marker.Write(new byte[] { 1 }); marker.Flush(true);
        }
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { file.Write(JsonSerializer.SerializeToUtf8Bytes(document)); file.Flush(true); }
            File.Move(temporary, _path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    internal Entry Begin(PersonalYouTubeStore.Prepared snapshot)
    {
        Entry? result = null;
        if (!_profiles.PublishIfCurrent(snapshot, () =>
        {
            lock (_gate)
            {
                var doc = Load();
                result = doc.Entries.SingleOrDefault(entry => entry.GenerationId == snapshot.GenerationId);
                if (result != null)
                {
                    if (result.OwnerUserId != snapshot.OwnerUserId || result.CollectionId != snapshot.CollectionId
                        || result.State == "Preparing" && result.CreationRevision != snapshot.Revision)
                        throw new InvalidOperationException("Private publication identity changed.");
                    return;
                }
                result = new(snapshot.OwnerUserId, snapshot.CollectionId, snapshot.GenerationId, snapshot.Revision, "Preparing", null);
                Persist(new(1, doc.Entries.Append(result).ToArray()));
            }
        })) throw new InvalidOperationException("Private publication snapshot is stale.");
        return result!;
    }
    // Call synchronously before the native root becomes externally observable.
    // The caller must hold a trusted creation context; names/client parameters
    // alone cannot authorize this reservation. Failure must abort native create.
    internal bool ReserveRootIdentity(PersonalYouTubeStore.Prepared snapshot, Guid rootId)
    {
        if (rootId == Guid.Empty) throw new ArgumentException("Native root identity required.");
        return _profiles.PublishIfCurrent(snapshot, () =>
        {
            lock (_gate)
            {
                var doc = Load();
                var pending = doc.Entries.SingleOrDefault(entry => entry.GenerationId == snapshot.GenerationId);
                if (pending == null || pending.State != "Preparing" || pending.OwnerUserId != snapshot.OwnerUserId
                    || pending.CollectionId != snapshot.CollectionId || pending.CreationRevision != snapshot.Revision
                    || pending.ReservedRootId.HasValue && pending.ReservedRootId != rootId
                    || doc.Entries.Any(entry => entry != pending && (entry.ReservedRootId == rootId || entry.Root?.ItemId == rootId))
                    || _bindings.Find(rootId.ToString("N")) != null)
                    throw new InvalidOperationException("Native root identity cannot be reserved.");
                if (pending.ReservedRootId == rootId) return;
                Persist(new(1, doc.Entries.Select(entry => entry == pending ? entry with { ReservedRootId = rootId } : entry).ToArray()));
            }
        });
    }
    internal bool Activate(PersonalYouTubeStore.Prepared snapshot, NativeItem nativeRoot)
    {
        return _profiles.PublishIfCurrent(snapshot, () =>
        {
            lock (_gate)
            {
                var doc = Load();
                var pending = doc.Entries.SingleOrDefault(entry => entry.GenerationId == snapshot.GenerationId);
                if (pending == null || pending.OwnerUserId != snapshot.OwnerUserId || pending.CollectionId != snapshot.CollectionId
                    || pending.State == "Preparing" && pending.CreationRevision != snapshot.Revision)
                    throw new InvalidOperationException("Private publication was not prepared.");
                var bound = _bindings.Find(nativeRoot.InternalId.ToString(System.Globalization.CultureInfo.InvariantCulture));
                if (bound == null || bound.InternalId != nativeRoot.InternalId || bound.ItemId != nativeRoot.ItemId
                    || bound.OwnerUserId != snapshot.OwnerUserId || bound.CollectionId != snapshot.CollectionId || bound.GenerationId != snapshot.GenerationId
                    || pending.State == "Active" && pending.Root != nativeRoot
                    || pending.ReservedRootId.HasValue && pending.ReservedRootId != nativeRoot.ItemId)
                    throw new InvalidOperationException("Private root is not durably bound.");
                if (pending.State == "Active") return;
                Persist(new(1, doc.Entries.Select(entry => entry == pending ? entry with { State = "Active", Root = nativeRoot } : entry).ToArray()));
            }
        });
    }
    internal Access DecideItem(NativeItem item, IEnumerable<NativeItem> ancestors, Guid authenticatedOwner, string? actualPath)
        => DecideSources(item, ancestors, authenticatedOwner, string.IsNullOrEmpty(actualPath) ? Array.Empty<string>() : new[] { actualPath });
    // The native resolver has established absence. Retired/reserved identities
    // must still be private; no missing native object can grant owner access.
    internal Access DecideAbsentReference(string reference)
    {
        long? number = null; Guid? guid = null;
        if (long.TryParse(reference, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var id) && id > 0)
            number = id;
        else if (Guid.TryParse(reference, out var itemId) && itemId != Guid.Empty) guid = itemId;
        var canonical = number?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? guid?.ToString("N") ?? reference;
        var binding = _bindings.Find(canonical);
        Document doc;
        lock (_gate) doc = Load();
        if (binding != null || doc.Entries.Any(entry => guid.HasValue && (entry.ReservedRootId == guid || entry.Root?.ItemId == guid)
            || number.HasValue && entry.Root?.InternalId == number)) return Access.Denied;
        return Access.Unknown;
    }
    internal long[] DeniedRegisteredIds(Guid authenticatedOwner)
    {
        var snapshot = _bindings.ReadAccessSnapshot(authenticatedOwner);
        Document doc;
        lock (_gate) doc = Load();
        var denied = snapshot.DeniedIds.ToHashSet();
        foreach (var binding in snapshot.Items)
        {
            var entry = doc.Entries.SingleOrDefault(value => value.GenerationId == binding.GenerationId);
            if (entry != null && (entry.State != "Active" || entry.OwnerUserId != binding.OwnerUserId
                || entry.CollectionId != binding.CollectionId)) denied.Add(binding.InternalId);
        }
        return denied.ToArray();
    }
    // Include configured physical locations for virtual roots whose own Path
    // is elsewhere. These locations must be obtained from the native server.
    internal Access DecideSources(NativeItem item, IEnumerable<NativeItem> ancestors, Guid authenticatedOwner, IEnumerable<string> actualSources)
    {
        var parents = ancestors.ToArray();
        var native = _bindings.DecideItem(item, parents, authenticatedOwner);
        Document doc;
        lock (_gate) doc = Load();
        foreach (var reserved in doc.Entries.Where(entry => entry.ReservedRootId.HasValue
            && (entry.ReservedRootId == item.ItemId || parents.Any(parent => parent.ItemId == entry.ReservedRootId))))
            if (reserved.State != "Active" || reserved.OwnerUserId != authenticatedOwner
                || !(reserved.Root == item || reserved.Root.HasValue && parents.Contains(reserved.Root.Value))) return Access.Denied;
        Entry? pathEntry = null;
        var sources = actualSources.ToArray();
        if (sources.Length > 512) throw new ArgumentException("Too many native source locations.");
        foreach (var actualPath in sources.Where(path => !string.IsNullOrEmpty(path)))
        {
            var path = Path.GetFullPath(actualPath);
            if (Under(path, _mediaRoot))
            {
                var matched = doc.Entries.SingleOrDefault(entry => Under(path, MediaPath(entry)));
                if (matched == null || matched.State != "Active" || pathEntry != null && pathEntry != matched) return Access.Denied;
                pathEntry = matched;
            }
        }
        var binding = _bindings.Find(item.InternalId.ToString(System.Globalization.CultureInfo.InvariantCulture));
        var entry = binding == null ? null : doc.Entries.SingleOrDefault(value => value.GenerationId == binding.GenerationId);
        if (pathEntry != null && entry != pathEntry) return Access.Denied;
        if (entry != null && (entry.State != "Active" || entry.OwnerUserId != authenticatedOwner
            || entry.OwnerUserId != binding!.OwnerUserId || entry.CollectionId != binding.CollectionId
            || !(entry.Root == item || entry.Root.HasValue && parents.Contains(entry.Root.Value)))) return Access.Denied;
        return native;
    }
}
