using System.Text.Json;
using System.Text.RegularExpressions;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;

namespace Emby.YouTubePlugin;

// Deletes only journal-owned generations, after the profile has revoked them.
// The journal and binding tombstones survive physical/native cleanup.
internal sealed class PersonalYouTubeLifecycle
{
    private readonly string _directory;
    private readonly ILibraryManager _library;
    private readonly IUserManager? _users;
    internal PersonalYouTubeLifecycle(string directory, ILibraryManager library, IUserManager? users)
    { _directory = Path.GetFullPath(directory); _library = library; _users = users; }
    internal PersonalYouTubeInitialRefresh.Result? ReadActive(PersonalYouTubeStore.Prepared snapshot)
    {
        using var lease = PersonalYouTubeTransferLease.Enter(_directory, snapshot.OwnerUserId);
        if(!new PersonalYouTubeStore(_directory).IsCurrent(snapshot)) return null;
        var journal = new PersonalYouTubePublicationJournal(_directory);
        var entry = journal.Entries().SingleOrDefault(entry => entry.GenerationId == snapshot.GenerationId);
        if(entry == null || entry.State != "Active" || entry.OwnerUserId != snapshot.OwnerUserId || entry.CollectionId != snapshot.CollectionId
            || entry.CreationRevision != snapshot.Revision || !entry.Root.HasValue) return null;
        var root = _library.GetItemById(entry.Root.Value.InternalId);
        if(root is not CollectionFolder || root.Id != entry.Root.Value.ItemId) return null;
        var media = journal.MediaPath(entry);
        var source = _library.GetVirtualFolders().SingleOrDefault(folder => folder.ItemId == root.InternalId.ToString());
        if(source == null || source.Locations.Length != 1 || Path.GetFullPath(source.Locations[0]) != media) return null;
        ValidateDirectory(media, "media");
        var bindings = new PersonalYouTubeNativeBindings(_directory);
        var videos = _library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { root.InternalId }, Recursive = true }).OfType<Video>().ToArray();
        if(videos.Length == 0) return null;
        foreach(var video in videos)
        {
            var binding = bindings.Find(video.InternalId.ToString());
            if(binding == null || binding.ItemId != video.Id || binding.OwnerUserId != snapshot.OwnerUserId || binding.GenerationId != snapshot.GenerationId
                || Path.GetDirectoryName(Path.GetFullPath(video.Path)) != media || !File.Exists(video.Path)
                || (File.GetAttributes(video.Path) & FileAttributes.ReparsePoint) != 0) return null;
        }
        return new(entry.Root.Value, videos.Select(video => new PersonalYouTubeNativeBindings.NativeItem(video.InternalId, video.Id)).ToArray(), snapshot.Revision);
    }
    internal void RepairInterrupted()
    {
        if(!Directory.Exists(_directory)) return;
        var profiles = new PersonalYouTubeStore(_directory);
        var journal = new PersonalYouTubePublicationJournal(_directory);
        foreach(var path in Directory.EnumerateFiles(_directory, "*.json"))
        {
            if(!Guid.TryParseExact(Path.GetFileNameWithoutExtension(path), "N", out var owner)) continue;
            var view = profiles.Read(owner);
            if(view.State != "Draft" || !view.HasApiKey || view.Channels.Length == 0) continue;
            var entry = journal.Entries().SingleOrDefault(entry => entry.GenerationId == view.GenerationId);
            if(entry == null) continue;
            var snapshot = profiles.Prepare(owner);
            if(entry.State == "Preparing" || ReadActive(snapshot) == null)
                profiles.SaveForRefresh(owner, view.Revision, view.Channels, null, false);
        }
    }
    internal Task CleanupAsync(Guid owner, CancellationToken token)
    {
        using var lease = PersonalYouTubeTransferLease.Enter(_directory, owner);
        var profile = new PersonalYouTubeStore(_directory).Read(owner);
        var journal = new PersonalYouTubePublicationJournal(_directory);
        foreach(var entry in journal.Entries().Where(entry => entry.OwnerUserId == owner && entry.CollectionId == profile.CollectionId
            && (profile.State == "Deleted" || entry.GenerationId != profile.GenerationId)))
        {
            token.ThrowIfCancellationRequested();
            var root = entry.Root.HasValue ? _library.GetItemById(entry.Root.Value.InternalId)
                : entry.ReservedRootId.HasValue ? _library.GetItemById(entry.ReservedRootId.Value) : null;
            var media = journal.MediaPath(entry);
            if(root != null)
            {
                if(root is not CollectionFolder || root.Id != (entry.Root?.ItemId ?? entry.ReservedRootId))
                    throw new InvalidDataException("Retired native identity changed.");
                var source = _library.GetVirtualFolders().Single(folder => folder.ItemId == root.InternalId.ToString());
                var pendingWithoutSource = entry.State == "Preparing" && source.Locations.Length == 0;
                if(!pendingWithoutSource && (source.Locations.Length != 1 || Path.GetFullPath(source.Locations[0]) != media))
                    throw new InvalidDataException("Retired native source changed.");
                _library.RemoveVirtualFolder(root.InternalId, false);
            }
            var rootGuid = entry.Root?.ItemId ?? entry.ReservedRootId;
            var user = _users?.GetUserById(owner.ToString("N"));
            if(user != null && rootGuid.HasValue)
            {
                var policy = _users!.GetUserPolicy(user);
                if(policy.EnabledFolders.Any(id => Guid.TryParse(id, out var parsed) && parsed == rootGuid.Value))
                {
                    var copy = JsonSerializer.Deserialize<MediaBrowser.Model.Users.UserPolicy>(JsonSerializer.Serialize(policy))!;
                    copy.EnabledFolders = copy.EnabledFolders.Where(id => !Guid.TryParse(id, out var parsed) || parsed != rootGuid.Value).ToArray();
                    _users.UpdateUserPolicy(user.InternalId, copy);
                }
            }
            DeleteMedia(media);
            DeleteStaging(owner, entry.CollectionId, entry.GenerationId);
        }
        return Task.CompletedTask;
    }
    private void ValidateDirectory(string path, string kind)
    {
        var expectedBase = Path.GetFullPath(Path.Combine(_directory, kind)) + Path.DirectorySeparatorChar;
        if(!Path.GetFullPath(path).StartsWith(expectedBase, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
            throw new InvalidDataException("Personal cleanup path escaped storage.");
        var current = new DirectoryInfo(path);
        while(current != null && current.FullName != _directory)
        {
            if(current.Exists && (current.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Personal cleanup encountered a link.");
            current = current.Parent;
        }
        if(current == null) throw new InvalidDataException("Personal cleanup root unavailable.");
    }
    private void DeleteMedia(string path)
    {
        ValidateDirectory(path, "media");
        if(!Directory.Exists(path)) return;
        var entries = new DirectoryInfo(path).EnumerateFileSystemInfos().ToArray();
        if(entries.Any(file => file is not FileInfo || (file.Attributes & FileAttributes.ReparsePoint) != 0
            || !Regex.IsMatch(file.Name, @"\A[A-Za-z0-9_-]{11}\.mp4\z")))
            throw new InvalidDataException("Unexpected managed media content.");
        foreach(var file in entries) File.Delete(file.FullName);
        Directory.Delete(path, false);
    }
    internal void DeleteStaging(Guid owner, Guid collection, Guid generation)
    {
        var path = Path.Combine(_directory, "buffer", owner.ToString("N"), collection.ToString("N"), generation.ToString("N"));
        ValidateDirectory(path, "buffer");
        if(!Directory.Exists(path)) return;
        var tasks = new DirectoryInfo(path).EnumerateFileSystemInfos().ToArray();
        foreach(var task in tasks)
        {
            if(task is not DirectoryInfo directory || !Guid.TryParseExact(task.Name, "N", out _) || (task.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Unexpected managed staging directory.");
            var files = directory.EnumerateFileSystemInfos().ToArray();
            if(files.Any(file => file is not FileInfo || (file.Attributes & FileAttributes.ReparsePoint) != 0
                || !Regex.IsMatch(file.Name, @"\A[A-Za-z0-9_-]{11}(?:\.[A-Za-z0-9_-]+)+\z")))
                throw new InvalidDataException("Unexpected managed staging content.");
            foreach(var file in files) File.Delete(file.FullName);
            Directory.Delete(directory.FullName, false);
        }
        Directory.Delete(path, false);
    }
}
