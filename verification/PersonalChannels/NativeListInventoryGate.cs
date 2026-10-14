using System.Reflection;
using HarmonyLib;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

// Timing only: holds the completed production list inventory before native Execute.
internal static class NativeListInventoryGate
{
    private static readonly object Gate = new();
    private static readonly ManualResetEventSlim Signal = new(false);
    private static bool Installed, Armed, Reached, Active, TimedOut;
    private static Guid Owner;
    internal static object Arm(IUserManager users, string ownerId)
    {
        var owner = users.GetUserById(ownerId);
        if (owner == null || owner.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator)
            throw new ArgumentException("Only controlled synthetic A");
        lock (Gate)
        {
            if (Active || Armed) throw new InvalidOperationException("List gate already armed");
            if (!Installed)
            {
                var production = AppDomain.CurrentDomain.GetAssemblies().Single(assembly => assembly.GetName().Name == "Emby.YouTubePlugin");
                var method = production.GetType("Emby.YouTubePlugin.PersonalYouTubeItemListGate", true)!
                    .GetMethod("BeforeService", BindingFlags.Static | BindingFlags.NonPublic)!;
                new Harmony("isolated-list-inventory-timing").Patch(method,
                    postfix: new HarmonyMethod(typeof(NativeListInventoryGate), nameof(AfterInventory)));
                Installed = true;
            }
            Owner = owner.Id; Armed = true; Reached = Active = TimedOut = false; Signal.Reset();
            return Snapshot();
        }
    }
    private static void AfterInventory(object __0, IRequest __1, bool __result)
    {
        lock (Gate)
        {
            if (!Armed || Reached || !__result || __0.GetType().FullName != "Emby.Api.UserLibrary.GetItems"
                || __1.Headers["X-Isolated-List-Gate"] != "after-inventory"
                || (__0.GetType().GetProperty("UserId")!.GetValue(__0) is not Guid id || id != Owner)) return;
            Reached = Active = true;
        }
        var released = Signal.Wait(TimeSpan.FromSeconds(25));
        lock (Gate) { TimedOut = !released; Armed = Active = false; }
    }
    internal static object Release() { lock (Gate) { Signal.Set(); return Snapshot(); } }
    internal static object Snapshot() { lock (Gate) return new { Installed, Armed, Reached, Active, TimedOut }; }
}
