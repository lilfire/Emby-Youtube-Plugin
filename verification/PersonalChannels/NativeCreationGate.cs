using System.Reflection;
using HarmonyLib;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;

namespace PersonalChannelsFixture;

// Timing only: pause after the actual root CreateItem, before library options/paths.
internal static class NativeCreationGate
{
    private static readonly object Gate = new();
    private static readonly ManualResetEventSlim Signal = new(false);
    private static bool Installed, Armed, Reached, Active, TimedOut;
    private static string Name = "";
    private static CollectionFolder? Root;
    private static bool ReserveIdentity;
    internal static object Arm(ILibraryManager library, string name, bool reserveIdentity = false)
    {
        var prefix = name.StartsWith("JournalPending_", StringComparison.Ordinal) ? "JournalPending_" : "YouTube ";
        if (!name.StartsWith(prefix, StringComparison.Ordinal)
            || !Guid.TryParseExact(name.Substring(prefix.Length), "N", out _))
            throw new ArgumentException("Only controlled synthetic roots");
        lock (Gate)
        {
            if (Active || Armed) throw new InvalidOperationException("Creation gate already armed");
            if (!Installed)
            {
                var method = library.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                    .Single(method => method.Name == "CreateItem" && method.GetParameters().Length == 3
                        && method.GetParameters()[0].ParameterType == typeof(BaseItem));
                new Harmony("isolated-native-creation-gate").Patch(method,
                    prefix: new HarmonyMethod(typeof(NativeCreationGate), nameof(BeforeCreate)),
                    postfix: new HarmonyMethod(typeof(NativeCreationGate), nameof(AfterCreate)));
                Installed = true;
            }
            Name = name; Root = null; ReserveIdentity = reserveIdentity; Armed = true; Reached = Active = TimedOut = false; Signal.Reset();
            return Snapshot();
        }
    }
    private static void BeforeCreate(BaseItem __0)
    {
        lock (Gate)
        {
            if (Armed && ReserveIdentity && __0 is CollectionFolder && __0.Name == Name)
                ProductionBindingBridge.ReserveCreatingRoot(Name, __0.Id);
        }
    }
    private static void AfterCreate(BaseItem __0)
    {
        lock (Gate)
        {
            if (!Armed || Reached || __0 is not CollectionFolder folder || folder.Name != Name) return;
            Root = folder; Reached = Active = true;
        }
        var released = Signal.Wait(TimeSpan.FromSeconds(25));
        lock (Gate) { TimedOut = !released; Active = Armed = false; }
    }
    internal static object Release() { lock (Gate) { Signal.Set(); return Snapshot(); } }
    internal static object Snapshot(ILibraryManager? library = null)
    {
        lock (Gate) return new { Installed, Armed, Reached, Active, TimedOut, Name,
            InternalId = Root?.InternalId ?? 0, Guid = Root?.Id.ToString("N") ?? "",
            NativeExists = library != null && Root != null && library.GetItemById(Root.InternalId) != null,
            Locations = library != null && Root != null ? library.GetVirtualFolders()
                .Where(folder => folder.ItemId == Root.InternalId.ToString()).SelectMany(folder => folder.Locations ?? Array.Empty<string>()).ToArray() : Array.Empty<string>() };
    }
}
