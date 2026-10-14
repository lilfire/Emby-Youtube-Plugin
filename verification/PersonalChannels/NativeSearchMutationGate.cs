using System.Reflection;
using HarmonyLib;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

// Timing only: a marked synthetic A report before native Post can mutate data.
internal static class NativeSearchMutationGate
{
    private static readonly object Gate = new();
    private static readonly ManualResetEventSlim Signal = new(false);
    private static IAuthorizationContext? Authorization;
    private static Guid Owner;
    private static bool Installed, Armed, Active, Reached, TimedOut, AfterCheck;
    internal static object Arm(IUserManager users, IAuthorizationContext authorization, IHttpServer server, string ownerId, bool afterCheck)
    {
        var user = users.GetUserById(ownerId);
        if(user == null || user.Policy.IsAdministrator || user.Name != "native-privacy-fixture-a")
            throw new ArgumentException("Synthetic A mutation timing only");
        lock(Gate)
        {
            if(Armed || Active) throw new InvalidOperationException("Mutation gate already armed");
            if(Installed && AfterCheck != afterCheck) throw new InvalidOperationException("Restart required for mutation timing order");
            if(!Installed)
            {
                var method = server.GetType().Assembly.GetType("Emby.Server.Implementations.Services.ServiceController", true)!
                    .GetMethod("Execute", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic, null,
                        new[] { server.GetType(), typeof(object), typeof(IRequest), typeof(Type) }, null)!;
                new Harmony("isolated-native-search-mutation-timing").Patch(method,
                    prefix: new HarmonyMethod(typeof(NativeSearchMutationGate), nameof(BeforeExecute)) { priority = afterCheck ? 100 : 1000 });
                Installed = true;
            }
            Authorization = authorization; Owner = user.Id; AfterCheck = afterCheck;
            Armed = true; Active = Reached = TimedOut = false; Signal.Reset();
            return Snapshot();
        }
    }
    private static void BeforeExecute(object __1, IRequest __2)
    {
        if(__1.GetType().FullName != "Emby.Api.UserLibrary.ReportItemsSearched"
            || __2.Headers["X-Isolated-Search-Mutation"] != "pause"
            || Authorization!.GetAuthorizationInfo(__2).User?.Id != Owner) return;
        lock(Gate)
        {
            if(!Armed || Reached) return;
            Reached = Active = true;
        }
        var released = Signal.Wait(TimeSpan.FromSeconds(25));
        lock(Gate) { TimedOut = !released; Armed = Active = false; }
    }
    internal static object Release() { lock(Gate) { Signal.Set(); return Snapshot(); } }
    internal static object Snapshot() { lock(Gate) return new { Installed, Armed, Active, Reached, TimedOut, AfterCheck }; }
}
