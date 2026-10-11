using MediaBrowser.Controller.Channels;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.Events;
using MediaBrowser.Model.Querying;
using MediaBrowser.Model.Tasks;
using System.Collections.Concurrent;
using System.Text.Json;
using System.Reflection;

namespace Emby.YouTubePlugin;

/// <summary>Derived folder state only; never calls Folder.MarkPlayed or changes videos.</summary>
internal sealed class YouTubeFolderWatchStateSynchronizer : IDisposable
{
    internal const string ProviderKey = "YouTubeChannel";
    internal const string ProviderValue = "youtube_channel_10";
    private readonly ILibraryManager _library;
    private readonly IUserDataManager _data;
    private readonly IUserManager _users;
    private readonly ConcurrentDictionary<(long User, long Folder), byte> _pending = new();
    private readonly ConcurrentDictionary<(long User, long Item), BaseItem> _changed = new();
    private readonly ConcurrentDictionary<(long User, string Video), bool> _played = new();
    private readonly ConcurrentDictionary<long, long> _knownParents = new();
    private readonly ConcurrentDictionary<long, byte> _oldParents = new();
    private readonly SemaphoreSlim _signal = new(0, 1);
    private readonly CancellationTokenSource _stop = new();
    private readonly Func<bool> _scanActive;
    private readonly ITaskManager? _tasks;
    private readonly TimeSpan _settle;
    private readonly Func<Channel, bool>? _ownsChannel;
    private Task? _worker;
    private long _revision;
    private int _all;
    private int _disposed;

    internal YouTubeFolderWatchStateSynchronizer(ILibraryManager library, IUserDataManager data,
        IUserManager users, Func<bool>? scanActive = null, TimeSpan? settle = null, ITaskManager? tasks = null,
        IChannelManager? channels = null, Func<Channel, bool>? ownsChannel = null)
    {
        _library = library;
        _data = data;
        _users = users;
        _tasks = tasks;
        _scanActive = scanActive ?? (() => ChannelRefreshInvoker.IsRefreshInProgress || library.IsScanRunning
            || tasks?.ScheduledTasks.Any(task => IsChannelScan(task)
                && task.State != TaskState.Idle) == true);
        _settle = settle ?? TimeSpan.FromSeconds(2);
        _ownsChannel = ownsChannel ?? (channels == null ? null : channel => OwnsChannel(channels, channel));
    }

    private static bool OwnsChannel(IChannelManager manager, Channel channel)
    {
        // The SDK does not expose this mapping. Resolve the actual registered
        // provider, never a display name or a guessed channel/database id.
        var method = manager.GetType().GetMethod("GetChannelProvider",
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            null, new[] { typeof(Channel) }, null);
        return method?.Invoke(manager, new object[] { channel }) is YouTubeChannel provider
            && provider.Id == ProviderValue;
    }

    internal bool IsOwnedLegacyFolder(BaseItem item)
    {
        if (_ownsChannel == null || item is not Folder || !IsManagedExternalId(item.ExternalId)
            || !string.IsNullOrEmpty(item.GetProviderId(ProviderKey))) return false;
        var visited = new HashSet<long>();
        BaseItem current = item;
        while (visited.Add(current.InternalId))
        {
            var parent = _library.GetItemById(current.ParentId);
            if (parent is Channel channel)
                return YouTubeChannel.IsSavedChannelRootExternalId(current.ExternalId) && _ownsChannel(channel);
            if (parent is not Folder || !YouTubeChannel.IsSavedChannelRootExternalId(parent.ExternalId)
                || YouTubeChannel.IsSavedChannelRootExternalId(current.ExternalId)) return false;
            current = parent;
        }
        return false;
    }

    private bool MigrateLegacyFolders(CancellationToken ct)
    {
        if (_ownsChannel == null) return true;
        var migrated = 0;
        foreach (var folder in _library.GetItemList(new InternalItemsQuery
            { IsFolder = true, Recursive = true }, ct).OfType<Folder>())
        {
            ct.ThrowIfCancellationRequested();
            if (_scanActive()) return false;
            if (!IsOwnedLegacyFolder(folder)) continue;
            if (_scanActive()) return false;
            folder.SetProviderId(ProviderKey, ProviderValue);
            try
            {
                _library.UpdateItem(folder, null, ItemUpdateType.MetadataEdit);
                if (_library.GetProviderIds(folder.InternalId, ct)?.GetValueOrDefault(ProviderKey) != ProviderValue)
                    throw new InvalidOperationException("Folder ownership marker was not retained.");
                migrated++;
            }
            catch
            {
                folder.ProviderIds.Remove(ProviderKey);
                throw;
            }
        }
        if (migrated > 0) YouTubeChannel.LogPublic($"[YT] Migrated {migrated} legacy channel folders for watched-state synchronization.");
        return true;
    }

