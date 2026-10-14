using System.Reflection;
using System.Security.Cryptography;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;
using MediaBrowser.Model.MediaInfo;
using Access = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Access;

namespace Emby.YouTubePlugin;

// First audited service families only. Lists, streams, Sync and other DTOs
// require their own contracts; this is not the universal access boundary.
internal static class PersonalYouTubeServiceReferenceGate
{
    private const string Owner = "emby.youtubeplugin.personal-service-reference";
    private static readonly object Gate = new();
    private static readonly string[] DtoNames = {
        "Emby.Api.UserLibrary.GetItem", "Emby.Api.Library.GetDownload",
        "Emby.Server.MediaEncoding.Api.GetPlaybackInfo", "Emby.Server.MediaEncoding.Api.GetPostedPlaybackInfo",
        "Emby.Server.MediaEncoding.Api.MarkPlayedItem", "Emby.Server.MediaEncoding.Api.MarkUnplayedItem",
        "Emby.Api.UserLibrary.MarkFavoriteItem", "Emby.Api.UserLibrary.UnmarkFavoriteItem",
        "Emby.Api.UserLibrary.UpdateUserItemRating", "Emby.Api.UserLibrary.DeleteUserItemRating",
        "Emby.Server.MediaEncoding.Api.Progressive.GetVideoStream",
        "Emby.Api.Images.GetItemImage", "Emby.Api.Subtitles.GetSubtitle",
        "Emby.Api.UserLibrary.GetGenre", "Emby.Api.UserLibrary.GetStudio", "Emby.Api.Images.GetItemByNameImage",
        "Emby.Api.UserLibrary.ReportItemsSearched", "Emby.Server.MediaEncoding.Api.UpdateUserData"
    };
    private static Dictionary<Type, PropertyInfo> _targets = new();
    private static PersonalYouTubeNativeAccess? _access;
    private static IAuthorizationContext? _authorization;
    private static string? _directory;
    private static IHttpResultFactory? _results;
    private sealed record RequestContext(User User, string Reference, IDisposable Lease, bool ProtectWriter, IRequest Request, Func<bool> Allowed, PersonalYouTubeStaticSourceGate.Scope? SourceScope, PersonalYouTubeAssetSourceGate.Scope? AssetScope);
    private static MethodInfo? _native;
    private static Type? _harmony;
    private static long _checked, _denied;
    private static string _lastResponseContract = "";
    internal sealed record State(bool Installed, string Error, int AuditedDtoCount, long Checked, long Denied, string LastResponseContract = "", PersonalYouTubeStaticSourceGate.State? StaticSources = null, PersonalYouTubeAssetSourceGate.State? AssetSources = null);
    private static State _state = new(false, "NotInitialized", 0, 0, 0);
    internal static State Snapshot()
    {
        lock (Gate)
        {
            var state = _state;
            if (state.Installed)
            {
                try { if (!HasPrefix() || !PersonalYouTubeStaticSourceGate.Snapshot().Installed || !PersonalYouTubeAssetSourceGate.Snapshot().Installed) state = state with { Installed = false, Error = "PatchLost" }; }
                catch (Exception) { state = state with { Installed = false, Error = "PatchVerificationFailed" }; }
            }
            return state with { Checked = Interlocked.Read(ref _checked), Denied = Interlocked.Read(ref _denied), LastResponseContract = Volatile.Read(ref _lastResponseContract), StaticSources = PersonalYouTubeStaticSourceGate.Snapshot(), AssetSources = PersonalYouTubeAssetSourceGate.Snapshot() };
        }
    }
    internal static State Install(IHttpServer server, ILibraryManager library, IAuthorizationContext authorization, string directory, IHttpResultFactory results)
    {
        lock (Gate)
        {
            if (_state.Installed) return Snapshot();
            try
            {
                var controller = server.GetType().Assembly.GetType("Emby.Server.Implementations.Services.ServiceController", true)!;
                var method = controller.GetMethod("Execute", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                    null, new[] { server.GetType(), typeof(object), typeof(IRequest), typeof(Type) }, null);
                if (server.GetType().FullName != "Emby.Server.Implementations.HttpServer.HttpListenerHost"
                    || method?.ReturnType != typeof(Task<object>) || method.GetMethodBody()?.GetILAsByteArray() is not byte[] bytes
                    || Convert.ToHexString(SHA256.HashData(bytes)) != "8BA7FF537CD85A04E017952B69ED59468D65F557CCC3D62ACB14CBE24EF4F2CA")
                    return _state = new(false, "UnsupportedServiceContract", 0, 0, 0);
                if (!PersonalYouTubeNativeAccess.StaticVideoSourceContractVerified())
                    return _state = new(false, "UnsupportedVideoSourceContract", 0, 0, 0);
                if (!PersonalYouTubeStaticSourceGate.Install(results).Installed)
                    return _state = new(false, "UnsupportedStaticFactoryContract", 0, 0, 0);
                if (!PersonalYouTubeAssetSourceGate.Install().Installed)
                    return _state = new(false, "UnsupportedAssetProducerContract", 0, 0, 0);
                var targets = new Dictionary<Type, PropertyInfo>();
                foreach (var name in DtoNames)
                {
                    var dto = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType(name)).Single(type => type != null)!;
                    var report = name == "Emby.Api.UserLibrary.ReportItemsSearched";
                    var field = report ? "Ids" : name == "Emby.Server.MediaEncoding.Api.UpdateUserData" ? "ItemId" : name is "Emby.Api.UserLibrary.GetGenre" or "Emby.Api.UserLibrary.GetStudio" or "Emby.Api.Images.GetItemByNameImage" ? "Name" : "Id";
                    var id = dto.GetProperty(field, BindingFlags.Instance | BindingFlags.Public);
                    if (id?.PropertyType != (report ? typeof(string[]) : typeof(string)) || id.GetMethod == null || id.GetIndexParameters().Length != 0)
                        return _state = new(false, "UnsupportedItemDto", 0, 0, 0);
                    if(report)
                    {
                        var native = dto.Assembly.GetType("Emby.Api.UserLibrary.UserLibraryService", true)!.GetMethod("Post", new[] { dto })!;
                        if(!id.CanWrite || dto.GetProperty("UserId")?.PropertyType != typeof(string) || dto.GetProperty("UserId")?.CanWrite != true
                            || dto.GetProperty("WasSearched")?.PropertyType != typeof(bool) || native.ReturnType != typeof(void)
                            || Convert.ToHexString(SHA256.HashData(native.GetMethodBody()!.GetILAsByteArray()!)) != "DB1EC783D88823724C2D93D300DEFB0C40E76C107749F9CF1DC10E81478D4AF3")
                            return _state = new(false, "UnsupportedSearchReportDto", 0, 0, 0);
                    }
                    if(name == "Emby.Server.MediaEncoding.Api.UpdateUserData")
                    {
                        var native = dto.Assembly.GetType("Emby.Server.MediaEncoding.Api.PlaystateService", true)!.GetMethod("Post", new[] { dto })!;
                        if(dto.GetProperty("UserId")?.PropertyType != typeof(string) || native.ReturnType != typeof(void)
                            || Convert.ToHexString(SHA256.HashData(native.GetMethodBody()!.GetILAsByteArray()!)) != "4125023F4E13D0805D20F0DB56567B920889850F900FDFA5EAAD7FEA9F68B6B4")
                            return _state = new(false, "UnsupportedUserDataDto", 0, 0, 0);
                    }
                    if(field == "Name" && name != "Emby.Api.Images.GetItemByNameImage" && (dto.GetProperty("UserId")?.PropertyType != typeof(Guid)
                        || dto.GetProperty("UserId")?.CanWrite != true))
                        return _state = new(false, "UnsupportedMetadataSubjectDto", 0, 0, 0);
                    if(name == "Emby.Api.Images.GetItemByNameImage" && (dto.GetProperty("Index")?.PropertyType != typeof(int)
                        || dto.GetProperty("Type")?.PropertyType != typeof(MediaBrowser.Model.Entities.ImageType)))
                        return _state = new(false, "UnsupportedNamedImageDto", 0, 0, 0);
                    targets.Add(dto, id);
                    if (name == "Emby.Server.MediaEncoding.Api.Progressive.GetVideoStream"
                        && (dto.GetProperty("Static")?.PropertyType != typeof(bool)
                            || dto.GetProperty("StreamFileName")?.PropertyType != typeof(string)
                            || dto.GetProperty("MediaSourceId")?.PropertyType != typeof(string)
                            || dto.GetProperty("LiveStreamId")?.PropertyType != typeof(string)))
                        return _state = new(false, "UnsupportedVideoStreamDto", 0, 0, 0);
                    if (name is "Emby.Api.Images.GetItemImage" or "Emby.Api.Subtitles.GetSubtitle"
                        && dto.GetProperty("MediaSourceId")?.PropertyType != typeof(string))
                        return _state = new(false, "UnsupportedAssetSourceDto", 0, 0, 0);
                }
                _access = new(directory, library); _authorization = authorization; _targets = targets; _directory = directory; _results = results;
                var assembly = EmbeddedDependencyLoader.LoadHarmonyAssembly()!;
                _harmony = assembly.GetType("HarmonyLib.Harmony", true)!;
                var methodType = assembly.GetType("HarmonyLib.HarmonyMethod", true)!;
                var prefix = Activator.CreateInstance(methodType, typeof(PersonalYouTubeServiceReferenceGate)
                    .GetMethod(nameof(BeforeExecute), BindingFlags.Static | BindingFlags.NonPublic)!)!;
                methodType.GetField("priority")!.SetValue(prefix, 800);
                object PatchMethod(string name)
                {
                    var patch = Activator.CreateInstance(methodType, typeof(PersonalYouTubeServiceReferenceGate).GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic)!)!;
                    methodType.GetField("priority")!.SetValue(patch, 800); return patch;
                }
                var instance = Activator.CreateInstance(_harmony, Owner)!;
                _harmony.GetMethods().Single(value => value.Name == "Patch" && value.GetParameters().Length == 5)
                    .Invoke(instance, new object?[] { method, prefix, PatchMethod(nameof(AfterExecute)), null, PatchMethod(nameof(ExecuteFailed)) });
                _native = method;
                if (!HasPrefix()) throw new InvalidOperationException();
                _state = new(true, "", targets.Count, 0, 0);
            }
            catch (Exception) { _state = new(false, "PatchVerificationFailed", 0, 0, 0); }
            return Snapshot();
        }
    }
    private static bool HasPrefix()
    {
        var info = _harmony!.GetMethod("GetPatchInfo", BindingFlags.Static | BindingFlags.Public)!.Invoke(null, new object?[] { _native });
        bool Has(string field, string name)
        {
            var entries = info?.GetType().GetField(field)!.GetValue(info) as System.Collections.IEnumerable;
            return entries != null && entries.Cast<object>().Any(entry => (string?)entry.GetType().GetField("owner")!.GetValue(entry) == Owner
                && (MethodInfo?)entry.GetType().GetProperty("PatchMethod")!.GetValue(entry)
                    == typeof(PersonalYouTubeServiceReferenceGate).GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic));
        }
        return Has("Prefixes", nameof(BeforeExecute)) && Has("Postfixes", nameof(AfterExecute)) && Has("Finalizers", nameof(ExecuteFailed));
    }
    private static bool BeforeExecute(object __1, IRequest __2, ref Task<object> __result, out object? __state)
    {
        __state = null;
        if (!_targets.TryGetValue(__1.GetType(), out var target)) return true;
        Interlocked.Increment(ref _checked);
        IDisposable? lease = null;
        PersonalYouTubeStaticSourceGate.Scope? sourceScope = null;
        PersonalYouTubeAssetSourceGate.Scope? assetScope = null;
        try
        {
            var user = _authorization!.GetAuthorizationInfo(__2).User;
            if(__1.GetType().FullName == "Emby.Api.UserLibrary.ReportItemsSearched")
            {
                if(user == null || user.Policy.IsDisabled) throw new ResourceNotFoundException("Item not found.");
                var ids = ((string[]?)target.GetValue(__1) ?? Array.Empty<string>()).ToArray();
                if(ids.Length > 2048 || ids.Any(id => string.IsNullOrWhiteSpace(id)))
                    throw new ResourceNotFoundException("Item not found.");
                var subjectProperty = __1.GetType().GetProperty("UserId")!;
                var claim = (string?)subjectProperty.GetValue(__1);
                if(!string.IsNullOrEmpty(claim) && (!Guid.TryParse(claim, out var reportSubject) || reportSubject != user.Id))
                    throw new ResourceNotFoundException("Item not found.");
                var reportAccess = _access!;
                bool ReportAllowed() => !user.Policy.IsDisabled && ids.All(id => reportAccess.ReferenceExists(id)
                    && reportAccess.DecideReference(id, user) != Access.Denied);
                // Validate the entire frame before native Post can mutate its
                // first item. Repeat under the same owner lease as deletion.
                if(!ReportAllowed()) throw new ResourceNotFoundException("Item not found.");
                lease = PersonalYouTubeTransferLease.Enter(_directory!, user.Id);
                if(!ReportAllowed()) throw new ResourceNotFoundException("Item not found.");
                subjectProperty.SetValue(__1, user.Id.ToString("N")); target.SetValue(__1, ids);
                __state = new RequestContext(user, "", lease, false, __2, ReportAllowed, null, null);
                return true;
            }
            var reference = (string?)target.GetValue(__1) ?? "";
            var namedImage = __1.GetType().FullName == "Emby.Api.Images.GetItemByNameImage";
            var metadataDto = __1.GetType().FullName!;
            if(namedImage)
            {
                var segments = __2.PathInfo.Trim('/').Split('/');
                var offset = segments[0].Equals("emby", StringComparison.OrdinalIgnoreCase) ? 1 : 0;
                if(segments.Length <= offset) throw new ResourceNotFoundException("Item not found.");
                var category = segments[offset];
                if(category.Equals("Genres", StringComparison.OrdinalIgnoreCase)) metadataDto = "Emby.Api.UserLibrary.GetGenre";
                else if(category.Equals("Studios", StringComparison.OrdinalIgnoreCase)) metadataDto = "Emby.Api.UserLibrary.GetStudio";
                else return true; // Other index types need their own source contracts.
            }
            if(target.Name == "Name") reference = _access!.ResolveMetadataName(metadataDto, reference);
            var decision = _access!.DecideReference(reference, user);
            if (decision == Access.Unknown) return true;
            if (decision == Access.Denied) throw new ResourceNotFoundException("Item not found.");
            if(target.Name == "Name" && !namedImage && user != null && __1.GetType().GetProperty("UserId")!.GetValue(__1) is Guid namedSubject
                && namedSubject == Guid.Empty)
                __1.GetType().GetProperty("UserId")!.SetValue(__1, user.Id);
            // Native services may use the DTO UserId for history mutations.
            // For private content, do not let an allowed owner target another
            // account's native user state through that parameter.
            var supplied = __1.GetType().GetProperty("UserId")?.GetValue(__1)?.ToString();
            if (!string.IsNullOrEmpty(supplied) && (!Guid.TryParse(supplied, out var subject) || user == null || subject != user.Id))
                throw new ResourceNotFoundException("Item not found.");
            if (user == null) throw new ResourceNotFoundException("Item not found.");
            lease = PersonalYouTubeTransferLease.Enter(_directory!, user.Id);
            var video = __1.GetType().FullName == "Emby.Server.MediaEncoding.Api.Progressive.GetVideoStream";
            var asset = namedImage || __1.GetType().FullName is "Emby.Api.Images.GetItemImage" or "Emby.Api.Subtitles.GetSubtitle";
            var isStatic = video && ((bool)__1.GetType().GetProperty("Static")!.GetValue(__1)!
                || PersonalYouTubeNativeAccess.IsOriginalStaticStream((string?)__1.GetType().GetProperty("StreamFileName")!.GetValue(__1)));
            var sourceId = (video || asset) && !namedImage ? (string?)__1.GetType().GetProperty("MediaSourceId")!.GetValue(__1) ?? "" : "";
            var liveStreamId = video ? (string?)__1.GetType().GetProperty("LiveStreamId")!.GetValue(__1) ?? "" : "";
            var access = _access!;
            bool Allowed() => (video || (asset && !string.IsNullOrEmpty(sourceId))
                ? access.DecideStaticVideoSource(reference, user, asset || isStatic, sourceId, liveStreamId)
                : access.DecideReference(reference, user)) == Access.Allowed;
            if (!Allowed()) throw new ResourceNotFoundException("Item not found.");
            if (video) sourceScope = PersonalYouTubeStaticSourceGate.Begin(__2, path => Allowed() && access.StaticVideoPathAllowed(reference, user, sourceId, path));
            if (asset)
            {
                var image = namedImage || __1.GetType().FullName == "Emby.Api.Images.GetItemImage";
                var type = image ? (MediaBrowser.Model.Entities.ImageType)__1.GetType().GetProperty("Type")!.GetValue(__1)! : default;
                var index = (int)__1.GetType().GetProperty("Index")!.GetValue(__1)!;
                assetScope = PersonalYouTubeAssetSourceGate.Begin(image, type, index,
                    (id, path) => Allowed() && access.AssetImageInputAllowed(reference, user, type, index, id, path),
                    (input, stream) => Allowed() && access.AssetSubtitleInputAllowed(reference, user, sourceId, index, input, stream),
                    path => Allowed() && access.AssetDirectPathAllowed(reference, user, sourceId, image, type, index, path));
                var captured = assetScope;
                sourceScope = PersonalYouTubeStaticSourceGate.Begin(__2, path => Allowed() && captured.AllowedPath(path));
            }
            var protectWriter = __1.GetType().FullName is "Emby.Api.UserLibrary.GetItem" or "Emby.Api.UserLibrary.GetGenre" or "Emby.Api.UserLibrary.GetStudio"
                or "Emby.Api.Library.GetDownload"
                or "Emby.Server.MediaEncoding.Api.GetPlaybackInfo" or "Emby.Server.MediaEncoding.Api.GetPostedPlaybackInfo"
                or "Emby.Server.MediaEncoding.Api.Progressive.GetVideoStream"
                or "Emby.Api.Images.GetItemImage" or "Emby.Api.Subtitles.GetSubtitle" or "Emby.Api.Images.GetItemByNameImage";
            __state = new RequestContext(user, reference, lease, protectWriter, __2, Allowed, sourceScope, assetScope);
            return true;
        }
        catch (Exception)
        {
            PersonalYouTubeStaticSourceGate.End(sourceScope);
            PersonalYouTubeAssetSourceGate.End(assetScope);
            lease?.Dispose();
            Interlocked.Increment(ref _denied);
            __result = Task.FromException<object>(new ResourceNotFoundException("Item not found."));
            return false;
        }
    }
    private static void AfterExecute(ref Task<object> __result, object? __state)
    {
        if (__state is RequestContext context)
        {
            PersonalYouTubeAssetSourceGate.Restore(context.AssetScope);
            __result = Finish(__result, context);
        }
    }
    private static async Task<object> Finish(Task<object> task, RequestContext context)
    {
        object? result = null;
        try
        {
            result = await task.ConfigureAwait(false);
            if (context.ProtectWriter)
            {
                Volatile.Write(ref _lastResponseContract, result?.GetType().FullName ?? "null");
                if (result is PlaybackInfoResponse playback) result = _results!.GetResult(context.Request, playback, new Dictionary<string, string>());
                if (result == null) throw new ResourceNotFoundException("Item not found.");
                if (!context.Allowed()) throw new ResourceNotFoundException("Item not found.");
                var sourceAllowed = context.SourceScope == null ? null : PersonalYouTubeStaticSourceGate.ProtectResult(context.SourceScope, result);
                PersonalYouTubeItemListGate.RegisterWriter(result, context.User.Id, () => context.Allowed() && (sourceAllowed?.Invoke() ?? true));
            }
            return result;
        }
        catch (Exception) when (context.ProtectWriter)
        {
            PersonalYouTubeStaticSourceGate.Abort(context.SourceScope);
            PersonalYouTubeItemListGate.DiscardPrivateResult(result, context.Request.Response);
            throw new ResourceNotFoundException("Item not found.");
        }
        finally { PersonalYouTubeStaticSourceGate.End(context.SourceScope); PersonalYouTubeAssetSourceGate.End(context.AssetScope); context.Lease.Dispose(); }
    }
    private static Exception? ExecuteFailed(Exception? __exception, object? __state)
    {
        if (__exception != null && __state is RequestContext context) { PersonalYouTubeStaticSourceGate.End(context.SourceScope); PersonalYouTubeAssetSourceGate.End(context.AssetScope); context.Lease.Dispose(); }
        return __exception;
    }
}
