using Emby.YouTubePlugin;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

if(args.Contains("--inspect-personal-assets"))
{
    using var stream = typeof(PersonalYouTubeService).Assembly.GetManifestResourceStream("Emby.YouTubePlugin.Configuration.YouTubePersonalSettings.html")!;
    using var reader = new StreamReader(stream);
    var html = reader.ReadToEnd();
    Console.WriteLine(JsonSerializer.Serialize(new { Version = typeof(PersonalYouTubeService).Assembly.GetName().Version?.ToString(), HasHiddenButtonStyle = html.Contains(".ytPersonalCancelDelete[hidden]"), HasOldBodyHeading = html.Contains("<h2>YouTube</h2>") }));
    return;
}

if (args.Contains("--inspect-refresh-sdk"))
{
    foreach(var method in typeof(MediaBrowser.Controller.Library.IUserManager).GetMethods().Where(method => method.Name.Contains("Policy")))
        Console.WriteLine(method);
    foreach (var constructor in typeof(MediaBrowser.Controller.Providers.MetadataRefreshOptions).GetConstructors())
        Console.WriteLine(constructor);
    foreach (var constructor in typeof(MediaBrowser.Controller.Providers.DirectoryService).GetConstructors())
        Console.WriteLine(constructor);
    foreach (var method in typeof(MediaBrowser.Controller.Library.ILibraryManager).GetMethods().Where(method => method.Name.Contains("VirtualFolder") || method.Name.Contains("UpdateItem")))
        Console.WriteLine(method);
    foreach (var property in typeof(MediaBrowser.Model.Configuration.LibraryOptions).GetProperties().Where(property => property.Name.Contains("Type")))
        Console.WriteLine(property);
    return;
}

