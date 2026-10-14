using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;

namespace Emby.YouTubePlugin;

// A synchronous server-only scope for the verified native AddVirtualFolder
// call chain. It intentionally does not flow into tasks, queued work or requests.
// Native pre-insert hooks must call ReserveCurrentRoot before root visibility.
internal sealed class PersonalYouTubeNativeCreation
{
    [ThreadStatic] private static Scope? _current;
    private readonly PersonalYouTubePublicationJournal _journal;
    internal PersonalYouTubeNativeCreation(string directory) => _journal = new(directory);

    internal Scope Open(PersonalYouTubeStore.Prepared snapshot)
    {
        if (_current != null) throw new InvalidOperationException("Nested private native creation is not allowed.");
        var entry = _journal.Begin(snapshot);
        if (entry.State != "Preparing" || entry.ReservedRootId.HasValue)
            throw new InvalidOperationException("Private creation requires recovery rather than another native root.");
        var scope = new Scope(_journal, snapshot, _journal.MediaPath(entry));
        _current = scope;
        return scope;
    }
    // False means an ordinary native creation has no private publisher context.
    // An error in an active context must propagate and abort native creation.
    internal static bool ReserveCurrentRoot(Guid rootId)
    {
        if (_current == null) return false;
        _current.Reserve(rootId);
        return true;
    }
    internal sealed class Scope : IDisposable
    {
        private readonly PersonalYouTubePublicationJournal _journal;
        private readonly PersonalYouTubeStore.Prepared _snapshot;
        private readonly int _threadId = Environment.CurrentManagedThreadId;
        private readonly int? _taskId = Task.CurrentId;
        private Guid? _reserved;
        private bool _disposed, _completed;
        internal string MediaPath { get; }
        internal Scope(PersonalYouTubePublicationJournal journal, PersonalYouTubeStore.Prepared snapshot, string path)
        { _journal = journal; _snapshot = snapshot; MediaPath = path; }
        private void RequireCurrent()
        {
            if (_disposed || _current != this || _threadId != Environment.CurrentManagedThreadId || _taskId != Task.CurrentId)
                throw new InvalidOperationException("Native creation context is not current on this thread.");
        }
        internal void Reserve(Guid rootId)
        {
            RequireCurrent();
            if (_completed || _reserved.HasValue)
                throw new InvalidOperationException("Only one root may be created in a private creation context.");
            if (!_journal.ReserveRootIdentity(_snapshot, rootId))
                throw new InvalidOperationException("Native creation profile snapshot is stale.");
            _reserved = rootId;
        }
        internal NativeItem Complete(NativeItem actualRoot)
        {
            RequireCurrent();
            if (_completed || !_reserved.HasValue || actualRoot.InternalId <= 0 || actualRoot.ItemId != _reserved)
                throw new InvalidOperationException("Native root does not match the reserved creation identity.");
            _completed = true;
            return actualRoot;
        }
        public void Dispose()
        {
            if (_disposed) return;
            RequireCurrent();
            _current = null;
            _disposed = true;
            // Never remove reservations on failure: a partially created root
            // must stay denied until explicit recovery handles native state.
        }
    }
}
