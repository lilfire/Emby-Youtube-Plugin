using MediaBrowser.Controller.Library;
using MediaBrowser.Model.IO;

namespace Emby.YouTubePlugin;

internal static class PersonalYouTubeJobRuntime
{
    internal static PersonalYouTubeJobs Start(string directory, ILibraryManager library, IFileSystem files,
        PluginConfiguration configuration, HttpClient? catalogClient = null, IUserManager? users = null)
    {
        var lifecycle = new PersonalYouTubeLifecycle(directory, library, users);
        var jobs = new PersonalYouTubeJobs(directory, async (snapshot, progress, token) => {
            using var budget = await PersonalYouTubeStorageBudget.EnterAsync(directory, token).ConfigureAwait(false);
            var owner = users?.GetUserById(snapshot.OwnerUserId.ToString("N"));
            if(users != null && (owner == null || owner.Policy.IsDisabled))
                throw new InvalidOperationException("Personal account unavailable.");
            if(!PersonalYouTubeNativeCreationHook.Snapshot().Installed || !PersonalYouTubeServiceReferenceGate.Snapshot().Installed
                || !PersonalYouTubeItemListGate.Snapshot().Installed)
                throw new InvalidOperationException("Personal server controls unavailable.");
            progress("Cleaning", 0, 0);
            await lifecycle.CleanupAsync(snapshot.OwnerUserId, token).ConfigureAwait(false);
            lifecycle.DeleteStaging(snapshot.OwnerUserId, snapshot.CollectionId, snapshot.GenerationId);
            var result = lifecycle.ReadActive(snapshot);
            if(result == null && (!Path.IsPathRooted(configuration.PersonalYouTubeDownloaderPath) || !File.Exists(configuration.PersonalYouTubeDownloaderPath)
                || !Path.IsPathRooted(configuration.PersonalYouTubeFfmpegPath) || !File.Exists(configuration.PersonalYouTubeFfmpegPath)
                || !Path.IsPathRooted(configuration.PersonalYouTubeNodePath) || !File.Exists(configuration.PersonalYouTubeNodePath)))
                throw new PersonalYouTubeJobFailure("MediaToolsUnavailable");
            if(result == null)
            {
                var allowance = budget.DownloadAllowance(configuration.PersonalYouTubeMaxStorageBytes, configuration.PersonalYouTubeMaxCollectionBytes);
                if(configuration.PersonalYouTubeMaxVideos is < 1 or > 10000 || configuration.PersonalYouTubeMaxVideoBytes is < 1024 or > 4294967296
                    || configuration.PersonalYouTubeMaxCollectionBytes < configuration.PersonalYouTubeMaxVideoBytes)
                    throw new PersonalYouTubeJobFailure("InvalidServerSettings");
                var refresh = new PersonalYouTubeInitialRefresh(directory, new PersonalYouTubeCatalog(new(directory), catalogClient),
                    new PersonalYouTubeVideoBuffer(directory, configuration.PersonalYouTubeDownloaderPath, configuration.PersonalYouTubeFfmpegPath, configuration.PersonalYouTubeNodePath),
                    new PersonalYouTubeNativePublisher(directory, library), files) { Progress = progress };
                result = await refresh.RunPreparedAsync(snapshot, configuration.PersonalYouTubeMaxVideos, Math.Min(configuration.PersonalYouTubeMaxVideoBytes, allowance),
                    allowance, null, token).ConfigureAwait(false);
            }
            if(users != null)
            {
                using var lease = PersonalYouTubeTransferLease.Enter(directory, snapshot.OwnerUserId);
                if(!new PersonalYouTubeStore(directory).IsCurrent(snapshot)) throw new OperationCanceledException();
                owner = users.GetUserById(snapshot.OwnerUserId.ToString("N"));
                if(owner == null || owner.Policy.IsDisabled) throw new OperationCanceledException();
                var policy = users.GetUserPolicy(owner);
                if(!policy.EnableAllFolders && !policy.EnabledFolders.Contains(result.Root.ItemId.ToString("N"), StringComparer.OrdinalIgnoreCase))
                {
                    // Keep the existing folder policy and grant only this
                    // account access to its newly published native root.
                    var copy = System.Text.Json.JsonSerializer.Deserialize<MediaBrowser.Model.Users.UserPolicy>(System.Text.Json.JsonSerializer.Serialize(policy))!;
                    copy.EnabledFolders = copy.EnabledFolders.Append(result.Root.ItemId.ToString("N")).ToArray();
                    users.UpdateUserPolicy(owner.InternalId, copy);
                }
            }
            return result;
        }, lifecycle.CleanupAsync, (owner, status) => {
            var active = lifecycle.ReadActive(new PersonalYouTubeStore(directory).Prepare(owner));
            return active != null && active.Root.InternalId == status.LibraryId && active.Videos.Length == status.TotalVideos;
        });
        PersonalYouTubeJobs.Current = jobs;
        try { lifecycle.RepairInterrupted(); jobs.Recover(); }
        catch { jobs.Dispose(); throw; }
        return jobs;
    }
}
