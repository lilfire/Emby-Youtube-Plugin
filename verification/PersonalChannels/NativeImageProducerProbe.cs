using System.Reflection;
using HarmonyLib;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

// Controlled producer-result fault. Only authenticated synthetic A/B,
// actual synthetic native items, and B's observed own native output qualify.
internal static class NativeImageProducerProbe
{
    private sealed record Context(Context? Previous, bool Inject, int Generation);
    private static readonly AsyncLocal<Context?> Current = new();
    private static readonly object Gate = new();
    private static IAuthorizationContext? Authorization;
    private static Guid Owner, ForeignOwner;
    private static long Item, ForeignItem;
    private static string Input = "", ForeignInput = "";
    private static Tuple<string, string, DateTimeOffset>? ForeignOutput;
    private static bool Installed, CachePathFault;
    private static int Generation, Controls, Injected;
    private static string IncomingTaskContract = "";
    internal static object Arm(IUserManager users, ILibraryManager library, IAuthorizationContext authorization,
        IHttpServer server, string ownerId, string foreignOwnerId, long itemId, long foreignItemId, bool cachePathFault)
    {
        var owner = users.GetUserById(ownerId); var foreignOwner = users.GetUserById(foreignOwnerId);
        if (owner?.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator
            || foreignOwner?.Name != "native-privacy-fixture-b" || foreignOwner.Policy.IsAdministrator)
            throw new ArgumentException("Ordinary synthetic A/B only");
        string Source(long id, string actor)
        {
            var item = library.GetItemById(id);
            if (item == null || !item.Path.EndsWith(Path.DirectorySeparatorChar + "PrivateNativeVideo_" + actor + "_client.mp4", StringComparison.OrdinalIgnoreCase)
                || !library.GetCollectionFolders(item).Any(root => root.Name == "Private Native Fixture " + actor))
                throw new ArgumentException("Actual synthetic native item only");
            return item.GetImageInfo(ImageType.Primary, 0)?.Path ?? throw new ArgumentException("No synthetic primary image");
        }
        var input = Source(itemId, "a"); var foreignInput = Source(foreignItemId, "b");
        lock (Gate)
        {
            if (!Installed)
            {
                var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
                var service = server.GetType().Assembly.GetType("Emby.Server.Implementations.Services.ServiceController", true)!
                    .GetMethod("Execute", flags, null, new[] { server.GetType(), typeof(object), typeof(IRequest), typeof(Type) }, null)!;
                var processor = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Drawing.ImageProcessor")).Single(type => type != null)!;
                var process = processor.GetMethod("ProcessImage", new[] { typeof(ImageProcessingOptions), typeof(CancellationToken) })!;
                if (service.ReturnType != typeof(Task<object>) || process.ReturnType != typeof(Task<Tuple<string, string, DateTimeOffset>>))
                    throw new InvalidOperationException("Unsupported synthetic producer probe contract");
                var harmony = new Harmony("isolated-native-image-producer-probe");
                harmony.Patch(service,
                    prefix: new HarmonyMethod(typeof(NativeImageProducerProbe), nameof(BeforeService)) { priority = 1000 },
                    postfix: new HarmonyMethod(typeof(NativeImageProducerProbe), nameof(AfterService)) { priority = 1000 },
                    finalizer: new HarmonyMethod(typeof(NativeImageProducerProbe), nameof(ServiceFinally)) { priority = 1000 });
                // Explicit owner ordering is required: production must receive
                // the controlled task, rather than a later replacement of its
                // already-validated result. Numeric priority alone is insufficient.
                harmony.Patch(process, postfix: new HarmonyMethod(typeof(NativeImageProducerProbe), nameof(AfterImage))
                    { priority = 1000, before = new[] { "emby.youtubeplugin.personal-asset-source" } });
                var cache = processor.GetMethod("GetCacheFilePath", flags)!;
                harmony.Patch(cache, postfix: new HarmonyMethod(typeof(NativeImageProducerProbe), nameof(AfterImageCache))
                    { priority = 1000, before = new[] { "emby.youtubeplugin.personal-asset-source" } });
                Installed = true;
            }
            Authorization = authorization; Owner = owner.Id; ForeignOwner = foreignOwner.Id;
            Item = itemId; ForeignItem = foreignItemId; Input = input; ForeignInput = foreignInput;
            CachePathFault = cachePathFault;
            ForeignOutput = null; Controls = Injected = 0; IncomingTaskContract = ""; Generation++;
            return Snapshot();
        }
    }
    private static void BeforeService(object __1, IRequest __2, out object? __state)
    {
        __state = null;
        if (__1.GetType().FullName != "Emby.Api.Images.GetItemImage") return;
        var marker = __2.Headers["X-Isolated-Image-Producer"];
        if (marker is not ("producer-control" or "producer-inject")) return;
        var user = Authorization?.GetAuthorizationInfo(__2).User;
        if (!long.TryParse(__1.GetType().GetProperty("Id")?.GetValue(__1) as string, out var id)) return;
        lock (Gate)
        {
            var inject = marker == "producer-inject";
            if (user?.Id != (inject ? Owner : ForeignOwner) || id != (inject ? Item : ForeignItem)) return;
            var context = new Context(Current.Value, inject, Generation); Current.Value = context; __state = context;
        }
    }
    private static void Restore(object? state)
    { if (state is Context context && ReferenceEquals(Current.Value, context)) Current.Value = context.Previous; }
    private static void AfterService(object? __state) => Restore(__state);
    private static void ServiceFinally(object? __state) => Restore(__state);
    private static void AfterImage(ImageProcessingOptions __0, ref Task<Tuple<string, string, DateTimeOffset>> __result)
    {
        var context = Current.Value; if (context == null) return;
        lock (Gate)
        {
            if (context.Generation != Generation || (__0.Item?.InternalId ?? __0.ItemId) != (context.Inject ? Item : ForeignItem)
                || __0.ImageIndex != 0 || __0.Image?.Type != ImageType.Primary
                || __0.Image.Path != (context.Inject ? Input : ForeignInput)) return;
            if(context.Inject) IncomingTaskContract = __result.GetType().FullName ?? "";
            if(context.Inject && CachePathFault) return;
        }
        __result = Track(__result, context);
    }
    private static void AfterImageCache(string __0, ref string __result)
    {
        var context = Current.Value;
        lock(Gate)
        {
            if(context == null || !context.Inject || context.Generation != Generation || !CachePathFault || __0 != Input) return;
            if(Injected != 0 || ForeignOutput == null) throw new InvalidOperationException("One captured synthetic cache output required");
            Injected++; __result = ForeignOutput.Item1;
        }
    }
    private static async Task<Tuple<string, string, DateTimeOffset>> Track(Task<Tuple<string, string, DateTimeOffset>> task, Context context)
    {
        var result = await task.ConfigureAwait(false);
        lock (Gate)
        {
            if (context.Generation != Generation) return result;
            if (!context.Inject)
            {
                if (!File.Exists(result.Item1) || result.Item1 == ForeignInput) throw new InvalidOperationException("Derived native B output required");
                ForeignOutput = result; Controls++; return result;
            }
            if (Injected != 0 || ForeignOutput == null) throw new InvalidOperationException("One captured synthetic producer output required");
            Injected++; return ForeignOutput;
        }
    }
    internal static object Snapshot()
    { lock (Gate) return new { Installed, Controls, Injected, CachePathFault, DerivedForeignOutputCaptured = ForeignOutput != null,
        ProductionWrappedBeforeProbe = IncomingTaskContract.Contains("PersonalYouTubeAssetSourceGate", StringComparison.Ordinal), IncomingTaskContract }; }
}
