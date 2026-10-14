using System.Collections.Concurrent;

namespace Emby.YouTubePlugin;

// One process, one owner: profile mutations and native write tasks share this
// gate. No thread-affine monitor is held across an asynchronous transfer.
internal static class PersonalYouTubeTransferLease
{
    private sealed class Entry { internal readonly SemaphoreSlim Semaphore = new(1, 1); internal int Waiting; }
    private static readonly ConcurrentDictionary<string, ConcurrentDictionary<Guid, Entry>> Roots = new(StringComparer.OrdinalIgnoreCase);
    internal sealed record State(bool Held, int Waiting);
    internal static State Snapshot(string directory, Guid owner)
    {
        var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        return Roots.TryGetValue(root, out var owners) && owners.TryGetValue(owner, out var entry)
            ? new(entry.Semaphore.CurrentCount == 0, Volatile.Read(ref entry.Waiting)) : new(false, 0);
    }
    private sealed class Lease : IDisposable
    {
        private SemaphoreSlim? _semaphore;
        internal Lease(SemaphoreSlim semaphore) => _semaphore = semaphore;
        public void Dispose() => Interlocked.Exchange(ref _semaphore, null)?.Release();
    }
    internal static IDisposable Enter(string directory, Guid owner)
    {
        if (owner == Guid.Empty) throw new ArgumentException("An authenticated owner is required.");
        var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory));
        var owners = Roots.GetOrAdd(root, _ => new());
        var entry = owners.GetOrAdd(owner, _ => new());
        Interlocked.Increment(ref entry.Waiting);
        try { entry.Semaphore.Wait(); }
        finally { Interlocked.Decrement(ref entry.Waiting); }
        return new Lease(entry.Semaphore);
    }
    internal static async Task Complete(Task task, IDisposable lease)
    {
        try { await task.ConfigureAwait(false); }
        finally { lease.Dispose(); }
    }
}
