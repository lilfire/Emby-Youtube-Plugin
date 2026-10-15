using System.Reflection;
using HarmonyLib;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

[Route("/PersonalChannelsFixture/NativeSourceInventoryAudit", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class NativeSourceInventoryAudit : IReturn<object>
{
    public long ItemKey { get; set; }
    public bool Fault { get; set; }
    public bool Reader { get; set; }
    public long OptionsRootKey { get; set; }
}

public sealed partial class FixtureService
{
    public object Post(NativeSourceInventoryAudit request)
    {
        var item = _library.GetItemById(request.ItemKey);
        if (item?.Name != "PrivateNativeVideo_a_client" || string.IsNullOrEmpty(item.Path)
            || !item.Path.Contains(Path.Combine("verification", "PersonalChannels", "bin", "native-client", "a") + Path.DirectorySeparatorChar))
            throw new ArgumentException("Only the isolated synthetic A video is permitted.");
        var repository = _library.GetType().GetProperty("ItemRepository")!.GetValue(_library)!;
        if (request.OptionsRootKey > 0)
        {
            if (!_library.GetCollectionFolders(item).Any(folder => folder.InternalId == request.OptionsRootKey)
                || _library.GetItemById(request.OptionsRootKey) is not CollectionFolder root)
                throw new ArgumentException("Only the synthetic video's actual collection root is permitted.");
            return SourceInventoryAudit.RunOptions(root);
        }
        return request.Reader ? SourceInventoryAudit.RunReader(repository, item) : SourceInventoryAudit.Run(repository, item, request.Fault);
    }
}

internal static class SourceInventoryAudit
{
    [ThreadStatic] private static bool Armed, Fault;
    [ThreadStatic] private static object? Observed;
    private static readonly object Gate = new();
    private static bool Installed;
    private static object State() => AppDomain.CurrentDomain.GetAssemblies().Single(assembly => assembly.GetName().Name == "Emby.YouTubePlugin")
        .GetType("Emby.YouTubePlugin.PersonalYouTubeNativeSourceBarrier", true)!
        .GetMethod("Snapshot", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, null)!;
    private static void Observe()
    {
        if (!Armed) return;
        Observed = State();
        if (Fault) throw new IOException("Isolated repository boundary fault");
    }
    internal static object Run(object repository, BaseItem item, bool fault)
    {
        var save = repository.GetType().GetMethod("SaveItems", new[] { typeof(List<BaseItem>), typeof(CancellationToken) })!;
        lock (Gate)
        {
            if (!Installed)
            {
                new Harmony("isolated-source-inventory-audit").Patch(save,
                    prefix: new HarmonyMethod(typeof(SourceInventoryAudit), nameof(Observe)) { priority = 700 });
                Installed = true;
            }
        }
        var before = State(); Armed = true; Fault = fault; Observed = null;
        var threw = false;
        try { save.Invoke(repository, new object[] { new List<BaseItem> { item }, CancellationToken.None }); }
        catch (TargetInvocationException error) when (fault && error.InnerException is IOException) { threw = true; }
        finally { Armed = false; }
        return new { Before = before, During = Observed, After = State(), ExpectedFault = fault, Threw = threw };
    }
    internal static object RunReader(object repository, BaseItem item)
    {
        var before = State();
        var version = (long)before.GetType().GetProperty("Version")!.GetValue(before)!;
        var type = before.GetType().DeclaringType!;
        var reader = (IDisposable)type.GetMethod("EnterRead", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, new object[] { version })!;
        Task<object>? pending = null;
        object? waiting = null;
        var transactionRejected = false;
        try
        {
            try { type.GetMethod("Begin", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, new object[] { false }); }
            catch (TargetInvocationException error) when (error.InnerException is IOException) { transactionRejected = true; }
            if (!transactionRejected) throw new InvalidOperationException("Transaction-held mutation waited for its own reader.");
            // This writer represents another native operation, not work spawned
            // by the reader's serialization callback; suppress that context.
            using (ExecutionContext.SuppressFlow()) pending = Task.Run(() => Run(repository, item, false));
            var deadline = DateTime.UtcNow.AddSeconds(5);
            do
            {
                waiting = State();
                if ((int)waiting.GetType().GetProperty("Waiting")!.GetValue(waiting)! > 0) break;
                Thread.Sleep(10);
            } while (DateTime.UtcNow < deadline && !pending.IsCompleted);
            if (pending.IsCompleted || waiting == null || (int)waiting.GetType().GetProperty("Waiting")!.GetValue(waiting)! == 0)
                throw new InvalidOperationException("Native writer did not wait for the production reader lease.");
        }
        finally { reader.Dispose(); }
        var completed = pending!.GetAwaiter().GetResult();
        return new { Before = before, Waiting = waiting, Completed = completed, After = State(), TransactionWriteRejected = transactionRejected };
    }
    internal static object RunOptions(CollectionFolder root)
    {
        var options = root.GetType().GetMethod("GetLibraryOptions", Type.EmptyTypes)!.Invoke(root, null)!;
        var before = State();
        root.GetType().GetMethod("UpdateLibraryOptions", new[] { options.GetType() })!.Invoke(root, new[] { options });
        return new { Before = before, After = State() };
    }
}
