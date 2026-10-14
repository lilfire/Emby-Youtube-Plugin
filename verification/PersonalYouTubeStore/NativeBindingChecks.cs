using Emby.YouTubePlugin;
using System.Text.Json.Nodes;

internal static class NativeBindingChecks
{
    internal static async Task Run(string root, Action<string, bool> check)
    {
        void Denied<T>(string name, Action action) where T : Exception
        {
            try { action(); }
            catch (T) { check(name, true); return; }
            throw new Exception(name);
        }
        var profiles = new PersonalYouTubeStore(root);
        var ledger = new PersonalYouTubeNativeBindings(root);
        var a = Guid.NewGuid(); var b = Guid.NewGuid();
        var channel = "UC" + new string('a', 22);
        var av = profiles.Save(a, 0, new[] { channel }, null, false);
        var bv = profiles.Save(b, 0, new[] { channel }, null, false);
        var sa = profiles.Prepare(a); var sb = profiles.Prepare(b);
        var ai = new PersonalYouTubeNativeBindings.NativeItem(70001, Guid.NewGuid());
        var bi = new PersonalYouTubeNativeBindings.NativeItem(70002, Guid.NewGuid());
        var path = Path.Combine(root, "native-reference-bindings.json");
        var marker = Path.Combine(root, "native-reference-bindings.required");
        check("Never-created native ledger distinguishes unknown reference", ledger.Decide("70001", a) == PersonalYouTubeNativeBindings.Access.Unknown);
        check("Current A snapshot registers native identity pair", ledger.Register(sa, new[] { ai }));
        check("Current B snapshot registers same channel with distinct native identities", ledger.Register(sb, new[] { bi }));
        foreach (var item in new[] { (ai, a, b), (bi, b, a) })
        {
            var number = item.Item1.InternalId.ToString(System.Globalization.CultureInfo.InvariantCulture);
            var guid = item.Item1.ItemId.ToString("N");
            check("Both native aliases allow their actual owner", ledger.Decide(number, item.Item2) == PersonalYouTubeNativeBindings.Access.Allowed && ledger.Decide(guid, item.Item2) == PersonalYouTubeNativeBindings.Access.Allowed);
            check("Both native aliases deny another account and anonymous access", ledger.Decide(number, item.Item3) == PersonalYouTubeNativeBindings.Access.Denied && ledger.Decide(guid, item.Item3) == PersonalYouTubeNativeBindings.Access.Denied && ledger.Decide(number, Guid.Empty) == PersonalYouTubeNativeBindings.Access.Denied);
        }
        var persisted = File.ReadAllText(path);
        check("Idempotent registration leaves ledger bytes unchanged", ledger.Register(sa, new[] { ai }) && File.ReadAllText(path) == persisted);
        Denied<InvalidOperationException>("Foreign owner cannot adopt existing native pair", () => ledger.Register(sb, new[] { ai }));
        var newItem = new PersonalYouTubeNativeBindings.NativeItem(70003, Guid.NewGuid());
        Denied<InvalidOperationException>("Batch collision rejects entire registration", () => ledger.Register(sb, new[] { newItem, ai }));
        check("Rejected batch persists no partial reference", File.ReadAllText(path) == persisted && ledger.Find("70003") == null);
        check("Unbound descendant of private ancestor is denied even to owner", ledger.DecideItem(newItem, new[] { ai }, a) == PersonalYouTubeNativeBindings.Access.Denied);
        check("Unbound descendant is denied to foreign and anonymous subjects", ledger.DecideItem(newItem, new[] { ai }, b) == PersonalYouTubeNativeBindings.Access.Denied && ledger.DecideItem(newItem, new[] { ai }, Guid.Empty) == PersonalYouTubeNativeBindings.Access.Denied);
        check("Unbound item without known private ancestry remains unknown", ledger.DecideItem(newItem, Array.Empty<PersonalYouTubeNativeBindings.NativeItem>(), a) == PersonalYouTubeNativeBindings.Access.Unknown);
        check("Actual matched pair and same-generation ancestry are allowed", ledger.DecideItem(ai, new[] { ai }, a) == PersonalYouTubeNativeBindings.Access.Allowed);
        check("Conflicting ancestor owner denies known item", ledger.DecideItem(ai, new[] { bi }, a) == PersonalYouTubeNativeBindings.Access.Denied);
        check("Reused numeric alias with different actual GUID is denied", ledger.DecideItem(new(ai.InternalId, Guid.NewGuid()), Array.Empty<PersonalYouTubeNativeBindings.NativeItem>(), a) == PersonalYouTubeNativeBindings.Access.Denied);
        check("Reused GUID with different actual numeric ID is denied", ledger.DecideItem(new(70999, ai.ItemId), Array.Empty<PersonalYouTubeNativeBindings.NativeItem>(), a) == PersonalYouTubeNativeBindings.Access.Denied);
        check("Conflicting actual ancestor pair denies known item", ledger.DecideItem(ai, new[] { new PersonalYouTubeNativeBindings.NativeItem(bi.InternalId, Guid.NewGuid()) }, a) == PersonalYouTubeNativeBindings.Access.Denied);
        Denied<ArgumentException>("Duplicate aliases within new batch rejected", () => ledger.Register(sa, new[] { newItem, new PersonalYouTubeNativeBindings.NativeItem(70003, Guid.NewGuid()) }));
        check("Fresh ledger instance recovers exact owner and generation", new PersonalYouTubeNativeBindings(root).Find(ai.ItemId.ToString("N")) is { } recovered && recovered.OwnerUserId == a && recovered.GenerationId == sa.GenerationId && recovered.CollectionId == sa.CollectionId);
        profiles.Delete(a, av.Revision);
        check("Deleted profile denies old native aliases", ledger.Decide("70001", a) == PersonalYouTubeNativeBindings.Access.Denied && ledger.Decide(ai.ItemId.ToString("N"), a) == PersonalYouTubeNativeBindings.Access.Denied);
        check("Late deleted-generation registration is never persisted", !ledger.Register(sa, new[] { newItem }) && File.ReadAllText(path) == persisted);
        av = profiles.Read(a);
        av = profiles.Save(a, av.Revision, new[] { channel }, null, false);
        var recreated = profiles.Prepare(a);
        check("New generation cannot reopen old aliases after restart", new PersonalYouTubeNativeBindings(root).Decide("70001", a) == PersonalYouTubeNativeBindings.Access.Denied);
        Denied<InvalidOperationException>("New generation cannot reuse an old numeric ID", () => ledger.Register(recreated, new[] { new PersonalYouTubeNativeBindings.NativeItem(70001, Guid.NewGuid()) }));
        Denied<InvalidOperationException>("New generation cannot reuse an old GUID", () => ledger.Register(recreated, new[] { new PersonalYouTubeNativeBindings.NativeItem(70004, ai.ItemId) }));
        check("New generation can register a genuinely new identity pair", ledger.Register(recreated, new[] { newItem }) && ledger.Decide("70003", a) == PersonalYouTubeNativeBindings.Access.Allowed);
        check("New-generation item cannot inherit an old-generation ancestor", ledger.DecideItem(newItem, new[] { ai }, a) == PersonalYouTubeNativeBindings.Access.Denied);
        check("Registered new-generation pair is allowed with no conflicting ancestry", ledger.DecideItem(newItem, Array.Empty<PersonalYouTubeNativeBindings.NativeItem>(), a) == PersonalYouTubeNativeBindings.Access.Allowed);
        var newRoot = new PersonalYouTubeNativeBindings.NativeItem(70100, Guid.NewGuid());
        check("Current generation registers a new ancestor identity", ledger.Register(recreated, new[] { newRoot }));
        check("Registered descendant and ancestor from same generation are allowed", ledger.DecideItem(newItem, new[] { newRoot }, a) == PersonalYouTubeNativeBindings.Access.Allowed);
        var aPath = Path.Combine(root, a.ToString("N") + ".json");
        var aBytes = File.ReadAllText(aPath);
        File.WriteAllText(aPath, "{");
        check("Corrupt A profile denies A while B stays allowed", ledger.Decide("70003", a) == PersonalYouTubeNativeBindings.Access.Denied && ledger.Decide("70002", b) == PersonalYouTubeNativeBindings.Access.Allowed);
        File.WriteAllText(aPath, aBytes);
        var contested = new PersonalYouTubeNativeBindings.NativeItem(70005, Guid.NewGuid());
        var wins = 0; var collisions = 0;
        await Task.WhenAll(new[] { recreated, sb }.Select(snapshot => Task.Run(() =>
        {
            try { if (new PersonalYouTubeNativeBindings(root).Register(snapshot, new[] { contested })) Interlocked.Increment(ref wins); }
            catch (InvalidOperationException) { Interlocked.Increment(ref collisions); }
        })));
        var winner = ledger.Find("70005")!;
        check("Concurrent owners competing for same pair have one durable winner", wins == 1 && collisions == 1 && ledger.Decide("70005", winner.OwnerUserId) == PersonalYouTubeNativeBindings.Access.Allowed && ledger.Decide("70005", winner.OwnerUserId == a ? b : a) == PersonalYouTubeNativeBindings.Access.Denied);
        persisted = File.ReadAllText(path);
        File.Delete(path);
        Denied<InvalidDataException>("Missing required ledger is not unknown/public", () => new PersonalYouTubeNativeBindings(root).Decide("70002", b));
        Denied<InvalidDataException>("Missing ledger cannot silently recreate and lose old tombstones", () => ledger.Register(sb, new[] { new PersonalYouTubeNativeBindings.NativeItem(70006, Guid.NewGuid()) }));
        File.WriteAllText(path, persisted);
        File.Delete(marker);
        Denied<InvalidDataException>("Missing required marker rejects existing ledger", () => ledger.Find("70002"));
        File.WriteAllBytes(marker, new byte[] { 1 });
        File.WriteAllText(path, "{");
        Denied<InvalidDataException>("Corrupt ledger is unavailable even for unknown alias", () => ledger.Find("unknown"));
        File.WriteAllText(path, persisted);
        var malformed = JsonNode.Parse(persisted)!;
        malformed["Items"]!.AsArray().Add(malformed["Items"]![0]!.DeepClone());
        File.WriteAllText(path, malformed.ToJsonString());
        Denied<InvalidDataException>("Duplicate persisted native identity is rejected", () => ledger.Find("70002"));
        File.WriteAllText(path, persisted);
        check("Recovered ledger retains old denial and positive B access", ledger.Decide("70001", a) == PersonalYouTubeNativeBindings.Access.Denied && ledger.Decide("70002", b) == PersonalYouTubeNativeBindings.Access.Allowed);
        check("Native binding persist leaves no temporary files", !Directory.EnumerateFiles(root, "*.tmp").Any());
    }
}
