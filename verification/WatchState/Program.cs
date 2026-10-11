using System.Reflection;
using Emby.YouTubePlugin;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Channels;
using MediaBrowser.Model.Configuration;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.Users;
using MediaBrowser.Model.Tasks;
using System.Diagnostics;

if (args.Length == 4 && args[0] == "--load-state-check")
{
    YouTubeWatchStateScan.Initialize(args[1]);
    if (YouTubeWatchStateScan.IsIncomplete(args[2]) != bool.Parse(args[3]))
        throw new Exception("persisted state did not survive process restart");
    return;
}

if (args.Contains("--sdk"))
{
    foreach (var t in new[] { typeof(MediaBrowser.Model.Tasks.ITaskManager), typeof(MediaBrowser.Model.Tasks.IScheduledTaskWorker), typeof(MediaBrowser.Model.Tasks.TaskCompletionEventArgs), typeof(MediaBrowser.Model.Tasks.IScheduledTask) })
    {
        Console.WriteLine("TYPE " + t.FullName);
        foreach (var m in t.GetMembers()) Console.WriteLine(m);
    }
    return;
}

int passed = 0;
void Check(bool ok, string message = "assertion failed") { if (!ok) throw new Exception(message); }
void Test(string name, Action<Fixture> test)
{
    using var f = new Fixture(); test(f); passed++; Console.WriteLine("PASS " + name);
}
Test("unwatched, mixed, watched, unwatch, unchanged writes", f =>
{
    f.Sync(); Check(!f.Data(1, 10).Played);
    f.Data(1, 11).Played = true; f.Sync(); Check(!f.Data(1, 10).Played);
    f.Data(1, 12).Played = true; f.Sync(); Check(f.Data(1, 10).Played && f.Saves == 1);
    f.Sync(); Check(f.Saves == 1);
    f.Data(1, 11).Played = false; f.Sync(); Check(!f.Data(1, 10).Played);
});
Test("new video and deletion of last unwatched video", f =>
{
    f.WatchAll(); f.Sync(); Check(f.Data(1, 10).Played);
    f.Items.Add(f.Video(13, 10)); f.Sync(); Check(!f.Data(1, 10).Played);
    f.Items.RemoveAll(i => i.InternalId == 13); f.Sync(); Check(f.Data(1, 10).Played);
});
Test("two users and folder-only manual marks", f =>
{
    f.Data(1, 10).Played = true; f.Sync(); Check(!f.Data(1, 10).Played);
    Check(!f.Data(1, 11).Played && !f.Data(1, 12).Played);
    f.WatchAll(); f.Sync(); f.Sync(2); Check(f.Data(1, 10).Played && !f.Data(2, 10).Played);
    f.Data(1, 10).Played = false; f.Sync(); Check(f.Data(1, 10).Played);
});
Test("empty channel and nonplayable placeholders", f =>
{
    f.Items.RemoveAll(i => i is Video);
    f.Items.Add(new Folder { InternalId = 99, ParentId = 10, ExternalId = "msg", Name = "No results found." });
    f.Data(1, 10).Played = true; f.Sync(); Check(!f.Data(1, 10).Played);
});
Test("SDK ancestor query returning the folder itself still repairs empty state", f =>
{
    f.Items.RemoveAll(i => i is Video); f.IncludeRootInDescendants = true;
    f.Data(1, 10).Played = true; f.Sync(); Check(!f.Data(1, 10).Played);
});
Test("access filters on folders and descendants", f =>
{
    f.Hidden.Add((1, 12)); f.Data(1, 11).Played = true; f.Sync(); Check(f.Data(1, 10).Played);
    Check(!f.Data(1, 12).Played);
    f.Hidden.Clear(); f.Sync(); Check(!f.Data(1, 10).Played);
    f.Hidden.Add((1, 10)); f.Sync(); Check(f.Saves == 2);
});
Test("recursive Videos, Shorts, Live", f =>
{
    f.Items.RemoveAll(i => i is Video);
    foreach (var (id, type) in new[] { (20L, "channelvideos"), (30L, "channelshorts"), (40L, "channellive") })
    {
        f.Items.Add(f.Folder(id, 10, type + "_x_UCfixture")); f.Items.Add(f.Video(id + 1, id)); f.Data(1, id + 1).Played = true;
    }
    f.Sync(); Check(f.Data(1, 10).Played);
    f.Data(1, 31).Played = false; f.Sync(); f.Sync(1, 30); Check(!f.Data(1, 10).Played && !f.Data(1, 30).Played);
    f.Sync(1, 20); Check(f.Data(1, 20).Played);
});
Test("unpopulated branch and error defer", f =>
{
    f.WatchAll(); f.Items.Add(f.Folder(20, 10, "channelshorts_x_unpopulated")); f.Sync(); Check(f.Saves == 0);
    f.Items.RemoveAll(i => i.InternalId == 20);
    f.Items.Add(new Folder { InternalId = 99, ParentId = 10, ExternalId = "msg", Name = "ERROR: unavailable" });
    f.Sync(); Check(f.Saves == 0);
});
Test("scan gate independent of 120-second tracking window", f =>
{
    f.WatchAll(); f.ScanActive = true; Check(!f.Sync() && f.Saves == 0); Check(!f.Sync() && f.Saves == 0);
    f.ScanActive = false; f.Sync(); Check(f.Data(1, 10).Played);
});
Test("concurrent new video invalidates result", f =>
{
    f.WatchAll(); f.BeforeRead = n => { if (n == 2) f.Items.Add(f.Video(13, 10)); };
    Check(!f.Sync() && f.Saves == 0); f.Sync(); Check(!f.Data(1, 10).Played);
});
Test("scan starts during confirmation", f =>
{
    f.WatchAll(); f.BeforeRead = n => { if (n == 2) f.ScanActive = true; }; Check(!f.Sync() && f.Saves == 0);
});
Test("read failure is not all watched", f =>
{
    f.WatchAll(); f.FailRead = true;
    try { f.Sync(); throw new Exception("expected failure"); } catch (IOException) { }
    Check(f.Saves == 0 && !f.Data(1, 10).Played);
});
Test("failed save restores cache and supports retry", f =>
{
    f.WatchAll(); f.FailSave = true;
    try { f.Sync(); throw new Exception("expected failure"); } catch (IOException) { }
    Check(!f.Data(1, 10).Played); f.FailSave = false; f.Sync(); Check(f.Data(1, 10).Played);
});
Test("preserve all other folder data and every video", f =>
{
    var d = f.Data(1, 10); d.IsFavorite = true; d.Rating = 8; d.PlayCount = 7; d.PlaybackPositionTicks = 12345;
    d.HideFromResume = true; d.LastPlayedDate = DateTimeOffset.UtcNow; d.AudioStreamIndex = 2; d.SubtitleStreamIndex = 3;
    var props = typeof(UserItemData).GetProperties().Where(p => p.Name != "Played").ToArray();
    var before = props.Select(p => p.GetValue(d)).ToArray(); f.WatchAll(); f.Sync(); Check(d.Played);
    Check(props.Select(p => p.GetValue(d)).SequenceEqual(before));
    Check(f.Items.OfType<Video>().All(v => f.Data(1, v.InternalId).Played));
});
Test("exclude other providers and non-channel roots", f =>
{
    f.WatchAll(); f.Root.SetProviderId(YouTubeFolderWatchStateSynchronizer.ProviderKey, "other"); f.Sync(); Check(f.Saves == 0);
    foreach (var id in new[] { "playlist_x_PLtest", "trending_x_all", "search_x_test", "categories_x_root" })
        Check(!YouTubeFolderWatchStateSynchronizer.IsManagedFolder(f.Folder(77, 0, id)));
});
Test("cancellation before save", f =>
{
    f.WatchAll(); using var stop = new CancellationTokenSource(); stop.Cancel();
    try { f.Synchronizer.TrySynchronize(1, 10, stop.Token); throw new Exception("expected cancellation"); }
    catch (OperationCanceledException) { } Check(f.Saves == 0);
});
Test("failed provider fetch requires successful retry", f =>
{
    f.Root.ExternalId = "channel_x_failure-test"; f.WatchAll();
    YouTubeWatchStateScan.RunAsync(f.Root.ExternalId, () => { YouTubeWatchStateScan.MarkIncomplete();
        return Task.FromResult(new ChannelItemResult { Items = new List<ChannelItemInfo>() }); }).GetAwaiter().GetResult();
    f.Sync(); Check(f.Saves == 0);
    YouTubeWatchStateScan.RunAsync(f.Root.ExternalId, () => Task.FromResult(new ChannelItemResult { Items = new List<ChannelItemInfo>() }))
        .GetAwaiter().GetResult(); f.Sync(); Check(f.Data(1, 10).Played);
});
Test("unknown video placeholders do not count", f =>
{
    f.WatchAll(); var unknown = f.Video(13, 10); unknown.ExternalId = "unknown-placeholder"; f.Items.Add(unknown);
    f.Sync(); Check(f.Data(1, 10).Played);
});
Test("manual descendant marks drive derived folder state", f =>
{
    f.WatchAll(); f.Sync(); Check(f.Data(1, 10).Played);
    f.Data(1, 11).Played = false; f.Data(1, 12).Played = false; f.Sync(); Check(!f.Data(1, 10).Played);
});
using (var f = new Fixture())
{
    f.WatchAll(); f.SaveFailuresRemaining = 1; f.Synchronizer.Start();
    await f.WaitFor(() => f.Data(1, 10).Played && f.Saves > 0);
    passed++; Console.WriteLine("PASS background retry after transient database failure");
    var (task, tp) = Proxy.Create<IScheduledTask>(); tp.Handler = (m, _) => m.Name == "get_Key" ? "RefreshInternetChannels" : throw new Exception(m.Name);
    var (worker, wp) = Proxy.Create<IScheduledTaskWorker>(); wp.Handler = (m, _) => m.Name == "get_ScheduledTask" ? task : throw new Exception(m.Name);
    Check(YouTubeFolderWatchStateSynchronizer.IsChannelScan(worker));
    // Ensure any self-save event has drained before changing state without an event.
    await Task.Delay(50); f.Data(1, 10).Played = false;
    f.TaskProxy.Raise("TaskCompleted", new TaskCompletionEventArgs { Task = worker, Result = new TaskResult { Status = TaskCompletionStatus.Failed } });
    await Task.Delay(50); Check(!f.Data(1, 10).Played);
    f.TaskProxy.Raise("TaskCompleted", new TaskCompletionEventArgs { Task = worker, Result = new TaskResult { Status = TaskCompletionStatus.Completed } });
    await f.WaitFor(() => f.Data(1, 10).Played);
    passed++; Console.WriteLine("PASS successful scheduled scan completion, failed completion ignored");
}
using (var f = new Fixture())
{
    f.Synchronizer.Start(); f.WatchAll(); f.RaiseVideo(12); await f.WaitFor(() => f.Data(1, 10).Played);
    var saved = f.Saves; await Task.Delay(50); Check(f.Saves == saved, "self-save loop");
    f.Data(1, 10).Played = false; f.RaiseVideo(10); await f.WaitFor(() => f.Data(1, 10).Played);
    f.Items.Add(f.Video(13, 10));
    f.LibraryProxy.Raise("ItemAdded", new ItemChangeEventArgs(f.Library) { Item = f.Items.Last(), Parent = f.Root });
    await f.WaitFor(() => !f.Data(1, 10).Played);
    f.Items.Add(f.Folder(50, 0, "channel_x_second"));
    var copy = f.Video(51, 50); var original = f.Items.Single(i => i.InternalId == 13);
    copy.ExternalId = original.ExternalId; copy.Path = original.Path; copy.SetProviderId("YouTube", original.GetProviderId("YouTube"));
    f.Items.Add(copy); f.Data(1, 51).Played = true; f.Data(1, 13).Played = true; f.RaiseVideo(13);
    await f.WaitFor(() => f.Data(1, 10).Played && f.Data(1, 50).Played);
    f.Data(1, 12).Played = false; f.RaiseVideo(12); await f.WaitFor(() => !f.Data(1, 10).Played);
    var moved = f.Items.Single(i => i.InternalId == 12); moved.ParentId = 50;
    f.LibraryProxy.Raise("ItemUpdated", new ItemChangeEventArgs(f.Library) { Item = moved, Parent = f.Items.Single(i => i.InternalId == 50) });
    await f.WaitFor(() => f.Data(1, 10).Played && !f.Data(1, 50).Played);
    f.Synchronizer.Dispose();
    Check(f.DataProxy.SubscriberCount == 0 && f.LibraryProxy.SubscriberCount == 0 && f.UserProxy.SubscriberCount == 0 && f.TaskProxy.SubscriberCount == 0);
    passed++; Console.WriteLine("PASS worker, events, shared parents, moved video, self-save convergence, unsubscribe");
}
var stateDirectory = Path.Combine(AppContext.BaseDirectory, "load-state-fixture");
Directory.CreateDirectory(stateDirectory);
File.WriteAllText(Path.Combine(stateDirectory, "youtube-folder-watch-load-state.json"), "{}");
YouTubeWatchStateScan.Initialize(stateDirectory);
const string persistedFolder = "channel_x_persisted-failure";
async Task CheckRestart(bool expectedIncomplete)
{
    using var child = Process.Start(new ProcessStartInfo("dotnet")
    {
        ArgumentList = { typeof(Proxy).Assembly.Location, "--load-state-check", stateDirectory, persistedFolder, expectedIncomplete.ToString() },
        UseShellExecute = false, CreateNoWindow = true
    }) ?? throw new Exception("could not start restart check");
    await child.WaitForExitAsync();
    Check(child.ExitCode == 0, "persisted state failed in a fresh process");
}
await YouTubeWatchStateScan.RunAsync(persistedFolder, () =>
{
    YouTubeWatchStateScan.MarkIncomplete(); return Task.FromResult(new ChannelItemResult { Items = new List<ChannelItemInfo>() });
});
await CheckRestart(true);
await YouTubeWatchStateScan.RunAsync(persistedFolder, () => Task.FromResult(new ChannelItemResult { Items = new List<ChannelItemInfo>() }));
await CheckRestart(false);
passed++; Console.WriteLine("PASS incomplete scan and successful recovery survive a fresh process");
foreach (var (name, queried, found, unavailable, expectedIncomplete) in new[]
{
    ("confirmed missing", new[] { "candidate" }, Array.Empty<string>(), Array.Empty<string>(), false),
    ("confirmed unplayable", new[] { "candidate" }, new[] { "candidate" }, new[] { "candidate" }, false),
    ("failed detail lookup", Array.Empty<string>(), Array.Empty<string>(), Array.Empty<string>(), true),
    ("unknown playable classification", new[] { "candidate" }, new[] { "candidate" }, Array.Empty<string>(), true)
})
{
    var folderId = "channel_x_enrichment_" + name;
    await YouTubeWatchStateScan.RunAsync(folderId, () =>
    {
        var unresolved = new HashSet<string> { "candidate" };
        YouTubeChannel.ExcludeConfirmedUnavailableCandidates(unresolved, queried.ToHashSet(), found.ToHashSet(), unavailable.ToHashSet());
        if (unresolved.Count > 0) YouTubeWatchStateScan.MarkIncomplete();
        return Task.FromResult(new ChannelItemResult { Items = new List<ChannelItemInfo>() });
    });
    Check(YouTubeWatchStateScan.IsIncomplete(folderId) == expectedIncomplete, name);
}
passed++; Console.WriteLine("PASS excluded unavailable videos complete the load; failed lookups and unknown playable videos still defer");
using (var f = new Fixture(migrateLegacy: true))
{
    f.Root.ParentId = 100;
    f.Root.ProviderIds.Remove(YouTubeFolderWatchStateSynchronizer.ProviderKey);
    f.Items.Add(new Channel { InternalId = 100, Name = "renamed YouTube" });
    f.Items.Add(new Channel { InternalId = 200, Name = "YouTube" });
    var foreign = new Folder { InternalId = 201, ParentId = 200, ExternalId = f.Root.ExternalId };
    var playlist = new Folder { InternalId = 202, ParentId = 100, ExternalId = "playlist_x_fixture" };
    var conflict = new Folder { InternalId = 203, ParentId = 100, ExternalId = f.Root.ExternalId };
    conflict.SetProviderId(YouTubeFolderWatchStateSynchronizer.ProviderKey, "other-provider");
    var branch = new Folder { InternalId = 20, ParentId = 10, ExternalId = "channelvideos_x_UCfixture" };
    f.Items.AddRange(new BaseItem[] { foreign, playlist, conflict, branch, f.Video(21, 20) });
    Check(f.Synchronizer.IsOwnedLegacyFolder(f.Root) && f.Synchronizer.IsOwnedLegacyFolder(branch));
    Check(!f.Synchronizer.IsOwnedLegacyFolder(foreign) && !f.Synchronizer.IsOwnedLegacyFolder(playlist)
        && !f.Synchronizer.IsOwnedLegacyFolder(conflict));
    f.WatchAll(); f.ScanActive = true; f.MarkerSaveFailuresRemaining = 1;
    f.Synchronizer.Start(); await Task.Delay(30);
    Check(f.MetadataSaves == 0 && f.Saves == 0);
    f.ScanActive = false;
    await f.WaitFor(() => f.MetadataSaves == 2 && f.Data(1, 10).Played && f.Data(1, 20).Played);
    Check(!f.Data(2, 10).Played && !f.Data(2, 20).Played);
    Check(string.IsNullOrEmpty(foreign.GetProviderId(YouTubeFolderWatchStateSynchronizer.ProviderKey)));
    Check(conflict.GetProviderId(YouTubeFolderWatchStateSynchronizer.ProviderKey) == "other-provider");
    f.Synchronizer.RequestAll(); await Task.Delay(30); Check(f.MetadataSaves == 2);
    f.Data(1, 21).Played = false; f.RaiseVideo(21);
    await f.WaitFor(() => !f.Data(1, 10).Played && !f.Data(1, 20).Played);
    passed++; Console.WriteLine("PASS legacy migration: actual owner, branches, scan gate, save retry, idempotency and video events");
}
Console.WriteLine($"{passed} checks passed. Actual Emby REST/client filtering requires integration validation.");

