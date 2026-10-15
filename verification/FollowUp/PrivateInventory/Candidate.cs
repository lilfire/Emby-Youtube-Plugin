using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using Binding = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Binding;
using Entry = Emby.YouTubePlugin.PersonalYouTubePublicationJournal.Entry;

// Experimental only. Never installed in the production list gate. A native
// path-prefix query is not a proof that all canonical private paths were found.
internal static class Candidate
{
    internal static BaseItem[] Collect(ILibraryManager library, Binding[] bindings, Entry[] entries,
        string mediaRoot, bool directParents)
    {
        var found = new Dictionary<long, BaseItem>();
        void Add(BaseItem? item) { if (item != null) found[item.InternalId] = item; }
        // Both permanent aliases are needed even when only one alias was reused.
        foreach (var binding in bindings)
        {
            Add(library.GetItemById(binding.InternalId));
            Add(library.GetItemById(binding.ItemId));
        }
        foreach (var entry in entries)
        {
            if (entry.Root.HasValue) Add(library.GetItemById(entry.Root.Value.InternalId));
            if (entry.ReservedRootId.HasValue) Add(library.GetItemById(entry.ReservedRootId.Value));
        }
        // Queries have no User: discovery must also find invisible private sources.
        foreach (var item in library.GetItemList(new InternalItemsQuery { Recursive = true, Path = mediaRoot })) Add(item);
        foreach (var item in library.GetItemList(new InternalItemsQuery { Recursive = true, PathStartsWith = mediaRoot + Path.DirectorySeparatorChar })) Add(item);
        foreach (var folder in library.GetVirtualFolders())
            if ((folder.Locations ?? Array.Empty<string>()).Any(path => Under(Path.GetFullPath(path), mediaRoot))
                && long.TryParse(folder.ItemId, out var id)) Add(library.GetItemById(id));
        var visited = new HashSet<long>();
        while (true)
        {
            var parents = found.Keys.Where(id => !visited.Contains(id)).ToArray();
            if (parents.Length == 0) break;
            visited.UnionWith(parents);
            foreach (var chunk in parents.Chunk(500))
                foreach (var item in library.GetItemList(directParents
                    ? new InternalItemsQuery { Recursive = false, ParentIds = chunk }
                    : new InternalItemsQuery { Recursive = true, AncestorIds = chunk })) Add(item);
        }
        return found.Values.ToArray();
    }
    private static bool Under(string path, string root)
        => path.Equals(root, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)
            || path.StartsWith(root + Path.DirectorySeparatorChar, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
}
