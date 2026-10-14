using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Configuration;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Providers;
using MediaBrowser.Model.IO;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using NativeItem = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.NativeItem;

namespace Emby.YouTubePlugin;

// Creates the real Emby library in a denied Preparing state. Activation is a
// separate step after media buffering, native indexing and member binding.
internal sealed class PersonalYouTubeNativePublisher
{
    internal sealed record PreparingLibrary(NativeItem Root, string MediaPath);
    private readonly string _directory;
    private readonly ILibraryManager _library;
    internal IReadOnlyDictionary<string, PersonalYouTubeCatalog.Video>? Metadata { get; set; }
    internal PersonalYouTubeNativePublisher(string directory, ILibraryManager library)
    { _directory = Path.GetFullPath(directory); _library = library; }

    internal PreparingLibrary CreatePreparingLibrary(PersonalYouTubeStore.Prepared snapshot, string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 128
            || name.IndexOfAny(new[] { '/', '\\', ':' }) >= 0 || name.Any(char.IsControl))
            throw new ArgumentException("Invalid personal library name.");
        PersonalYouTubeNativeCreationHook.RequireAvailable(_library);
        var profiles = new PersonalYouTubeStore(_directory);
        using var lease = PersonalYouTubeTransferLease.Enter(_directory, snapshot.OwnerUserId);
        // Save/Delete use the same owner lease. Do not hold the profile-store
        // monitor across native callbacks: those callbacks may read profiles
        // on another thread and must not deadlock library creation.
        if (!profiles.IsCurrent(snapshot)) throw new InvalidOperationException("Personal library profile changed.");
        using var creation = new PersonalYouTubeNativeCreation(_directory).Open(snapshot);
        Directory.CreateDirectory(creation.MediaPath);
        var options = new LibraryOptions {
            ContentType = "homevideos", EnableRealtimeMonitor = false, SaveLocalMetadata = false,
            TypeOptions = new[] { new TypeOptions { Type = "Video", MetadataFetchers = Array.Empty<string>(), ImageFetchers = Array.Empty<string>() } },
            PathInfos = new[] { new MediaPathInfo { Path = creation.MediaPath } }
        };
        // Synchronous audited call: the production pre-insert hook reserves
        // the actual root GUID before it becomes externally observable.
        var root = _library.AddVirtualFolder(name, "homevideos", options, false);
        var identity = creation.Complete(new(root.InternalId, root.Id));
        if (!new PersonalYouTubeNativeBindings(_directory).Register(snapshot, new[] { identity }))
            throw new InvalidOperationException("Personal library profile changed.");
        // Do not activate on failure, infer success from a directory, or remove
        // a reservation. Recovery must inspect the real native state.
        return new(identity, creation.MediaPath);
    }

    internal async Task<NativeItem[]> PublishInitialVideosAsync(PersonalYouTubeStore.Prepared snapshot,
        PreparingLibrary preparing, PersonalYouTubeVideoBuffer.BufferedVideo[] videos,
        IFileSystem fileSystem, CancellationToken cancellationToken)
    {
        if (videos.Length == 0 || videos.Select(video => video.VideoId).Distinct().Count() != videos.Length)
            throw new ArgumentException("Distinct buffered videos required.");
        using var lease = PersonalYouTubeTransferLease.Enter(_directory, snapshot.OwnerUserId);
        var profiles = new PersonalYouTubeStore(_directory);
        var journal = new PersonalYouTubePublicationJournal(_directory);
        var bindings = new PersonalYouTubeNativeBindings(_directory);
        if (!profiles.IsCurrent(snapshot)) throw new InvalidOperationException("Personal publication profile changed.");
        var entry = journal.Pending().SingleOrDefault(value => value.GenerationId == snapshot.GenerationId);
        if (entry == null || entry.OwnerUserId != snapshot.OwnerUserId || entry.CollectionId != snapshot.CollectionId
            || entry.ReservedRootId != preparing.Root.ItemId || journal.MediaPath(entry) != preparing.MediaPath)
            throw new InvalidOperationException("Personal preparing library unavailable.");
        var root = _library.GetItemById(preparing.Root.InternalId);
        var binding = bindings.Find(preparing.Root.InternalId.ToString(System.Globalization.CultureInfo.InvariantCulture));
        if (root is not CollectionFolder || root.Id != preparing.Root.ItemId || binding == null
            || binding.OwnerUserId != snapshot.OwnerUserId || binding.GenerationId != snapshot.GenerationId)
            throw new InvalidOperationException("Personal native root binding unavailable.");
        var locations = _library.GetVirtualFolders().Single(folder => folder.ItemId == root.InternalId.ToString()).Locations;
        if (locations.Length != 1 || Path.GetFullPath(locations[0]) != Path.GetFullPath(preparing.MediaPath))
            throw new InvalidOperationException("Personal native root source changed.");
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        var bufferRoot = Path.Combine(_directory, "buffer", snapshot.OwnerUserId.ToString("N"),
            snapshot.CollectionId.ToString("N"), snapshot.GenerationId.ToString("N")) + Path.DirectorySeparatorChar;
        // Validate every file before copying the first one. The root remains
        // Preparing throughout copying and native indexing, including on failure.
        foreach (var video in videos)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (video.OwnerUserId != snapshot.OwnerUserId || video.CollectionId != snapshot.CollectionId
                || video.GenerationId != snapshot.GenerationId || video.Revision != snapshot.Revision
                || !Regex.IsMatch(video.VideoId, @"\A[A-Za-z0-9_-]{11}\z")
                || !Path.GetFullPath(video.Path).StartsWith(bufferRoot, comparison)
                || Path.GetFileName(video.Path) != video.VideoId + ".mp4"
                || !File.Exists(video.Path) || new FileInfo(video.Path).Length != video.Bytes)
                throw new InvalidDataException("Personal buffered source mismatch.");
            using var source = File.OpenRead(video.Path);
            using var hash = SHA256.Create();
            if (Convert.ToHexString(await hash.ComputeHashAsync(source, cancellationToken).ConfigureAwait(false)) != video.SHA256)
                throw new InvalidDataException("Personal buffered source changed.");
        }
        foreach (var video in videos)
        {
            cancellationToken.ThrowIfCancellationRequested();
            File.Copy(video.Path, Path.Combine(preparing.MediaPath, video.VideoId + ".mp4"), overwrite: false);
        }
        // Refresh the new library's location graph, then index that library.
        // Do not combine a whole-server scan with a second folder scan: native
        // background indexing may overlap and create duplicate identities.
        var refresh = new MetadataRefreshOptions(fileSystem) { MetadataRefreshMode = MetadataRefreshMode.FullRefresh };
        await root.RefreshMetadata(refresh, cancellationToken).ConfigureAwait(false);
        await root.ValidateChildren(new Progress<double>(), cancellationToken, refresh, true).ConfigureAwait(false);
        var physical = _library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { root.InternalId }, Recursive = true })
            .OfType<Folder>().Where(folder => !string.IsNullOrEmpty(folder.Path)
                && Path.GetFullPath(folder.Path).Equals(Path.GetFullPath(preparing.MediaPath), comparison)).ToArray();
        foreach (var folder in physical)
            await folder.ValidateChildren(new Progress<double>(), cancellationToken, refresh, true).ConfigureAwait(false);
        var members = _library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { root.InternalId }, Recursive = true })
            .GroupBy(item => item.InternalId).Select(group => group.First()).ToArray();
        var indexed = members.OfType<Video>().ToArray();
        if (indexed.Length != videos.Length || indexed.Any(item => videos.All(video =>
                !Path.GetFullPath(item.Path).Equals(Path.Combine(preparing.MediaPath, video.VideoId + ".mp4"), comparison))))
        {
            var sourceMatches = _library.GetItemList(new InternalItemsQuery { Recursive = true })
                .Where(item => !string.IsNullOrEmpty(item.Path) && Path.GetFullPath(item.Path)
                    .StartsWith(preparing.MediaPath + Path.DirectorySeparatorChar, comparison)).ToArray();
            throw new InvalidDataException($"Personal native media indexing incomplete. Root members={members.Length}; indexed videos={indexed.Length}; source matches={sourceMatches.Length}; types={string.Join(',', sourceMatches.Select(item => item.GetType().Name + ':' + item.InternalId + ':' + item.ParentId + ':' + Path.GetFileName(item.Path)))}.");
        }
        if (members.Any(item => string.IsNullOrEmpty(item.Path)
            || !Path.GetFullPath(item.Path).Equals(preparing.MediaPath, comparison)
                && !Path.GetFullPath(item.Path).StartsWith(preparing.MediaPath + Path.DirectorySeparatorChar, comparison)))
            throw new InvalidDataException("Personal native member source mismatch.");
        // Keep file names and native identities stable. Set presentation
        // metadata only after indexing and before activating the collection.
        if(Metadata != null)
        {
            foreach(var video in indexed)
            {
                var id = Path.GetFileNameWithoutExtension(video.Path);
                if(!Metadata.TryGetValue(id, out var metadata)) throw new InvalidDataException("Personal video metadata missing.");
                video.Name = string.IsNullOrWhiteSpace(metadata.Title) ? id : metadata.Title;
                video.Overview = System.Net.WebUtility.HtmlEncode(metadata.Description);
                _library.UpdateItem(video, video.Parent, ItemUpdateType.MetadataEdit);
            }
            root.Name = "YouTube";
            _library.UpdateItem(root, root.Parent, ItemUpdateType.MetadataEdit);
        }
        var identities = members.Append(root).Select(item => new NativeItem(item.InternalId, item.Id)).Distinct().ToArray();
        if (!bindings.Register(snapshot, identities) || !journal.Activate(snapshot, preparing.Root))
            throw new InvalidOperationException("Personal native publication profile changed.");
        return indexed.Select(item => new NativeItem(item.InternalId, item.Id)).ToArray();
    }
}
