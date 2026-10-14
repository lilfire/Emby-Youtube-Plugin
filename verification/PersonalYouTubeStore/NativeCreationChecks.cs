using Emby.YouTubePlugin;
using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;
using Access = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Access;

internal static class NativeCreationChecks
{
    internal static void Run(string root, Action<string, bool> check)
    {
        void Denied(string name, Action action)
        {
            try { action(); } catch (InvalidOperationException) { check(name, true); return; }
            throw new Exception(name);
        }
        var profiles = new PersonalYouTubeStore(root);
        var journal = new PersonalYouTubePublicationJournal(root);
        var creation = new PersonalYouTubeNativeCreation(root);
        var owner = Guid.NewGuid(); var foreign = Guid.NewGuid();
        var view = profiles.Save(owner, 0, new[] { "UC" + new string('a', 22) }, null, false);
        var snapshot = profiles.Prepare(owner);
        var native = new NativeItem(91001, Guid.NewGuid());
        check("Ordinary native create cannot acquire a private context", !PersonalYouTubeNativeCreation.ReserveCurrentRoot(native.ItemId));
        using (var scope = creation.Open(snapshot))
        {
            check("Creation source comes from persisted owner generation", scope.MediaPath == journal.MediaPath(journal.Pending().Single(entry => entry.GenerationId == snapshot.GenerationId)));
            Denied("Nested creation cannot replace current owner", () => creation.Open(snapshot));
            check("Detached or inlined task cannot inherit native creation authority", Task.Run(() => {
                try { return !PersonalYouTubeNativeCreation.ReserveCurrentRoot(native.ItemId); }
                catch (InvalidOperationException) { return true; }
            }).GetAwaiter().GetResult());
            var inlined = new Task<bool>(() => {
                try { PersonalYouTubeNativeCreation.ReserveCurrentRoot(native.ItemId); return false; }
                catch (InvalidOperationException) { return true; }
            });
            inlined.RunSynchronously();
            check("Explicit same-thread task cannot borrow creation authority", inlined.Result);
            Denied("Native completion without pre-insert reservation is rejected", () => scope.Complete(native));
            check("Server context reserves actual native GUID", PersonalYouTubeNativeCreation.ReserveCurrentRoot(native.ItemId));
            check("Root stays denied to owner and foreign account before native completion", journal.DecideSources(native, Array.Empty<NativeItem>(), owner, Array.Empty<string>()) == Access.Denied && journal.DecideSources(native, Array.Empty<NativeItem>(), foreign, Array.Empty<string>()) == Access.Denied);
            Denied("Context cannot reserve a second native root", () => PersonalYouTubeNativeCreation.ReserveCurrentRoot(Guid.NewGuid()));
            Denied("Native completion cannot substitute another root", () => scope.Complete(new(91002, Guid.NewGuid())));
            check("Actual matching native root completes context", scope.Complete(native) == native);
            Denied("Creation completion cannot be replayed", () => scope.Complete(native));
        }
        check("Creation authority disappears after disposal", !PersonalYouTubeNativeCreation.ReserveCurrentRoot(Guid.NewGuid()));
        check("Durable reservation remains denied after scope disposal", new PersonalYouTubePublicationJournal(root).DecideSources(native, Array.Empty<NativeItem>(), owner, Array.Empty<string>()) == Access.Denied);
        Denied("Partially created generation requires recovery before retry", () => creation.Open(snapshot));
        var staleOwner = Guid.NewGuid();
        var staleView = profiles.Save(staleOwner, 0, new[] { "UC" + new string('a', 22) }, null, false);
        var staleSnapshot = profiles.Prepare(staleOwner);
        using (var scope = creation.Open(staleSnapshot))
        {
            profiles.Save(staleOwner, staleView.Revision, new[] { "UC" + new string('b', 22) }, null, false);
            Denied("Profile update aborts pre-insert reservation in opened context", () => PersonalYouTubeNativeCreation.ReserveCurrentRoot(Guid.NewGuid()));
        }
        check("Failed reservation leaves no native GUID assigned", journal.Pending().Single(entry => entry.OwnerUserId == staleOwner).ReservedRootId == null);
        var racingOwner = Guid.NewGuid();
        profiles.Save(racingOwner, 0, new[] { "UC" + new string('a', 22) }, null, false);
        var racingSnapshot = profiles.Prepare(racingOwner);
        using var bothOpened = new CountdownEvent(2);
        using var release = new ManualResetEventSlim(false);
        int nativeCreates = 0;
        Task<bool> Start(int key) => Task.Factory.StartNew(() => {
            using var scope = creation.Open(racingSnapshot);
            bothOpened.Signal();
            if (!release.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException("Creation race was not released");
            var pair = new NativeItem(key, Guid.NewGuid());
            try { PersonalYouTubeNativeCreation.ReserveCurrentRoot(pair.ItemId); }
            catch (InvalidOperationException) { return false; }
            Interlocked.Increment(ref nativeCreates);
            scope.Complete(pair);
            return true;
        }, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
        var first = Start(91101); var second = Start(91102);
        try {
            check("Concurrent generation creation scopes reach real reservation race", bothOpened.Wait(TimeSpan.FromSeconds(5)));
        } finally { release.Set(); Task.WaitAll(first, second); }
        check("Only one concurrent creator reaches native mutation", nativeCreates == 1 && new[] { first.Result, second.Result }.Count(success => success) == 1);
        var reserved = journal.Pending().Single(entry => entry.OwnerUserId == racingOwner).ReservedRootId;
        check("Concurrent winner retains one durable denied identity", reserved.HasValue && journal.DecideSources(new NativeItem(91199, reserved.Value), Array.Empty<NativeItem>(), racingOwner, Array.Empty<string>()) == Access.Denied);
    }
}
