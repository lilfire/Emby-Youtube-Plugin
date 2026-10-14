using System.Text.Json;

namespace Emby.YouTubePlugin;

public sealed class PersonalYouTubeJobView
{
    public Guid OwnerUserId { get; set; }
    public Guid JobId { get; set; }
    public long ProfileRevision { get; set; }
    public string State { get; set; } = "Idle";
    public string? ErrorCode { get; set; }
    public int CompletedVideos { get; set; }
    public int TotalVideos { get; set; }
    public long? LibraryId { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

// One job per owner. Status never contains keys, URLs, channel names, paths
// or raw provider exceptions. The service chooses the authenticated owner.
internal sealed class PersonalYouTubeJobs : IDisposable
{
    private sealed class Slot
    {
        internal readonly CancellationTokenSource Cancellation;
        internal readonly PersonalYouTubeJobView View;
        internal Task Task = Task.CompletedTask;
        internal Slot(CancellationTokenSource cancellation, PersonalYouTubeJobView view)
        { Cancellation = cancellation; View = view; }
    }
    private readonly object _gate = new();
    private readonly string _directory;
    private readonly PersonalYouTubeStore _profiles;
    private readonly Func<PersonalYouTubeStore.Prepared, Action<string, int, int>, CancellationToken, Task<PersonalYouTubeInitialRefresh.Result>> _execute;
    private readonly Func<Guid, CancellationToken, Task>? _cleanup;
    private readonly Func<Guid, PersonalYouTubeJobView, bool>? _readyValid;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly Dictionary<Guid, Slot> _slots = new();
    private bool _disposed;
    internal static PersonalYouTubeJobs? Current { get; set; }
    internal PersonalYouTubeJobs(string directory,
        Func<PersonalYouTubeStore.Prepared, Action<string, int, int>, CancellationToken, Task<PersonalYouTubeInitialRefresh.Result>> execute,
        Func<Guid, CancellationToken, Task>? cleanup = null, Func<Guid, PersonalYouTubeJobView, bool>? readyValid = null)
    { _directory = Path.GetFullPath(directory); _profiles = new(_directory); _execute = execute; _cleanup = cleanup; _readyValid = readyValid; }

    private string StatusPath(Guid owner) => Path.Combine(_directory, "jobs", owner.ToString("N") + ".json");
    private void Persist(PersonalYouTubeJobView view)
    {
        view.UpdatedAt = DateTimeOffset.UtcNow;
        var path = StatusPath(view.OwnerUserId);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using(var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { file.Write(JsonSerializer.SerializeToUtf8Bytes(view)); file.Flush(true); }
            File.Move(temporary, path, true);
        }
        finally { if(File.Exists(temporary)) File.Delete(temporary); }
    }
    internal PersonalYouTubeJobView Read(Guid owner)
    {
        if(owner == Guid.Empty) throw new ArgumentException("Owner required.");
        lock(_gate)
        {
            var path = StatusPath(owner);
            var view = File.Exists(path) ? JsonSerializer.Deserialize<PersonalYouTubeJobView>(File.ReadAllText(path)) : null;
            if(view != null && (view.OwnerUserId != owner || view.JobId == Guid.Empty || view.ProfileRevision <= 0))
                throw new InvalidDataException("Invalid personal job status.");
            return view ?? new() { OwnerUserId = owner };
        }
    }
    internal void Notify(Guid owner)
    {
        lock(_gate)
        {
            if(_disposed) return;
            _slots.TryGetValue(owner, out var previous);
            if(previous != null)
            {
                if(previous.Task.IsCompleted) previous.Cancellation.Dispose();
                else previous.Cancellation.Cancel();
            }
            var profile = _profiles.Read(owner);
            if(profile.Revision == 0) return;
            var view = new PersonalYouTubeJobView {
                OwnerUserId = owner, JobId = Guid.NewGuid(), ProfileRevision = profile.Revision,
                State = profile.State == "Deleted" ? "Deleted" : !profile.HasApiKey || profile.Channels.Length == 0 ? "WaitingForSettings" : "Queued"
            };
            var slot = new Slot(CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token), view);
            _slots[owner] = slot;
            Persist(view);
            if(view.State != "Queued")
            {
                if(_cleanup == null) { slot.Task = previous?.Task ?? Task.CompletedTask; return; }
                var terminal = view.State;
                view.State = "Cleaning"; Persist(view);
                slot.Task = Task.Run(async () => {
                    if(previous != null) { try { await previous.Task.ConfigureAwait(false); } catch(Exception) { } }
                    try { await _cleanup(owner, slot.Cancellation.Token).ConfigureAwait(false); Update(owner, slot, terminal, 0, 0); }
                    catch(OperationCanceledException) { Update(owner, slot, "Cancelled", 0, 0); }
                    catch(Exception) { Update(owner, slot, "Failed", 0, 0, error: "CleanupFailed"); }
                });
                return;
            }
            var snapshot = _profiles.Prepare(owner);
            slot.Task = Task.Run(async () => {
                if(previous != null) { try { await previous.Task.ConfigureAwait(false); } catch(Exception) { } }
                try
                {
                    slot.Cancellation.Token.ThrowIfCancellationRequested();
                    if(!_profiles.IsCurrent(snapshot)) throw new OperationCanceledException();
                    var result = await _execute(snapshot, (state, done, total) => Update(owner, slot, state, done, total), slot.Cancellation.Token).ConfigureAwait(false);
                    if(!_profiles.IsCurrent(snapshot)) throw new OperationCanceledException();
                    Update(owner, slot, "Ready", result.Videos.Length, result.Videos.Length, result.Root.InternalId);
                }
                catch(OperationCanceledException) { Update(owner, slot, "Cancelled", 0, 0); }
                catch(Exception error)
                {
                    var frames = new System.Diagnostics.StackTrace(error).GetFrames()?.Take(4)
                        .Select(frame => frame.GetMethod()?.DeclaringType?.Name + "." + frame.GetMethod()?.Name) ?? Array.Empty<string>();
                    YouTubeChannel.LogPublic("[YT] Personal refresh failed at " + slot.View.State + " (" + error.GetType().Name + "): " + string.Join(" <- ", frames));
                    Update(owner, slot, "Failed", 0, 0, error: error is PersonalYouTubeJobFailure failure ? failure.Code : "RefreshFailed");
                }
                finally
                {
                    lock(_gate)
                        if(!_slots.TryGetValue(owner, out var current) || current != slot) slot.Cancellation.Dispose();
                }
            });
        }
    }
    private void Update(Guid owner, Slot slot, string state, int done, int total, long? library = null, string? error = null)
    {
        lock(_gate)
        {
            if(_disposed || !_slots.TryGetValue(owner, out var current) || current != slot) return;
            slot.View.State = state; slot.View.CompletedVideos = done; slot.View.TotalVideos = total;
            slot.View.LibraryId = library; slot.View.ErrorCode = error;
            Persist(slot.View);
        }
    }
    internal void Recover()
    {
        if(!Directory.Exists(_directory)) return;
        foreach(var path in Directory.EnumerateFiles(_directory, "*.json"))
        {
            if(!Guid.TryParseExact(Path.GetFileNameWithoutExtension(path), "N", out var owner)) continue;
            var profile = _profiles.Read(owner);
            var status = Read(owner);
            if(status.State == "Ready" && status.ProfileRevision == profile.Revision && (_readyValid == null || _readyValid(owner, status))) continue;
            Notify(owner);
        }
    }
    internal Task DrainAsync()
    { lock(_gate) return Task.WhenAll(_slots.Values.Select(slot => slot.Task)); }
    public void Dispose()
    {
        lock(_gate)
        {
            if(_disposed) return;
            _disposed = true; _lifetime.Cancel();
            if(ReferenceEquals(Current, this)) Current = null;
        }
    }
}
