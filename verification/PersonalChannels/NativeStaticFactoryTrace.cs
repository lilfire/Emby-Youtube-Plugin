using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using HarmonyLib;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

// Native observation and explicit source-path fault, validated synthetic A/B only.
internal static class NativeStaticFactoryTrace
{
    private static readonly object Gate = new();
    private static readonly List<object> Events = new();
    private static IAuthorizationContext? Authorization;
    private static Guid Owner;
    private static string ExpectedPath = "";
    private static string InjectedPath = "";
    private static int Injected;
    private static bool Installed;
    internal static object Arm(IUserManager users, ILibraryManager library, IAuthorizationContext authorization, IHttpResultFactory results, string ownerId, long itemId, long foreignItemId = 0, string asset = "")
    {
        if (asset is not ("" or "Image" or "Subtitle")) throw new ArgumentException("Unsupported synthetic asset trace");
        var owner = users.GetUserById(ownerId);
        var item = library.GetItemById(itemId);
        if (owner?.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator
            || item == null || !item.Path.EndsWith(Path.DirectorySeparatorChar + "PrivateNativeVideo_a_client.mp4", StringComparison.OrdinalIgnoreCase)
            || !library.GetCollectionFolders(item).Any(root => root.Name == "Private Native Fixture a"))
            throw new ArgumentException("Synthetic A only");
        var foreign = foreignItemId == 0 ? null : library.GetItemById(foreignItemId);
        if (foreignItemId != 0 && (foreign == null
            || !foreign.Path.EndsWith(Path.DirectorySeparatorChar + "PrivateNativeVideo_b_client.mp4", StringComparison.OrdinalIgnoreCase)
            || !library.GetCollectionFolders(foreign).Any(root => root.Name == "Private Native Fixture b")))
            throw new ArgumentException("Synthetic B mismatch target only");
        var expected = AssetPath(item, asset, "a");
        var injected = foreign == null ? "" : AssetPath(foreign, asset, "b");
        lock (Gate)
        {
            if (!Installed)
            {
                var methods = results.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                    .Where(method => method.Name is "GetStaticFileResult" or "GetStaticResult")
                    .Where(method => method.GetParameters().Length == 2).ToArray();
                if (methods.Length != 2 || methods.Any(method => method.ReturnType != typeof(Task<object>) || method.GetParameters()[0].ParameterType != typeof(IRequest)))
                    throw new InvalidOperationException("Unexpected static result factory");
                var harmony = new Harmony("isolated-native-static-factory-trace");
                foreach (var method in methods)
                    harmony.Patch(method, prefix: new HarmonyMethod(typeof(NativeStaticFactoryTrace), nameof(Before)),
                        postfix: new HarmonyMethod(typeof(NativeStaticFactoryTrace), nameof(After)));
                Installed = true;
            }
            Authorization = authorization; Owner = owner.Id; ExpectedPath = Path.GetFullPath(expected);
            InjectedPath = injected; Injected = 0; Events.Clear();
            return Snapshot();
        }
    }
    private static string AssetPath(BaseItem item, string asset, string owner)
    {
        var expected = Path.GetFullPath(item.Path);
        if (asset == "Image")
        {
            expected = item.GetImageInfo(MediaBrowser.Model.Entities.ImageType.Primary, 0)?.Path ?? throw new ArgumentException("No synthetic image");
            var original = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(item.Path))!, "fixture-primary-" + owner + ".png");
            if (!File.Exists(expected) || !File.Exists(original)
                || !SHA256.HashData(File.ReadAllBytes(expected)).SequenceEqual(SHA256.HashData(File.ReadAllBytes(original))))
                throw new ArgumentException("Synthetic image content not established");
        }
        if (asset == "Subtitle")
        {
            var subtitle = item.GetMediaStreams().Where(stream => stream.Type == MediaBrowser.Model.Entities.MediaStreamType.Subtitle && stream.IsExternal).Single();
            expected = subtitle.Path;
            if (Path.GetFullPath(expected) != Path.Combine(Path.GetDirectoryName(Path.GetFullPath(item.Path))!, "PrivateNativeVideo_" + owner + "_client.en.srt")
                || !File.ReadAllText(expected).Contains("PrivateSubtitle_" + owner + "_native_media", StringComparison.Ordinal))
                throw new ArgumentException("Synthetic subtitle source not established");
        }
        return Path.GetFullPath(expected);
    }
    private static bool SamePath(string? path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        try { return string.Equals(Path.GetFullPath(path), ExpectedPath, StringComparison.OrdinalIgnoreCase); }
        catch (Exception) { return false; }
    }
    private static void Before(IRequest __0, object __1, MethodBase __originalMethod, out object? __state)
    {
        __state = null;
        var marker = __0.Headers["X-Isolated-Static-Factory"];
        if (marker is not ("trace" or "inject") || Authorization?.GetAuthorizationInfo(__0).User?.Id != Owner) return;
        // Read the live argument; Harmony's __args array can write a stale
        // argument back after an earlier prefix replaced it with a copy.
        var options = __1;
        var path = options as string ?? options.GetType().GetProperty("Path")?.GetValue(options) as string;
        var factory = options.GetType().GetProperty("ContentFactory")?.GetValue(options) as Delegate;
        lock (Gate)
            Events.Add(new { Phase = "Before", Method = __originalMethod.ToString(),
                OptionsType = options.GetType().FullName,
                PathPresent = !string.IsNullOrEmpty(path), MatchesExpectedPath = SamePath(path),
                ContentFactoryPresent = factory != null, FactoryTargetType = factory?.Target?.GetType().FullName ?? "",
                FactoryMethodContract = FactoryMethod(factory),
                BoundReaderContract = BoundReader(factory, options),
                FactoryTargetFields = FactoryFields(factory, options),
                IsHeadRequest = __0.Verb.Equals("HEAD", StringComparison.OrdinalIgnoreCase) });
        __state = __originalMethod.ToString();
        // Explicit fault injection, synthetic A/B only. The nested factory
        // already holds its closure over this same mutable options object.
        if (marker == "inject" && __originalMethod.Name == "GetStaticResult"
            && options is StaticFileResultOptions fileOptions && factory != null && SamePath(fileOptions.Path))
        {
            lock (Gate)
            {
                if (Injected == 0 && !string.IsNullOrEmpty(InjectedPath))
                {
                    fileOptions.Path = InjectedPath; Injected++;
                    Events.Add(new { Phase = "SyntheticMismatch", AuthenticatedSyntheticOwnerVerified = true,
                        ChangedNestedOptionsPath = true, ContentFactoryAlreadyCreated = true });
                }
            }
        }
    }
    private static object[] FactoryFields(Delegate? factory, object? options)
    {
        if (factory?.Target == null) return Array.Empty<object>();
        return factory.Target.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            .Select(field => {
                var value = field.GetValue(factory.Target);
                var path = value as string ?? value?.GetType().GetProperty("Path")?.GetValue(value) as string;
                return (object)new { Field = field.ToString(), SameOptionsObject = ReferenceEquals(value, options),
                    PathPresent = !string.IsNullOrEmpty(path), MatchesExpectedPath = SamePath(path) };
            }).ToArray();
    }
    private static object? FactoryMethod(Delegate? factory)
    {
        if (factory == null) return null;
        string Hash(MethodInfo? method) => method?.GetMethodBody()?.GetILAsByteArray() is byte[] body
            ? Convert.ToHexString(SHA256.HashData(body)) : "";
        var state = factory.Method.GetCustomAttribute<AsyncStateMachineAttribute>()?.StateMachineType;
        return new { Method = factory.Method.ToString(), BodyHash = Hash(factory.Method),
            AsyncStateMachineType = state?.FullName ?? "",
            MoveNextHash = Hash(state?.GetMethod("MoveNext", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)) };
    }
    private static object? BoundReader(Delegate? factory, object? options)
    {
        if (factory?.Target == null) return null;
        var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        var field = factory.Target.GetType().GetFields(flags).SingleOrDefault(field => field.FieldType.FullName == "Emby.YouTubePlugin.PersonalYouTubeStaticSourceGate+Proof");
        var proof = field?.GetValue(factory.Target);
        if (proof == null) return null;
        var reader = proof.GetType().GetField("Reader", flags)?.GetValue(proof) as Delegate;
        var readerOptions = proof.GetType().GetField("ReaderOptions", flags)?.GetValue(proof) as StaticFileResultOptions;
        var metadataOptions = proof.GetType().GetField("Options", flags)?.GetValue(proof) as StaticFileResultOptions;
        return new { NativeReaderMethod = FactoryMethod(reader), ReaderMatchesExpectedPath = SamePath(readerOptions?.Path),
            SeparateReaderOptions = readerOptions != null && metadataOptions != null && !ReferenceEquals(readerOptions, metadataOptions),
            SameMetadataOptions = ReferenceEquals(metadataOptions, options) };
    }
    private static void After(ref Task<object> __result, object? __state)
    {
        if (__state is string method) __result = Track(__result, method);
    }
    private static async Task<object> Track(Task<object> task, string method)
    {
        var result = await task.ConfigureAwait(false);
        var flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        var path = result.GetType().GetField("_filePath", flags)?.GetValue(result) as string;
        var factory = result.GetType().GetProperty("ContentFactory", flags)?.GetValue(result) as Delegate;
        lock (Gate)
            Events.Add(new { Phase = "After", Method = method, ResultType = result.GetType().FullName,
                WriterPathPresent = !string.IsNullOrEmpty(path), WriterMatchesExpectedPath = SamePath(path),
                WriterFactoryPresent = factory != null, WriterFactoryTargetType = factory?.Target?.GetType().FullName ?? "",
                WriterFactoryMethodContract = FactoryMethod(factory),
                BoundReaderContract = BoundReader(factory, null),
                WriterFactoryTargetFields = FactoryFields(factory, null) });
        return result;
    }
    internal static object Snapshot() { lock (Gate) return new { Installed, Injected, Events = Events.ToArray() }; }
}
