using Emby.YouTubePlugin;
using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;
using Access = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Access;

internal static class PublicationJournalChecks
{
    internal static void Run(string root, Action<string, bool> check)
    {
        void Denied<T>(string name, Action action) where T : Exception
        {
            try { action(); }
            catch (T) { check(name, true); return; }
            throw new Exception(name);
        }
        var profiles = new PersonalYouTubeStore(root);
        var bindings = new PersonalYouTubeNativeBindings(root);
        var journal = new PersonalYouTubePublicationJournal(root);
        var a = Guid.NewGuid(); var b = Guid.NewGuid();
        var av = profiles.Save(a, 0, new[] { "UC" + new string('a', 22) }, null, false);
        var bv = profiles.Save(b, 0, new[] { "UC" + new string('a', 22) }, null, false);
        var sa = profiles.Prepare(a); var sb = profiles.Prepare(b);
        var ea = journal.Begin(sa); var eb = journal.Begin(sb);
        var pathA = journal.MediaPath(ea); var pathB = journal.MediaPath(eb);
        check("Private creation is journaled before any media directory exists", ea.State == "Preparing" && !Directory.Exists(pathA) && !Directory.Exists(pathB));
        check("Same channel owners reserve distinct generation directories", pathA != pathB && ea.GenerationId != eb.GenerationId);
        var journalPath = Path.Combine(root, "publication-journal.json");
        var marker = Path.Combine(root, "publication-journal.required");
        var initial = File.ReadAllText(journalPath);
        check("Repeated Begin is idempotent without rewriting journal", journal.Begin(sa) == ea && File.ReadAllText(journalPath) == initial);
        check("Fresh journal exposes persisted pending work for recovery", new PersonalYouTubePublicationJournal(root).Pending().Contains(ea));
        var ra = new NativeItem(80001, Guid.NewGuid()); var va = new NativeItem(80002, Guid.NewGuid());
        var rb = new NativeItem(80003, Guid.NewGuid()); var vb = new NativeItem(80004, Guid.NewGuid());
        var unknown = new NativeItem(80999, Guid.NewGuid());
        check("Private preparing path is denied before native registration", journal.DecideItem(unknown, Array.Empty<NativeItem>(), a, Path.Combine(pathA, "video.mp4")) == Access.Denied);
        check("Unbound virtual root is denied from configured private source despite public native path", journal.DecideSources(unknown, Array.Empty<NativeItem>(), a, new[] { Path.Combine(root, "virtual-roots", "entry"), pathA }) == Access.Denied);
        check("Configured preparing source denial is independent of source ordering", journal.DecideSources(unknown, Array.Empty<NativeItem>(), a, new[] { pathA, Path.Combine(root, "virtual-roots", "entry") }) == Access.Denied);
        check("Unreserved path under private namespace is denied", journal.DecideItem(unknown, Array.Empty<NativeItem>(), a, Path.Combine(root, "media", "unreserved", "video.mp4")) == Access.Denied);
        check("Unrelated public path and identity remain unknown", journal.DecideItem(unknown, Array.Empty<NativeItem>(), a, Path.Combine(root, "public", "video.mp4")) == Access.Unknown);
        Denied<InvalidOperationException>("Activation without durable native root binding is rejected", () => journal.Activate(sa, ra));
        check("Rejected activation preserves journal", File.ReadAllText(journalPath) == initial);
        Denied<ArgumentException>("Empty provisional native root identity is rejected", () => journal.ReserveRootIdentity(sa, Guid.Empty));
        check("Actual root GUID can be reserved before numeric binding", journal.ReserveRootIdentity(sa, ra.ItemId));
        var reservedText = File.ReadAllText(journalPath);
        check("Repeated provisional root reservation is idempotent", journal.ReserveRootIdentity(sa, ra.ItemId) && File.ReadAllText(journalPath) == reservedText);
        check("Unbound reserved root denies owner without any source locations", journal.DecideSources(ra, Array.Empty<NativeItem>(), a, Array.Empty<string>()) == Access.Denied);
        check("Unbound reserved root denies foreign and anonymous accounts", journal.DecideSources(ra, Array.Empty<NativeItem>(), b, Array.Empty<string>()) == Access.Denied && journal.DecideSources(ra, Array.Empty<NativeItem>(), Guid.Empty, Array.Empty<string>()) == Access.Denied);
        check("Unbound descendant cannot bypass reserved root ancestry", journal.DecideSources(unknown, new[] { ra }, a, Array.Empty<string>()) == Access.Denied);
        check("Fresh instance preserves provisional root denial", new PersonalYouTubePublicationJournal(root).DecideSources(ra, Array.Empty<NativeItem>(), a, Array.Empty<string>()) == Access.Denied);
        Denied<InvalidOperationException>("Preparing generation cannot switch reserved root GUID", () => journal.ReserveRootIdentity(sa, va.ItemId));
        Denied<InvalidOperationException>("Other generation cannot reserve same native root GUID", () => journal.ReserveRootIdentity(sb, ra.ItemId));
        check("B reserves independent native root identity", journal.ReserveRootIdentity(sb, rb.ItemId));
        check("Reserved absent GUID stays private before native persistence", journal.DecideAbsentReference(ra.ItemId.ToString("N")) == Access.Denied);
        check("Hyphenated absent reserved GUID cannot escape denial", journal.DecideAbsentReference(ra.ItemId.ToString("D")) == Access.Denied);
        check("Uppercase absent reserved GUID stays private", journal.DecideAbsentReference(ra.ItemId.ToString("N").ToUpperInvariant()) == Access.Denied);
        check("Unrelated absent GUID remains unknown", journal.DecideAbsentReference(unknown.ItemId.ToString("N")) == Access.Unknown);
        check("Unrelated absent numeric identity remains unknown", journal.DecideAbsentReference(unknown.InternalId.ToString()) == Access.Unknown);
        bindings.Register(sa, new[] { ra, va }); bindings.Register(sb, new[] { rb, vb });
        var rawRefresh = bindings.ReadAccessSnapshot(a);
        check("Storage-only binding refresh keeps foreign identities denied", rawRefresh.DeniedIds.Contains(rb.InternalId) && !rawRefresh.DeniedIds.Contains(ra.InternalId));
        check("Registered Preparing refresh denies even owner without native DB lookup", journal.DeniedRegisteredIds(a).Contains(ra.InternalId) && journal.DeniedRegisteredIds(a).Contains(va.InternalId));
        var anonymousRefresh = journal.DeniedRegisteredIds(Guid.Empty);
        check("Anonymous registered refresh denies all private pairs", anonymousRefresh.Length == bindings.ReadAccessSnapshot(Guid.Empty).Items.Length
            && new[] { ra.InternalId, va.InternalId, rb.InternalId, vb.InternalId }.All(anonymousRefresh.Contains));
        check("Bound absent numeric alias is never an owner permission", journal.DecideAbsentReference(va.InternalId.ToString()) == Access.Denied);
        check("Alternate numeric spelling cannot escape old private binding", journal.DecideAbsentReference("000" + va.InternalId) == Access.Denied);
        check("Bound absent child GUID remains private", journal.DecideAbsentReference(va.ItemId.ToString("D")) == Access.Denied);
        Denied<InvalidOperationException>("Bound child cannot substitute for reserved activation root", () => journal.Activate(sa, va));
        check("Registered preparing root metadata remains denied without path context", journal.DecideItem(ra, Array.Empty<NativeItem>(), a, null) == Access.Denied);
        check("Registered preparing child remains denied", journal.DecideItem(va, new[] { ra }, a, Path.Combine(pathA, "video.mp4")) == Access.Denied);
        check("Fresh journal instance retains preparing denial", new PersonalYouTubePublicationJournal(root).DecideItem(ra, Array.Empty<NativeItem>(), a, null) == Access.Denied);
        Denied<InvalidOperationException>("Foreign native root cannot activate reservation", () => journal.Activate(sa, rb));
        Denied<InvalidOperationException>("Mismatched root ID and GUID cannot activate reservation", () => journal.Activate(sa, new(ra.InternalId, Guid.NewGuid())));
        check("Durably bound own root activates current publication", journal.Activate(sa, ra));
        check("Active native root is allowed without filesystem path context", journal.DecideItem(ra, Array.Empty<NativeItem>(), a, null) == Access.Allowed);
        check("Activated own registered IDs leave refreshed denial set", !journal.DeniedRegisteredIds(a).Contains(ra.InternalId) && !journal.DeniedRegisteredIds(a).Contains(va.InternalId));
        check("Active journal cannot allow an absent native root", journal.DecideAbsentReference(ra.InternalId.ToString()) == Access.Denied);
        check("Registered active child with real root ancestry is allowed", journal.DecideItem(va, new[] { ra }, a, Path.Combine(pathA, "video.mp4")) == Access.Allowed);
        check("Active virtual root accepts its configured source and separate native path", journal.DecideSources(ra, Array.Empty<NativeItem>(), a, new[] { Path.Combine(root, "virtual-roots", "entry"), pathA }) == Access.Allowed);
        check("Unreserved second private source cannot be hidden by an allowed first source", journal.DecideSources(ra, Array.Empty<NativeItem>(), a, new[] { pathA, Path.Combine(root, "media", "unreserved") }) == Access.Denied);
        check("Active private child is denied to foreign and anonymous accounts", journal.DecideItem(va, new[] { ra }, b, Path.Combine(pathA, "video.mp4")) == Access.Denied && journal.DecideItem(va, new[] { ra }, Guid.Empty, Path.Combine(pathA, "video.mp4")) == Access.Denied);
        check("Known child cannot bypass publication root ancestry", journal.DecideItem(va, Array.Empty<NativeItem>(), a, null) == Access.Denied);
        check("Native identity cannot borrow another reservation's path", journal.DecideItem(va, new[] { ra }, a, Path.Combine(pathB, "video.mp4")) == Access.Denied);
        check("Unregistered child stays denied under active root", journal.DecideItem(unknown, new[] { ra }, a, Path.Combine(pathA, "new.mp4")) == Access.Denied);
        var active = File.ReadAllText(journalPath);
        check("Same-root activation is idempotent", journal.Activate(sa, ra) && File.ReadAllText(journalPath) == active);
        Denied<InvalidOperationException>("Already active publication cannot switch native root", () => journal.Activate(sa, va));
        check("B can activate independent publication", journal.Activate(sb, rb) && journal.DecideItem(vb, new[] { rb }, b, Path.Combine(pathB, "video.mp4")) == Access.Allowed);
        check("Multiple active private generations in one source list are denied", journal.DecideSources(ra, Array.Empty<NativeItem>(), a, new[] { pathA, pathB }) == Access.Denied);
        check("Conflicting private sources are denied in reverse order", journal.DecideSources(ra, Array.Empty<NativeItem>(), a, new[] { pathB, pathA }) == Access.Denied);
        profiles.Delete(a, av.Revision);
        check("Profile deletion immediately denies active publication", journal.DecideItem(va, new[] { ra }, a, Path.Combine(pathA, "video.mp4")) == Access.Denied);
        check("Storage-only refresh picks up completed owner deletion", journal.DeniedRegisteredIds(a).Contains(ra.InternalId) && journal.DeniedRegisteredIds(a).Contains(va.InternalId));
        check("B registered refresh stays allowed while A is deleted", !journal.DeniedRegisteredIds(b).Contains(rb.InternalId) && !journal.DeniedRegisteredIds(b).Contains(vb.InternalId));
        check("Deleted snapshot cannot activate publication", !journal.Activate(sa, ra));
        check("Deleted snapshot cannot reserve another native root identity", !journal.ReserveRootIdentity(sa, Guid.NewGuid()));
        Denied<InvalidOperationException>("Deleted snapshot cannot begin another publication", () => journal.Begin(sa));
        av = profiles.Read(a); profiles.Save(a, av.Revision, new[] { "UC" + new string('a', 22) }, null, false);
        var recreated = profiles.Prepare(a); var next = journal.Begin(recreated);
        check("New generation reserves a distinct directory and retains old journal entry", journal.MediaPath(next) != pathA && File.ReadAllText(journalPath).Contains(ea.GenerationId.ToString()));
        check("New generation cannot inherit old active native identities", journal.DecideItem(va, new[] { ra }, a, Path.Combine(pathA, "video.mp4")) == Access.Denied);
        check("Fresh instance denial refresh retains old generation IDs", new PersonalYouTubePublicationJournal(root).DeniedRegisteredIds(a).Contains(ra.InternalId));
        check("Retired absent aliases stay denied after generation replacement", new PersonalYouTubePublicationJournal(root).DecideAbsentReference(va.ItemId.ToString("D")) == Access.Denied);
        check("B remains allowed after A lifecycle", journal.DecideItem(vb, new[] { rb }, b, Path.Combine(pathB, "video.mp4")) == Access.Allowed);
        var persisted = File.ReadAllText(journalPath);
        File.Delete(journalPath);
        Denied<InvalidDataException>("Missing required journal blocks registered refresh", () => journal.DeniedRegisteredIds(a));
        Denied<InvalidDataException>("Missing required journal never falls back to public", () => new PersonalYouTubePublicationJournal(root).DecideItem(unknown, Array.Empty<NativeItem>(), a, Path.Combine(root, "public", "video.mp4")));
        Denied<InvalidDataException>("Missing journal cannot silently recreate reservations", () => journal.Begin(recreated));
        File.WriteAllText(journalPath, persisted);
        File.Delete(marker);
        Denied<InvalidDataException>("Missing publication marker rejects existing journal", () => journal.Begin(recreated));
        File.WriteAllBytes(marker, new byte[] { 1 });
        File.WriteAllText(journalPath, "{");
        Denied<InvalidDataException>("Corrupt journal blocks registered refresh", () => journal.DeniedRegisteredIds(b));
        Denied<InvalidDataException>("Corrupt publication journal cannot permit known private data", () => journal.DecideItem(vb, new[] { rb }, b, Path.Combine(pathB, "video.mp4")));
        File.WriteAllText(journalPath, persisted);
        check("Journal recovery preserves old denial and B positive control", new PersonalYouTubePublicationJournal(root).DecideItem(va, new[] { ra }, a, Path.Combine(pathA, "video.mp4")) == Access.Denied && journal.DecideItem(vb, new[] { rb }, b, Path.Combine(pathB, "video.mp4")) == Access.Allowed);
        check("Publication journal leaves no temporary files", !Directory.EnumerateFiles(root, "*.tmp").Any());
    }
}
