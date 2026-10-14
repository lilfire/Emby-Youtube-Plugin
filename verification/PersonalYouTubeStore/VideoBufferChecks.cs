using Emby.YouTubePlugin;

internal static class VideoBufferChecks
{
    internal static async Task Run(string root, Action<string, bool> check)
    {
        var repo = Path.GetFullPath(".");
        var tools = Path.Combine(repo, "verification/PersonalChannels/bin/media-tools");
        var downloader = Path.Combine(tools, "yt-dlp.exe");
        var ffmpeg = Path.Combine(repo, "verification/WatchState/bin/emby-isolated/server/system/ffmpeg.exe");
        var javascript = "C:/Program Files/nodejs/node.exe";
        var store = new PersonalYouTubeStore(root);
        var a = Guid.NewGuid(); var b = Guid.NewGuid(); var channel = "UC" + new string('a', 22);
        store.Save(a, 0, new[] { channel }, "synthetic-a", false);
        store.Save(b, 0, new[] { channel }, "synthetic-b", false);
        var snapshot = store.Prepare(a);
        // Controlled catalog input; this test makes a real media download but
        // does not claim a real Data API call or automatic native publication.
        var page = new PersonalYouTubeCatalog.Page(a, snapshot.CollectionId, snapshot.GenerationId,
            snapshot.Revision, snapshot.KeyRevision, channel,
            new[] { new PersonalYouTubeCatalog.Video("DTi8wZ1a1TA", "Public upstream test video", "") }, null);
        var buffer = new PersonalYouTubeVideoBuffer(root, downloader, ffmpeg, javascript);
        await Reject<InvalidOperationException>(() => buffer.DownloadAsync(store.Prepare(b), page, "DTi8wZ1a1TA", 64 * 1024 * 1024, CancellationToken.None));
        check("Buffer rejects another owner's catalog before staging or process start", !Directory.Exists(Path.Combine(root, "buffer")));
        var result = await buffer.DownloadAsync(snapshot, page, "DTi8wZ1a1TA", 64 * 1024 * 1024, CancellationToken.None);
        check("Production buffer downloads a real MP4 under A's generation", File.Exists(result.Path)
            && result.Path.StartsWith(Path.Combine(root, "buffer", a.ToString("N"), snapshot.CollectionId.ToString("N"), snapshot.GenerationId.ToString("N")) + Path.DirectorySeparatorChar)
            && result.OwnerUserId == a && result.Bytes > 1000 && result.SHA256.Length == 64);
        check("Buffer never includes B's identity or key in its output", !result.Path.Contains(b.ToString("N"))
            && !System.Text.Json.JsonSerializer.Serialize(result).Contains("synthetic"));
        using var cancel = new CancellationTokenSource();
        var pending = buffer.DownloadAsync(snapshot, page, "DTi8wZ1a1TA", 64 * 1024 * 1024, cancel.Token);
        var generationRoot = Path.GetDirectoryName(Path.GetDirectoryName(result.Path)!)!;
        check("Cancellation targets a started staging task", !pending.IsCompleted && Directory.GetDirectories(generationRoot).Length == 2);
        cancel.Cancel();
        await Reject<OperationCanceledException>(() => pending);
        check("Canceled buffer retains only the already successful file", Directory.GetFiles(Path.GetDirectoryName(result.Path)!).Length == 1);
        check("Canceled task staging is cleaned after its process terminates", Directory.GetDirectories(generationRoot).Length == 1);
        var revoked = buffer.DownloadAsync(snapshot, page, "DTi8wZ1a1TA", 64 * 1024 * 1024, CancellationToken.None);
        check("Profile revocation targets a started download", !revoked.IsCompleted && Directory.GetDirectories(generationRoot).Length == 2);
        var view = store.Read(a); store.Delete(a, view.Revision);
        await Reject<InvalidOperationException>(() => revoked);
        check("Profile deletion terminates the download and cleans its task", Directory.GetDirectories(generationRoot).Length == 1);
        check("Revoking A preserves B's profile and key", store.Prepare(b).ApiKey == "synthetic-b");
        await Reject<InvalidOperationException>(() => buffer.DownloadAsync(snapshot, page, "DTi8wZ1a1TA", 64 * 1024 * 1024, CancellationToken.None));
        check("Deleted profile cannot start another buffer download", Directory.GetDirectories(generationRoot).Length == 1);
    }
    private static async Task Reject<T>(Func<Task<PersonalYouTubeVideoBuffer.BufferedVideo>> action) where T : Exception
    { try { await action(); } catch (T) { return; } throw new Exception("Expected " + typeof(T).Name); }
}
