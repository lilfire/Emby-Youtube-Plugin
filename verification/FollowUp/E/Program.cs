using System.Diagnostics;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using Emby.YouTubePlugin;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using Access = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Access;
using Item = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;

// Calls production storage/creation/lifecycle code. LibraryProxy is deliberately
// an adapter: it does not prove native Emby events, HTTP, indexing or patch loss.
internal static class Program
{
    private static readonly List<object> Rows = new();
    private static readonly List<string> Skips = new();
    private static string Base = "";
    private static void Check(string id, bool condition, string observation, bool? requirementMet = null)
    {
        Rows.Add(new { Id = id, Reproduced = condition, RequirementMet = requirementMet, Observation = observation });
        if (!condition) throw new InvalidOperationException("Unexpected result: " + id);
    }
    private static bool Throws<T>(Action action) where T : Exception
    { try { action(); return false; } catch (T) { return true; } }
    private static bool DiskFailure(Action action)
    { try { action(); return false; } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return true; } }
    private static Case New(string name) => new(Path.Combine(Base, name));
    internal static async Task Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--child") { Child(args[1], args[2]); return; }
        var output = Path.GetFullPath(args.Length > 0 ? args[0] : "verification/FollowUp/E/bin/windows");
        Directory.CreateDirectory(output);
        Base = Path.Combine(output, "data-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Base);
        var completed = false;
        try
        {
            Identity(); Mismatches(); Recovery(); Cleanup(); Restore(); HookAvailability();
            foreach (var phase in new[] { "Waiting", "Buffering", "Preparing", "Reserved", "Publishing", "Active", "Cleaning" })
                await Crash(phase);
            completed = true;
        }
        finally
        {
            // All links created by tests are removed at their creation site.
            // Refuse recursive cleanup if a link was unexpectedly left behind.
            if (!Path.GetFullPath(Base).StartsWith(output + Path.DirectorySeparatorChar)) throw new Exception("Unsafe test root");
            if (Directory.EnumerateFileSystemEntries(Base, "*", SearchOption.AllDirectories)
                .Any(path => (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)) throw new Exception("Link left in test root");
            Directory.Delete(Base, true);
            var dll = typeof(PersonalYouTubeService).Assembly.Location;
            File.WriteAllText(Path.Combine(output, "EVIDENCE.json"), JsonSerializer.Serialize(new {
                Completed = completed, Platform = OperatingSystem.IsWindows() ? "Windows" : "Linux",
                Runtime = Environment.Version.ToString(), PluginVersion = typeof(PersonalYouTubeService).Assembly.GetName().Version!.ToString(),
                PluginSHA256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(dll))),
                TestSHA256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Assembly.GetExecutingAssembly().Location))),
                Scope = "Production components; synthetic SDK library adapter; real child process kills; no Emby server, Google or downloader",
                Observations = Rows, Skipped = Skips, TestDataGone = !Directory.Exists(Base)
            }, new JsonSerializerOptions { WriteIndented = true }));
        }
        Console.WriteLine($"E completed: {Rows.Count} observations, {Skips.Count} skipped; test data removed.");
    }
    private static void Controls(Case c, string phase)
    {
        Check(phase + ".owner", c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Allowed, "Owner A allowed", true);
        Check(phase + ".foreign", c.Decide(c.Va, c.Ra, c.B, c.MediaA) == Access.Denied, "Foreign B denied A", true);
        Check(phase + ".other-owner", c.Decide(c.Vb, c.Rb, c.B, c.MediaB) == Access.Allowed, "Owner B still allowed", true);
    }
    private static void Identity()
    {
        var c = New("identity"); c.ActivateBoth(); Controls(c, "identity.baseline");
        var unknown = new Item(999, Guid.NewGuid());
        Check("identity.unregistered", c.Decide(unknown, c.Ra, c.A, c.MediaA) == Access.Denied && c.Decide(unknown, c.Ra, c.B, c.MediaA) == Access.Denied,
            "Unknown descendant denied even to owner before durable registration", true);
        c.Bindings.Register(c.Sa, new[] { unknown });
        Check("identity.registered", c.Decide(unknown, c.Ra, c.A, c.MediaA) == Access.Allowed && c.Decide(unknown, c.Ra, c.B, c.MediaA) == Access.Denied,
            "Registered descendant has paired owner/foreign decisions", true);
        Check("identity.reparent", c.Decide(c.Va, c.Rb, c.A, c.MediaB) == Access.Denied && c.Decide(c.Va, c.Rb, c.B, c.MediaB) == Access.Denied,
            "Reparenting across owners cannot transfer binding", true);
        Check("identity.detached", c.Journal.DecideSources(c.Va, Array.Empty<Item>(), c.A, Array.Empty<string>()) == Access.Denied,
            "Detached bound child denied without active root ancestry", true);
        Check("identity.same-name-new-account", c.Decide(c.Va, c.Ra, Guid.NewGuid(), c.MediaA) == Access.Denied,
            "New account GUID cannot inherit owner identity", true);
        c.Profiles.Delete(c.A, c.Profiles.Read(c.A).Revision);
        var fresh = new PersonalYouTubePublicationJournal(c.Root);
        Check("identity.retired", fresh.DecideAbsentReference(unknown.InternalId.ToString()) == Access.Denied
            && fresh.DecideAbsentReference(unknown.ItemId.ToString("D")) == Access.Denied,
            "Registered old aliases stay denied without new snapshot", true);
        Check("identity.unseen-removed", fresh.DecideAbsentReference(Guid.NewGuid().ToString("N")) == Access.Unknown,
            "Never-registered, already absent descendant has no durable provenance; not proof of HTTP leakage", false);
        Check("identity.reuse", Throws<InvalidOperationException>(() => c.Bindings.Register(c.Sb, new[] { new Item(unknown.InternalId, Guid.NewGuid()) }))
            && Throws<InvalidOperationException>(() => c.Bindings.Register(c.Sb, new[] { new Item(998, unknown.ItemId) })),
            "Numeric ID and GUID reuse rejected independently", true);
        Check("identity.other-after-delete", c.Decide(c.Vb, c.Rb, c.B, c.MediaB) == Access.Allowed, "B unaffected by A profile deletion", true);
    }
    private static void Mismatches()
    {
        var c = New("mismatch"); c.ActivateBoth(); Controls(c, "mismatch.baseline");
        var journalPath = Path.Combine(c.Root, "publication-journal.json"); var saved = File.ReadAllText(journalPath);
        var doc = JsonNode.Parse(saved)!;
        doc["Entries"] = new JsonArray(doc["Entries"]!.AsArray().Where(n => n!["OwnerUserId"]!.GetValue<Guid>() != c.A).Select(n => n!.DeepClone()).ToArray());
        File.WriteAllText(journalPath, doc.ToJsonString());
        Check("mismatch.missing-entry-own", c.Journal.DecideSources(c.Va, new[] { c.Ra }, c.A, Array.Empty<string>()) == Access.Allowed,
            "Valid journal missing A entry permits bound A child without private physical source", false);
        Check("mismatch.missing-entry-list", !c.Journal.DeniedRegisteredIds(c.A).Contains(c.Va.InternalId),
            "Missing A journal entry not added to owner's pre-query denial IDs", false);
        Check("mismatch.missing-entry-path", c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Denied,
            "Private media source compensates for missing journal entry only when supplied", true);
        Check("mismatch.missing-entry-foreign", c.Journal.DecideSources(c.Va, new[] { c.Ra }, c.B, Array.Empty<string>()) == Access.Denied,
            "Foreign owner still denied by binding; missing entry is not demonstrated cross-owner byte leakage", true);
        Check("mismatch.missing-entry-B", c.Decide(c.Vb, c.Rb, c.B, c.MediaB) == Access.Allowed, "B unaffected by omitted A entry", true);
        File.WriteAllText(journalPath, saved);
        doc = JsonNode.Parse(saved)!;
        var aEntry = doc["Entries"]!.AsArray().Single(n => n!["OwnerUserId"]!.GetValue<Guid>() == c.A)!;
        aEntry["OwnerUserId"] = Guid.NewGuid(); File.WriteAllText(journalPath, doc.ToJsonString());
        Check("mismatch.owner-entry", c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Denied
            && c.Decide(c.Vb, c.Rb, c.B, c.MediaB) == Access.Allowed, "Owner mismatch quarantines A and preserves B", true);
        File.WriteAllText(journalPath, saved);
        doc = JsonNode.Parse(saved)!;
        aEntry = doc["Entries"]!.AsArray().Single(n => n!["OwnerUserId"]!.GetValue<Guid>() == c.A)!;
        aEntry["CreationRevision"] = c.Sa.Revision + 10; File.WriteAllText(journalPath, doc.ToJsonString());
        Check("mismatch.revision-resume", c.Lifecycle.ReadActive(c.Sa) == null, "Publication revision mismatch rejects resume", true);
        Check("mismatch.revision-access", c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Allowed
            && c.Decide(c.Va, c.Ra, c.B, c.MediaA) == Access.Denied, "Revision mismatch is not quarantined at journal access boundary", false);
        File.WriteAllText(journalPath, "{");
        Check("mismatch.corrupt-global", Throws<InvalidDataException>(() => c.Decide(c.Vb, c.Rb, c.B, c.MediaB)),
            "Global corrupt journal blocks unaffected B too", false);
        File.WriteAllText(journalPath, saved);
        var profile = Path.Combine(c.Root, c.A.ToString("N") + ".json"); var profileSaved = File.ReadAllText(profile);
        File.WriteAllText(profile, "{");
        Check("mismatch.corrupt-profile-A", c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Denied, "Corrupt A profile denies A", true);
        Check("mismatch.corrupt-profile-B", c.Decide(c.Vb, c.Rb, c.B, c.MediaB) == Access.Allowed, "B access survives corrupt A profile", true);
        Check("mismatch.corrupt-startup", Throws<InvalidDataException>(() => c.Lifecycle.RepairInterrupted()),
            "One corrupt profile aborts RepairInterrupted; JobRuntime.Start disposes all jobs on this exception", false);
        File.WriteAllText(profile, profileSaved);
        var marker = Path.Combine(c.Root, "publication-journal.required"); File.Delete(marker);
        Check("mismatch.marker", Throws<InvalidDataException>(() => c.Decide(c.Va, c.Ra, c.A, c.MediaA)), "Missing required marker fails closed", true);
        File.WriteAllBytes(marker, new byte[] { 1 });
        File.Delete(journalPath);
        Check("mismatch.missing-journal", Throws<InvalidDataException>(() => c.Decide(c.Va, c.Ra, c.A, c.MediaA)), "Missing required journal fails closed", true);
        File.WriteAllText(journalPath, saved);
        // A directory at the rename target reproduces an OS write failure, not ENOSPC.
        var f = New("journal-write-failure");
        Directory.CreateDirectory(Path.Combine(f.Root, "publication-journal.json"));
        Check("mismatch.write-failure", DiskFailure(() => f.Journal.Begin(f.Sa)), "Journal rename target failure rejects Begin", true);
        Check("mismatch.write-failure-temp", !Directory.EnumerateFiles(f.Root, "*.tmp").Any(), "Failed journal write cleans temporary file", true);
        Check("mismatch.write-failure-marker", File.Exists(Path.Combine(f.Root, "publication-journal.required"))
            && Throws<InvalidDataException>(() => f.Journal.Entries()), "Failed first journal write leaves fail-closed marker", true);
    }
    private static void Recovery()
    {
        var c = New("recovery"); c.ActivateBoth(); Controls(c, "recovery.baseline");
        Check("recovery.read-active", c.Lifecycle.ReadActive(c.Sa) != null && c.Lifecycle.ReadActive(c.Sb) != null,
            "Adapter supplies matching root, source, bound video and actual file", true);
        c.Proxy.Items.Remove(c.Ra.InternalId);
        Check("recovery.missing-root", c.Lifecycle.ReadActive(c.Sa) == null, "Missing native A root cannot be resumed", true);
        c.Lifecycle.RepairInterrupted();
        Check("recovery.rollover-A", !c.Profiles.IsCurrent(c.Sa), "Missing root rotates A generation", true);
        Check("recovery.keep-B", c.Profiles.IsCurrent(c.Sb) && c.Lifecycle.ReadActive(c.Sb) != null, "B remains resumable after A repair", true);
        var orphan = New("pre-journal-orphan");
        var staging = orphan.Staging(orphan.Sa); Directory.CreateDirectory(staging); File.WriteAllText(Path.Combine(staging, "orphan00001.mp4"), "synthetic");
        orphan.Profiles.Delete(orphan.A, orphan.Profiles.Read(orphan.A).Revision);
        orphan.Lifecycle.CleanupAsync(orphan.A, default).GetAwaiter().GetResult();
        Check("recovery.pre-journal-orphan", File.Exists(Path.Combine(staging, "orphan00001.mp4")),
            "Retired staging created before Begin is not discovered by journal-only CleanupAsync", false);
    }
    private static void Cleanup()
    {
        var c = New("cleanup"); c.ActivateBoth(); Controls(c, "cleanup.baseline");
        var staging = c.Staging(c.Sa); Directory.CreateDirectory(staging); File.WriteAllText(Path.Combine(staging, "staging0001.mp4"), "synthetic");
        c.Profiles.Delete(c.A, c.Profiles.Read(c.A).Revision);
        c.Lifecycle.CleanupAsync(c.A, default).GetAwaiter().GetResult();
        Check("cleanup.native-media-staging", !c.Proxy.Items.ContainsKey(c.Ra.InternalId) && !Directory.Exists(c.MediaA)
            && !Directory.Exists(Path.GetDirectoryName(staging)), "Retired root, owned media and staging removed", true);
        c.Lifecycle.CleanupAsync(c.A, default).GetAwaiter().GetResult();
        Check("cleanup.idempotent", c.Journal.DecideAbsentReference(c.Va.InternalId.ToString()) == Access.Denied,
            "Retry retains durable identity tombstone", true);
        Check("cleanup.other", c.Lifecycle.ReadActive(c.Sb) != null, "B files and resume survive A cleanup", true);
        var unexpected = New("cleanup-unexpected"); unexpected.ActivateBoth();
        File.WriteAllText(Path.Combine(unexpected.MediaA, "unmanaged.txt"), "synthetic");
        unexpected.Profiles.Delete(unexpected.A, unexpected.Profiles.Read(unexpected.A).Revision);
        Check("cleanup.unexpected", Throws<InvalidDataException>(() => unexpected.Lifecycle.CleanupAsync(unexpected.A, default).GetAwaiter().GetResult())
            && File.Exists(Path.Combine(unexpected.MediaA, "unmanaged.txt")), "Unexpected media retained for explicit handling", true);
        Check("cleanup.non-atomic", !unexpected.Proxy.Items.ContainsKey(unexpected.Ra.InternalId) && Directory.Exists(unexpected.MediaA),
            "Native removal precedes disk rejection; cleanup is retryable, not atomic", null);
        var outside = Path.Combine(Base, "link-target"); Directory.CreateDirectory(outside);
        File.WriteAllText(Path.Combine(outside, "sentinel000.mp4"), "synthetic");
        var linked = New("cleanup-link");
        var gen = Path.GetDirectoryName(linked.Staging(linked.Sa))!; Directory.CreateDirectory(Path.GetDirectoryName(gen)!);
        try { Directory.CreateSymbolicLink(gen, outside); }
        catch (Exception e) when (e is UnauthorizedAccessException or IOException)
        { Skips.Add("cleanup.symlink: OS denied link creation"); Skips.Add("cleanup.storage-root-link: OS denied link creation"); return; }
        try
        {
            Check("cleanup.symlink", Throws<InvalidDataException>(() => linked.Lifecycle.DeleteStaging(linked.A, linked.Sa.CollectionId, linked.Sa.GenerationId))
                && File.Exists(Path.Combine(outside, "sentinel000.mp4")), "Generation directory link rejected; outside sentinel intact", true);
        }
        finally { Directory.Delete(gen); }
        // The configured storage directory itself is excluded from the loop in
        // ValidateDirectory. This separate test uses only a disposable target.
        var storageLink = Path.Combine(Base, "storage-link"); Directory.CreateSymbolicLink(storageLink, outside);
        var owner = Guid.NewGuid(); var collection = Guid.NewGuid(); var generation = Guid.NewGuid();
        var taskPath = Path.Combine(outside, "buffer", owner.ToString("N"), collection.ToString("N"), generation.ToString("N"), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(taskPath); var file = Path.Combine(taskPath, "outside0001.mp4"); File.WriteAllText(file, "synthetic");
        try
        {
            new PersonalYouTubeLifecycle(storageLink, linked.Library, null).DeleteStaging(owner, collection, generation);
            Check("cleanup.storage-root-link", !File.Exists(file), "Configured storage root symlink is followed; target staging deleted", false);
        }
        finally { Directory.Delete(storageLink); }
    }
    private static void Restore()
    {
        var c = New("restore"); c.ActivateBoth(); Controls(c, "restore.baseline");
        var backup = Path.Combine(Base, "backup"); Copy(c.Root, backup);
        c.Profiles.Delete(c.A, c.Profiles.Read(c.A).Revision);
        Check("restore.deleted-before", c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Denied, "Current deletion denies A", true);
        Copy(backup, c.Root);
        Check("restore.coherent", new PersonalYouTubeStore(c.Root).Prepare(c.A).ApiKey == "synthetic-key-A"
            && c.Lifecycle.ReadActive(c.Sa) != null && c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Allowed,
            "Coherent file backup restores key, profile, binding and journal against matching adapter native state", true);
        Check("restore.replays-revocation", c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Allowed,
            "Older coherent backup reactivates previously deleted generation; no external monotonic revocation anchor", false);
        var keyPath = Path.Combine(c.Root, "encryption.key"); var key = File.ReadAllBytes(keyPath);
        File.WriteAllBytes(keyPath, RandomNumberGenerator.GetBytes(key.Length));
        Check("restore.key-mismatch", Throws<CryptographicException>(() => c.Profiles.Prepare(c.A)), "Wrong encryption key prevents preparation", true);
        Check("restore.key-access", c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Allowed,
            "Access decision does not decrypt key; key mismatch does not quarantine already active native media", false);
        File.WriteAllBytes(keyPath, key); CryptographicOperations.ZeroMemory(key);
        c.Proxy.Items[c.Ra.InternalId] = new CollectionFolder { InternalId = c.Ra.InternalId, Id = Guid.NewGuid() };
        Check("restore.native-mismatch", c.Lifecycle.ReadActive(c.Sa) == null, "Mismatched native GUID cannot resume", true);
        var path = Path.Combine(c.Root, "publication-journal.json"); var saved = File.ReadAllText(path); var doc = JsonNode.Parse(saved)!;
        doc["Version"] = 2; File.WriteAllText(path, doc.ToJsonString());
        Check("restore.unsupported-version", Throws<InvalidDataException>(() => c.Journal.Entries()), "No migration from unsupported journal version; fails closed", true);
        File.WriteAllText(path, saved);
    }
    private static void HookAvailability()
    {
        var c = New("hook");
        var state = PersonalYouTubeNativeCreationHook.Install(c.Library);
        Check("hook.unsupported", !state.Installed && !state.ContractMatched, "Unverified SDK adapter cannot satisfy native hook contract", true);
        var before = c.Journal.Entries().Length;
        Check("hook.publisher-blocked", Throws<InvalidOperationException>(() => new PersonalYouTubeNativePublisher(c.Root, c.Library)
            .CreatePreparingLibrary(c.Sa, "YouTube synthetic")) && c.Proxy.AddCalls == 0 && c.Journal.Entries().Length == before
            && !Directory.Exists(Path.Combine(c.Root, "media")), "Publisher blocks before journal/media/native mutation when hook unavailable", true);
    }
    private static async Task Crash(string phase)
    {
        var directory = Path.Combine(Base, "crash-" + phase); Directory.CreateDirectory(directory);
        var start = new ProcessStartInfo("dotnet") { UseShellExecute = false, RedirectStandardError = true, RedirectStandardOutput = true };
        foreach (var arg in new[] { Assembly.GetExecutingAssembly().Location, "--child", directory, phase }) start.ArgumentList.Add(arg);
        using var process = Process.Start(start)!;
        try
        {
            var deadline = Stopwatch.StartNew();
            while (!File.Exists(Path.Combine(directory, "ready")))
            {
                if (process.HasExited) throw new Exception("Child did not reach phase: " + await process.StandardError.ReadToEndAsync());
                if (deadline.Elapsed > TimeSpan.FromSeconds(20)) throw new Exception("Child phase timeout");
                await Task.Delay(25);
            }
            process.Kill(); await process.WaitForExitAsync();
            var c = new Case(directory, load: true);
            Check("crash." + phase + ".process", process.HasExited && process.ExitCode != 0, "Actual .NET child forcibly terminated at persisted component boundary", true);
            Check("crash." + phase + ".B", c.Decide(c.Vb, c.Rb, c.B, c.MediaB) == Access.Allowed, "B binding/journal positive control after new process", true);
            if (phase is "Preparing" or "Reserved" or "Publishing")
            {
                Check("crash." + phase + ".denied", c.Decide(c.Va, c.Ra, c.A, c.MediaA) == Access.Denied
                    && c.Decide(c.Va, c.Ra, c.B, c.MediaA) == Access.Denied, "Unfinished A publication denied to owner and foreign", true);
                c.Lifecycle.RepairInterrupted();
                Check("crash." + phase + ".repair", !c.Profiles.IsCurrent(c.Sa), "Repair rotates incomplete generation", true);
                c.Lifecycle.CleanupAsync(c.A, default).GetAwaiter().GetResult();
                Check("crash." + phase + ".cleanup", !Directory.Exists(c.MediaA), "Retired partially copied media removed with adapter native state", true);
            }
            else if (phase == "Active")
            {
                Check("crash.Active.resume", c.Lifecycle.ReadActive(c.Sa) != null && c.Decide(c.Va, c.Ra, c.B, c.MediaA) == Access.Denied,
                    "Activated component state resumes; foreign remains denied", true);
            }
            else if (phase == "Cleaning")
            {
                c.Lifecycle.CleanupAsync(c.A, default).GetAwaiter().GetResult();
                Check("crash.Cleaning.retry", !Directory.Exists(c.MediaA) && c.Lifecycle.ReadActive(c.Sb) != null,
                    "Cleanup retry finishes remaining files and preserves B", true);
            }
            else
            {
                c.Lifecycle.RepairInterrupted();
                Check("crash." + phase + ".pre-journal", c.Profiles.IsCurrent(c.Sa), "Pre-journal generation retained; job runtime must restart work", true);
            }
        }
        finally { if (!process.HasExited) { process.Kill(); await process.WaitForExitAsync(); } }
    }
    private static void Child(string directory, string phase)
    {
        var c = new Case(directory); c.ActivateB();
        File.WriteAllText(Path.Combine(directory, "identities.json"), JsonSerializer.Serialize(new Identities(c.A, c.B, c.Ra, c.Va, c.Rb, c.Vb)));
        if (phase == "Buffering") { var path = c.Staging(c.Sa); Directory.CreateDirectory(path); File.WriteAllText(Path.Combine(path, "staging0001.mp4"), "synthetic"); }
        if (phase is "Preparing" or "Reserved" or "Publishing" or "Active" or "Cleaning") c.Journal.Begin(c.Sa);
        if (phase is "Reserved" or "Publishing" or "Active" or "Cleaning") c.Journal.ReserveRootIdentity(c.Sa, c.Ra.ItemId);
        if (phase is "Publishing" or "Active" or "Cleaning") { c.FilesA(); c.Bindings.Register(c.Sa, new[] { c.Ra, c.Va }); }
        if (phase is "Active" or "Cleaning") c.Journal.Activate(c.Sa, c.Ra);
        if (phase == "Cleaning") { c.Profiles.Delete(c.A, c.Profiles.Read(c.A).Revision); File.Delete(Path.Combine(c.MediaA, "aaaaaaaaaaa.mp4")); }
        File.WriteAllText(Path.Combine(directory, "ready"), phase);
        Thread.Sleep(Timeout.Infinite);
    }
    private static void Copy(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (var file in Directory.EnumerateFiles(from)) File.Copy(file, Path.Combine(to, Path.GetFileName(file)), true);
        foreach (var directory in Directory.EnumerateDirectories(from)) Copy(directory, Path.Combine(to, Path.GetFileName(directory)));
    }
    private sealed record Identities(Guid A, Guid B, Item Ra, Item Va, Item Rb, Item Vb);
    private sealed class Case
    {
        internal string Root;
        internal Guid A = Guid.NewGuid(), B = Guid.NewGuid();
        internal Item Ra = new(101, Guid.NewGuid()), Va = new(102, Guid.NewGuid()), Rb = new(201, Guid.NewGuid()), Vb = new(202, Guid.NewGuid());
        internal PersonalYouTubeStore Profiles;
        internal PersonalYouTubeStore.Prepared Sa, Sb;
        internal PersonalYouTubePublicationJournal Journal;
        internal PersonalYouTubeNativeBindings Bindings;
        internal ILibraryManager Library;
        internal LibraryProxy Proxy;
        internal PersonalYouTubeLifecycle Lifecycle;
        internal string MediaA => Journal.MediaPath(new(A, Sa.CollectionId, Sa.GenerationId, Sa.Revision, "Preparing", null));
        internal string MediaB => Journal.MediaPath(new(B, Sb.CollectionId, Sb.GenerationId, Sb.Revision, "Preparing", null));
        internal Case(string root, bool load = false)
        {
            Root = root; Profiles = new(root); Journal = new(root); Bindings = new(root);
            if (load)
            {
                var ids = JsonSerializer.Deserialize<Identities>(File.ReadAllText(Path.Combine(root, "identities.json")))!;
                (A, B, Ra, Va, Rb, Vb) = (ids.A, ids.B, ids.Ra, ids.Va, ids.Rb, ids.Vb);
                // Cleaning snapshots were valid before persisted deletion.
                var av = Profiles.Read(A);
                Sa = new(A, av.CollectionId, av.GenerationId, av.State == "Deleted" ? av.Revision - 1 : av.Revision,
                    av.State == "Deleted" ? av.KeyRevision - 1 : av.KeyRevision, new[] { "UC" + new string('a', 22) }, "synthetic-key-A");
            }
            else
            {
                Profiles.Save(A, 0, new[] { "UC" + new string('a', 22) }, "synthetic-key-A", false);
                Profiles.Save(B, 0, new[] { "UC" + new string('b', 22) }, "synthetic-key-B", false);
                Sa = Profiles.Prepare(A);
            }
            Sb = Profiles.Prepare(B);
            Library = DispatchProxy.Create<ILibraryManager, LibraryProxy>(); Proxy = (LibraryProxy)Library;
            Lifecycle = new(root, Library, null);
            Proxy.Add(Ra, Va, MediaA, "aaaaaaaaaaa.mp4"); Proxy.Add(Rb, Vb, MediaB, "bbbbbbbbbbb.mp4");
        }
        internal Access Decide(Item item, Item parent, Guid owner, string media) => Journal.DecideItem(item, new[] { parent }, owner, Path.Combine(media, "aaaaaaaaaaa.mp4"));
        internal void FilesA() { Directory.CreateDirectory(MediaA); File.WriteAllText(Path.Combine(MediaA, "aaaaaaaaaaa.mp4"), "synthetic-A"); }
        internal void ActivateB()
        {
            var entry = Journal.Begin(Sb); Journal.ReserveRootIdentity(Sb, Rb.ItemId); Bindings.Register(Sb, new[] { Rb, Vb });
            Directory.CreateDirectory(MediaB); File.WriteAllText(Path.Combine(MediaB, "bbbbbbbbbbb.mp4"), "synthetic-B"); Journal.Activate(Sb, Rb);
        }
        internal void ActivateBoth()
        {
            ActivateB(); Journal.Begin(Sa); Journal.ReserveRootIdentity(Sa, Ra.ItemId); Bindings.Register(Sa, new[] { Ra, Va }); FilesA(); Journal.Activate(Sa, Ra);
        }
        internal string Staging(PersonalYouTubeStore.Prepared snapshot) => Path.Combine(Root, "buffer", snapshot.OwnerUserId.ToString("N"), snapshot.CollectionId.ToString("N"), snapshot.GenerationId.ToString("N"), Guid.NewGuid().ToString("N"));
    }
}

