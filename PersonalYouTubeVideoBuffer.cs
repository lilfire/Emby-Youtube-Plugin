using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace Emby.YouTubePlugin;

// Server-internal staging only. A buffered file is not a published native item.
internal sealed class PersonalYouTubeVideoBuffer
{
    internal sealed record BufferedVideo(Guid OwnerUserId, Guid CollectionId, Guid GenerationId,
        long Revision, string VideoId, string Path, long Bytes, string SHA256);
    private readonly string _directory, _downloader, _ffmpeg, _javascript;
    private readonly PersonalYouTubeStore _profiles;
    internal PersonalYouTubeVideoBuffer(string directory, string downloader, string ffmpeg, string javascript)
    {
        _directory = System.IO.Path.GetFullPath(directory);
        _profiles = new(_directory);
        _downloader = System.IO.Path.GetFullPath(downloader);
        _ffmpeg = System.IO.Path.GetFullPath(ffmpeg);
        _javascript = System.IO.Path.GetFullPath(javascript);
    }

    internal async Task<BufferedVideo> DownloadAsync(PersonalYouTubeStore.Prepared snapshot,
        PersonalYouTubeCatalog.Page page, string videoId, long maxBytes, CancellationToken cancellationToken)
    {
        if (maxBytes is < 1024 or > 4L * 1024 * 1024 * 1024) throw new ArgumentOutOfRangeException(nameof(maxBytes));
        if (!_profiles.IsCurrent(snapshot) || page.OwnerUserId != snapshot.OwnerUserId
            || page.CollectionId != snapshot.CollectionId || page.GenerationId != snapshot.GenerationId
            || page.Revision != snapshot.Revision || page.KeyRevision != snapshot.KeyRevision
            || !snapshot.Channels.Contains(page.ChannelId, StringComparer.Ordinal)
            || !Regex.IsMatch(videoId, @"\A[A-Za-z0-9_-]{11}\z") || !page.Videos.Any(video => video.Id == videoId))
            throw new InvalidOperationException("Personal YouTube download source unavailable.");
        foreach (var tool in new[] { _downloader, _ffmpeg, _javascript })
            if (!File.Exists(tool)) throw new InvalidOperationException("Personal YouTube media tools unavailable.");

        var stage = System.IO.Path.Combine(_directory, "buffer", snapshot.OwnerUserId.ToString("N"),
            snapshot.CollectionId.ToString("N"), snapshot.GenerationId.ToString("N"), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(stage);
        var retained = false;
        try
        {
            var start = new ProcessStartInfo(_downloader) {
                UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = stage,
                RedirectStandardOutput = true, RedirectStandardError = true
            };
            if(OperatingSystem.IsLinux())
            {
                // Emby can set its private native-library search path on the
                // server process. Inheriting it crashes unrelated Linux tools
                // (confirmed for yt-dlp, Node and FFmpeg in the Docker image).
                // Configured tool wrappers may establish their own environment.
                start.Environment.Remove("LD_LIBRARY_PATH");
                start.Environment.Remove("LD_PRELOAD");
            }
            // Never inherit downloader config, browser cookies, shared caches,
            // user filenames or API keys. All executable paths are server-owned.
            foreach (var argument in new[] { "--ignore-config", "--no-playlist", "--no-cache-dir", "--no-progress",
                "--js-runtimes", "node:" + _javascript, "--ffmpeg-location", _ffmpeg,
                "--format", "bestvideo[ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/best[ext=mp4]",
                "--merge-output-format", "mp4", "--max-filesize", maxBytes.ToString(System.Globalization.CultureInfo.InvariantCulture),
                "--socket-timeout", "20", "--retries", "1", "--output", System.IO.Path.Combine(stage, videoId + ".%(ext)s"),
                "https://www.youtube.com/watch?v=" + videoId }) start.ArgumentList.Add(argument);
            using var process = Process.Start(start) ?? throw new InvalidOperationException("Personal YouTube downloader unavailable.");
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromMinutes(15));
            var drainOut = DrainAsync(process.StandardOutput);
            var drainError = DrainAsync(process.StandardError);
            var exit = process.WaitForExitAsync();
            try
            {
                while (!exit.IsCompleted)
                {
                    timeout.Token.ThrowIfCancellationRequested();
                    if (!_profiles.IsCurrent(snapshot)) throw new InvalidOperationException("Personal YouTube profile changed during download.");
                    if (Directory.EnumerateFiles(stage).Sum(path => new FileInfo(path).Length) > maxBytes)
                        throw new InvalidDataException("Personal YouTube buffer limit exceeded.");
                    await Task.WhenAny(exit, Task.Delay(250, timeout.Token)).ConfigureAwait(false);
                }
                await exit.ConfigureAwait(false);
                await Task.WhenAll(drainOut, drainError).ConfigureAwait(false);
                if (process.ExitCode != 0) throw new InvalidDataException("Personal YouTube download failed.");
            }
            finally
            {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
                await exit.ConfigureAwait(false);
                await Task.WhenAll(drainOut, drainError).ConfigureAwait(false);
            }
            var path = System.IO.Path.Combine(stage, videoId + ".mp4");
            if (!File.Exists(path) || new FileInfo(path).Length is 0 || new FileInfo(path).Length > maxBytes)
                throw new InvalidDataException("Personal YouTube buffered video unavailable.");
            using var input = File.OpenRead(path);
            using var sha = SHA256.Create();
            var hash = Convert.ToHexString(await sha.ComputeHashAsync(input, cancellationToken).ConfigureAwait(false));
            if (!_profiles.IsCurrent(snapshot)) throw new InvalidOperationException("Personal YouTube profile changed during download.");
            retained = true;
            return new(snapshot.OwnerUserId, snapshot.CollectionId, snapshot.GenerationId, snapshot.Revision,
                videoId, path, input.Length, hash);
        }
        finally
        {
            if (!retained && Directory.Exists(stage))
            {
                // The randomly generated target stays within this owner's staging
                // tree. Reject links before recursively deleting task-owned files.
                if (!System.IO.Path.GetFullPath(stage).StartsWith(_directory + System.IO.Path.DirectorySeparatorChar,
                    OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)
                    || (File.GetAttributes(stage) & FileAttributes.ReparsePoint) != 0
                    || Directory.EnumerateFileSystemEntries(stage, "*", SearchOption.AllDirectories)
                        .Any(path => (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0))
                    throw new InvalidDataException("Unsafe personal YouTube staging cleanup.");
                Directory.Delete(stage, recursive: true);
            }
        }
    }
    private static async Task DrainAsync(StreamReader reader)
    {
        var buffer = new char[2048];
        while (await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false) != 0) { }
    }
    internal void Release(BufferedVideo video)
    {
        var root = System.IO.Path.Combine(_directory, "buffer", video.OwnerUserId.ToString("N"),
            video.CollectionId.ToString("N"), video.GenerationId.ToString("N"));
        var task = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(video.Path))!;
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (!System.IO.Path.GetDirectoryName(task)!.Equals(root, comparison)
            || !Guid.TryParseExact(System.IO.Path.GetFileName(task), "N", out _)
            || System.IO.Path.GetFileName(video.Path) != video.VideoId + ".mp4"
            || (Directory.Exists(task) && (File.GetAttributes(task) & FileAttributes.ReparsePoint) != 0)
            || (File.Exists(video.Path) && (File.GetAttributes(video.Path) & FileAttributes.ReparsePoint) != 0))
            throw new InvalidDataException("Unsafe personal buffered file release.");
        if (File.Exists(video.Path)) File.Delete(video.Path);
        if (Directory.Exists(task) && !Directory.EnumerateFileSystemEntries(task).Any()) Directory.Delete(task);
    }
}
