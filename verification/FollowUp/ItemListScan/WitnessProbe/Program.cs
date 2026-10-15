using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using Emby.YouTubePlugin;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;

// Calls the production list resolver with a native-library adapter. These
// checks exercise hint invalidation/fallback, not native SQL or HTTP access.
var directory = Directory.CreateTempSubdirectory("metadata-witness-probe-").FullName;
var assembly = typeof(Plugin).Assembly;
var flags = BindingFlags.Instance | BindingFlags.NonPublic;
var observations = new List<object>();
try
{
    var library = DispatchProxy.Create<ILibraryManager, LibraryAdapter>();
    var accessType = assembly.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeAccess", true)!;
    var access = Activator.CreateInstance(accessType, flags, null, new object[] { directory, library }, null)!;
    var user = new User { Id = Guid.NewGuid(), InternalId = 99 };
    user.Policy = new();
    var tag = new Tag { Id = Guid.NewGuid(), InternalId = 10 };
    var source = new Video { Id = Guid.NewGuid(), InternalId = 20, Path = Path.Combine(directory, "public.mp4") };
    var alternate = new Video { Id = Guid.NewGuid(), InternalId = 21, Path = Path.Combine(directory, "alternate.mp4") };
    LibraryAdapter.Items = new[] { source, alternate }.ToDictionary(item => item.InternalId, item => (BaseItem)item);

    (HashSet<long> Denied, Dictionary<long, long> Witnesses) Run(string name, long[] hints, long[] visible, long[] linked, bool expectedDenied, int expectedQueries)
    {
        LibraryAdapter.Visible = visible; LibraryAdapter.Linked = linked; LibraryAdapter.Queries = 0;
        var context = accessType.GetMethod("CreateListContext", flags, null, new[] { typeof(User), typeof(IReadOnlyDictionary<long, BaseItem>) }, null)!.Invoke(access, new object[] { user, new Dictionary<long, BaseItem>() })!;
        var witnesses = new Dictionary<long, long>();
        var denied = (HashSet<long>)context.GetType().GetMethod("DeniedMetadata", flags)!.Invoke(context,
            new object[] { new BaseItem[] { tag }, CancellationToken.None, witnesses, hints })!;
        var pass = denied.Contains(10) == expectedDenied && LibraryAdapter.Queries == expectedQueries;
        observations.Add(new { Name = name, Pass = pass, Queries = LibraryAdapter.Queries });
        if (!pass) throw new InvalidOperationException(name);
        return (denied, witnesses);
    }
    var initial = Run("Initial source search records a witness", Array.Empty<long>(), new long[] { 20, 21 }, new long[] { 20, 21 }, false, 1);
    if (initial.Witnesses[10] != 20) throw new InvalidOperationException("Witness mismatch");
    Run("Fresh valid witness avoids the full source search", new long[] { 20 }, new long[] { 20, 21 }, new long[] { 20, 21 }, false, 1);
    Run("Invisible witness falls back to another visible source", new long[] { 20 }, new long[] { 21 }, new long[] { 20, 21 }, false, 2);
    Run("Changed native link falls back to another source", new long[] { 20 }, new long[] { 20, 21 }, new long[] { 21 }, false, 2);
    Run("Old witness cannot authorize a tag without a current source", new long[] { 20 }, new long[] { 20 }, Array.Empty<long>(), true, 2);
    source.ParentId = 404;
    Run("Changed parent denies a stale witness", new long[] { 20 }, new long[] { 20 }, new long[] { 20 }, true, 2);
    source.ParentId = 0;
    user.Policy.IsDisabled = true;
    Run("Disabled account cannot use a stored witness", new long[] { 20 }, new long[] { 20 }, new long[] { 20 }, true, 0);
}
finally { Directory.Delete(directory, true); }
Console.WriteLine(JsonSerializer.Serialize(new {
    ProductionDLLSHA256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(assembly.Location))),
    Observations = observations,
    Limit = "Production resolver with a library adapter and public sources; native private ownership and writer races require the separate Emby matrices. Temporary directory removed."
}, new JsonSerializerOptions { WriteIndented = true }));

public class LibraryAdapter : DispatchProxy
{
    public static Dictionary<long, BaseItem> Items = new();
    public static long[] Visible = Array.Empty<long>(), Linked = Array.Empty<long>();
    public static int Queries;
    protected override object? Invoke(MethodInfo? method, object?[]? args)
    {
        switch (method!.Name)
        {
            case "GetVirtualFolders": return new List<VirtualFolderInfo>();
            case "GetReadDataContext": return null;
            case "GetCollectionFolders": return Array.Empty<Folder>();
            case "GetItemById": return Items.GetValueOrDefault((long)args![0]!);
            case "GetInternalItemIds":
                Queries++;
                var query = (InternalItemsQuery)args![0]!;
                return Visible.Where(id => query.ItemIds?.Length > 0 ? query.ItemIds.Contains(id) : true).ToArray();
            case "GetItemLinks": return Linked.Contains((long)args![0]!)
                ? new List<(ItemLinkType, string, long)> { (ItemLinkType.Tags, "tag", 10) }
                : new List<(ItemLinkType, string, long)>();
            default: throw new NotSupportedException(method.Name);
        }
    }
}
