using System.Reflection;
using System.Runtime.CompilerServices;
using HarmonyLib;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

// Timing only, an explicitly selected synthetic A service result at native write entry.
internal static class NativeReferenceWriteGate
{
    private sealed record Subject(Guid Owner);
    private static readonly ConditionalWeakTable<object, Subject> Writers = new();
    private static readonly object Gate = new();
    private static readonly ManualResetEventSlim Signal = new(false);
    private static IAuthorizationContext? Authorization;
    private static Guid Owner;
    private static string Dto = "Emby.Api.UserLibrary.GetItem";
    private static string ResultContract = "";
    private static bool Installed, Armed, Reached, Active, TimedOut, AfterCheck;
    internal static object Arm(IUserManager users, IAuthorizationContext authorization, string ownerId, IHttpServer server, bool playback = false, bool download = false, bool video = false, string asset = "", bool afterCheck = false)
    {
        if (asset is not ("" or "Image" or "Subtitle" or "MetadataImage")) throw new ArgumentException("Unsupported synthetic asset timing target");
        var owner = users.GetUserById(ownerId);
        if (owner == null || owner.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator)
            throw new ArgumentException("Synthetic A only");
        lock (Gate)
        {
            if (Armed || Active) throw new InvalidOperationException("Reference gate already armed");
            if (Installed && AfterCheck != afterCheck) throw new InvalidOperationException("Restart required to change reference timing order");
            if (!Installed)
            {
                var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
                var service = server.GetType().Assembly.GetType("Emby.Server.Implementations.Services.ServiceController", true)!
                    .GetMethod("Execute", flags, null, new[] { server.GetType(), typeof(object), typeof(IRequest), typeof(Type) }, null)!;
                var harmony = new Harmony("isolated-native-reference-write-timing");
                harmony.Patch(service, postfix: new HarmonyMethod(typeof(NativeReferenceWriteGate), nameof(AfterService)));
                foreach(var type in server.GetType().Assembly.GetTypes().Where(type => !type.IsAbstract && typeof(IAsyncStreamWriter).IsAssignableFrom(type)))
                foreach(var write in type.GetMethods(flags).Where(method => method.Name.EndsWith("WriteToAsync", StringComparison.Ordinal)
                    && method.ReturnType == typeof(Task) && method.GetParameters().Select(parameter => parameter.ParameterType).SequenceEqual(new[] { typeof(IResponse), typeof(CancellationToken) })))
                    harmony.Patch(write, prefix: new HarmonyMethod(typeof(NativeReferenceWriteGate), nameof(BeforeWrite)) { priority = afterCheck ? 100 : 1000 });
                Installed = true;
            }
            AfterCheck = afterCheck;
            Dto = asset == "MetadataImage" ? "Emby.Api.Images.GetItemByNameImage" : asset == "Image" ? "Emby.Api.Images.GetItemImage" : asset == "Subtitle" ? "Emby.Api.Subtitles.GetSubtitle"
                : video ? "Emby.Server.MediaEncoding.Api.Progressive.GetVideoStream" : download ? "Emby.Api.Library.GetDownload" : playback ? "Emby.Server.MediaEncoding.Api.GetPlaybackInfo" : "Emby.Api.UserLibrary.GetItem";
            ResultContract = ""; Authorization = authorization; Owner = owner.Id; Armed = true; Reached = Active = TimedOut = false; Signal.Reset();
            return Snapshot();
        }
    }
    private static void AfterService(object __1, IRequest __2, ref Task<object> __result)
    {
        if (__1.GetType().FullName != Dto || __2.Headers["X-Isolated-Reference-Gate"] != "before-write") return;
        var user = Authorization!.GetAuthorizationInfo(__2).User;
        if (user?.Id != Owner) return;
        __result = Track(__result, user.Id);
    }
    private static async Task<object> Track(Task<object> task, Guid owner)
    {
        var result = await task.ConfigureAwait(false);
        lock (Gate) ResultContract = result.GetType().FullName ?? "";
        Writers.Add(result, new(owner));
        return result;
    }
    private static void BeforeWrite(object __instance)
    {
        lock (Gate)
        {
            if (!Armed || Reached || !Writers.TryGetValue(__instance, out var subject) || subject.Owner != Owner) return;
            Reached = Active = true;
        }
        var released = Signal.Wait(TimeSpan.FromSeconds(25));
        lock (Gate) { TimedOut = !released; Armed = Active = false; }
    }
    internal static object Release() { lock (Gate) { Signal.Set(); return Snapshot(); } }
    internal static object Snapshot() { lock (Gate) return new { Installed, Armed, Reached, Active, TimedOut, ResultContract, AfterCheck }; }
}
