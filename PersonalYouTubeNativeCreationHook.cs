using System.Reflection;
using System.Security.Cryptography;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Configuration;

namespace Emby.YouTubePlugin;

// Creation-only guard for the audited synchronous native implementation.
// This does not install the separate universal access boundary.
internal static class PersonalYouTubeNativeCreationHook
{
    private const string Owner = "emby.youtubeplugin.personal-native-creation";
    private static readonly object Gate = new();
    private static MethodInfo? _native;
    private static Type? _harmonyType;
    internal sealed record State(bool ContractMatched, bool Installed, string RuntimeType, string Error);
    private static State _state = new(false, false, "", "NotInitialized");
    internal static State Snapshot()
    {
        lock (Gate)
        {
            if (_state.Installed)
            {
                try { if (!HasOwnPrefix()) return _state with { Installed = false, Error = "PatchLost" }; }
                catch (Exception) { return _state with { Installed = false, Error = "PatchVerificationFailed" }; }
            }
            return _state;
        }
    }
    private static bool HasBody(MethodInfo method, string expected) => method.GetMethodBody()?.GetILAsByteArray() is byte[] bytes
        && Convert.ToHexString(SHA256.HashData(bytes)) == expected;
    internal static State Install(ILibraryManager library)
    {
        lock (Gate)
        {
            var type = library.GetType();
            if (_state.Installed)
            {
                RequireAvailable(library);
                return _state;
            }
            _state = new(false, false, type.FullName ?? "", "UnsupportedNativeContract");
            var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
            var add = type.GetMethod("AddVirtualFolder", flags, null, new[] { typeof(string), typeof(LibraryOptions), typeof(bool) }, null);
            var core = type.GetMethod("AddVirtualFolder", flags, null, new[] { typeof(string), typeof(string), typeof(LibraryOptions), typeof(bool) }, null);
            var create = type.GetMethod("CreateItem", flags, null, new[] { typeof(BaseItem), typeof(BaseItem), typeof(BaseItem[]) }, null);
            if (type.FullName != "Emby.Server.Implementations.Library.LibraryManager"
                || add == null || core == null || create == null
                || add.ReturnType != typeof(CollectionFolder) || core.ReturnType != typeof(CollectionFolder) || create.ReturnType != typeof(void)
                || !HasBody(add, "D1B76D1B04009C52581FE12CA8BD22C54159CC68D3704C58C53C7ACCEF7E5C2B")
                || !HasBody(core, "7E434D454448AD6C10712C378C5F2A2B4A70CD2B8EF615A22862D171E56B5025")
                || !HasBody(create, "9ACE3CB9AA9B9E8B3E139ABB3660A4112FF73DB10C3058D1B9C7E113D0EB491F")) return _state;
            _state = _state with { ContractMatched = true, Error = "PatchUnavailable" };
            try
            {
                var assembly = EmbeddedDependencyLoader.LoadHarmonyAssembly() ?? throw new InvalidOperationException();
                var harmonyType = assembly.GetType("HarmonyLib.Harmony", true)!;
                var methodType = assembly.GetType("HarmonyLib.HarmonyMethod", true)!;
                var prefixMethod = typeof(PersonalYouTubeNativeCreationHook).GetMethod(nameof(BeforeCreate), BindingFlags.Static | BindingFlags.NonPublic)!;
                var prefix = Activator.CreateInstance(methodType, prefixMethod)!;
                methodType.GetField("priority")!.SetValue(prefix, 800);
                var harmony = Activator.CreateInstance(harmonyType, Owner)!;
                var patch = harmonyType.GetMethods().Single(method => method.Name == "Patch" && method.GetParameters().Length == 5);
                patch.Invoke(harmony, new object?[] { create, prefix, null, null, null });
                _native = create; _harmonyType = harmonyType;
                if (!HasOwnPrefix()) throw new InvalidOperationException();
                _state = _state with { Installed = true, Error = "" };
            }
            catch (Exception) { _state = _state with { Installed = false, Error = "PatchVerificationFailed" }; }
            return _state;
        }
    }
    private static bool HasOwnPrefix()
    {
        var info = _harmonyType?.GetMethod("GetPatchInfo", BindingFlags.Public | BindingFlags.Static)!.Invoke(null, new object?[] { _native });
        var prefixes = info?.GetType().GetField("Prefixes")!.GetValue(info) as System.Collections.IEnumerable;
        return prefixes != null && prefixes.Cast<object>().Any(prefix =>
            (string?)prefix.GetType().GetField("owner")!.GetValue(prefix) == Owner
            && (MethodInfo?)prefix.GetType().GetProperty("PatchMethod")!.GetValue(prefix)
                == typeof(PersonalYouTubeNativeCreationHook).GetMethod(nameof(BeforeCreate), BindingFlags.Static | BindingFlags.NonPublic));
    }
    internal static void RequireAvailable(ILibraryManager library)
    {
        lock (Gate)
        {
            if (!_state.Installed || _native?.DeclaringType != library.GetType() || !HasOwnPrefix())
                throw new InvalidOperationException("Verified native private creation guard is unavailable.");
        }
    }
    private static void BeforeCreate(BaseItem __0)
    {
        if (__0 is CollectionFolder) PersonalYouTubeNativeCreation.ReserveCurrentRoot(__0.Id);
    }
}