    internal static bool IsManagedFolder(BaseItem item) => item is Folder
        && string.Equals(item.GetProviderId(ProviderKey), ProviderValue, StringComparison.Ordinal)
        && IsManagedExternalId(item.ExternalId);

    internal static bool IsManagedExternalId(string? id) => YouTubeChannel.IsSavedChannelRootExternalId(id)
        || id?.StartsWith("channelvideos_x_", StringComparison.Ordinal) == true
        || id?.StartsWith("channelshorts_x_", StringComparison.Ordinal) == true
        || id?.StartsWith("channellive_x_", StringComparison.Ordinal) == true;

    public void Start()
    {
        _library.ItemAdded += OnContentChanged;
        _library.ItemUpdated += OnContentChanged;
        _library.ItemRemoved += OnContentChanged;
        _data.UserDataSaved += OnUserDataSaved;
        _users.UserCreated += OnUserChanged;
        _users.UserPolicyUpdated += OnUserChanged;
        _users.UserConfigurationUpdated += OnUserChanged;
        if (_tasks != null) _tasks.TaskCompleted += OnTaskCompleted;
        _worker = Task.Run(ProcessAsync);
        RequestAll();
    }

    public void RequestAll()
    {
        Interlocked.Exchange(ref _all, 1);
        Wake();
    }

    private void Wake()
    {
        Interlocked.Increment(ref _revision);
        if (Volatile.Read(ref _disposed) != 0) return;
        try { _signal.Release(); }
        catch (SemaphoreFullException) { }
        catch (ObjectDisposedException) { }
    }

    private void OnUserChanged(object? sender, GenericEventArgs<User> e) => RequestAll();

    internal static bool IsChannelScan(IScheduledTaskWorker task) =>
        string.Equals(task.ScheduledTask.Key, "RefreshInternetChannels", StringComparison.Ordinal)
        || task.ScheduledTask.GetType().FullName?.Contains(".Channels.", StringComparison.Ordinal) == true;

    private void OnTaskCompleted(object? sender, TaskCompletionEventArgs e)
    {
        if (!IsChannelScan(e.Task)) return;
        if (e.Result.Status == TaskCompletionStatus.Completed) RequestAll();
        else YouTubeWatchStateScan.MarkAllIncomplete();
    }

    private void OnContentChanged(object? sender, ItemChangeEventArgs e)
    {
        if (e.Item == null || !IsManagedFolder(e.Item) && YouTubeImageProvider.TryGetVideoId(e.Item) == null) return;
        // Keep the old parent supplied on removal/move, as well as the new item.
        _changed[(0, e.Item.InternalId)] = e.Item;
        if (_knownParents.TryGetValue(e.Item.InternalId, out var oldParent) && oldParent != e.Item.ParentId)
            _oldParents[oldParent] = 0;
        _knownParents[e.Item.InternalId] = e.Item.ParentId;
        if (e.Parent != null) _changed[(0, e.Parent.InternalId)] = e.Parent;
        Wake();
    }

    private void OnUserDataSaved(object? sender, UserDataSaveEventArgs e)
    {
        if (e.User == null || e.Item == null || e.UserData == null) return;
        var video = YouTubeImageProvider.TryGetVideoId(e.Item);
        if (video != null)
        {
            // Progress events need work only when Played changes. Key by the raw
            // video identity: copies in other saved channels share user data.
            var key = (e.User.InternalId, video);
            var played = e.UserData.Played;
            if (_played.TryGetValue(key, out var previous) && previous == played) return;
            if (_played.Count > 20000) _played.Clear();
            _played[key] = played;
            // Discovery stays on the worker, never on Emby's event thread.
            _changed[(e.User.InternalId, e.Item.InternalId)] = e.Item;
        }
        else if (IsManagedFolder(e.Item))
        {
            _pending[(e.User.InternalId, e.Item.InternalId)] = 0;
        }
        else return;
        // A save emitted by this component can queue one more read. It cannot
        // cause a write loop because unchanged state is never saved.
        Wake();
    }