public class LibraryProxy : DispatchProxy
{
    internal Dictionary<long, BaseItem> Items = new();
    private Dictionary<long, string> Sources = new();
    internal int AddCalls;
    internal void Add(Item root, Item video, string path, string filename)
    {
        Items[root.InternalId] = new CollectionFolder { InternalId = root.InternalId, Id = root.ItemId };
        Items[video.InternalId] = new Video { InternalId = video.InternalId, Id = video.ItemId, ParentId = root.InternalId, Path = Path.Combine(path, filename) };
        Sources[root.InternalId] = path;
    }
    protected override object? Invoke(MethodInfo? method, object?[]? args)
    {
        switch (method!.Name)
        {
            case "GetItemById": return args![0] is long id ? Items.GetValueOrDefault(id) : Items.Values.SingleOrDefault(i => i.Id == (Guid)args![0]!);
            case "GetItemList":
                var query = (InternalItemsQuery)args![0]!;
                return Items.Values.Where(i => query.AncestorIds.Contains(i.ParentId)).ToArray();
            case "GetVirtualFolders":
                // Construct the SDK's declared return type without using server internals.
                var element = method.ReturnType.IsArray ? method.ReturnType.GetElementType()! : method.ReturnType.GetGenericArguments()[0];
                var values = Sources.Where(pair => Items.ContainsKey(pair.Key)).Select(pair => {
                    var value = Activator.CreateInstance(element)!;
                    element.GetProperty("ItemId")!.SetValue(value, pair.Key.ToString());
                    element.GetProperty("Locations")!.SetValue(value, new[] { pair.Value });
                    return value;
                }).ToArray();
                var array = Array.CreateInstance(element, values.Length); for (var i = 0; i < values.Length; i++) array.SetValue(values[i], i);
                return method.ReturnType.IsArray ? array : Activator.CreateInstance(method.ReturnType, array);
            case "RemoveVirtualFolder": Items.Remove((long)args![0]!); return null;
            case "AddVirtualFolder": AddCalls++; throw new Exception("Unprotected native call reached adapter");
            default: throw new NotSupportedException(method.Name);
        }
    }
}