public class Proxy : DispatchProxy
{
    public Func<MethodInfo, object?[], object?> Handler = (_, _) => throw new NotImplementedException();
    private readonly Dictionary<string, Delegate?> _events = new();
    public int SubscriberCount => _events.Values.Sum(d => d?.GetInvocationList().Length ?? 0);
    public void Raise(string name, object args)
    {
        if (_events.TryGetValue(name, out var handlers))
            foreach (var d in handlers?.GetInvocationList() ?? Array.Empty<Delegate>()) d.DynamicInvoke(this, args);
    }
    protected override object? Invoke(MethodInfo? method, object?[]? args)
    {
        var m = method!; var a = args ?? Array.Empty<object?>();
        if (m.Name.StartsWith("add_") || m.Name.StartsWith("remove_"))
        {
            var key = m.Name[(m.Name.IndexOf('_') + 1)..]; _events.TryGetValue(key, out var current);
            _events[key] = m.Name.StartsWith("add_") ? Delegate.Combine(current, (Delegate)a[0]!) : Delegate.Remove(current, (Delegate)a[0]!);
            return null;
        }
        return Handler(m, a);
    }
    public static (T, Proxy) Create<T>() where T : class
    {
        var instance = Create<T, Proxy>(); return (instance, (Proxy)(object)instance);
    }
}

