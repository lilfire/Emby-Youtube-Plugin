using System.Reflection;
using System.Security.Cryptography;
using MediaBrowser.Controller.Library;

namespace Emby.YouTubePlugin;

// Synchronous repository boundary, not an event listener. No native/database
// lock is acquired here. A mutation invalidates old readers before native I/O
// and stays in progress through the outer transaction wrapper and exceptions.
internal static class PersonalYouTubeNativeSourceBarrier
{
    private const string Owner = "emby.youtubeplugin.private-source-barrier";
    private static readonly object Gate = new();
    private static readonly HashSet<string> Contracts = new(StringComparer.Ordinal) {
        "A41A55148802952D7CCADD0186636B424C871C3E3805BC45080B6651C2F2B130",
        "2281DDB6592F4AC98F4AE5211254673E2DD56D63FA1C667BCA713398A1D336F2",
        "13D531F426E6474823762D88C405F977DA5BC024E90031E7D0F082ADC97E221D",
        "B2FB7971A8943947CCEE67B1F2F17624B8BB806B87061CAB1B35B78FB214BECD",
        "3EDFFBFABA9D1D020425932D9BF1AB1CA29C5852966DEF52FC4C222CBE8A29B2",
        "CA1780655850684545BE0AAA4406BB30EE407CFD48A42FE2C805B4801609D61F",
        "09BDDE194040C5B3511A4C3EE668A445C4C4C70A8F70242A374E2D531B641EA9",
        "1C9D4CE644204EC22CDAF696A14CEFEA461A17BF61105008732407FD14054CF8",
        "11F7399D649C27F575139E97D3A723CE444DBE38560CEBBDD0541C8D93B00CD5",
        "21635DEEF2EAA54F107ECD62324366280E07530D4F197FE0311D732445D94D38",
        "941689F149301785CDC06C4E1A8E6EB8145879219796DCF8B62F6CE0DF83A2B5",
        "AC594BBAEE614ABD438D30886BFCF9BAF33B8B77F4FA476948DC8B1C24B55036",
        "72706D435FF8E0ADEDC425DEA71A4A3FFFA06D0880C963DD10085D659A0111C5"
    };
    private static Func<bool>? _verified;
    private static readonly HashSet<string> LibraryContracts = new(StringComparer.Ordinal) {
        "D1B76D1B04009C52581FE12CA8BD22C54159CC68D3704C58C53C7ACCEF7E5C2B",
        "7E434D454448AD6C10712C378C5F2A2B4A70CD2B8EF615A22862D171E56B5025",
        "E837AB5B30F93C906C713F38436F78BBD2573952C12CFA955C4B6DC46577691B",
        "50D1603B726945D0F19F6BCF61CFAC3FB6C58578880BB4A27023E17162732A3E",
        "C0122F63A01083FA6109413BAE2EE8922A644281F621D203450427BF5311D93D",
        "85537D2261896D3EFA71DF17BC7ED2868341DC46753B2A77768B80411C7B3028",
        "BA38A01DBAF6BBD383683357E606C559ED02534CD0D1EE5A9356B3039BE22B0F",
        "612CCAD0F42E46FC413425D8922243AB30C7AA0DFC8746CF5977D1B06F27AA13",
        "6C0E4CDA5CDE181CF730AD22D74E78F2337BC9C80A90B82AD6224E6B70C40106",
        "322B08B64E079F14F2F9BC770348ACE447E5227955CB3BA58FBEA6152B4F5AD6"
    };
    private static object? _repository;
    private static object? _library;
    private static readonly HashSet<string> FolderContracts = new(StringComparer.Ordinal) {
        "A44A21AAC66414587E3ACA086CD4DFE5F49511E2F39C1E94A70E3DE07D13970A",
        "BEC6A9DF6B0ADDDAF5AA98DB9AFB69F26302D5DC2E3A39F2E3AF1EBD10DE2672"
    };
    private static long _version;
    private static int _writers;
    private static int _readers, _waiting;
    private static readonly AsyncLocal<Reader?> ReaderContext = new();
    internal sealed record State(bool Installed, long Version, int Writers, int Readers, int Waiting);
    internal static State Snapshot()
    {
        lock (Gate)
        {
            bool verified;
            try { verified = _verified?.Invoke() == true; } catch (Exception) { verified = false; }
            return new(verified, _version, _writers, _readers, _waiting);
        }
    }
    internal static bool Install(ILibraryManager library)
    {
        lock (Gate)
        {
            try
            {
                var flags = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
                var repository = library.GetType().GetProperty("ItemRepository", flags)?.GetValue(library);
                if (repository == null || repository.GetType().FullName != "Emby.Server.Implementations.Data.SqliteItemRepository") return false;
                if (_repository != null) return ReferenceEquals(_repository, repository) && Snapshot().Installed;
                var type = repository.GetType();
                var methods = type.GetMethods(flags).Where(method => method.DeclaringType == type
                    && method.Name is "SaveItems" or "DeleteItems" or "UpdateValuesIfNeeded" or "SaveImages" or "DeleteObsoleteCollectionFolderAncestorIds" or "UpdatePeople"
                        or "SetItemExtradata" or "ClearItemExtradata").ToArray();
                if (methods.Length != Contracts.Count || methods.Any(method => method.ReturnType != typeof(void))
                    || !methods.Select(method => Convert.ToHexString(SHA256.HashData(method.GetMethodBody()!.GetILAsByteArray()!))).ToHashSet().SetEquals(Contracts)) return false;
                // Cover native library/path configuration BEFORE it changes
                // virtual-folder locations, not only the later item DB save.
                var structure = library.GetType().GetMethods(flags).Where(method => method.DeclaringType == library.GetType()
                    && method.Name is "AddVirtualFolder" or "AddMediaPaths" or "AddMediaPathInternal" or "UpdateMediaPath" or "RemoveVirtualFolder" or "RemoveMediaPath" or "AddBackMediaPathToAllCollectionFolders").ToArray();
                if (structure.Length != LibraryContracts.Count || structure.Any(method => typeof(Task).IsAssignableFrom(method.ReturnType))
                    || !structure.Select(method => Convert.ToHexString(SHA256.HashData(method.GetMethodBody()!.GetILAsByteArray()!))).ToHashSet().SetEquals(LibraryContracts)) return false;
                var folderType = typeof(MediaBrowser.Controller.Entities.CollectionFolder);
                var folderMethods = folderType.GetMethods(flags).Where(method => method.DeclaringType == folderType && method.Name is "UpdateLibraryOptions" or "SaveLibraryOptions").ToArray();
                if (folderMethods.Length != FolderContracts.Count || folderMethods.Any(method => method.ReturnType != typeof(void))
                    || !folderMethods.Select(method => Convert.ToHexString(SHA256.HashData(method.GetMethodBody()!.GetILAsByteArray()!))).ToHashSet().SetEquals(FolderContracts)) return false;
                methods = methods.Concat(structure).Concat(folderMethods).ToArray();
                string Prefix(MethodInfo method) => method.IsStatic || method.DeclaringType == folderType ? nameof(BeforeStaticMutation) : nameof(BeforeMutation);
                var assembly = EmbeddedDependencyLoader.LoadHarmonyAssembly()!;
                var harmonyType = assembly.GetType("HarmonyLib.Harmony", true)!;
                var methodType = assembly.GetType("HarmonyLib.HarmonyMethod", true)!;
                var harmony = Activator.CreateInstance(harmonyType, Owner)!;
                var patch = harmonyType.GetMethods().Single(method => method.Name == "Patch" && method.GetParameters().Length == 5);
                MethodInfo Callback(string name) => typeof(PersonalYouTubeNativeSourceBarrier).GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic)!;
                object PatchMethod(string name)
                {
                    var result = Activator.CreateInstance(methodType, Callback(name))!;
                    methodType.GetField("priority")!.SetValue(result, 800);
                    return result;
                }
                _repository = repository; _library = library;
                foreach (var method in methods) patch.Invoke(harmony, new object?[] { method,
                    PatchMethod(Prefix(method)), null, null, PatchMethod(nameof(MutationFinished)) });
                bool Has(MethodInfo method, string field, string name)
                {
                    var info = harmonyType.GetMethod("GetPatchInfo", BindingFlags.Public | BindingFlags.Static)!.Invoke(null, new object[] { method });
                    var entries = info?.GetType().GetField(field)!.GetValue(info) as System.Collections.IEnumerable;
                    return entries != null && entries.Cast<object>().Any(entry => (string?)entry.GetType().GetField("owner")!.GetValue(entry) == Owner
                        && (MethodInfo?)entry.GetType().GetProperty("PatchMethod")!.GetValue(entry) == Callback(name));
                }
                _verified = () => methods.All(method => Has(method, "Prefixes", Prefix(method)) && Has(method, "Finalizers", nameof(MutationFinished)));
                return Snapshot().Installed;
            }
            catch (Exception) { _verified = null; return false; }
        }
    }
    internal static IDisposable Begin(bool waitForReaders = true)
    {
        lock (Gate)
        {
            if (_readers > 0 && (!waitForReaders || ReaderContext.Value?.Active == true))
                throw new IOException("Native source write conflicts with active list output.");
            _waiting++;
            try
            {
                var deadline = Environment.TickCount64 + 30000;
                while (_readers > 0)
                {
                    var remaining = deadline - Environment.TickCount64;
                    if (remaining <= 0 || !Monitor.Wait(Gate, (int)remaining)) throw new IOException("Native source writer lease timed out.");
                }
                _writers++; _version++;
            }
            finally { _waiting--; }
        }
        return new Mutation();
    }
    internal static IDisposable EnterRead(long version)
    {
        lock (Gate)
        {
            if (!IsCurrent(version) || _waiting > 0) throw new IOException("Native source snapshot expired.");
            _readers++;
            var reader = new Reader(ReaderContext.Value);
            ReaderContext.Value = reader;
            return reader;
        }
    }
    private sealed class Reader : IDisposable
    {
        private int _disposed;
        private readonly Reader? _previous;
        internal Reader(Reader? previous) => _previous = previous;
        internal bool Active => Volatile.Read(ref _disposed) == 0;
        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
            if (ReferenceEquals(ReaderContext.Value, this)) ReaderContext.Value = _previous;
            lock (Gate) { _readers--; Monitor.PulseAll(Gate); }
        }
    }
    internal static IDisposable Combine(IDisposable owner, IDisposable source) => new Combined(owner, source);
    private sealed class Combined : IDisposable
    {
        private IDisposable? _owner, _source;
        internal Combined(IDisposable owner, IDisposable source) { _owner = owner; _source = source; }
        public void Dispose()
        { try { Interlocked.Exchange(ref _source, null)?.Dispose(); } finally { Interlocked.Exchange(ref _owner, null)?.Dispose(); } }
    }
    private sealed class Mutation : IDisposable
    {
        private int _disposed;
        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
            lock (Gate) { _writers--; _version++; }
        }
    }
    internal static bool IsCurrent(long version)
    {
        var state = Snapshot();
        return state.Installed && state.Writers == 0 && state.Version == version;
    }
    private static bool CanWait(MethodBase method) => !method.GetParameters().Any(parameter => parameter.ParameterType.FullName == "SQLitePCL.pretty.IDatabaseConnection");
    private static void BeforeMutation(object __instance, MethodBase __originalMethod, out object? __state)
        => __state = ReferenceEquals(__instance, _repository) || ReferenceEquals(__instance, _library) ? Begin(CanWait(__originalMethod)) : null;
    private static void BeforeStaticMutation(MethodBase __originalMethod, out object? __state) => __state = Begin(CanWait(__originalMethod));
    private static Exception? MutationFinished(Exception? __exception, object? __state)
    { (__state as IDisposable)?.Dispose(); return __exception; }
}
