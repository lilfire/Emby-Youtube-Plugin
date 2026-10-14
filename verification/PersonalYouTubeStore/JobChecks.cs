using Emby.YouTubePlugin;
using System.Text.Json;

internal static class JobChecks
{
    internal static async Task Run(string directory, Action<string, bool> check)
    {
        var profiles = new PersonalYouTubeStore(directory);
        var a = Guid.NewGuid(); var b = Guid.NewGuid();
        var channel = "UC" + new string('a', 22);
        profiles.Save(a, 0, new[] { channel }, "synthetic-private-job-key", false);
        profiles.Save(b, 0, new[] { channel }, "synthetic-other-key", false);
        var reached = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = new List<Guid>(); var cancellations = 0;
        using var jobs = new PersonalYouTubeJobs(directory, async (snapshot, progress, token) => {
            lock(calls) calls.Add(snapshot.OwnerUserId);
            progress("Buffering", 0, 1);
            if(snapshot.OwnerUserId == a && snapshot.Revision == 1)
            {
                reached.SetResult();
                try { await Task.Delay(Timeout.Infinite, token); }
                catch(OperationCanceledException) { Interlocked.Increment(ref cancellations); throw; }
            }
            return new(new(99, Guid.NewGuid()), new[] { new PersonalYouTubeNativeBindings.NativeItem(100, Guid.NewGuid()) }, snapshot.Revision);
        });
        jobs.Notify(a); await reached.Task.WaitAsync(TimeSpan.FromSeconds(5));
        check("Personal job runs from saved owner snapshot", jobs.Read(a).State == "Buffering" && jobs.Read(a).ProfileRevision == 1);
        check("Other owner job status does not reveal active task", jobs.Read(b).State == "Idle" && jobs.Read(b).LibraryId == null);
        jobs.Notify(b);
        profiles.Save(a, 1, new[] { channel }, null, false); jobs.Notify(a);
        await jobs.DrainAsync().WaitAsync(TimeSpan.FromSeconds(5));
        check("New save cancels and serializes old task", cancellations == 1 && jobs.Read(a).State == "Ready" && jobs.Read(a).ProfileRevision == 2);
        check("Other owner can finish independently", jobs.Read(b).State == "Ready");
        check("Persisted job status contains no API keys", !File.ReadAllText(Path.Combine(directory, "jobs", a.ToString("N") + ".json")).Contains("synthetic-private-job-key"));
        using var recovered = new PersonalYouTubeJobs(directory, (_, _, _) => throw new InvalidOperationException("A ready task must not restart"));
        recovered.Recover(); await recovered.DrainAsync();
        check("Restart reads completed status without repeating publication", recovered.Read(a).State == "Ready" && recovered.Read(b).State == "Ready");
        profiles.Delete(a, 2); jobs.Notify(a); await jobs.DrainAsync();
        check("Profile deletion clears active publication status", jobs.Read(a).State == "Deleted" && jobs.Read(a).LibraryId == null);
        using var failing = new PersonalYouTubeJobs(directory, (_, _, _) => throw new InvalidOperationException("provider URL contains synthetic-other-key"));
        failing.Notify(b); await failing.DrainAsync();
        check("Provider failures produce sanitized persisted status", failing.Read(b).State == "Failed" && failing.Read(b).ErrorCode == "RefreshFailed"
            && !File.ReadAllText(Path.Combine(directory, "jobs", b.ToString("N") + ".json")).Contains("synthetic-other-key"));
        var prior = profiles.Prepare(b);
        new PersonalYouTubePublicationJournal(directory).Begin(prior);
        var replaced = profiles.SaveForRefresh(b, prior.Revision, new[] { channel }, null, false);
        var next = profiles.Prepare(b);
        check("Published refresh rotates generation and keeps encrypted owner key", replaced.GenerationId != prior.GenerationId
            && next.CollectionId == prior.CollectionId && next.ApiKey == prior.ApiKey && !profiles.IsCurrent(prior));
        var document = JsonSerializer.Deserialize<PersonalYouTubeStore.Document>(File.ReadAllText(Path.Combine(directory, b.ToString("N") + ".json")))!;
        check("Retired generation contains no reusable key or channels", document.Retired.Length == 1
            && document.Retired[0].State == "Deleted" && document.Retired[0].EncryptedApiKey == null && document.Retired[0].Channels.Length == 0);
        var budgetDirectory = Path.Combine(directory, "storage-budget-check");
        Directory.CreateDirectory(Path.Combine(budgetDirectory, "media"));
        Directory.CreateDirectory(Path.Combine(budgetDirectory, "buffer"));
        File.WriteAllBytes(Path.Combine(budgetDirectory, "media", "existing.mp4"), new byte[4096]);
        File.WriteAllBytes(Path.Combine(budgetDirectory, "buffer", "existing.part"), new byte[2048]);
        var budget = await PersonalYouTubeStorageBudget.EnterAsync(budgetDirectory, CancellationToken.None);
        check("Combined storage reserves both staging and publication copies", budget.DownloadAllowance(16384, 16384) == 5120);
        check("Collection budget remains the lower bound", budget.DownloadAllowance(16384, 2048) == 2048);
        try { budget.DownloadAllowance(8192 - 1, 16384); check("Storage budget rejects insufficient publication capacity", false); }
        catch(PersonalYouTubeJobFailure error) { check("Storage budget rejects insufficient publication capacity", error.Code == "StorageBudgetExceeded"); }
        var secondBudget = PersonalYouTubeStorageBudget.EnterAsync(budgetDirectory, CancellationToken.None);
        check("Other owners wait for shared server storage admission", !secondBudget.IsCompleted);
        budget.Dispose(); using var admitted = await secondBudget.WaitAsync(TimeSpan.FromSeconds(5));
    }
}
