using System.Reflection;
using System.Runtime.CompilerServices;
using HarmonyLib;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;

namespace PersonalChannelsFixture;

// Timing only: track the actual completed list writer and pause its native write.
internal static class NativeListWriteGate
{
    private sealed record Subject(Guid Id);
    private static readonly ConditionalWeakTable<object, Subject> Subjects = new();
    private static readonly object Gate = new();
    private static readonly ManualResetEventSlim Signal = new(false);
    private static bool Installed, Armed, Reached, Active, TimedOut, AfterCheck;
    private static Guid Owner;
    internal static object Arm(IUserManager users, string ownerId, bool afterCheck = false)
    {
        var owner = users.GetUserById(ownerId);
        if (owner == null || owner.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator)
            throw new ArgumentException("Only synthetic A write timing");
        lock (Gate)
        {
            if (Active || Armed) throw new InvalidOperationException("Write gate already armed");
            if (Installed && AfterCheck != afterCheck) throw new InvalidOperationException("Restart required to change timing order");
            if (!Installed)
            {
                var production = AppDomain.CurrentDomain.GetAssemblies().Single(value => value.GetName().Name == "Emby.YouTubePlugin");
                var finish = production.GetType("Emby.YouTubePlugin.PersonalYouTubeItemListGate", true)!
                    .GetMethod("Finish", BindingFlags.Static | BindingFlags.NonPublic)!;
                var writer = AppDomain.CurrentDomain.GetAssemblies().Select(value => value.GetType("Emby.Server.Implementations.HttpServer.StreamWriter"))
                    .Single(value => value != null)!;
                var harmony = new Harmony("isolated-native-list-write-timing");
                harmony.Patch(finish, postfix: new HarmonyMethod(typeof(NativeListWriteGate), nameof(AfterFinish)));
                harmony.Patch(writer.GetMethod("WriteToAsync")!, prefix: new HarmonyMethod(typeof(NativeListWriteGate), nameof(BeforeWrite)) { priority = afterCheck ? 100 : 1000 });
                Installed = true;
            }
            AfterCheck = afterCheck; Owner = owner.Id; Armed = true; Reached = Active = TimedOut = false; Signal.Reset();
            return Snapshot();
        }
    }
    private static void AfterFinish(ref Task<object> __result, object __1) => __result = Track(__result, __1);
    private static async Task<object> Track(Task<object> task, object scope)
    {
        var result = await task.ConfigureAwait(false);
        var user = (User)scope.GetType().GetField("User", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(scope)!;
        Subjects.Add(result, new(user.Id));
        return result;
    }
    private static void BeforeWrite(object __instance)
    {
        lock (Gate)
        {
            if (!Armed || Reached || !Subjects.TryGetValue(__instance, out var subject) || subject.Id != Owner) return;
            Active = Reached = true;
        }
        var released = Signal.Wait(TimeSpan.FromSeconds(25));
        lock (Gate) { TimedOut = !released; Armed = Active = false; }
    }
    internal static object Release() { lock (Gate) { Signal.Set(); return Snapshot(); } }
    internal static object Snapshot() { lock (Gate) return new { Installed, Armed, Reached, Active, TimedOut, AfterCheck }; }
}