    private BaseItem[] ManagedFolders(User? user, CancellationToken ct) => _library.GetItemList(
        new InternalItemsQuery(user)
        {
            IsFolder = true,
            HasAnyProviderId = new[] { ProviderKey },
            Recursive = true,
            EnforceShareLevel = user != null,
            EnforceContentRestriction = user != null
        }, ct).Where(IsManagedFolder).ToArray();

    private void Discover(CancellationToken ct)
    {
        if (Volatile.Read(ref _all) != 0 && !MigrateLegacyFolders(ct))
        {
            Wake();
            return;
        }
        if (Interlocked.Exchange(ref _all, 0) != 0)
        {
            foreach (var user in _users.GetUserList(new UserQuery()))
                foreach (var folder in ManagedFolders(user, ct))
                    _pending[(user.InternalId, folder.InternalId)] = 0;
        }
        foreach (var id in _oldParents.Keys)
        {
            if (!_oldParents.TryRemove(id, out _)) continue;
            if (_library.GetItemById(id) is { } oldParent) _changed[(0, id)] = oldParent;
        }
        foreach (var id in _changed.Keys)
        {
            if (!_changed.TryRemove(id, out var item)) continue;
            var video = YouTubeImageProvider.TryGetVideoId(item);
            var affected = new HashSet<long>();
            AddParents(item, affected);
            if (video != null)
            {
                // Resolve every materialized occurrence, including Shorts/Live
                // variants. This query is bounded to one video's external ids.
                foreach (var externalId in new[] { video, "REEL_" + video, "LIVE_" + video })
                    foreach (var copy in _library.GetItemList(new InternalItemsQuery
                        { ExternalId = externalId, IsFolder = false, Recursive = true }, ct))
                        if (YouTubeImageProvider.TryGetVideoId(copy) == video) AddParents(copy, affected);
            }
            foreach (var user in _users.GetUserList(new UserQuery()))
            {
                if (id.User != 0 && id.User != user.InternalId) continue;
                foreach (var folder in affected) _pending[(user.InternalId, folder)] = 0;
            }
        }
    }

    private void AddParents(BaseItem item, HashSet<long> affected)
    {
        var visited = new HashSet<long>();
        for (BaseItem? current = item; current != null && visited.Add(current.InternalId);)
        {
            if (IsManagedFolder(current)) affected.Add(current.InternalId);
            _knownParents[current.InternalId] = current.ParentId;
            current = current.ParentId == 0 ? null : _library.GetItemById(current.ParentId);
        }
    }

    private bool? Calculate(User user, Folder folder, CancellationToken ct)
    {
        if (YouTubeWatchStateScan.IsIncomplete(folder.ExternalId)) return null;
        var descendants = _library.GetItemList(new InternalItemsQuery(user)
        {
            AncestorIds = new[] { folder.InternalId },
            Recursive = true,
            EnforceShareLevel = true,
            EnforceContentRestriction = true
        }, ct).Where(item => item.InternalId != folder.InternalId).ToArray();
        foreach (var item in descendants) _knownParents.TryAdd(item.InternalId, item.ParentId);
        var videos = descendants.Where(item => item is Video && !item.IsPlaceHolder
            && YouTubeImageProvider.TryGetVideoId(item) != null).ToArray();
        // A visible unpopulated/failed branch must not make a partly loaded root
        // appear fully watched. Message folders are not playable videos.
        if (descendants.Any(item => item.ExternalId == "msg"
                && item.Name is not ("No results found." or "No live or upcoming streams found."))
            || descendants.Where(item => item is Folder && IsManagedExternalId(item.ExternalId)).Any(branch =>
                YouTubeWatchStateScan.IsIncomplete(branch.ExternalId)
                || !descendants.Any(item => item.ParentId == branch.InternalId)
                   && !YouTubeWatchStateScan.HasCompleted(branch.ExternalId))) return null;
        return videos.Length > 0 && videos.All(item => _data.GetUserData(user, item, ct).Played);
    }

