using System.Reflection;
using HarmonyLib;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.IO;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

[Route("/PersonalChannelsFixture/DVideoBoundary", "GET,POST")]
[Authenticated(Roles = "Admin")]
public sealed class DVideoBoundaryRequest : IReturn<object>
{
    public long ItemId { get; set; }
    public long ForeignItemId { get; set; }
    public string Phase { get; set; } = "";
    public string Mutation { get; set; } = "";
    public bool Release { get; set; }
}

public sealed partial class FixtureService
{
    public object Get(DVideoBoundaryRequest request) => DVideoBoundary.Snapshot();
    public object Post(DVideoBoundaryRequest request)
    {
        if(request.Release) return DVideoBoundary.Release();
        if(request.Mutation.Length != 0)
        {
            var a = _library.GetItemById(request.ItemId);
            var b = _library.GetItemById(request.ForeignItemId);
            if(a?.Name != "PrivateNativeVideo_a_client" || b?.Name != "PrivateNativeVideo_b_client")
                throw new ArgumentException("Synthetic A/B only");
            if(request.Mutation == "Restore") DVideoBoundary.Restore(a);
            else DVideoBoundary.Mutate(a, b, request.Mutation);
            _library.UpdateItem(a, a.Parent, ItemUpdateType.MetadataEdit);
            var readback = _library.GetItemById(a.InternalId)!;
            return new { PersistedPathIsForeign = readback.Path == b.Path, PersistedParentIsForeign = readback.ParentId == b.ParentId,
                Restored = request.Mutation == "Restore" && DVideoBoundary.IsRestored(readback) };
        }
        var item = _library.GetItemById(request.ItemId);
        if(item?.Name != "PrivateNativeVideo_a_client" || !item.Path.EndsWith("PrivateNativeVideo_a_client.mp4"))
            throw new ArgumentException("Synthetic A only");
        return DVideoBoundary.Arm(_results, item, request.Phase);
    }
}

// Timing instrumentation only. No access decision, factory replacement or
// source adapter. The original production reader and actual native file run.
internal static class DVideoBoundary
{
    private static readonly object Gate = new();
    private static readonly ManualResetEventSlim Signal = new(false);
    private static string Phase = "", OriginalPath = "";
    private static long OriginalParent;
    private static bool Installed, Armed, Reached, Active, TimedOut;
    internal static object Arm(IHttpResultFactory factory, BaseItem item, string phase)
    {
        if(phase is not ("Factory" or "Reader" or "AfterReader")) throw new ArgumentException("Unsupported boundary");
        lock(Gate)
        {
            if(Armed || Active) throw new InvalidOperationException("D boundary already armed");
            if(!Installed)
            {
                var type = factory.GetType();
                var file = type.GetMethod("GetStaticFileResult", new[] { typeof(IRequest), typeof(StaticFileResultOptions) })!;
                var closure = type.GetNestedType("<>c__DisplayClass30_0", BindingFlags.NonPublic)!;
                var reader = closure.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                    .Single(m => m.Name.Contains("b__0") && m.ReturnType == typeof(Task<StreamHandler>));
                var harmony = new Harmony("isolated-D-video-boundary");
                harmony.Patch(file, prefix: new HarmonyMethod(typeof(DVideoBoundary), nameof(BeforeFile)) { priority = 100 });
                harmony.Patch(reader, prefix: new HarmonyMethod(typeof(DVideoBoundary), nameof(BeforeReader)),
                    postfix: new HarmonyMethod(typeof(DVideoBoundary), nameof(AfterReader)));
                Installed = true;
            }
            OriginalPath = item.Path; OriginalParent = item.ParentId; Phase = phase;
            Armed = true; Reached = Active = TimedOut = false; Signal.Reset(); return Snapshot();
        }
    }
    private static bool Matches(object target)
        => (target.GetType().GetField("options", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(target)
            as StaticFileResultOptions)?.Path == OriginalPath;
    private static void BeforeFile(IRequest __0)
    {
        if(Phase == "Factory" && __0.Headers["X-Isolated-D-Boundary"] == "pause") Pause();
    }
    private static void BeforeReader(object __instance)
    {
        if(Phase == "Reader" && Matches(__instance)) Pause();
    }
    private static void AfterReader(object __instance, ref Task<StreamHandler> __result)
    {
        if(Phase == "AfterReader" && Matches(__instance)) __result = AfterOpen(__result);
    }
    private static async Task<StreamHandler> AfterOpen(Task<StreamHandler> original)
    {
        var opened = await original.ConfigureAwait(false); Pause(); return opened;
    }
    private static void Pause()
    {
        lock(Gate) { if(!Armed || Reached) return; Reached = Active = true; }
        var released = Signal.Wait(TimeSpan.FromSeconds(25));
        lock(Gate) { TimedOut = !released; Armed = Active = false; }
    }
    internal static void Mutate(BaseItem a, BaseItem b, string mutation)
    {
        lock(Gate)
        {
            if(!Active) throw new InvalidOperationException("Mutation requires actual paused boundary");
            if(mutation == "Path") a.Path = b.Path;
            else if(mutation == "Parent") a.ParentId = b.ParentId;
            else throw new ArgumentException("Unsupported mutation");
        }
    }
    internal static void Restore(BaseItem a) { lock(Gate) { a.Path = OriginalPath; a.ParentId = OriginalParent; } }
    internal static bool IsRestored(BaseItem a) => a.Path == OriginalPath && a.ParentId == OriginalParent;
    internal static object Release() { lock(Gate) { Signal.Set(); return Snapshot(); } }
    internal static object Snapshot() { lock(Gate) return new { Installed, Armed, Reached, Active, TimedOut, Phase }; }
}
