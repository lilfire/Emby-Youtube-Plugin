using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.MediaEncoding;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.Drawing;

namespace Emby.YouTubePlugin;

// Binds audited native producer outputs to one private request. Local image
// output must match an independently computed recipe or an owned original.
// Cache contents, localization and other providers need further verification.
internal static class PersonalYouTubeAssetSourceGate
{
    private const string Owner = "emby.youtubeplugin.personal-asset-source";
    private static readonly AsyncLocal<Scope?> Current = new();
    private static readonly object Gate = new();
    private static Func<bool>? Verify;
    private static PropertyInfo? JobOutput;
    private static MethodInfo? JobFinish, JobFault;
    private static MethodInfo? ImageCacheRoot;
    private static bool Installed;
    private static string Error = "NotInitialized";
    private static long Producers, Outputs, Denied, ImageRecipes;
    internal sealed record State(bool Installed, string Error, long Producers, long Outputs, long Denied, long ImageRecipes = 0, int ImageRecipeVersion = 0);
    internal sealed class Scope
    {
        internal readonly Scope? Previous;
        internal readonly bool Image;
        internal readonly Func<long, string, bool> ImageInput;
        internal readonly Func<string, string, bool> SubtitleInput;
        internal readonly Func<string, bool> Direct;
        internal readonly ImageType Type;
        internal readonly int Index;
        internal volatile bool Failed, Constructing = true;
        private readonly Dictionary<string, Func<bool>> Paths = new(OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
        private readonly Dictionary<string, Func<bool>> ImageSources = new(OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
        private readonly Dictionary<string, Func<bool>> ImageCandidates = new(OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
        internal Scope(bool image, ImageType type, int index, Func<long, string, bool> imageInput, Func<string, string, bool> subtitleInput, Func<string, bool> direct)
        { Previous = Current.Value; Image = image; Type = type; Index = index; ImageInput = imageInput; SubtitleInput = subtitleInput; Direct = direct; }
        internal bool AllowedPath(string path)
        {
            lock (Paths) return !Failed && (Direct(path) || Paths.TryGetValue(Path.GetFullPath(path), out var input) && input());
        }
        internal void Add(string path, Func<bool> input)
        {
            lock (Paths)
            {
                if (Failed || !Constructing || string.IsNullOrEmpty(path) || !input()) throw Missing();
                Paths[Path.GetFullPath(path)] = input; Interlocked.Increment(ref Outputs);
            }
        }
        internal void ImageSource(string path, Func<bool> input)
        { lock(Paths) { if(Failed || !Constructing || !input()) throw Missing(); ImageSources[Path.GetFullPath(path)] = input; } }
        internal Func<bool> ImageSourceProof(string path)
        {
            lock(Paths)
            {
                if(Failed || !Constructing || !ImageSources.TryGetValue(Path.GetFullPath(path), out var input) || !input()) throw Missing();
                return input;
            }
        }
        internal void ImageCandidate(string path, Func<bool> input)
        { lock(Paths) { if(Failed || !Constructing || !input()) throw Missing(); ImageCandidates[Path.GetFullPath(path)] = input; Interlocked.Increment(ref ImageRecipes); } }
        internal bool ImageOutputAllowed(string path)
        { lock(Paths) return !Failed && (Direct(path) || ImageCandidates.TryGetValue(Path.GetFullPath(path), out var input) && input()); }
    }
    private sealed record Proof(Scope Scope, Func<bool> Stable);
    private sealed record CacheProof(Scope Scope, string Expected, Func<bool> Stable);
    internal static State Snapshot()
    {
        lock (Gate)
        {
            bool valid; try { valid = Installed && Verify?.Invoke() == true; } catch (Exception) { valid = false; }
            return new(valid, valid ? "" : Installed ? "PatchLost" : Error, Interlocked.Read(ref Producers), Interlocked.Read(ref Outputs), Interlocked.Read(ref Denied), Interlocked.Read(ref ImageRecipes), valid ? 1 : 0);
        }
    }
    private static string Hash(MethodInfo method) => Convert.ToHexString(SHA256.HashData(method.GetMethodBody()!.GetILAsByteArray()!));
    internal static State Install()
    {
        lock (Gate)
        {
            if (Installed) return Snapshot();
            var stage = "FindImage";
            try
            {
                Type Find(string name) => AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType(name)).Single(type => type != null)!;
                var image = Find("Emby.Drawing.ImageProcessor").GetMethod("ProcessImage", new[] { typeof(ImageProcessingOptions), typeof(CancellationToken) })!;
                stage = "FindSubtitle";
                var subtitle = Find("Emby.Server.MediaEncoding.Subtitles.SubtitleEncoder").GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                    .Single(method => method.Name == "GetSubtitleJob" && method.GetParameters().Length == 12);
                stage = "Contract";
                if (image.ReturnType != typeof(Task<Tuple<string, string, DateTimeOffset>>)
                    || !subtitle.ReturnType.IsGenericType || subtitle.ReturnType.GetGenericTypeDefinition() != typeof(Task<>)
                    || subtitle.ReturnType.GetGenericArguments()[0].FullName != "MediaBrowser.Controller.MediaEncoding.ISubtitleConversionJob"
                    || Hash(image) != "F7FEFE139B5BD9049FE7DEC85A3490D6ADEC300CC3E4F401951726A21714B7AB"
                    || Hash(subtitle) != "648D30A8D9F44E7D8BF0F4A0BDBEDB7DE587BEA890F3AC304F610E3AD885648A") throw new InvalidOperationException();
                string AsyncHash(MethodInfo method) => Hash(method.GetCustomAttribute<AsyncStateMachineAttribute>()!.StateMachineType
                    .GetMethod("MoveNext", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)!);
                if (AsyncHash(image) != "F1118A4EBEABCC48A75D8658E1ACF6C70BE6C193D03B8A955B9A814269999B7B"
                    || AsyncHash(subtitle) != "71C777FEC44EF018D12A6E4A7B832F442C03FFE53C44ED4DDC9664423D194288") throw new InvalidOperationException();
                stage = "ImageCacheContract";
                var cache = image.DeclaringType!.GetMethod("GetCacheFilePath", BindingFlags.Instance | BindingFlags.NonPublic)!;
                ImageCacheRoot = image.DeclaringType.GetMethod("GetResizedImageCachePath", BindingFlags.Instance | BindingFlags.NonPublic)!;
                if(cache.ReturnType != typeof(string) || !cache.GetParameters().Select(parameter => parameter.ParameterType).SequenceEqual(new[] {
                    typeof(string), typeof(int), typeof(int), typeof(int), typeof(int), typeof(int), typeof(DateTimeOffset), typeof(ImageFormat), typeof(int?), typeof(string), typeof(string) })
                    || Hash(cache) != "6099FEDB8EC28B3BF08D9D055EC3160991107083A62FCD98506478261505A628"
                    || ImageCacheRoot.ReturnType != typeof(string) || Hash(ImageCacheRoot) != "7CD0EDE19C22395EF13DBA3A76A7F757A44EF8CD1E0FE21A8BC28BF5A0765F4D") throw new InvalidOperationException();
                var assembly = EmbeddedDependencyLoader.LoadHarmonyAssembly()!;
                var harmonyType = assembly.GetType("HarmonyLib.Harmony", true)!;
                var methodType = assembly.GetType("HarmonyLib.HarmonyMethod", true)!;
                var jobType = subtitle.ReturnType.GetGenericArguments()[0];
                JobFinish = typeof(PersonalYouTubeAssetSourceGate).GetMethod(nameof(FinishSubtitle), BindingFlags.Static | BindingFlags.NonPublic)!.MakeGenericMethod(jobType);
                JobFault = typeof(Task).GetMethod(nameof(Task.FromException), 1, new[] { typeof(Exception) })!.MakeGenericMethod(jobType);
                stage = "JobOutput";
                JobOutput = jobType.GetProperty("OutputPath") ?? throw new InvalidOperationException();
                if (JobOutput.PropertyType != typeof(string) || JobOutput.GetMethod == null) throw new InvalidOperationException();
                MethodInfo Hook(string name)
                {
                    var hook = typeof(PersonalYouTubeAssetSourceGate).GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic)!;
                    return hook.IsGenericMethodDefinition ? hook.MakeGenericMethod(jobType) : hook;
                }
                object Patch(string name)
                {
                    var patch = Activator.CreateInstance(methodType, Hook(name))!;
                    methodType.GetField("priority")!.SetValue(patch, 800); return patch;
                }
                var harmony = Activator.CreateInstance(harmonyType, Owner)!;
                var apply = harmonyType.GetMethods().Single(method => method.Name == "Patch" && method.GetParameters().Length == 5);
                stage = "ApplyImage";
                apply.Invoke(harmony, new object?[] { image, Patch(nameof(BeforeImage)), Patch(nameof(AfterImage)), null, null });
                stage = "ApplySubtitle";
                apply.Invoke(harmony, new object?[] { subtitle, Patch(nameof(BeforeSubtitle)), Patch(nameof(AfterSubtitle)), null, null });
                stage = "ApplyImageCache";
                apply.Invoke(harmony, new object?[] { cache, Patch(nameof(BeforeImageCache)), Patch(nameof(AfterImageCache)), null, null });
                bool Has(MethodInfo native, string field, string name)
                {
                    var info = harmonyType.GetMethod("GetPatchInfo", BindingFlags.Static | BindingFlags.Public)!.Invoke(null, new object[] { native });
                    var entries = info?.GetType().GetField(field)!.GetValue(info) as System.Collections.IEnumerable;
                    return entries != null && entries.Cast<object>().Any(entry => (string?)entry.GetType().GetField("owner")!.GetValue(entry) == Owner
                        && (MethodInfo?)entry.GetType().GetProperty("PatchMethod")!.GetValue(entry) == Hook(name));
                }
                stage = "Verify";
                Verify = () => Has(image, "Prefixes", nameof(BeforeImage)) && Has(image, "Postfixes", nameof(AfterImage))
                    && Has(subtitle, "Prefixes", nameof(BeforeSubtitle)) && Has(subtitle, "Postfixes", nameof(AfterSubtitle))
                    && Has(cache, "Prefixes", nameof(BeforeImageCache)) && Has(cache, "Postfixes", nameof(AfterImageCache));
                if (!Verify()) throw new InvalidOperationException();
                Installed = true; Error = "";
            }
            catch (Exception error) { Installed = false; Error = stage + ":" + (error is TargetInvocationException { InnerException: not null } reflection ? reflection.InnerException!.GetType().Name : error.GetType().Name); }
            return Snapshot();
        }
    }
    internal static Scope Begin(bool image, ImageType type, int index, Func<long, string, bool> imageInput, Func<string, string, bool> subtitleInput, Func<string, bool> direct)
    {
        if (!Snapshot().Installed) throw Missing();
        var scope = new Scope(image, type, index, imageInput, subtitleInput, direct); Current.Value = scope; return scope;
    }
    internal static void Restore(Scope? scope) { if (scope != null && ReferenceEquals(Current.Value, scope)) Current.Value = scope.Previous; }
    internal static void End(Scope? scope) { if (scope != null) scope.Constructing = false; Restore(scope); }
    private static ResourceNotFoundException Missing() => new("Item not found.");
    private static void Fail(Scope scope) { scope.Failed = true; Interlocked.Increment(ref Denied); }
    private static T Copy<T>(T source) where T : class, new()
    {
        if (source.GetType() != typeof(T)) throw Missing();
        var copy = new T();
        foreach (var property in typeof(T).GetProperties(BindingFlags.Instance | BindingFlags.Public).Where(property => property.CanRead && property.CanWrite && property.GetIndexParameters().Length == 0))
        {
            var value = property.GetValue(source);
            if (value is Array array) value = array.Clone();
            if (value is IDictionary<string, string> headers) value = new Dictionary<string, string>(headers);
            property.SetValue(copy, value);
        }
        return copy;
    }
    private static bool BeforeImage(ref ImageProcessingOptions __0, ref Task<Tuple<string, string, DateTimeOffset>> __result, out object? __state)
    {
        __state = null; var scope = Current.Value; if (scope == null || !scope.Constructing) return true;
        try
        {
            if (!scope.Image || scope.Failed || !scope.Constructing || __0.ImageIndex != scope.Index || __0.Image == null || __0.Image.Type != scope.Type) throw Missing();
            var id = __0.Item?.InternalId ?? __0.ItemId; var source = __0.Image.Path;
            if (id <= 0 || (__0.ItemId != 0 && __0.ItemId != id)) throw Missing();
            if (!scope.ImageInput(id, source)) throw Missing();
            var copy = Copy(__0); copy.Image = Copy(__0.Image); __0 = copy;
            bool Stable() => !scope.Failed && (copy.Item?.InternalId ?? copy.ItemId) == id && copy.Image.Path == source && scope.ImageInput(id, source);
            scope.ImageSource(source, Stable);
            __state = new Proof(scope, Stable); Interlocked.Increment(ref Producers); return true;
        }
        catch (Exception) { Fail(scope); __result = Task.FromException<Tuple<string, string, DateTimeOffset>>(Missing()); return false; }
    }
    private static void AfterImage(ref Task<Tuple<string, string, DateTimeOffset>> __result, object? __state)
    { if (__state is Proof proof) __result = FinishImage(__result, proof); }
    private static async Task<Tuple<string, string, DateTimeOffset>> FinishImage(Task<Tuple<string, string, DateTimeOffset>> task, Proof proof)
    {
        try
        {
            var result = await task.ConfigureAwait(false); var path = result.Item1;
            bool OutputStable() => proof.Stable() && proof.Scope.ImageOutputAllowed(path);
            if (!OutputStable()) throw Missing();
            proof.Scope.Add(path, OutputStable); return result;
        }
        catch (Exception) { Fail(proof.Scope); throw Missing(); }
    }
    private static void BeforeImageCache(object __instance, string __0, int __1, int __2, int __3, int __4, int __5,
        DateTimeOffset __6, ImageFormat __7, int? __8, string __9, string __10, out object? __state)
    {
        __state = null; var scope = Current.Value;
        if(scope == null || !scope.Constructing) return;
        try
        {
            if(!scope.Image || scope.Failed) throw Missing();
            var input = scope.ImageSourceProof(__0);
            var recipe = __0 + "requestedWidth=" + __1.ToString() + "requestedHeight=" + __2.ToString()
                + "requestedMaxWidth=" + __3.ToString() + "requestedMaxHeight=" + __4.ToString()
                + "quality=" + __5.ToString() + "datemodified=" + __6.UtcDateTime.Ticks.ToString() + "f=" + __7.ToString();
            if(__8.HasValue) recipe += "blur=" + __8.Value.ToString();
            if(!string.IsNullOrEmpty(__9)) recipe += "b=" + __9;
            if(!string.IsNullOrEmpty(__10)) recipe += "fl=" + __10;
            // Audited server provider hashes UTF-16LE, then formats a Guid.
            var name = new Guid(MD5.HashData(Encoding.Unicode.GetBytes(recipe))).ToString() + "." + __7.ToString().ToLowerInvariant();
            var root = (string)ImageCacheRoot!.Invoke(__instance, null)!;
            var expected = Path.GetFullPath(Path.Combine(root, name[..1], name));
            bool Stable() => !scope.Failed && input() && SamePath(root, (string)ImageCacheRoot!.Invoke(__instance, null)!);
            __state = new CacheProof(scope, expected, Stable);
        }
        catch(Exception) { Fail(scope); throw Missing(); }
    }
    private static void AfterImageCache(string __result, object? __state)
    {
        if(__state is not CacheProof proof) return;
        try
        {
            if(!proof.Stable() || !SamePath(__result, proof.Expected)) throw Missing();
            proof.Scope.ImageCandidate(proof.Expected, proof.Stable);
        }
        catch(Exception) { Fail(proof.Scope); throw Missing(); }
    }
    private static bool SamePath(string first, string second) => string.Equals(Path.GetFullPath(first), Path.GetFullPath(second),
        OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
    private static bool BeforeSubtitle(string __0, ref IDictionary<string, string> __3, ref MediaStream __4, ref object __result, out object? __state)
    {
        __state = null; var scope = Current.Value; if (scope == null || !scope.Constructing) return true;
        try
        {
            if (scope.Image || scope.Failed || !scope.Constructing || __4.Index != scope.Index || __4.Type != MediaStreamType.Subtitle) throw Missing();
            var source = __4.Path ?? "";
            if (!scope.SubtitleInput(__0, source)) throw Missing();
            __4 = Copy(__4); var stream = __4; if (__3 != null) __3 = new Dictionary<string, string>(__3);
            bool Stable() => !scope.Failed && (stream.Path ?? "") == source && stream.Index == scope.Index && scope.SubtitleInput(__0, source);
            __state = new Proof(scope, Stable); Interlocked.Increment(ref Producers); return true;
        }
        catch (Exception) { Fail(scope); __result = JobFault!.Invoke(null, new object[] { Missing() })!; return false; }
    }
    private static void AfterSubtitle(ref object __result, object? __state)
    { if (__state is Proof proof) __result = JobFinish!.Invoke(null, new object[] { __result, proof })!; }
    private static async Task<T> FinishSubtitle<T>(Task<T> task, Proof proof) where T : class
    {
        T? result = null;
        try { result = await task.ConfigureAwait(false); if (!proof.Stable()) throw Missing(); proof.Scope.Add((string)JobOutput!.GetValue(result)!, proof.Stable); return result; }
        catch (Exception) { (result as IDisposable)?.Dispose(); Fail(proof.Scope); throw Missing(); }
    }
}