var artifactRoot = Path.GetFullPath("verification/PersonalYouTubeStore/bin");
Directory.CreateDirectory(artifactRoot);
var root = Path.Combine(artifactRoot, "data-" + Guid.NewGuid().ToString("N"));
var rows = new List<string>();
var completed = false;
void Check(string name, bool condition) { if (!condition) throw new Exception(name); rows.Add(name); }
void Denied<T>(string name, Action action) where T : Exception
{ try { action(); } catch (T) { rows.Add(name); return; } throw new Exception(name); }
try
{
    var store = new PersonalYouTubeStore(root);
    var a = Guid.NewGuid(); var b = Guid.NewGuid();
    var channel = "UC" + new string('a', 22);
    var av = store.Read(a);
    Check("Absent read has no persisted generation", av.Revision == 0 && av.State == "Absent" && !Directory.Exists(root));
    av = store.Save(a, 0, new[] { channel, channel }, "synthetic-a-key", false);
    var bv = store.Save(b, 0, new[] { channel }, "synthetic-b-key", false);
    Check("Same channel retains distinct owners and collection/generation IDs", av.CollectionId != bv.CollectionId && av.GenerationId != bv.GenerationId && av.Channels.Length == 1);
    Check("Keys prepared under their own identity", store.Prepare(a).ApiKey == "synthetic-a-key" && store.Prepare(b).ApiKey == "synthetic-b-key");
    Check("Public profile has no key field or value", !JsonSerializer.Serialize(av).Contains("synthetic-a-key") && typeof(PersonalYouTubeStore.View).GetProperty("ApiKey") == null);
    var aFile = Path.Combine(root, a.ToString("N") + ".json");
    var bFile = Path.Combine(root, b.ToString("N") + ".json");
    var aOriginal = File.ReadAllText(aFile); var bOriginal = File.ReadAllText(bFile);
    Check("No plaintext key in persisted profile", !aOriginal.Contains("synthetic-a-key") && !bOriginal.Contains("synthetic-b-key"));
    var snapshot = store.Prepare(a);
    Denied<InvalidOperationException>("Stale revision cannot overwrite profile", () => store.Save(a, 0, Array.Empty<string>(), null, true));
    Check("Rejected update preserved profile and B", File.ReadAllText(aFile) == aOriginal && File.ReadAllText(bFile) == bOriginal);
    Denied<ArgumentException>("Noncanonical channels rejected", () => store.Save(a, av.Revision, new[] { "../other" }, null, false));
    Denied<ArgumentException>("Ambiguous key update rejected", () => store.Save(a, av.Revision, Array.Empty<string>(), "key", true));
    Denied<ArgumentException>("Non-ASCII key rejected before persistence", () => store.Save(a, av.Revision, Array.Empty<string>(), "nøkkel", false));
    var tampered = JsonNode.Parse(aOriginal)!;
    tampered["Current"]!["EncryptedApiKey"] = JsonNode.Parse(bOriginal)!["Current"]!["EncryptedApiKey"]!.GetValue<string>();
    File.WriteAllText(aFile, tampered.ToJsonString());
    Denied<CryptographicException>("Cross-owner ciphertext cannot decrypt", () => store.Prepare(a));
    Check("B still decrypts after A tampering", store.Prepare(b).ApiKey == "synthetic-b-key");
    File.WriteAllText(aFile, aOriginal);
    var recreated = new PersonalYouTubeStore(root);
    Check("Fresh store recovers persisted identities and keys", recreated.Read(a).GenerationId == av.GenerationId && recreated.Prepare(a).ApiKey == "synthetic-a-key");
    av = store.Delete(a, av.Revision);
    Check("Deletion invalidates prepared snapshot and clears secret", !store.IsCurrent(snapshot) && !av.HasApiKey && av.State == "Deleted");
    Denied<InvalidOperationException>("Deleted generation cannot prepare requests", () => store.Prepare(a));
    av = store.Save(a, av.Revision, new[] { channel }, "synthetic-new-a-key", false);
    Check("Recreation retains collection but creates a new generation", av.CollectionId == snapshot.CollectionId && av.GenerationId != snapshot.GenerationId && store.Prepare(a).ApiKey == "synthetic-new-a-key");
    Check("Old generation remains a durable tombstone", JsonNode.Parse(File.ReadAllText(aFile))!["Retired"]!.AsArray().Count == 1);
    tampered = JsonNode.Parse(File.ReadAllText(aFile))!;
    var recreatedOriginal = File.ReadAllText(aFile);
    tampered["Current"]!["EncryptedApiKey"] = JsonNode.Parse(aOriginal)!["Current"]!["EncryptedApiKey"]!.GetValue<string>();
    File.WriteAllText(aFile, tampered.ToJsonString());
    Denied<CryptographicException>("Old-generation ciphertext cannot decrypt in new generation", () => store.Prepare(a));
    File.WriteAllText(aFile, recreatedOriginal);
    Check("Same name recreated account GUID has no old profile", store.Read(Guid.NewGuid()).State == "Absent");
    var revision = av.Revision;
    var successes = 0; var conflicts = 0;
    await Task.WhenAll(Enumerable.Range(0, 12).Select(_ => Task.Run(() =>
    {
        try { new PersonalYouTubeStore(root).Save(a, revision, new[] { channel }, null, false); Interlocked.Increment(ref successes); }
        catch (InvalidOperationException) { Interlocked.Increment(ref conflicts); }
    })));
    Check("Concurrent stale writers have exactly one winner", successes == 1 && conflicts == 11 && store.Read(a).Revision == revision + 1);
    Check("Concurrent A writes leave B file unchanged", File.ReadAllText(bFile) == bOriginal);
    File.WriteAllText(aFile, "{");
    Denied<InvalidDataException>("Corrupt A profile rejected", () => store.Read(a));
    Check("Corrupt A profile does not block B", store.Prepare(b).ApiKey == "synthetic-b-key");
    File.WriteAllText(aFile, recreatedOriginal);
    var keyPath = Path.Combine(root, "encryption.key"); var key = File.ReadAllBytes(keyPath);
    File.Delete(keyPath);
    Denied<InvalidDataException>("Missing key cannot silently rotate existing encryption", () => store.Save(b, bv.Revision, new[] { channel }, "replacement-b", false));
    Check("Key loss preserves B profile and does not create a key", File.ReadAllText(bFile) == bOriginal && !File.Exists(keyPath));
    File.WriteAllBytes(keyPath, key); CryptographicOperations.ZeroMemory(key);
    Check("No uncommitted temporary files remain", !Directory.EnumerateFiles(root, "*.tmp").Any());
    // Model an actual late job result: the preliminary check can pass, then
    // the profile changes before the result reaches its publication boundary.
    var jobOwner = Guid.NewGuid();
    var jobView = store.Save(jobOwner, 0, new[] { channel }, "synthetic-job-key", false);
    var job = store.Prepare(jobOwner);
    Check("Initial job snapshot is current", store.IsCurrent(job));
    jobView = recreated.Save(jobOwner, jobView.Revision, new[] { channel }, "rotated-job-key", false);
    var publications = 0;
    Check("Late result after key rotation cannot publish", !store.PublishIfCurrent(job, () => publications++) && publications == 0);
    job = store.Prepare(jobOwner);
    jobView = store.Delete(jobOwner, jobView.Revision);
    Check("Deleted generation result cannot publish", !recreated.PublishIfCurrent(job, () => publications++) && publications == 0);
    jobView = store.Save(jobOwner, jobView.Revision, new[] { channel }, "new-generation-key", false);
    Check("Recreated collection cannot accept old generation result", !store.PublishIfCurrent(job, () => publications++) && publications == 0);
    job = store.Prepare(jobOwner);
    using var publishing = new ManualResetEventSlim();
    using var releasePublication = new ManualResetEventSlim();
    using var changing = new ManualResetEventSlim();
    Task<bool>? publisher = null;
    Task<PersonalYouTubeStore.View>? writer = null;
    try
    {
        publisher = Task.Run(() => recreated.PublishIfCurrent(job, () =>
        {
            publishing.Set();
            if (!releasePublication.Wait(TimeSpan.FromSeconds(5))) throw new Exception("Publication gate timed out");
            Interlocked.Increment(ref publications);
        }));
        if (!publishing.Wait(TimeSpan.FromSeconds(3))) throw new Exception("Publication was not reached");
        writer = Task.Run(() =>
        {
            changing.Set();
            return new PersonalYouTubeStore(root).Save(jobOwner, jobView.Revision, new[] { "UC" + new string('b', 22) }, null, false);
        });
        if (!changing.Wait(TimeSpan.FromSeconds(3))) throw new Exception("Concurrent writer was not started");
        Check("Cross-instance profile update remains pending while publication is paused",
            await Task.WhenAny(writer, Task.Delay(150)) != writer && publications == 0);
    }
    finally
    {
        releasePublication.Set();
        if (publisher != null) await publisher.WaitAsync(TimeSpan.FromSeconds(5));
        if (writer != null) await writer.WaitAsync(TimeSpan.FromSeconds(5));
    }
    Check("Authorized publication completes before queued profile change", publisher!.Result && publications == 1 && writer!.Result.Revision == jobView.Revision + 1);
    Check("Old job cannot publish again after queued channel change", !store.PublishIfCurrent(job, () => publications++) && publications == 1);
    Check("A separate owner's snapshot remains publishable", store.PublishIfCurrent(store.Prepare(b), () => publications++) && publications == 2);
    File.WriteAllText(aFile, "{");
    Denied<InvalidDataException>("Corrupt profile prevents publication callback", () => store.PublishIfCurrent(snapshot, () => publications++));
    Check("Corrupt-profile publication produced no side effect", publications == 2);
    File.WriteAllText(aFile, recreatedOriginal);
    await NativeBindingChecks.Run(root, Check);
    PublicationJournalChecks.Run(root, Check);
    NativeCreationChecks.Run(root, Check);
    await TransferLeaseChecks.Run(root, Check);
    var coverage = new PersonalYouTubeQueryCoverage(new long[] { 1 });
    Check("Inventory without a filtered source cannot prove initial denials", !coverage.Covers(new long[] { 1 }));
    Check("No filtered source cannot prove an empty response", !coverage.Covers(Array.Empty<long>()));
    Check("No-query coverage rejects new denials", !coverage.Covers(new long[] { 2 }));
    var incompleteSource = new PersonalYouTubeQueryCoverage(new long[] { 99 });
    incompleteSource.Record(new long[] { 1 });
    Check("Filtered source must cover initial inventory even when late denial list is empty", !incompleteSource.Covers(Array.Empty<long>()));
    coverage.Record(new long[] { 1, 2 });
    Check("First query covers its exclusions", coverage.Covers(new long[] { 1, 2 }));
    Check("Late denial absent from query is unsafe", !coverage.Covers(new long[] { 3 }));
    coverage.Record(new long[] { 1, 2, 3 });
    Check("Later exclusion cannot bless earlier query", !coverage.Covers(new long[] { 3 }));
    coverage.Record(new long[] { 1 });
    Check("Every query must cover each denied ID", !coverage.Covers(new long[] { 2 }));
    Check("Common exclusion remains covered", coverage.Covers(new long[] { 1 }));
    Check("No late denials require no additional coverage", coverage.Covers(Array.Empty<long>()));
    var concurrentCoverage = new PersonalYouTubeQueryCoverage(Array.Empty<long>());
    await Task.WhenAll(Enumerable.Range(0, 12).Select(index => Task.Run(() => concurrentCoverage.Record(new long[] { 1, index + 2 }))));
    Check("Concurrent coverage preserves intersection instead of union", concurrentCoverage.Covers(new long[] { 1 }) && !concurrentCoverage.Covers(new long[] { 2 }));
    await CatalogChecks.Run(Path.Combine(root, "catalog"), Check);
    await JobChecks.Run(Path.Combine(root, "jobs"), Check);
    if (args.Contains("--buffer-youtube")) await VideoBufferChecks.Run(Path.Combine(root, "video-buffer"), Check);
    completed = true;
}
finally
{
    var safeRoot = Path.GetFullPath(root);
    if (!safeRoot.StartsWith(artifactRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new Exception("Unsafe test cleanup");
    if (Directory.Exists(safeRoot)) Directory.Delete(safeRoot, true);
    File.WriteAllText(Path.Combine(artifactRoot, "results.json"), JsonSerializer.Serialize(new { Completed = completed, Count = rows.Count, Checks = rows, TestDataGone = !Directory.Exists(safeRoot) }, new JsonSerializerOptions { WriteIndented = true }));
}
Console.WriteLine($"Production profile store checks passed: {rows.Count}");
