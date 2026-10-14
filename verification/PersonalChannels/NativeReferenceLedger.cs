using System.Text.Json;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;

namespace PersonalChannelsFixture;

// Isolated native-library experiment. No production API or YouTube integration.
internal static class NativeReferenceLedger
{
    private sealed record Collection(string RootKey, string OwnerGuid, bool Deleted, string[] References, string[]? RemovedReferences = null);
    private sealed record Ledger(int Version, Dictionary<string, Collection> Collections);
    private static Ledger? Current;
    private static string Path => FixturePlugin.StatePath + ".native-reference-owners.json";
    private static bool ValidReference(string value) =>
        (long.TryParse(value, out var number) && number > 0 && number.ToString() == value)
        || Guid.TryParseExact(value, "N", out _);

    internal static Dictionary<string, long> Reconcile(ILibraryManager library, IUserManager users,
        Dictionary<string, string>? mappings)
    {
        var ledger = File.Exists(Path)
            ? JsonSerializer.Deserialize<Ledger>(File.ReadAllText(Path))
                ?? throw new InvalidOperationException("Invalid native reference ledger")
            : new Ledger(1, new());
        if (ledger.Version != 1 || ledger.Collections == null) throw new InvalidOperationException("Unsupported native reference ledger");
        foreach (var pair in ledger.Collections.ToArray())
        {
            var value = pair.Value;
            if (!Guid.TryParseExact(pair.Key, "N", out _) || value == null
                || !long.TryParse(value.RootKey, out var rootId) || rootId <= 0
                || !Guid.TryParseExact(value.OwnerGuid, "N", out _)
                || value.References == null || value.References.Any(key => !ValidReference(key))
                || (value.RemovedReferences?.Any(key => !value.References.Contains(key)) ?? false)
                || !value.References.Contains(pair.Key) || !value.References.Contains(value.RootKey))
                throw new InvalidOperationException("Invalid native reference ownership entry");
            var current = library.GetItemById(rootId);
            if (current == null || current.Id.ToString("N") != pair.Key)
                ledger.Collections[pair.Key] = value with { Deleted = true };
        }
        foreach (var pair in mappings ?? new())
        {
            if (!long.TryParse(pair.Key, out var rootId) || rootId <= 0 || !Guid.TryParse(pair.Value, out var ownerGuid))
                throw new InvalidOperationException("Invalid native root mapping");
            var root = library.GetItemById(rootId);
            if (root == null)
            {
                // A missing root is only accepted if its former private identity
                // was recorded before deletion. Unknown configured IDs still fail.
                if (!ledger.Collections.Values.Any(value => value.RootKey == pair.Key && value.Deleted))
                    throw new InvalidOperationException("Unrecorded missing private root");
                continue;
            }
            if (root is not Folder || !root.Name.StartsWith("Private Native Fixture ", StringComparison.Ordinal))
                throw new InvalidOperationException("Only synthetic native roots are supported");
            var key = root.Id.ToString("N");
            if (ledger.Collections.TryGetValue(key, out var previous) && previous.Deleted)
                continue; // Native identity reuse never resurrects old references.
            var references = library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { root.InternalId }, Recursive = true })
                .Append(root).SelectMany(item => new[] { item.InternalId.ToString(), item.Id.ToString("N") })
                .Concat(previous?.References ?? Array.Empty<string>()).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            ledger.Collections[key] = new Collection(root.InternalId.ToString(), ownerGuid.ToString("N"), false, references, previous?.RemovedReferences);
        }
        Save(ledger);
        Current = ledger;
        return Owners(ledger, users);
    }

    // Called under the guard's Sync lock. Persist actual native scan/deletion
    // events; never infer a new collection or owner from a request parameter.
    internal static Dictionary<string, long> RecordChange(BaseItem item, BaseItem[] roots, bool removed, IUserManager users)
    {
        if (Current == null) return new();
        var keys = new[] { item.InternalId.ToString(), item.Id.ToString("N") };
        var rootGuids = roots.Select(root => root.Id.ToString("N")).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var changed = false;
        foreach (var pair in Current.Collections.ToArray())
        {
            var prior = pair.Value;
            if (!rootGuids.Contains(pair.Key) && !keys.Any(key => prior.References.Contains(key))) continue;
            var references = prior.References.Concat(keys).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            var deleted = prior.Deleted || (removed && prior.RootKey == item.InternalId.ToString());
            var tombstones = (prior.RemovedReferences ?? Array.Empty<string>())
                .Concat(removed ? keys : Array.Empty<string>()).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            if (prior.Deleted == deleted && references.Length == prior.References.Length
                && tombstones.Length == (prior.RemovedReferences?.Length ?? 0)) continue;
            Current.Collections[pair.Key] = prior with { References = references, RemovedReferences = tombstones, Deleted = deleted };
            changed = true;
        }
        if (changed) Save(Current);
        return Owners(Current, users);
    }

    private static void Save(Ledger ledger)
    {
        var json = JsonSerializer.Serialize(ledger);
        File.WriteAllText(Path + ".tmp", json);
        File.Move(Path + ".tmp", Path, true);
        if (File.ReadAllText(Path) != json) throw new InvalidOperationException("Native reference write did not verify");
    }

    private static Dictionary<string, long> Owners(Ledger ledger, IUserManager users)
    {
        var result = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        foreach (var value in ledger.Collections.Values)
        {
            var owner = value.Deleted ? -1 : users.GetUserById(value.OwnerGuid)?.InternalId ?? -1;
            foreach (var reference in value.References)
            {
                var assigned = value.RemovedReferences?.Contains(reference) == true ? -1 : owner;
                if (result.TryGetValue(reference, out var previous) && previous != assigned) assigned = -1;
                result[reference] = assigned;
            }
        }
        return result;
    }
}