sealed class Fixture : IDisposable
{
    public readonly List<BaseItem> Items = new();
    public readonly User[] Users = new[]
    {
        new User { InternalId = 1, Name = "one", Policy = new UserPolicy(), Configuration = new UserConfiguration() },
        new User { InternalId = 2, Name = "two", Policy = new UserPolicy(), Configuration = new UserConfiguration() }
    };
    public readonly HashSet<(long User, long Item)> Hidden = new();
    private readonly Dictionary<(long User, long Item), UserItemData> _data = new();
    public readonly ILibraryManager Library;
    public readonly Proxy LibraryProxy, DataProxy, UserProxy, TaskProxy;
    public readonly YouTubeFolderWatchStateSynchronizer Synchronizer;
    public readonly Folder Root;
    public int Saves, MetadataSaves, MarkerSaveFailuresRemaining;
    public bool ScanActive, FailRead, FailSave;
    public bool IncludeRootInDescendants;
    public int SaveFailuresRemaining;
    private int _reads;
    public Action<int>? BeforeRead;
    public Fixture(bool migrateLegacy = false)
    {
        (Library, LibraryProxy) = Proxy.Create<ILibraryManager>();
        var (data, dp) = Proxy.Create<IUserDataManager>(); DataProxy = dp;
        var (users, up) = Proxy.Create<IUserManager>(); UserProxy = up;
        var (tasks, taskProxy) = Proxy.Create<ITaskManager>(); TaskProxy = taskProxy;
        LibraryProxy.Handler = (m, args) => m.Name switch
        {
            "GetItemList" => Query((InternalItemsQuery)args[0]!),
            "GetItemById" => Items.FirstOrDefault(i => i.InternalId == (long)args[0]!),
            "get_IsScanRunning" => ScanActive,
            "GetProviderIds" => Items.Single(i => i.InternalId == (long)args[0]!).ProviderIds,
            "UpdateItem" => SaveMarker(),
            _ => throw new NotImplementedException(m.Name)
        };
        UserProxy.Handler = (m, args) => m.Name switch
        {
            "GetUserById" => Users.FirstOrDefault(u => u.InternalId == (long)args[0]!),
            "GetUserList" => Users,
            "GetUserPolicy" => ((User)args[0]!).Policy,
            _ => throw new NotImplementedException(m.Name)
        };
        DataProxy.Handler = (m, args) =>
        {
            if (m.Name == "GetUserData") return Data(((User)args[0]!).InternalId, ((BaseItem)args[1]!).InternalId);
            if (m.Name != "SaveUserData") throw new NotImplementedException(m.Name);
            if (FailSave || SaveFailuresRemaining-- > 0) throw new IOException("database is locked"); Saves++;
            DataProxy.Raise("UserDataSaved", new UserDataSaveEventArgs { User = (User)args[0]!, Item = (BaseItem)args[1]!,
                UserData = (UserItemData)args[2]!, SaveReason = (UserDataSaveReason)args[3]! }); return null;
        };
        Root = Folder(10, 0, "channel_x_UCfixture"); Items.AddRange(new BaseItem[] { Root, Video(11, 10), Video(12, 10) });
        Synchronizer = new YouTubeFolderWatchStateSynchronizer(Library, data, users, () => ScanActive, TimeSpan.FromMilliseconds(5), tasks,
            ownsChannel: migrateLegacy ? channel => channel.InternalId == 100 : null);
    }
    private object? SaveMarker()
    {
        if (MarkerSaveFailuresRemaining-- > 0) throw new IOException("database is locked");
        MetadataSaves++;
        return null;
    }
    public Folder Folder(long id, long parent, string external)
    {
        var f = new Folder { InternalId = id, ParentId = parent, Name = "fixture", ExternalId = external };
        f.SetProviderId(YouTubeFolderWatchStateSynchronizer.ProviderKey, YouTubeFolderWatchStateSynchronizer.ProviderValue); return f;
    }
    public Video Video(long id, long parent)
    {
        var video = "fixture" + id;
        var v = new Video { InternalId = id, ParentId = parent, ExternalId = video, Path = "https://www.youtube.com/watch?v=" + video };
        v.SetProviderId("YouTube", video); return v;
    }
    public UserItemData Data(long user, long item)
    {
        if (!_data.TryGetValue((user, item), out var d)) _data[(user, item)] = d = new UserItemData(); return d;
    }
    public void WatchAll() { foreach (var v in Items.OfType<Video>()) Data(1, v.InternalId).Played = true; }
    public bool Sync(long user = 1, long folder = 10) => Synchronizer.TrySynchronize(user, folder, CancellationToken.None);
    private BaseItem[] Query(InternalItemsQuery q)
    {
        if (q.AncestorIds.Length != 0) { if (FailRead) throw new IOException("read failed"); BeforeRead?.Invoke(++_reads); }
        IEnumerable<BaseItem> result = Items.ToArray();
        if (q.User != null)
        {
            if (!q.EnforceShareLevel || !q.EnforceContentRestriction) throw new Exception("access filter omitted");
            result = result.Where(i => !Hidden.Contains((q.User.InternalId, i.InternalId)));
        }
        if (q.ItemIds.Length != 0) result = result.Where(i => q.ItemIds.Contains(i.InternalId));
        if (q.AncestorIds.Length != 0) result = result.Where(i => HasAncestor(i, q.AncestorIds)
            || IncludeRootInDescendants && q.AncestorIds.Contains(i.InternalId));
        if (q.IsFolder.HasValue) result = result.Where(i => (i is Folder) == q.IsFolder);
        if (!string.IsNullOrEmpty(q.ExternalId)) result = result.Where(i => i.ExternalId == q.ExternalId);
        if (q.HasAnyProviderId.Length != 0) result = result.Where(i => q.HasAnyProviderId.Any(p => !string.IsNullOrEmpty(i.GetProviderId(p))));
        return result.ToArray();
    }
    private bool HasAncestor(BaseItem item, long[] ancestors)
    {
        while (item.ParentId != 0)
        {
            if (ancestors.Contains(item.ParentId)) return true;
            var parent = Items.FirstOrDefault(i => i.InternalId == item.ParentId); if (parent == null) break; item = parent;
        }
        return false;
    }
    public void RaiseVideo(long id) => DataProxy.Raise("UserDataSaved", new UserDataSaveEventArgs
        { User = Users[0], Item = Items.Single(i => i.InternalId == id), UserData = Data(1, id) });
    public async Task WaitFor(Func<bool> condition)
    {
        var timeout = DateTime.UtcNow.AddSeconds(3);
        while (!condition()) { if (DateTime.UtcNow > timeout) throw new Exception("worker timed out"); await Task.Delay(5); }
    }
    public void Dispose() => Synchronizer.Dispose();
}
