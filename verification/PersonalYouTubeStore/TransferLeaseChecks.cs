using Emby.YouTubePlugin;

internal static class TransferLeaseChecks
{
    internal static async Task Run(string root, Action<string, bool> check)
    {
        var a = Guid.NewGuid(); var b = Guid.NewGuid();
        var store = new PersonalYouTubeStore(root);
        var av = store.Save(a, 0, Array.Empty<string>(), null, false);
        var bv = store.Save(b, 0, Array.Empty<string>(), null, false);
        var lease = PersonalYouTubeTransferLease.Enter(root, a);
        var native = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var writing = PersonalYouTubeTransferLease.Complete(native.Task, lease);
        using var started = new ManualResetEventSlim();
        var deleting = Task.Run(() => { started.Set(); return new PersonalYouTubeStore(root).Delete(a, av.Revision); });
        try
        {
            if (!started.Wait(TimeSpan.FromSeconds(3))) throw new Exception("Delete did not start");
            check("Deletion waits for unfinished native write task", await Task.WhenAny(deleting, Task.Delay(150)) != deleting);
            check("Readback remains Draft while transfer is held", store.Read(a).State == "Draft");
            check("Other owner can save during A transfer", store.Save(b, bv.Revision, Array.Empty<string>(), null, false).Revision == bv.Revision + 1);
            check("Transfer wrapper remains pending until native task completes", !writing.IsCompleted);
        }
        finally { native.TrySetResult(); await writing.WaitAsync(TimeSpan.FromSeconds(3)); await deleting.WaitAsync(TimeSpan.FromSeconds(3)); }
        check("Deletion completes after native write task", (await deleting.WaitAsync(TimeSpan.FromSeconds(3))).State == "Deleted");
        lease.Dispose(); // idempotence must not increase semaphore capacity.
        Task? pending = null;
        using (PersonalYouTubeTransferLease.Enter(root, a))
        {
            var another = Task.Run(() => { using var held = PersonalYouTubeTransferLease.Enter(root, a); });
            check("Double release does not permit overlapping leases", await Task.WhenAny(another, Task.Delay(150)) != another);
            // Complete outside the using scope below.
            pending = another;
        }
        await pending!.WaitAsync(TimeSpan.FromSeconds(3));
        foreach (var cancelled in new[] { false, true })
        {
            var failed = cancelled ? Task.FromCanceled(new CancellationToken(true)) : Task.FromException(new IOException("synthetic failure"));
            var held = PersonalYouTubeTransferLease.Enter(root, a);
            try { await PersonalYouTubeTransferLease.Complete(failed, held); throw new Exception("Expected failure"); }
            catch (Exception error) when (cancelled ? error is OperationCanceledException : error is IOException) { }
            var reacquire = Task.Run(() => { using var next = PersonalYouTubeTransferLease.Enter(root, a); });
            await reacquire.WaitAsync(TimeSpan.FromSeconds(3));
            check(cancelled ? "Cancelled write releases owner lease" : "Faulted write releases owner lease", true);
        }
    }
}
