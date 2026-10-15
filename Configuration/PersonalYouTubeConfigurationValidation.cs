using System;
using System.IO;

namespace Emby.YouTubePlugin;

internal static class PersonalYouTubeConfigurationValidation
{
    internal static void Validate(bool enabled, string downloader, string ffmpeg, string node,
        int videos, long videoBytes, long collectionBytes, long storageBytes)
    {
        foreach (var path in new[] { downloader, ffmpeg, node })
        {
            if (string.IsNullOrWhiteSpace(path) && !enabled) continue;
            if (string.IsNullOrWhiteSpace(path) || path.IndexOfAny(new[] { '\r', '\n', '\0' }) >= 0
                || !Path.IsPathFullyQualified(path) || !File.Exists(path))
                throw new ArgumentException("Personal YouTube tools require absolute paths to existing files on the server.");
        }
        const long maximumBudget = 1048576L * 1048576;
        if (videos is < 1 or > 10000 || videoBytes is < 1048576 or > 4294967296L
            || collectionBytes < videoBytes || collectionBytes > maximumBudget
            || storageBytes < 2097152 || storageBytes < collectionBytes || storageBytes > maximumBudget)
            throw new ArgumentException("Invalid personal YouTube limits: video <= collection <= combined storage budget.");
    }
}
