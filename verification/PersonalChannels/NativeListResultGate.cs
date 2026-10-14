using System.Reflection;
using HarmonyLib;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;

namespace PersonalChannelsFixture;

// Timing only: completed native service task, before production result wrapper.
internal static class NativeListResultGate
{
    private static readonly object Gate = new();
    private static readonly ManualResetEventSlim Signal = new(false);
    private static bool Installed, Armed, Reached, Active, TimedOut, NativeTaskCompleted;
    private static Guid Owner;
    private static string ResultType = "";
    internal static object Arm(IUserManager users, string ownerId)
    {
        var owner = users.GetUserById(ownerId);
        if (owner == null || owner.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator)
            throw new ArgumentException("Only synthetic A result timing");
        lock (Gate)
        {
            if (Active || Armed) throw new InvalidOperationException("Result gate already armed");
            if (!Installed)
            {
                var assembly = AppDomain.CurrentDomain.GetAssemblies().Single(value => value.GetName().Name == "Emby.YouTubePlugin");
                var method = assembly.GetType("Emby.YouTubePlugin.PersonalYouTubeItemListGate", true)!
                    .GetMethod("AfterService", BindingFlags.Static | BindingFlags.NonPublic)!;
                new Harmony("isolated-native-list-result-timing").Patch(method,
                    prefix: new HarmonyMethod(typeof(NativeListResultGate), nameof(BeforeResultWrap)));
                Installed = true;
            }
            Owner = owner.Id; Armed = true; Reached = Active = TimedOut = NativeTaskCompleted = false; ResultType = ""; Signal.Reset();
            return Snapshot();
        }
    }
    private static void BeforeResultWrap(Task<object> __0, object? __1)
    {
        if (__1 == null || !__0.IsCompletedSuccessfully) return;
        var scope = __1.GetType().GetProperty("Created")!.GetValue(__1)!;
        var user = (User)scope.GetType().GetField("User", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(scope)!;
        lock (Gate)
        {
            if (!Armed || Reached || user.Id != Owner) return;
            NativeTaskCompleted = true; ResultType = __0.Result?.GetType().FullName ?? "null";
            Active = Reached = true;
        }
        var released = Signal.Wait(TimeSpan.FromSeconds(25));
        lock (Gate) { TimedOut = !released; Armed = Active = false; }
    }
    internal static object Release() { lock (Gate) { Signal.Set(); return Snapshot(); } }
    internal static object Snapshot() { lock (Gate) return new { Installed, Armed, Reached, Active, TimedOut, NativeTaskCompleted, ResultType }; }
}
