using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.IO;
using MediaBrowser.Model.Services;

namespace Emby.YouTubePlugin;

// Audited local static video factory only. Dynamic/live factories require
// separate provenance; no universal source/transport guarantee.
internal static class PersonalYouTubeStaticSourceGate
{
    private const string Owner = "emby.youtubeplugin.personal-static-source";
    internal sealed class Scope
    {
        internal readonly IRequest Request;
        internal readonly Func<string, bool> AllowedPath;
        internal volatile bool Constructing = true, Failed;
        internal Scope(IRequest request, Func<string, bool> allowed) { Request = request; AllowedPath = allowed; }
    }
    private sealed class Proof
    {
        internal readonly Scope Scope;
        internal readonly StaticFileResultOptions Options;
        internal readonly string Path;
        internal StaticFileResultOptions? ReaderOptions;
        internal Func<long, long, CancellationToken, Task<StreamHandler>>? Reader, BoundFactory;
        internal volatile bool Registered;
        internal Proof(Scope scope, StaticFileResultOptions options, string path) { Scope = scope; Options = options; Path = path; }
    }
    private static readonly ConditionalWeakTable<IRequest, Scope> Requests = new();
    private static readonly ConditionalWeakTable<StaticFileResultOptions, Proof> Options = new();
    private static readonly ConditionalWeakTable<object, Proof> Results = new();
    private static readonly object Gate = new();
    private static Func<bool>? Verify;
    private static bool Installed;
    private static string Error = "NotInitialized";
    private static string LastFailure = "";
    private static long Factories, Reads, IoCalls, Denied;
    internal sealed record State(bool Installed, string Error, long Factories, long Reads, long IoCalls, long Denied, string LastFailure);
    internal static State Snapshot()
    {
        lock (Gate)
        {
            bool valid;
            try { valid = Installed && Verify?.Invoke() == true; } catch (Exception) { valid = false; }
            return new(valid, valid ? "" : Installed ? "PatchLost" : Error, Interlocked.Read(ref Factories), Interlocked.Read(ref Reads), Interlocked.Read(ref IoCalls), Interlocked.Read(ref Denied), Volatile.Read(ref LastFailure));
        }
    }
    private static string Hash(MethodInfo method) => Convert.ToHexString(SHA256.HashData(method.GetMethodBody()!.GetILAsByteArray()!));
    internal static State Install(IHttpResultFactory factory)
    {
        lock (Gate)
        {
            if (Installed) return Snapshot();
            try
            {
                var type = factory.GetType();
                var file = type.GetMethod("GetStaticFileResult", new[] { typeof(IRequest), typeof(StaticFileResultOptions) })!;
                var core = type.GetMethod("GetStaticResult", new[] { typeof(IRequest), typeof(StaticResultOptions) })!;
                if (type.FullName != "Emby.Server.Implementations.HttpServer.HttpResultFactory"
                    || file.ReturnType != typeof(Task<object>) || core.ReturnType != typeof(Task<object>)
                    || Hash(file) != "2F31DF16E9D4669F8D95C3945A1D88A705DF182AF7635397030FD0D061C8A782"
                    || Hash(core) != "4C716F3B7CB1817B7B1B25FD24854AF16614FA227E09B1DA38D5F22A545ACB11") throw new InvalidOperationException();
                var assembly = EmbeddedDependencyLoader.LoadHarmonyAssembly()!;
                var harmonyType = assembly.GetType("HarmonyLib.Harmony", true)!;
                var methodType = assembly.GetType("HarmonyLib.HarmonyMethod", true)!;
                var harmony = Activator.CreateInstance(harmonyType, Owner)!;
                object Patch(string name)
                {
                    var result = Activator.CreateInstance(methodType, typeof(PersonalYouTubeStaticSourceGate).GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic)!)!;
                    methodType.GetField("priority")!.SetValue(result, 800); return result;
                }
                var patch = harmonyType.GetMethods().Single(method => method.Name == "Patch" && method.GetParameters().Length == 5);
                patch.Invoke(harmony, new object?[] { file, Patch(nameof(BeforeFile)), Patch(nameof(AfterFactory)), null, Patch(nameof(FactoryFailed)) });
                patch.Invoke(harmony, new object?[] { core, Patch(nameof(BeforeCore)), Patch(nameof(AfterFactory)), null, Patch(nameof(FactoryFailed)) });
                bool Has(MethodInfo original, string field, string name)
                {
                    var info = harmonyType.GetMethod("GetPatchInfo", BindingFlags.Static | BindingFlags.Public)!.Invoke(null, new object[] { original });
                    var entries = info?.GetType().GetField(field)!.GetValue(info) as System.Collections.IEnumerable;
                    return entries != null && entries.Cast<object>().Any(entry => (string?)entry.GetType().GetField("owner")!.GetValue(entry) == Owner
                        && (MethodInfo?)entry.GetType().GetProperty("PatchMethod")!.GetValue(entry)
                            == typeof(PersonalYouTubeStaticSourceGate).GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic));
                }
                Verify = () => Has(file, "Prefixes", nameof(BeforeFile)) && Has(core, "Prefixes", nameof(BeforeCore))
                    && new[] { file, core }.All(method => Has(method, "Postfixes", nameof(AfterFactory)) && Has(method, "Finalizers", nameof(FactoryFailed)));
                if (!Verify()) throw new InvalidOperationException();
                Installed = true; Error = "";
            }
            catch (Exception) { Installed = false; Error = "UnverifiedStaticFactoryContract"; }
            return Snapshot();
        }
    }
    internal static Scope Begin(IRequest request, Func<string, bool> allowed)
    {
        if (!Snapshot().Installed) throw Missing();
        var scope = new Scope(request, allowed);
        if (!ReferenceEquals(Requests.GetValue(request, _ => scope), scope)) throw Missing();
        return scope;
    }
    internal static void End(Scope? scope) { if (scope != null) scope.Constructing = false; }
    internal static void Abort(Scope? scope) { if (scope != null) { scope.Failed = true; scope.Constructing = false; } }
    private static ResourceNotFoundException Missing() => new("Item not found.");
    private static bool Stable(Proof proof) => !proof.Scope.Failed
        && string.Equals(System.IO.Path.GetFullPath(proof.Options.Path), proof.Path, StringComparison.OrdinalIgnoreCase)
        && (proof.ReaderOptions == null || string.Equals(System.IO.Path.GetFullPath(proof.ReaderOptions.Path), proof.Path, StringComparison.OrdinalIgnoreCase))
        && (proof.Reader == null || ReferenceEquals(proof.Options.ContentFactory, proof.BoundFactory))
        && proof.Scope.AllowedPath(proof.Path);
    private static void Fail(Scope scope, object? result = null)
    {
        scope.Failed = true; Interlocked.Increment(ref Denied);
        PersonalYouTubeItemListGate.DiscardPrivateResult(result, scope.Request.Response);
    }
    private static StaticFileResultOptions Copy(StaticFileResultOptions source)
    {
        if (source.GetType() != typeof(StaticFileResultOptions)) throw Missing();
        var target = new StaticFileResultOptions();
        foreach (var property in typeof(StaticFileResultOptions).GetProperties(BindingFlags.Instance | BindingFlags.Public).Where(property => property.CanRead && property.CanWrite && property.GetIndexParameters().Length == 0))
        {
            var value = property.GetValue(source);
            if (value is IDictionary<string, string> headers) value = new Dictionary<string, string>(headers);
            property.SetValue(target, value);
        }
        return target;
    }
    private static bool BeforeFile(IRequest __0, ref StaticFileResultOptions __1, ref Task<object> __result, out object? __state)
    {
        __state = null;
        if (!Requests.TryGetValue(__0, out var scope)) return true;
        var stage = "FileScope";
        try
        {
            if (!scope.Constructing || scope.Failed || __1.ContentFactory != null) throw Missing();
            stage = "FilePath"; var path = System.IO.Path.GetFullPath(__1.Path);
            stage = "FilePermission";
            if (!scope.AllowedPath(path)) throw Missing();
            stage = "FileCopy"; var copy = Copy(__1); copy.Path = path;
            var proof = new Proof(scope, copy, path); Options.Add(copy, proof);
            __1 = copy; __state = proof; Interlocked.Increment(ref Factories); return true;
        }
        catch (Exception error) { Volatile.Write(ref LastFailure, stage + ":" + error.GetType().Name); Fail(scope); __result = Task.FromException<object>(Missing()); return false; }
    }
    private static bool BeforeCore(object __instance, IRequest __0, StaticResultOptions __1, ref Task<object> __result, out object? __state)
    {
        __state = null;
        if (!Requests.TryGetValue(__0, out var scope)) return true;
        var stage = "CoreScope";
        try
        {
            if (!scope.Constructing || __1 is not StaticFileResultOptions file || !Options.TryGetValue(file, out var proof)
                || !ReferenceEquals(proof.Scope, scope) || proof.Reader != null || !Stable(proof)) throw Missing();
            stage = "CoreDelegate";
            var original = file.ContentFactory ?? throw Missing();
            var target = original.Target ?? throw Missing(); var type = target.GetType();
            var fields = type.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            var captured = fields.Single(field => field.Name == "options" && field.FieldType == typeof(StaticFileResultOptions));
            var instance = fields.Single(field => field.Name == "<>4__this" && field.FieldType == __instance.GetType());
            if (type.FullName != "Emby.Server.Implementations.HttpServer.HttpResultFactory+<>c__DisplayClass30_0"
                || fields.Length != 2 || !ReferenceEquals(captured.GetValue(target), file) || !ReferenceEquals(instance.GetValue(target), __instance)
                || Hash(original.Method) != "6EF1D70DA9C84A39140CC50C0166C4A8A9670A07ED10ECB324632061E649FC1B") throw Missing();
            stage = "CoreReaderCopy";
            var readerOptions = Copy(file); readerOptions.Path = proof.Path; readerOptions.ContentFactory = null;
            var readerTarget = Activator.CreateInstance(type, true)!;
            stage = "CoreReaderFields";
            captured.SetValue(readerTarget, readerOptions); instance.SetValue(readerTarget, __instance);
            proof.ReaderOptions = readerOptions;
            stage = "CoreReaderDelegate";
            proof.Reader = (Func<long, long, CancellationToken, Task<StreamHandler>>)Delegate.CreateDelegate(typeof(Func<long, long, CancellationToken, Task<StreamHandler>>), readerTarget, original.Method);
            proof.BoundFactory = (offset, count, token) => Read(proof, offset, count, token);
            file.ContentFactory = proof.BoundFactory; __state = proof; return true;
        }
        catch (Exception error) { Volatile.Write(ref LastFailure, stage + ":" + error.GetType().Name); Fail(scope); __result = Task.FromException<object>(Missing()); return false; }
    }
    private static async Task<StreamHandler> Read(Proof proof, long offset, long count, CancellationToken token)
    {
        Interlocked.Increment(ref Reads);
        StreamHandler? opened = null;
        try
        {
            if ((!proof.Scope.Constructing && !proof.Registered) || !Stable(proof)) throw Missing();
            Interlocked.Increment(ref IoCalls);
            opened = await proof.Reader!(offset, count, token).ConfigureAwait(false);
            if (!Stable(proof)) throw Missing();
            return opened;
        }
        catch (Exception) { opened?.Dispose(); Fail(proof.Scope); throw Missing(); }
    }
    private static void AfterFactory(ref Task<object> __result, object? __state)
    {
        if (__state is Proof proof) __result = Finish(__result, proof);
    }
    private static async Task<object> Finish(Task<object> task, Proof proof)
    {
        object? result = null;
        try
        {
            result = await task.ConfigureAwait(false);
            if (!Stable(proof)) throw Missing();
            if (result.GetType().FullName == "Emby.Server.Implementations.HttpServer.FileWriter")
            {
                var factory = result.GetType().GetProperty("ContentFactory")!.GetValue(result);
                if (!ReferenceEquals(factory, proof.BoundFactory)) throw Missing();
            }
            else if (result.GetType().FullName != "Emby.Server.Implementations.Services.EmptyHttpResult"
                || result is not IHttpResult http || http.StatusCode != System.Net.HttpStatusCode.NotModified) throw Missing();
            if (!ReferenceEquals(Results.GetValue(result, _ => proof), proof)) throw Missing();
            return result;
        }
        catch (Exception) { Fail(proof.Scope, result); throw Missing(); }
    }
    internal static Func<bool> ProtectResult(Scope scope, object result)
    {
        if (!Results.TryGetValue(result, out var proof) || !ReferenceEquals(proof.Scope, scope) || !Stable(proof))
        { Fail(scope, result); throw Missing(); }
        proof.Registered = true;
        return () => Stable(proof) && (result.GetType().FullName != "Emby.Server.Implementations.HttpServer.FileWriter"
            || ReferenceEquals(result.GetType().GetProperty("ContentFactory")!.GetValue(result), proof.BoundFactory));
    }
    private static Exception? FactoryFailed(Exception? __exception, object? __state)
    {
        if (__exception == null || __state is not Proof proof) return __exception;
        Fail(proof.Scope); return Missing();
    }
}
