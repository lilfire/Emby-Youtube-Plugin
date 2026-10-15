using System.Collections.Concurrent;
using System.Globalization;
using System.Text.Json;

namespace Emby.YouTubePlugin;

// Server-owned identity ledger, not a native HTTP access hook. Register before
// publishing private items. Old aliases are permanent; never transfer them to
// another generation even if Emby reuses an ID or a physical folder GUID.
internal sealed class PersonalYouTubeNativeBindings
{
    internal readonly record struct NativeItem(long InternalId, Guid ItemId);
    internal sealed record Binding(Guid OwnerUserId, Guid CollectionId, Guid GenerationId, long InternalId, Guid ItemId);
    internal enum Access { Unknown, Denied, Allowed }
    internal sealed record AccessSnapshot(Binding[] Items, long[] DeniedIds);
    private sealed record Document(int Version, Binding[] Items);
    private static readonly ConcurrentDictionary<string, object> Gates = new(StringComparer.OrdinalIgnoreCase);
    private readonly string _path;
    private readonly string _marker;
    private readonly object _gate;
    private readonly PersonalYouTubeStore _profiles;

    internal PersonalYouTubeNativeBindings(string directory)
    {
        var root = Path.GetFullPath(directory);
        _path = Path.Combine(root, "native-reference-bindings.json");
        _marker = Path.Combine(root, "native-reference-bindings.required");
        _gate = Gates.GetOrAdd(root, _ => new object());
        _profiles = new(root);
    }
    private static string Number(long value) => value.ToString(CultureInfo.InvariantCulture);
    private Document Load()
    {
        if (!File.Exists(_path))
        {
            if (File.Exists(_marker)) throw new InvalidDataException("Required private reference ledger unavailable.");
            return new(1, Array.Empty<Binding>());
        }
        if (!File.Exists(_marker)) throw new InvalidDataException("Private reference ledger marker unavailable.");
        Document doc;
        try { doc = JsonSerializer.Deserialize<Document>(File.ReadAllText(_path)) ?? throw new InvalidDataException(); }
        catch (JsonException) { throw new InvalidDataException("Invalid private reference ledger."); }
        if (doc.Version != 1 || doc.Items == null
            || doc.Items.Any(item => item == null || item.OwnerUserId == Guid.Empty || item.CollectionId == Guid.Empty
                || item.GenerationId == Guid.Empty || item.InternalId <= 0 || item.ItemId == Guid.Empty)
            || doc.Items.Select(item => item.InternalId).Distinct().Count() != doc.Items.Length
            || doc.Items.Select(item => item.ItemId).Distinct().Count() != doc.Items.Length)
            throw new InvalidDataException("Invalid private reference identities.");
        return doc;
    }
    private void Persist(Document document)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        // Record the obligation before the ledger. A crash between the two
        // leaves an unavailable ledger, rather than treating private IDs as public.
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
    internal bool Register(PersonalYouTubeStore.Prepared snapshot, IEnumerable<NativeItem> nativeItems)
    {
        var requested = nativeItems.ToArray();
        if (requested.Length == 0 || requested.Any(item => item.InternalId <= 0 || item.ItemId == Guid.Empty)
            || requested.Select(item => item.InternalId).Distinct().Count() != requested.Length
            || requested.Select(item => item.ItemId).Distinct().Count() != requested.Length)
            throw new ArgumentException("Distinct native item identities required.");
        // Lock order is profile then ledger. Lookup releases the ledger lock
        // before reading the profile; it never acquires them in reverse order.
        return _profiles.PublishIfCurrent(snapshot, () =>
        {
            lock (_gate)
            {
                var doc = Load();
                var next = doc.Items.ToList();
                foreach (var item in requested)
                {
                    var binding = new Binding(snapshot.OwnerUserId, snapshot.CollectionId, snapshot.GenerationId, item.InternalId, item.ItemId);
                    var matches = doc.Items.Where(prior => prior.InternalId == item.InternalId || prior.ItemId == item.ItemId).ToArray();
                    if (matches.Any(prior => prior != binding))
                        throw new InvalidOperationException("Private native identity is already bound.");
                    if (matches.Length == 0) next.Add(binding);
                }
                new PersonalYouTubePrivateScopes(Path.GetDirectoryName(_path)!).Remember(snapshot, aliases: requested);
                if (next.Count != doc.Items.Length) Persist(new(1, next.ToArray()));
            }
        });
    }
    internal Binding? Find(string reference)
    {
        long? number = null; Guid? guid = null;
        if (long.TryParse(reference, NumberStyles.None, CultureInfo.InvariantCulture, out var id) && id > 0 && Number(id) == reference)
            number = id;
        else if (Guid.TryParseExact(reference, "N", out var itemId) && itemId != Guid.Empty)
            guid = itemId;
        // Always load even for an unknown/malformed alias: missing required
        // ledger must not become an Unknown/public fallback.
        lock (_gate) return Load().Items.SingleOrDefault(item => number == item.InternalId || guid == item.ItemId);
    }
    // One validated read of the ledger for a single list request. Decisions
    // are identical to DecideItem; profiles are read at most once per owner.
    internal Ledger ReadLedger() { Binding[] items; lock (_gate) items = Load().Items; return new(this, items); }
    internal sealed class Ledger
    {
        private readonly PersonalYouTubeNativeBindings _bindings;
        private readonly Dictionary<long, Binding> _byInternal;
        private readonly Dictionary<Guid, Binding> _byItem;
        private readonly Dictionary<Guid, PersonalYouTubeStore.View?> _profiles = new();
        internal Ledger(PersonalYouTubeNativeBindings bindings, Binding[] items)
        {
            // Load() has already enforced distinct internal IDs and item IDs.
            _bindings = bindings;
            _byInternal = items.ToDictionary(item => item.InternalId);
            _byItem = items.ToDictionary(item => item.ItemId);
        }
        internal Binding? FindInternal(long internalId) => _byInternal.TryGetValue(internalId, out var binding) ? binding : null;
        internal Binding[] Items => _byInternal.Values.ToArray();
        private Binding[] Matching(NativeItem item)
        {
            _byInternal.TryGetValue(item.InternalId, out var byInternal);
            _byItem.TryGetValue(item.ItemId, out var byItem);
            if (byInternal == null) return byItem == null ? Array.Empty<Binding>() : new[] { byItem };
            return byItem == null || ReferenceEquals(byItem, byInternal) ? new[] { byInternal } : new[] { byInternal, byItem };
        }
        internal Access DecideItem(NativeItem item, NativeItem[] parents, Guid authenticatedOwner)
        {
            if (item.InternalId <= 0 || item.ItemId == Guid.Empty || parents.Length > 512
                || parents.Any(parent => parent.InternalId <= 0 || parent.ItemId == Guid.Empty))
                throw new ArgumentException("Actual native identities required.");
            var direct = Matching(item);
            var related = parents.SelectMany(parent => Matching(parent).Select(binding => (Parent: parent, Binding: binding))).ToArray();
            if (direct.Length == 0) return related.Length == 0 ? Access.Unknown : Access.Denied;
            if (direct.Length != 1 || direct[0].InternalId != item.InternalId || direct[0].ItemId != item.ItemId)
                return Access.Denied;
            var own = direct[0];
            if (related.Any(pair => pair.Binding.InternalId != pair.Parent.InternalId || pair.Binding.ItemId != pair.Parent.ItemId
                || pair.Binding.OwnerUserId != own.OwnerUserId || pair.Binding.CollectionId != own.CollectionId
                || pair.Binding.GenerationId != own.GenerationId)) return Access.Denied;
            return DecideBinding(own, authenticatedOwner);
        }
        private Access DecideBinding(Binding binding, Guid authenticatedOwner)
        {
            if (authenticatedOwner == Guid.Empty || authenticatedOwner != binding.OwnerUserId) return Access.Denied;
            if (!_profiles.TryGetValue(binding.OwnerUserId, out var profile))
            {
                try { profile = _bindings._profiles.Read(binding.OwnerUserId); }
                catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException) { profile = null; }
                _profiles[binding.OwnerUserId] = profile;
            }
            return profile != null && profile.State == "Draft" && profile.CollectionId == binding.CollectionId && profile.GenerationId == binding.GenerationId
                ? Access.Allowed : Access.Denied;
        }
    }
    internal Access Decide(string reference, Guid authenticatedOwner)
    {
        var binding = Find(reference);
        if (binding == null) return Access.Unknown;
        return DecideBinding(binding, authenticatedOwner);
    }
    // Storage-only refresh, suitable before a native query that may already
    // hold a data context. No library lookup or second native DB scan.
    internal AccessSnapshot ReadAccessSnapshot(Guid authenticatedOwner)
    {
        Binding[] items;
        lock (_gate) items = Load().Items;
        PersonalYouTubeStore.View? profile = null;
        if (authenticatedOwner != Guid.Empty)
        {
            try { profile = _profiles.Read(authenticatedOwner); }
            catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException) { }
        }
        var denied = items.Where(binding => binding.OwnerUserId != authenticatedOwner || profile == null
            || profile.State != "Draft" || profile.CollectionId != binding.CollectionId || profile.GenerationId != binding.GenerationId)
            .Select(binding => binding.InternalId).ToArray();
        return new(items, denied);
    }
    // Native callers supply the actual ID/GUID pair and ancestry obtained from
    // the server, never a client-supplied ancestry. A private descendant remains
    // denied until its own pair is durably registered. Known old bindings win
    // over current ancestry; ancestry cannot transfer an old reference.
    internal Access DecideItem(NativeItem item, IEnumerable<NativeItem> ancestors, Guid authenticatedOwner)
    {
        var parents = ancestors.ToArray();
        if (item.InternalId <= 0 || item.ItemId == Guid.Empty || parents.Length > 512
            || parents.Any(parent => parent.InternalId <= 0 || parent.ItemId == Guid.Empty))
            throw new ArgumentException("Actual native identities required.");
        return ReadLedger().DecideItem(item, parents, authenticatedOwner);
    }
    private Access DecideBinding(Binding binding, Guid authenticatedOwner)
    {
        if (authenticatedOwner == Guid.Empty || authenticatedOwner != binding.OwnerUserId) return Access.Denied;
        try
        {
            var profile = _profiles.Read(binding.OwnerUserId);
            return profile.State == "Draft" && profile.CollectionId == binding.CollectionId && profile.GenerationId == binding.GenerationId
                ? Access.Allowed : Access.Denied;
        }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException)
        { return Access.Denied; }
    }
}
