using System.Collections.Concurrent;

namespace Emby.YouTubePlugin;

// Serialize publication across owners: staging and native copies share one
// server budget. Other Emby media is never counted or removed here.
internal sealed class PersonalYouTubeStorageBudget : IDisposable
{
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Gates = new(OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
    private readonly string _directory;
    private readonly SemaphoreSlim _gate;
    private PersonalYouTubeStorageBudget(string directory, SemaphoreSlim gate) { _directory = directory; _gate = gate; }
    internal static async Task<PersonalYouTubeStorageBudget> EnterAsync(string directory, CancellationToken token)
    {
        var root = Path.GetFullPath(directory);
        var gate = Gates.GetOrAdd(root, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(token).ConfigureAwait(false);
        return new(root, gate);
    }
    internal long DownloadAllowance(long storageLimit, long collectionLimit)
    {
        if(storageLimit < 2048 || collectionLimit < 1024) throw new PersonalYouTubeJobFailure("InvalidServerSettings");
        long used = 0;
        foreach(var kind in new[] { "media", "buffer" })
            used = checked(used + Size(Path.Combine(_directory, kind)));
        // Every completed staging file can coexist with its native copy until
        // publication returns. Reserve both copies before starting a download.
        var available = storageLimit > used ? (storageLimit - used) / 2 : 0;
        if(available < 1024) throw new PersonalYouTubeJobFailure("StorageBudgetExceeded");
        return Math.Min(collectionLimit, available);
    }
    private static long Size(string path)
    {
        if(!Directory.Exists(path)) return 0;
        if((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new PersonalYouTubeJobFailure("StorageUnavailable");
        long total = 0;
        foreach(var entry in new DirectoryInfo(path).EnumerateFileSystemInfos())
        {
            if((entry.Attributes & FileAttributes.ReparsePoint) != 0) throw new PersonalYouTubeJobFailure("StorageUnavailable");
            total = checked(total + (entry is FileInfo file ? file.Length : Size(entry.FullName)));
        }
        return total;
    }
    public void Dispose() => _gate.Release();
}

internal sealed class PersonalYouTubeJobFailure : IOException
{
    internal string Code { get; }
    internal PersonalYouTubeJobFailure(string code) : base(code) { Code = code; }
}
