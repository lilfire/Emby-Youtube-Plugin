using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using Emby.YouTubePlugin;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;
using Access = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Access;
using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;

var directory = Directory.CreateTempSubdirectory("private-inventory-probe-").FullName;
var observations = new List<object>();
var completed = false;
void Check(string name, bool pass)
{
    observations.Add(new { Name = name, Pass = pass });
    if (!pass) throw new InvalidOperationException(name);
}
try
{
    var profiles = new PersonalYouTubeStore(directory);
    var bindings = new PersonalYouTubeNativeBindings(directory);
    var journal = new PersonalYouTubePublicationJournal(directory);
    var library = DispatchProxy.Create<ILibraryManager, LibraryAdapter>();
    var adapter = (LibraryAdapter)library;
    var access = new PersonalYouTubeNativeAccess(directory, library);
    var owner = new User { Id = Guid.NewGuid(), InternalId = 901, Policy = new() };
    var foreign = new User { Id = Guid.NewGuid(), InternalId = 902, Policy = new() };
    profiles.Save(owner.Id, 0, new[] { "UC" + new string('a', 22) }, "synthetic-key", false);
    var prepared = profiles.Prepare(owner.Id);
    var entry = journal.Begin(prepared);
    var media = journal.MediaPath(entry);
    var mediaRoot = Path.Combine(directory, "media");
    var root = new CollectionFolder { InternalId = 1, Id = Guid.NewGuid() };
    var own = new Video { InternalId = 2, Id = Guid.NewGuid(), ParentId = 1, Path = Path.Combine(media, "own.mp4") };
    var unknown = new Video { InternalId = 3, Id = Guid.NewGuid(), ParentId = 1, Path = Path.Combine(directory, "external.mp4") };
    var nested = new Folder { InternalId = 4, Id = Guid.NewGuid(), ParentId = 1, Path = Path.Combine(directory, "external-folder") };
    var child = new Video { InternalId = 5, Id = Guid.NewGuid(), ParentId = 4, Path = Path.Combine(directory, "external-child.mp4") };
    var orphan = new Video { InternalId = 6, Id = Guid.NewGuid(), Path = Path.Combine(mediaRoot, "orphan.mp4") };
    // Lexically outside media, canonically inside it. Both the full production
    // resolver and Path.GetFullPath recognize it, while native string filters may not.
    var alias = new Video { InternalId = 7, Id = Guid.NewGuid(), Path = Path.Combine(directory, "ordinary", "..", "media", "alias.mp4") };
    var publicItem = new Video { InternalId = 8, Id = Guid.NewGuid(), Path = Path.Combine(directory, "public.mp4") };
    var physical = new Folder { InternalId = 9, Id = Guid.NewGuid(), Path = mediaRoot };
    var physicalChild = new Video { InternalId = 10, Id = Guid.NewGuid(), ParentId = 9, Path = Path.Combine(directory, "physical-external.mp4") };
    adapter.Items = new BaseItem[] { root, own, unknown, nested, child, orphan, alias, publicItem, physical, physicalChild }.ToDictionary(item => item.InternalId);
    adapter.Locations[1] = new[] { media };
    journal.ReserveRootIdentity(prepared, root.Id);
    var pair = new NativeItem(root.InternalId, root.Id);
    bindings.Register(prepared, new[] { pair, new NativeItem(own.InternalId, own.Id) });
    journal.Activate(prepared, pair);
    Check("Positive owner receives the registered active item", access.DecideItem(own, owner) == Access.Allowed);
    Check("Foreign account is denied that same item", access.DecideItem(own, foreign) == Access.Denied);
    Check("Ordinary public source works for both accounts", access.DecideItem(publicItem, owner) == Access.Unknown && access.DecideItem(publicItem, foreign) == Access.Unknown);
    Check("Unknown private descendants denied to both accounts", access.DecideItem(unknown, owner) == Access.Denied && access.DecideItem(unknown, foreign) == Access.Denied);
    Check("Canonical private path alias denied to both accounts", access.DecideItem(alias, owner) == Access.Denied && access.DecideItem(alias, foreign) == Access.Denied);
    var ledger = bindings.ReadAccessSnapshot(foreign.Id).Items;
    var direct = Candidate.Collect(library, ledger, journal.Entries(), mediaRoot, true).Select(item => item.InternalId).ToHashSet();
    var indexed = Candidate.Collect(library, ledger, journal.Entries(), mediaRoot, false).Select(item => item.InternalId).ToHashSet();
    Check("Direct-parent candidate includes registered source", direct.Contains(own.InternalId));
    Check("Direct-parent candidate includes unregistered child", direct.Contains(unknown.InternalId));
    Check("Direct-parent candidate includes nested external-path child", direct.Contains(child.InternalId));
    Check("Direct-parent candidate includes unregistered media orphan", direct.Contains(orphan.InternalId));
    Check("Direct-parent candidate includes descendant of private physical path", direct.Contains(physicalChild.InternalId));
    Check("Ordinary public source is outside the candidate private scope", !direct.Contains(publicItem.InternalId));
    Check("Indexed ancestry misses a child when its native ancestor index is stale", !indexed.Contains(unknown.InternalId));
    Check("Direct parent walk covers that stale-ancestor case", direct.Contains(unknown.InternalId));
    Check("Both string-prefix candidates miss the canonical private path alias", !direct.Contains(alias.InternalId) && !indexed.Contains(alias.InternalId));
    Check("Private inventory replacement must remain disabled", adapter.Items.Values.Any(item => access.DecideItem(item, foreign) == Access.Denied && !direct.Contains(item.InternalId)));

    // A preparing reservation without a binding is a separate private scope.
    profiles.Save(foreign.Id, 0, new[] { "UC" + new string('b', 22) }, "synthetic-key-B", false);
    var preparing = profiles.Prepare(foreign.Id);
    journal.Begin(preparing);
    var reserved = new CollectionFolder { InternalId = 11, Id = Guid.NewGuid() };
    var reservedChild = new Video { InternalId = 12, Id = Guid.NewGuid(), ParentId = 11, Path = Path.Combine(directory, "reserved-external.mp4") };
    adapter.Items[11] = reserved; adapter.Items[12] = reservedChild;
    journal.ReserveRootIdentity(preparing, reserved.Id);
    var reservedCandidate = Candidate.Collect(library, ledger, journal.Entries(), mediaRoot, true).Select(item => item.InternalId).ToHashSet();
    Check("Unbound reserved root remains denied to its owner", access.DecideItem(reserved, foreign) == Access.Denied);
    Check("Candidate resolves the reserved GUID and its unregistered child", reservedCandidate.Contains(11) && reservedCandidate.Contains(12));
    Check("Reserved child denied to both accounts", access.DecideItem(reservedChild, foreign) == Access.Denied && access.DecideItem(reservedChild, owner) == Access.Denied);
    var inventory = new PersonalYouTubeNativeAccess.SourceInventory(access, adapter.Items.Values.ToArray(), 0);
    var ownerContext = access.CreateListContext(owner, inventory);
    var foreignContext = access.CreateListContext(foreign, inventory);
    var ownerDenials = ownerContext.DeniedSourceIds();
    var foreignDenials = foreignContext.DeniedSourceIds();
    Check("Production inventory preserves owner positive control", !ownerDenials.Contains(own.InternalId));
    Check("Production inventory preserves foreign negative control", foreignDenials.Contains(own.InternalId));
    Check("Production inventory catches the canonical alias missed by the prototype", ownerDenials.Contains(alias.InternalId) && foreignDenials.Contains(alias.InternalId));
    Check("Production inventory catches unregistered descendants with external paths", ownerDenials.Contains(child.InternalId) && foreignDenials.Contains(child.InternalId));
    Check("Production inventory catches private physical ancestors", ownerDenials.Contains(physicalChild.InternalId) && foreignDenials.Contains(physicalChild.InternalId));
    Check("Production inventory catches unbound reserved children", ownerDenials.Contains(reservedChild.InternalId) && foreignDenials.Contains(reservedChild.InternalId));
    Check("Production inventory retains ordinary public content", !ownerDenials.Contains(publicItem.InternalId) && !foreignDenials.Contains(publicItem.InternalId));
    Check("Production inventory agrees with the full resolver for all ordinary sources", adapter.Items.Values.All(item => foreignDenials.Contains(item.InternalId) == (access.DecideItem(item, foreign) == Access.Denied)));
    Check("Source fingerprints start current", inventory.ObjectsCurrent);
    Check("Unsupported native library keeps full-scan fallback", !PersonalYouTubeNativeSourceBarrier.Install(library) && access.ReadSourceInventory() == null);
    publicItem.ParentId = root.InternalId;
    Check("In-memory reparenting invalidates a previously public snapshot", !inventory.ObjectsCurrent);
    publicItem.ParentId = 0;
    var authorityBefore = ownerContext.AuthorityCurrent();
    profiles.Delete(owner.Id, profiles.Read(owner.Id).Revision);
    Check("Profile content revocation invalidates the request authority stamp", authorityBefore && !ownerContext.AuthorityCurrent());
    Check("Revoked owner loses previously allowed private source", access.DecideItem(own, owner) == Access.Denied);
    Check("Public source survives private owner revocation", access.DecideItem(publicItem, owner) == Access.Unknown);
    var profilePath = Path.Combine(directory, foreign.Id.ToString("N") + ".json");
    File.WriteAllText(profilePath, "{");
    Check("Corrupt private profile fails closed without denying public source", access.DecideItem(reservedChild, foreign) == Access.Denied && access.DecideItem(publicItem, owner) == Access.Unknown);
    File.WriteAllText(Path.Combine(directory, "publication-journal.json"), "{");
    Check("Complete scope authority preserves public content under corrupt journal", access.DecideItem(publicItem, owner) == Access.Unknown);
    Check("Corrupt journal never grants private owner or foreign permission", access.DecideItem(own, owner) == Access.Denied && access.DecideItem(own, foreign) == Access.Denied);
    Check("Corrupt journal still denies reserved children", access.DecideItem(reservedChild, foreign) == Access.Denied);
    Check("Corrupt journal still denies canonical private aliases", access.DecideItem(alias, owner) == Access.Denied);
    Check("Absent retired identity remains denied under journal corruption", journal.DecideAbsentReference(own.InternalId.ToString()) == Access.Denied);
    Check("Absent unrelated public identity stays unknown under journal corruption", journal.DecideAbsentReference("999999") == Access.Unknown);
    var completePath = Path.Combine(directory, "private-source-scopes.json");
    var complete = File.ReadAllText(completePath);
    File.WriteAllText(completePath, "{");
    var lostAuthorityDenied = false;
    try { access.DecideItem(publicItem, owner); } catch (InvalidDataException) { lostAuthorityDenied = true; }
    Check("Loss of classification authority cannot fail open", lostAuthorityDenied);
    File.WriteAllText(completePath, complete);
    File.WriteAllText(completePath, complete.Replace("\"Complete\":true", "\"Complete\":false", StringComparison.Ordinal));
    var markerPath = Path.Combine(directory, "private-source-scopes.required");
    var completeMarker = File.ReadAllBytes(markerPath);
    File.WriteAllText(markerPath, Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(completePath))));
    var incompleteDenied = false;
    try { access.DecideItem(publicItem, owner); } catch (InvalidDataException) { incompleteDenied = true; }
    Check("Incomplete scope migration cannot recover a corrupt legacy journal", incompleteDenied);
    File.WriteAllText(completePath, complete);
    File.WriteAllBytes(markerPath, completeMarker);
    var stamp = File.GetLastWriteTimeUtc(completePath);
    File.WriteAllText(completePath, complete.Replace(owner.Id.ToString(), Guid.NewGuid().ToString(), StringComparison.Ordinal));
    File.SetLastWriteTimeUtc(completePath, stamp);
    var replayDenied = false;
    try { access.DecideItem(publicItem, owner); } catch (InvalidDataException) { replayDenied = true; }
    Check("Altered scope contents with restored timestamp fail the independent integrity marker", replayDenied);
    File.WriteAllText(completePath, complete);
    Check("Scope authority survives resolver restart", new PersonalYouTubeNativeAccess(directory, library).DecideItem(publicItem, owner) == Access.Unknown);
    var barrierBefore = PersonalYouTubeNativeSourceBarrier.Snapshot();
    var mutation = PersonalYouTubeNativeSourceBarrier.Begin();
    Check("Native mutation is visible before the write body", PersonalYouTubeNativeSourceBarrier.Snapshot().Writers == barrierBefore.Writers + 1);
    var nestedMutation = PersonalYouTubeNativeSourceBarrier.Begin();
    nestedMutation.Dispose();
    Check("Nested writer completion cannot release the outer mutation", PersonalYouTubeNativeSourceBarrier.Snapshot().Writers == barrierBefore.Writers + 1);
    mutation.Dispose(); mutation.Dispose();
    Check("Exception/finalizer disposal is idempotent and advances the source version", PersonalYouTubeNativeSourceBarrier.Snapshot().Writers == barrierBefore.Writers && PersonalYouTubeNativeSourceBarrier.Snapshot().Version > barrierBefore.Version);
    completed = true;
}
finally
{
    Directory.Delete(directory, true);
    var dll = typeof(Plugin).Assembly.Location;
    var evidence = new {
        Completed = completed, ProductionDLLSHA256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(dll))),
        Platform = System.Runtime.InteropServices.RuntimeInformation.OSDescription,
        Scope = "Production access resolver and storage; SDK library adapter with deliberately stale ancestor index and lexical path filters. No native SQL/HTTP, Emby process, Google or production data.",
        CandidateSafeToEnable = false, Observations = observations, TestDataGone = !Directory.Exists(directory)
    };
    var output = JsonSerializer.Serialize(evidence, new JsonSerializerOptions { WriteIndented = true });
    File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "IMPLEMENTATION-EVIDENCE.json"), output);
    Console.WriteLine(output);
}