    internal bool TrySynchronize(long userId, long folderId, CancellationToken ct)
    {
        var revision = Volatile.Read(ref _revision);
        if (_scanActive()) return false;
        var user = _users.GetUserById(userId);
        if (user == null || _users.GetUserPolicy(user).IsDisabled) return true;
        // The user-scoped lookup also guards folder sharing/access.
        var folder = _library.GetItemList(new InternalItemsQuery(user)
        {
            ItemIds = new[] { folderId }, EnforceShareLevel = true, EnforceContentRestriction = true
        }, ct).OfType<Folder>().FirstOrDefault(IsManagedFolder);
        if (folder == null) return true;
        var desired = Calculate(user, folder, ct);
        if (!desired.HasValue) return true; // Wait for a successful content event.
        var data = _data.GetUserData(user, folder, ct);
        if (data.Played == desired.Value) return true;
        // Read again after discovery and user-data reads. An event/scan during
        // either pass invalidates the result; the queue retries after settling.
        var scanRevision = YouTubeWatchStateScan.Revision;
        var confirmed = Calculate(user, folder, ct);
        ct.ThrowIfCancellationRequested();
        if (_scanActive() || revision != Volatile.Read(ref _revision)
            || scanRevision != YouTubeWatchStateScan.Revision || confirmed != desired) return false;
        data = _data.GetUserData(user, folder, ct);
        if (data.Played == desired.Value) return true;
        var previous = data.Played;
        data.Played = desired.Value;
        try
        {
            _data.SaveUserData(user, folder, data, UserDataSaveReason.TogglePlayed, ct);
        }
        catch
        {
            // GetUserData can return cached objects. A failed persistence must
            // not leave that cache pretending the desired value was saved.
            data.Played = previous;
            throw;
        }
        if (_data.GetUserData(user, folder, ct).Played != desired.Value)
            throw new InvalidOperationException("Folder Played save was not retained.");
        return true;
    }

