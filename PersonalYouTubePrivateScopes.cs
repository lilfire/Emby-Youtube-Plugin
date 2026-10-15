using System.Collections.Concurrent;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;

namespace Emby.YouTubePlugin;

// Independent, append-only classification authority. This file never grants
// access: it only remembers which identities must not become public when a
// publication/ledger document is unavailable. Write it before publishing aliases.
internal sealed class PersonalYouTubePrivateScopes
{
    internal sealed record Scope(Guid Owner, Guid Collection, Guid Generation, Guid[] Roots, NativeItem[] Aliases);
    private sealed record Document(int Version, bool Complete, Scope[] Scopes);
    private static readonly ConcurrentDictionary<string, object> Gates = new(StringComparer.OrdinalIgnoreCase);
    private readonly string _path, _marker;
    private readonly object _gate;
    internal PersonalYouTubePrivateScopes(string directory)
    {
        var root = Path.GetFullPath(directory);
        _path = Path.Combine(root, "private-source-scopes.json");
        _marker = Path.Combine(root, "private-source-scopes.required");
        _gate = Gates.GetOrAdd(root, _ => new object());
    }
    private Document Load()
    {
        if (!File.Exists(_path))
        {
            if (File.Exists(_marker)) throw new InvalidDataException("Required private scope authority unavailable.");
            return new(1, false, Array.Empty<Scope>());
        }
        if (!File.Exists(_marker)) throw new InvalidDataException("Private scope marker unavailable.");
        var bytes = File.ReadAllBytes(_path);
        if (Encoding.ASCII.GetString(File.ReadAllBytes(_marker)) != Convert.ToHexString(SHA256.HashData(bytes)))
            throw new InvalidDataException("Private scope integrity mismatch.");
        Document doc;
        try { doc = JsonSerializer.Deserialize<Document>(bytes) ?? throw new InvalidDataException(); }
        catch (JsonException) { throw new InvalidDataException("Invalid private scope authority."); }
        if (doc.Version != 1 || doc.Scopes == null || doc.Scopes.Any(scope => scope == null
            || scope.Owner == Guid.Empty || scope.Collection == Guid.Empty || scope.Generation == Guid.Empty
            || scope.Roots == null || scope.Roots.Any(root => root == Guid.Empty) || scope.Roots.Distinct().Count() != scope.Roots.Length
            || scope.Aliases == null || scope.Aliases.Any(alias => alias.InternalId <= 0 || alias.ItemId == Guid.Empty)
            || scope.Aliases.Distinct().Count() != scope.Aliases.Length)
            || doc.Scopes.Select(scope => scope.Generation).Distinct().Count() != doc.Scopes.Length)
            throw new InvalidDataException("Invalid private scope identities.");
        return doc;
    }
    private void Persist(Document doc)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        if (!File.Exists(_marker))
        {
            using var marker = new FileStream(_marker, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            marker.WriteByte(1); marker.Flush(true);
        }
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        var markerTemporary = _marker + "." + Guid.NewGuid().ToString("N") + ".tmp";
        var bytes = JsonSerializer.SerializeToUtf8Bytes(doc);
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { file.Write(bytes); file.Flush(true); }
            File.Move(temporary, _path, true);
            // A crash between these replacements is a detectable torn index,
            // never an older classification accepted as current. Publication
            // cannot proceed until both durable writes have completed.
            using (var marker = new FileStream(markerTemporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { marker.Write(Encoding.ASCII.GetBytes(Convert.ToHexString(SHA256.HashData(bytes)))); marker.Flush(true); }
            File.Move(markerTemporary, _marker, true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
            if (File.Exists(markerTemporary)) File.Delete(markerTemporary);
        }
    }
    private static Scope Merge(Scope? old, Guid owner, Guid collection, Guid generation, Guid[] roots, NativeItem[] aliases)
    {
        if (old != null && (old.Owner != owner || old.Collection != collection))
            throw new InvalidDataException("Private scope identity conflict.");
        return new(owner, collection, generation, (old?.Roots ?? Array.Empty<Guid>()).Concat(roots).Distinct().OrderBy(value => value).ToArray(),
            (old?.Aliases ?? Array.Empty<NativeItem>()).Concat(aliases).Distinct().OrderBy(value => value.InternalId).ThenBy(value => value.ItemId).ToArray());
    }
    internal void Remember(PersonalYouTubeStore.Prepared prepared, Guid? root = null, NativeItem[]? aliases = null)
    {
        if (prepared.OwnerUserId == Guid.Empty || prepared.CollectionId == Guid.Empty || prepared.GenerationId == Guid.Empty
            || root == Guid.Empty || aliases?.Any(alias => alias.InternalId <= 0 || alias.ItemId == Guid.Empty) == true)
            throw new ArgumentException("Private scope identities required.");
        lock (_gate)
        {
            var doc = Load();
            var scopes = doc.Scopes.ToDictionary(scope => scope.Generation);
            scopes.TryGetValue(prepared.GenerationId, out var old);
            scopes[prepared.GenerationId] = Merge(old, prepared.OwnerUserId, prepared.CollectionId, prepared.GenerationId,
                root.HasValue ? new[] { root.Value } : Array.Empty<Guid>(), aliases ?? Array.Empty<NativeItem>());
            SaveIfChanged(doc, doc.Complete, scopes.Values.ToArray());
        }
    }
    private void SaveIfChanged(Document old, bool complete, Scope[] scopes)
    {
        var next = new Document(1, complete, scopes.OrderBy(scope => scope.Generation).ToArray());
        if (!JsonSerializer.SerializeToUtf8Bytes(old).AsSpan().SequenceEqual(JsonSerializer.SerializeToUtf8Bytes(next))) Persist(next);
    }
    // Only a successful read of BOTH old authorities may complete migration.
    // An incomplete/new authority cannot recover a corrupt legacy journal.
    internal Snapshot Reconcile(PersonalYouTubeNativeBindings.Binding[] bindings, PersonalYouTubePublicationJournal.Entry[] entries)
    {
        lock (_gate)
        {
            var doc = Load();
            var scopes = doc.Scopes.ToDictionary(scope => scope.Generation);
            foreach (var binding in bindings)
            {
                scopes.TryGetValue(binding.GenerationId, out var old);
                scopes[binding.GenerationId] = Merge(old, binding.OwnerUserId, binding.CollectionId, binding.GenerationId,
                    Array.Empty<Guid>(), new[] { new NativeItem(binding.InternalId, binding.ItemId) });
            }
            foreach (var entry in entries)
            {
                scopes.TryGetValue(entry.GenerationId, out var old);
                scopes[entry.GenerationId] = Merge(old, entry.OwnerUserId, entry.CollectionId, entry.GenerationId,
                    entry.ReservedRootId.HasValue ? new[] { entry.ReservedRootId.Value } : Array.Empty<Guid>(),
                    entry.Root.HasValue ? new[] { entry.Root.Value } : Array.Empty<NativeItem>());
            }
            if (scopes.Count > 0 || File.Exists(_marker)) SaveIfChanged(doc, true, scopes.Values.ToArray());
            return new(scopes.Values.ToArray());
        }
    }
    internal Snapshot ReadComplete()
    {
        lock (_gate)
        {
            var doc = Load();
            if (!doc.Complete) throw new InvalidDataException("Private scope migration incomplete.");
            return new(doc.Scopes);
        }
    }
    internal sealed class Snapshot
    {
        private readonly HashSet<long> _numbers;
        private readonly HashSet<Guid> _guids;
        internal Snapshot(Scope[] scopes)
        {
            _numbers = scopes.SelectMany(scope => scope.Aliases).Select(alias => alias.InternalId).ToHashSet();
            _guids = scopes.SelectMany(scope => scope.Roots.Concat(scope.Aliases.Select(alias => alias.ItemId))).ToHashSet();
        }
        internal long[] Numbers => _numbers.ToArray();
        internal Guid[] Guids => _guids.ToArray();
        internal bool Contains(NativeItem item) => _numbers.Contains(item.InternalId) || _guids.Contains(item.ItemId);
        internal bool Contains(long? number, Guid? guid) => number.HasValue && _numbers.Contains(number.Value) || guid.HasValue && _guids.Contains(guid.Value);
    }
}