public class LibraryAdapter : DispatchProxy
{
    internal Dictionary<long, BaseItem> Items = new();
    internal Dictionary<long, string[]> Locations = new();
    protected override object? Invoke(MethodInfo? method, object?[]? args)
    {
        switch (method!.Name)
        {
            case "GetItemById": return args![0] is long id ? Items.GetValueOrDefault(id) : Items.Values.SingleOrDefault(item => item.Id == (Guid)args![0]!);
            case "GetCollectionFolders": return Array.Empty<Folder>();
            case "GetVirtualFolders": return Locations.Select(pair => new VirtualFolderInfo { ItemId = pair.Key.ToString(), Locations = pair.Value }).ToList();
            case "GetItemList":
                var query = (InternalItemsQuery)args![0]!;
                var items = Items.Values.AsEnumerable();
                if (!string.IsNullOrEmpty(query.Path)) items = items.Where(item => item.Path == query.Path);
                if (!string.IsNullOrEmpty(query.PathStartsWith)) items = items.Where(item => item.Path?.StartsWith(query.PathStartsWith, StringComparison.OrdinalIgnoreCase) == true);
                if (query.ParentIds?.Length > 0) items = items.Where(item => query.ParentIds.Contains(item.ParentId));
                // Deliberately missing the private root's child aliases in the
                // ancestor index, even though current ParentId is accurate.
                if (query.AncestorIds?.Length > 0) items = items.Where(item => item.InternalId == 2 && query.AncestorIds.Contains(1));
                return items.ToArray();
            default: throw new NotSupportedException(method.Name);
        }
    }
}