    private async Task ProcessAsync()
    {
        var ct = _stop.Token;
        try
        {
            while (true)
            {
                await _signal.WaitAsync(ct).ConfigureAwait(false);
                await Task.Delay(_settle, ct).ConfigureAwait(false);
                while (_scanActive()) await Task.Delay(TimeSpan.FromMilliseconds(500), ct).ConfigureAwait(false);
                for (var discoveryAttempt = 0; discoveryAttempt < 5; discoveryAttempt++)
                {
                    try { Discover(ct); break; }
                    catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
                    catch (Exception ex)
                    {
                        Interlocked.Exchange(ref _all, 1);
                        if (discoveryAttempt == 4)
                            YouTubeChannel.LogPublic($"[YT] Folder watch-state discovery failed ({ex.GetType().Name}); waiting for next change.");
                        else await Task.Delay(TimeSpan.FromSeconds(discoveryAttempt + 1), ct).ConfigureAwait(false);
                    }
                }
                foreach (var key in _pending.Keys)
                {
                    if (!_pending.TryRemove(key, out _)) continue;
                    for (var attempt = 0; attempt < 5; attempt++)
                    {
                        ct.ThrowIfCancellationRequested();
                        while (_scanActive()) await Task.Delay(TimeSpan.FromMilliseconds(500), ct).ConfigureAwait(false);
                        try
                        {
                            if (TrySynchronize(key.User, key.Folder, ct)) break;
                            _pending[key] = 0;
                            Wake();
                            break;
                        }
                        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
                        catch (Exception ex)
                        {
                            if (attempt == 4)
                                YouTubeChannel.LogPublic($"[YT] Folder watch-state save failed ({ex.GetType().Name}); waiting for next change.");
                            else await Task.Delay(TimeSpan.FromSeconds(attempt + 1), ct).ConfigureAwait(false);
                        }
                    }
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        _library.ItemAdded -= OnContentChanged;
        _library.ItemUpdated -= OnContentChanged;
        _library.ItemRemoved -= OnContentChanged;
        _data.UserDataSaved -= OnUserDataSaved;
        _users.UserCreated -= OnUserChanged;
        _users.UserPolicyUpdated -= OnUserChanged;
        _users.UserConfigurationUpdated -= OnUserChanged;
        if (_tasks != null) _tasks.TaskCompleted -= OnTaskCompleted;
        _stop.Cancel();
        // Release primitives only after the worker exits, even if an SDK read
        // is still finishing during plugin unload.
        if (_worker == null) { _signal.Dispose(); _stop.Dispose(); }
        else _ = _worker.ContinueWith(_ => { _signal.Dispose(); _stop.Dispose(); }, TaskScheduler.Default);
    }
}

/// <summary>Tracks provider fetches, including Emby's own scheduled scans.</summary>
internal static class YouTubeWatchStateScan
{
    private sealed class Fetch { public bool Incomplete; }
    private static readonly AsyncLocal<Fetch?> Current = new();
    private static readonly ConcurrentDictionary<string, (long Generation, bool Complete)> Results = new(StringComparer.Ordinal);
    private static int _active;
    private static long _revision;
    private static readonly object StateGate = new();
    private static string? _statePath;
    private static bool _stateUnreadable;
    public static bool IsActive => Volatile.Read(ref _active) != 0;
    public static long Revision => Volatile.Read(ref _revision);
    public static bool IsIncomplete(string id) => Results.TryGetValue(id, out var result)
        ? !result.Complete : _stateUnreadable;
    public static bool HasCompleted(string id) => Results.TryGetValue(id, out var result) && result.Complete;
    public static void MarkIncomplete() { if (Current.Value is { } fetch) fetch.Incomplete = true; }

    public static void Initialize(string? dataPath)
    {
        if (string.IsNullOrEmpty(dataPath)) return;
        lock (StateGate)
        {
            _statePath = Path.Combine(dataPath, "youtube-folder-watch-load-state.json");
            try
            {
                if (!File.Exists(_statePath)) return;
                var saved = JsonSerializer.Deserialize<Dictionary<string, bool>>(File.ReadAllText(_statePath))
                    ?? throw new InvalidDataException();
                foreach (var entry in saved.Where(entry => YouTubeFolderWatchStateSynchronizer.IsManagedExternalId(entry.Key)))
                    Results[entry.Key] = (0, entry.Value);
            }
            catch (Exception ex)
            {
                _stateUnreadable = true;
                YouTubeChannel.LogPublic($"[YT] Folder load-state read failed ({ex.GetType().Name}); waiting for successful folder loads.");
            }
        }
    }

    public static void MarkAllIncomplete()
    {
        var generation = Interlocked.Increment(ref _revision);
        foreach (var id in Results.Keys) Store(id, generation, false);
    }

    private static void Store(string id, long generation, bool complete)
    {
        lock (StateGate)
        {
            if (Results.TryGetValue(id, out var prior) && generation < prior.Generation) return;
            Results[id] = (generation, complete);
            if (_statePath == null || prior.Complete == complete && prior.Generation != 0) return;
            try
            {
                // This is plugin-owned scan metadata, not Emby's user database.
                // Persist pending/failed loads so a restart cannot make a partial
                // channel suddenly qualify as fully watched.
                var temporary = _statePath + ".tmp";
                File.WriteAllText(temporary, JsonSerializer.Serialize(Results.ToDictionary(x => x.Key, x => x.Value.Complete)));
                File.Move(temporary, _statePath, overwrite: true);
            }
            catch (Exception ex)
            {
                _stateUnreadable = true;
                YouTubeChannel.LogPublic($"[YT] Folder load-state write failed ({ex.GetType().Name}).");
            }
        }
    }

    public static async Task<ChannelItemResult> RunAsync(string? folderId, Func<Task<ChannelItemResult>> fetch)
    {
        var previous = Current.Value;
        var state = new Fetch();
        Current.Value = state;
        Interlocked.Increment(ref _active);
        var generation = Interlocked.Increment(ref _revision);
        if (YouTubeFolderWatchStateSynchronizer.IsManagedExternalId(folderId)) Store(folderId!, generation, false);
        try
        {
            var result = await fetch().ConfigureAwait(false);
            state.Incomplete |= result.Items.Any(item => item.Id == "msg"
                && item.Name.StartsWith("ERROR:", StringComparison.Ordinal));
            return result;
        }
        catch { state.Incomplete = true; throw; }
        finally
        {
            if (YouTubeFolderWatchStateSynchronizer.IsManagedExternalId(folderId))
                Store(folderId!, generation, !state.Incomplete);
            Current.Value = previous;
            Interlocked.Decrement(ref _active);
            Interlocked.Increment(ref _revision);
            ChannelRefreshInvoker.NoteChannelScanActivity();
            PluginEntryPoint.RequestFolderWatchStateSync();
        }
    }
}
