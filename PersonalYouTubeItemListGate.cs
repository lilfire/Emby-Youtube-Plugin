using System.Collections.Concurrent;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Controller.Security;
using MediaBrowser.Model.Services;
using MediaBrowser.Model.IO;
using MediaBrowser.Model.Dto;
using MediaBrowser.Model.Querying;
using MediaBrowser.Model.Entities;
using Access = Emby.YouTubePlugin.PersonalYouTubeNativeBindings.Access;

namespace Emby.YouTubePlugin;

// Audited item/discovery list families and shared registered-result write boundary.
// Lists exclude private items before native counts/paging and refresh denials
// at result/write entry. Direct-reference services supply their own predicate.
// Not a universal/live byte-revocation proof.
internal static class PersonalYouTubeItemListGate
{
    private const string Owner = "emby.youtubeplugin.personal-item-list";
    private static readonly object Gate = new();
    private static readonly AsyncLocal<Scope?> Current = new();
    private static readonly AsyncLocal<int> InternalScan = new();
    private sealed record WriterContext(Guid Owner, Func<bool> Allowed, Func<IDisposable>? SourceLease, Func<bool>? FinalSourceCheck);
    private static readonly ConditionalWeakTable<object, WriterContext> Writers = new();
    private sealed class Scope
    {
        // Null only for a verified server API key: no account, so every
        // personal item is denied exactly as for Guid.Empty ownership.
        internal readonly User? User;
        internal readonly string? ServiceToken;
        internal readonly string Dto;
        internal readonly long[] Forbidden;
        internal readonly PersonalYouTubeQueryCoverage Coverage;
        internal readonly IRequest Request;
        internal readonly bool Suggestions;
        internal readonly bool Tags;
        internal readonly bool Libraries;
        internal Func<bool>? TagSourceStable;
        internal Func<bool, bool>? SourceStable;
        internal long? SourceVersion;
        // Denied Genre/Studio/Tag index IDs (a subset of Forbidden) and the
        // inventory's Tag index records for the Tags route.
        internal HashSet<long> ForbiddenMetadata = new();
        internal BaseItem[] TagItems = Array.Empty<BaseItem>();
        internal Dictionary<long, long> MetadataWitnesses = new();
        internal volatile bool Active = true;
        internal Scope(User? user, string? serviceToken, string dto, long[] forbidden, IRequest request, bool suggestions, bool tags = false, bool libraries = false) { User = user; ServiceToken = serviceToken; Dto = dto; Forbidden = forbidden; Coverage = new(forbidden); Request = request; Suggestions = suggestions; Tags = tags; Libraries = libraries; }
    }
    private sealed record Saved(Scope? Previous, Scope Created);
    private static ILibraryManager? _library;
    private static PersonalYouTubeNativeAccess? _access;
    private static IAuthorizationContext? _authorization;
    private static IAuthenticationRepository? _authentications;
    // Lease/writer owner for server-API-key results. Never a native user ID.
    private static readonly Guid ServiceKeyOwner = new("7c0e2a54-5f3b-4d2e-9b61-0c4a8f1d2e93");
    private static readonly ConcurrentDictionary<string, long> DiagnosticTimes = new();
    private static IHttpResultFactory? _results;
    private static PropertyInfo? _countsParent;
    private static Type? _tagResultType;
    private static MethodInfo? _tagFactory;
    private static Dictionary<Type, PropertyInfo?> _subjectDtos = new();
    private static string? _directory;
    private static bool _installed;
    private static Func<bool>? _verifyCurrent;
    private static FieldInfo? _streamContent, _fileContent;
    private static FieldInfo? _nativeResponse;
    private static PropertyInfo? _nativeHeaders;
    private static MethodInfo? _clearNativeHeaders;
    private static string _error = "NotInitialized";
    private static long _requests, _queries, _writes, _writesDenied, _viewSources, _countParentsDenied;
    internal sealed record State(bool Installed, string Error, long Requests, long Queries, long Writes, long WritesDenied, int AuditedDtoCount = 0, long ViewSources = 0, long CountParentsDenied = 0,
        bool SourceBarrierInstalled = false, long SourceInventoryBuilds = 0, long SourceInventoryHits = 0);
    internal static State Snapshot()
    {
        lock (Gate)
        {
            var installed = _installed; var error = _error;
            if (installed)
            {
                try { if (_verifyCurrent?.Invoke() != true) { installed = false; error = "PatchLost"; } }
                catch (Exception) { installed = false; error = "PatchVerificationFailed"; }
            }
            return new(installed, error, Interlocked.Read(ref _requests), Interlocked.Read(ref _queries), Interlocked.Read(ref _writes), Interlocked.Read(ref _writesDenied), installed ? _subjectDtos.Count : 0, Interlocked.Read(ref _viewSources), Interlocked.Read(ref _countParentsDenied),
                PersonalYouTubeNativeSourceBarrier.Snapshot().Installed, _access?.InventoryBuilds ?? 0, _access?.InventoryHits ?? 0);
        }
    }
    internal static State Install(IHttpServer server, ILibraryManager library, IAuthorizationContext authorization, string directory, IHttpResultFactory results, IAuthenticationRepository authentications)
    {
        lock (Gate)
        {
            if (_installed) return Snapshot();
            try
            {
                var controller = server.GetType().Assembly.GetType("Emby.Server.Implementations.Services.ServiceController", true)!;
                var service = controller.GetMethod("Execute", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                    null, new[] { server.GetType(), typeof(object), typeof(IRequest), typeof(Type) }, null)!;
                var writerType = server.GetType().Assembly.GetType("Emby.Server.Implementations.HttpServer.StreamWriter", true)!;
                var write = writerType.GetMethod("WriteToAsync", new[] { typeof(IResponse), typeof(CancellationToken) })!;
                var fileType = server.GetType().Assembly.GetType("Emby.Server.Implementations.HttpServer.FileWriter", true)!;
                var fileWrite = fileType.GetMethod("WriteToAsync", new[] { typeof(IResponse), typeof(CancellationToken) })!;
                var emptyType = server.GetType().Assembly.GetType("Emby.Server.Implementations.Services.EmptyHttpResult", true)!;
                var emptyWrite = emptyType.GetMethod("WriteToAsync", new[] { typeof(IResponse), typeof(CancellationToken) })!;
                var writes = new[] { write, fileWrite, emptyWrite };
                _streamContent = writerType.GetField("SourceStream", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                _fileContent = fileType.GetField("_initialContent", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                var responseType = AppDomain.CurrentDomain.GetAssemblies()
                    .Single(loaded => loaded.GetName().Name == "EmbyServer")
                    .GetType("Emby.Server.Implementations.HttpServer.KestrelHost.NetCoreResponse", true)!;
                _nativeResponse = responseType.GetField("response", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                _nativeHeaders = _nativeResponse?.FieldType.GetProperty("Headers");
                _clearNativeHeaders = _nativeHeaders?.PropertyType.GetInterfaces()
                    .Single(type => type.IsGenericType && type.GetGenericTypeDefinition() == typeof(ICollection<>)).GetMethod("Clear");
                string Hash(MethodInfo method) => Convert.ToHexString(SHA256.HashData(method.GetMethodBody()!.GetILAsByteArray()!));
                var expected = new HashSet<string> {
                    "4E4FC9A569C68970A8616F1B7CADBB564C18709DBE95748B8B08FEC0F56D3FFB", "FD5A95C974B2E735682142BF65C1C827BA95A79D29B9B38E94B89C6FCE81ECBE",
                    "9743414BD403372893AF90D309A035DDC7DE0E7BD2D30970078A4BBC1D0A3EAE", "105EDD92145B8A4A3883ECC833EB59D50EA418FD03C8728C120A075DDF32251D",
                    "251E983E97E666ABB59FA35C2B18E7F1C6650D1447AB1724B361FA5FEB0BD752", "8E64EC37B04F6D9712A5EB68FF0F2C281C3CC96C141BAA2491303954306F069E",
                    "9F29F152CDC7F80F51CF66B059E0B4CF81168604DC5E7DFAB200193A6B3277A7", "828A667BDD6F3D07D5799552211F3C332D5E1EE2D4E4F91CF6FE295588CD4D5A",
                    "2B8D25A2AC5D86A3C8E3D43745EB7BC717160FFE0D7B2989C1239549284E3C7E", "9DA0A1592BD855346743AF16D75D077C915D6C86BD1B83E0E49D84F8343CBF67",
                    "DEC60207871102AFD013D71872EECEA2959D3E42BC3B7A1465A8FF10081943EC", "6699BD63996CAEF1D99D4CCBD046C270A9E4B3AFE458795F7AD317B77DEF1E7D"
                };
                var methods = library.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                    .Where(method => method.Name is "GetItemList" or "GetItemIds" or "GetItemsResult" or "GetGenres" or "GetAllGenres" or "GetStudios" or "GetTags")
                    .Where(method => method.GetParameters().FirstOrDefault()?.ParameterType == typeof(InternalItemsQuery)).ToArray();
                if (server.GetType().FullName != "Emby.Server.Implementations.HttpServer.HttpListenerHost"
                    || library.GetType().FullName != "Emby.Server.Implementations.Library.LibraryManager"
                    || Hash(service) != "8BA7FF537CD85A04E017952B69ED59468D65F557CCC3D62ACB14CBE24EF4F2CA"
                    || write.ReturnType != typeof(Task) || Hash(write) != "6958BC6F05CD86EC1762FAF3AC2D12967D5C92C413A02E9A111A3374A9BA1C35"
                    || fileWrite.ReturnType != typeof(Task) || Hash(fileWrite) != "C727A5F81B37C15D6DFAB13492CCA85C01F8055AD7E4828C7FF0EDA9AE875F8C"
                    || emptyWrite.ReturnType != typeof(Task) || Hash(emptyWrite) != "78E5066A9C7F4D3FAB5C9C6A7E275F7048B50F4A8713D28ADFC851183FA5F454"
                    || _streamContent?.FieldType != typeof(StreamHandler) || _fileContent?.FieldType != typeof(StreamHandler)
                    || _nativeResponse?.FieldType.FullName != "Microsoft.AspNetCore.Http.HttpResponse"
                    || _nativeHeaders?.PropertyType.FullName != "Microsoft.AspNetCore.Http.IHeaderDictionary" || _clearNativeHeaders == null
                    || methods.Length != expected.Count || methods.Select(Hash).ToHashSet().SetEquals(expected) == false)
                    throw new InvalidOperationException();
                var subjects = new Dictionary<Type, PropertyInfo?>();
                foreach(var name in new[] { "Emby.Api.UserLibrary.GetItems", "Emby.Api.UserLibrary.GetLatestMedia", "Emby.Api.UserLibrary.GetUserViews", "Emby.Api.GetSuggestedItems", "Emby.Api.Library.GetItemCounts", "Emby.Api.UserLibrary.GetGenres", "Emby.Api.UserLibrary.GetStudios", "Emby.Api.UserLibrary.GetTags", "Emby.Api.Library.GetVirtualFoldersResult" })
                {
                    var dto = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType(name)).Single(type => type != null)!;
                    var subject = dto.GetProperty("UserId")!;
                    var expectedSubject = name is "Emby.Api.UserLibrary.GetItems" or "Emby.Api.GetSuggestedItems" or "Emby.Api.UserLibrary.GetGenres" or "Emby.Api.UserLibrary.GetStudios" or "Emby.Api.UserLibrary.GetTags" ? typeof(Guid) : typeof(string);
                    if(subject.PropertyType != expectedSubject || !subject.CanWrite) throw new InvalidOperationException();
                    subjects.Add(dto, subject);
                }
                var libraryQueryDto = subjects.Keys.Single(type => type.FullName == "Emby.Api.Library.GetVirtualFoldersResult");
                var libraryListDto = libraryQueryDto.Assembly.GetType("Emby.Api.Library.GetVirtualFolders", true)!;
                subjects.Add(libraryListDto, null);
                var libraryService = libraryQueryDto.Assembly.GetType("Emby.Api.Library.LibraryStructureService", true)!;
                if(Hash(libraryService.GetMethod("Get", new[] { libraryQueryDto })!) != "1CB16F47752B4418AF677DC394DE78011FDB0E551F7BCA76BAD7924DB30BD2A0"
                    || Hash(libraryService.GetMethod("Get", new[] { libraryListDto })!) != "A130FD218887AD79D44F17B0D5E20D13EF38CB6DF187C44B2549DAF08EE0DFA7") throw new InvalidOperationException();
                var librarySource = library.GetType().GetMethod("GetVirtualFolders", new[] { typeof(User), typeof(bool), typeof(CancellationToken) })!;
                if(librarySource.ReturnType != typeof(List<VirtualFolderInfo>)
                    || Hash(librarySource) != "E13F2F1B97A829D9C1C54902741CFEE96AAC04C8E08FFC598554614DAF8E1EAB") throw new InvalidOperationException();
                _subjectDtos = subjects;
                var tagItem = subjects.Keys.Single(type => type.FullName == "Emby.Api.UserLibrary.GetTags").Assembly.GetType("Emby.Api.UserLibrary.TagItem", true)!;
                if(tagItem.GetProperty("Name")?.PropertyType != typeof(string)) throw new InvalidOperationException();
                _tagResultType = typeof(QueryResult<>).MakeGenericType(tagItem);
                _tagFactory = typeof(IHttpResultFactory).GetMethods().Single(method => method.Name == "GetResult"
                    && method.IsGenericMethodDefinition && method.GetParameters().Length == 3).MakeGenericMethod(_tagResultType);
                var repository = library.GetType().GetProperty("ItemRepository", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)!.GetValue(library)!;
                var nativeTags = repository.GetType().GetMethod("GetTags", new[] { typeof(InternalItemsQuery), typeof(CancellationToken) })!;
                if(repository.GetType().FullName != "Emby.Server.Implementations.Data.SqliteItemRepository"
                    || Hash(nativeTags) != "10E642254294B22BEC2B7D4F69954DE5BF39582D9D20806404D411C2D1F18334")
                    throw new InvalidOperationException();
                var countsDto = subjects.Keys.Single(type => type.FullName == "Emby.Api.Library.GetItemCounts");
                _countsParent = countsDto.GetProperty("ParentId");
                var countsService = countsDto.Assembly.GetType("Emby.Api.Library.LibraryService", true)!;
                var countsGet = countsService.GetMethod("Get", new[] { countsDto })!;
                var countsSource = countsService.GetMethods(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public)
                    .Single(method => method.Name == "GetCount");
                if(_countsParent?.PropertyType != typeof(string) || !_countsParent.CanRead
                    || Hash(countsGet) != "729899A945BB781FF40674A0C908941941FB4D23A646F4BFFC63EAA86FF2B4C7"
                    || Hash(countsSource) != "697454884000CCDA0FBFDEBF3FB0129B139C73E6CD481C135F977028C4A7BAD4")
                    throw new InvalidOperationException();
                var viewsType = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Implementations.Library.UserViewManager")).Single(type => type != null)!;
                var views = viewsType.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                    .Single(method => method.Name == "GetUserViews" && method.GetParameters().Length == 5);
                if(views.ReturnType != typeof(Folder[]) || !views.GetParameters().Select(parameter => parameter.ParameterType.FullName).SequenceEqual(new[] {
                    "MediaBrowser.Model.Library.UserViewQuery", typeof(User).FullName, typeof(Folder[]).FullName, "MediaBrowser.Model.Data.IDataContext", typeof(CancellationToken).FullName })
                    || Hash(views) != "BC63BE59DFC9A0DB61A41FC202EF808C878B13449CA40B825D2F1981D8159CF9") throw new InvalidOperationException();
                _library = library; _access = new(directory, library); _authorization = authorization; _authentications = authentications; _directory = directory; _results = results;
                PersonalYouTubeNativeSourceBarrier.Install(library);
                var assembly = EmbeddedDependencyLoader.LoadHarmonyAssembly()!;
                var harmonyType = assembly.GetType("HarmonyLib.Harmony", true)!;
                var methodType = assembly.GetType("HarmonyLib.HarmonyMethod", true)!;
                var harmony = Activator.CreateInstance(harmonyType, Owner)!;
                var patch = harmonyType.GetMethods().Single(method => method.Name == "Patch" && method.GetParameters().Length == 5);
                object PatchMethod(string name) {
                    var result = Activator.CreateInstance(methodType, typeof(PersonalYouTubeItemListGate).GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic)!)!;
                    methodType.GetField("priority")!.SetValue(result, 800); return result;
                }
                foreach (var method in methods) patch.Invoke(harmony, new object?[] { method, PatchMethod(nameof(BeforeQuery)), null, null, null });
                patch.Invoke(harmony, new object?[] { views, PatchMethod(nameof(BeforeViewSources)), null, null, null });
                patch.Invoke(harmony, new object?[] { librarySource, PatchMethod(nameof(BeforeLibrarySources)), PatchMethod(nameof(AfterLibrarySources)), null, null });
                foreach (var nativeWrite in writes)
                    patch.Invoke(harmony, new object?[] { nativeWrite, PatchMethod(nameof(BeforeWrite)), PatchMethod(nameof(AfterWrite)), null, PatchMethod(nameof(WriteFailed)) });
                patch.Invoke(harmony, new object?[] { service, PatchMethod(nameof(BeforeService)), PatchMethod(nameof(AfterService)), null, PatchMethod(nameof(ServiceFailed)) });
                bool Verified(MethodInfo original, string field, string name) {
                    var info = harmonyType.GetMethod("GetPatchInfo", BindingFlags.Static | BindingFlags.Public)!.Invoke(null, new object[] { original });
                    var entries = info?.GetType().GetField(field)!.GetValue(info) as System.Collections.IEnumerable;
                    return entries != null && entries.Cast<object>().Any(entry => (string?)entry.GetType().GetField("owner")!.GetValue(entry) == Owner
                        && (MethodInfo?)entry.GetType().GetProperty("PatchMethod")!.GetValue(entry)
                            == typeof(PersonalYouTubeItemListGate).GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic));
                }
                if (methods.Any(method => !Verified(method, "Prefixes", nameof(BeforeQuery)))
                    || !Verified(librarySource, "Prefixes", nameof(BeforeLibrarySources)) || !Verified(librarySource, "Postfixes", nameof(AfterLibrarySources))
                    || !Verified(views, "Prefixes", nameof(BeforeViewSources))
                    || writes.Any(nativeWrite => !Verified(nativeWrite, "Prefixes", nameof(BeforeWrite))
                        || !Verified(nativeWrite, "Postfixes", nameof(AfterWrite)) || !Verified(nativeWrite, "Finalizers", nameof(WriteFailed)))
                    || !Verified(service, "Prefixes", nameof(BeforeService)) || !Verified(service, "Postfixes", nameof(AfterService))
                    || !Verified(service, "Finalizers", nameof(ServiceFailed))) throw new InvalidOperationException();
                _verifyCurrent = () => methods.All(method => Verified(method, "Prefixes", nameof(BeforeQuery)))
                    && Verified(librarySource, "Prefixes", nameof(BeforeLibrarySources)) && Verified(librarySource, "Postfixes", nameof(AfterLibrarySources))
                    && Verified(views, "Prefixes", nameof(BeforeViewSources))
                    && writes.All(nativeWrite => Verified(nativeWrite, "Prefixes", nameof(BeforeWrite))
                        && Verified(nativeWrite, "Postfixes", nameof(AfterWrite)) && Verified(nativeWrite, "Finalizers", nameof(WriteFailed)))
                    && Verified(service, "Prefixes", nameof(BeforeService)) && Verified(service, "Postfixes", nameof(AfterService))
                    && Verified(service, "Finalizers", nameof(ServiceFailed));
                _installed = true; _error = "";
            }
            catch (Exception) { _installed = false; _error = "UnverifiedListContract"; }
            return Snapshot();
        }
    }
    private static bool BeforeService(object __1, IRequest __2, ref Task<object> __result, out object? __state)
    {
        __state = null;
        if (!_subjectDtos.TryGetValue(__1.GetType(), out var subject)) return true;
        var dto = __1.GetType().Name;
        var auth = "none"; var phase = "authorize"; var started = Stopwatch.GetTimestamp(); var scanned = -1; var deniedCount = -1;
        try
        {
            var info = _authorization!.GetAuthorizationInfo(__2);
            var user = info.User;
            string? serviceToken = null;
            if (user == null)
            {
                // Null User alone is not proof of a server key: confirm the
                // token is an active, account-less native API key.
                if (!IsVerifiedServerKey(info.Token)) throw new ResourceNotFoundException("Items not found.");
                serviceToken = info.Token; auth = "serverkey";
            }
            else
            {
                auth = "user";
                if (user.Policy.IsDisabled) throw new ResourceNotFoundException("Items not found.");
            }
            var libraries = __1.GetType().FullName is "Emby.Api.Library.GetVirtualFolders" or "Emby.Api.Library.GetVirtualFoldersResult";
            // These are also the server administrator's library-management
            // routes. Keep that inventory available for management/cleanup;
            // ordinary account discovery always uses the authenticated user.
            // A server key has no account and gets the filtered inventory.
            if(user?.Policy.IsAdministrator == true && libraries) return true;
            Interlocked.Increment(ref _requests);
            phase = "counts-parent";
            if(__1.GetType().FullName == "Emby.Api.Library.GetItemCounts"
                && _countsParent!.GetValue(__1) is string parent && !string.IsNullOrWhiteSpace(parent)
                && _access!.DecideReference(parent, user) == Access.Denied)
            {
                Interlocked.Increment(ref _countParentsDenied);
                throw new ResourceNotFoundException("Items not found.");
            }
            phase = "scan";
            var sourceInventory = _access!.ReadSourceInventory();
            BaseItem[] inventory;
            InternalScan.Value++;
            try { inventory = sourceInventory?.Items ?? _library!.GetItemList(new InternalItemsQuery { Recursive = true }); }
            finally { InternalScan.Value--; }
            scanned = inventory.Length;
            var scanMs = ElapsedMs(started);
            phase = "decide";
            // Same per-item rule as PersonalYouTubeNativeAccess.DecideItem, with
            // storage and virtual folders read once for this request.
            var byId = new Dictionary<long, BaseItem>(inventory.Length);
            foreach (var item in inventory) byId.TryAdd(item.InternalId, item);
            var context = sourceInventory == null ? _access!.CreateListContext(user, byId) : _access!.CreateListContext(user, sourceInventory);
            var deniedIds = new HashSet<long>();
            var metadata = new List<BaseItem>();
            if (sourceInventory != null)
            { metadata.AddRange(sourceInventory.Metadata); deniedIds = context.DeniedSourceIds(); }
            else foreach (var item in inventory)
            {
                if (PersonalYouTubeNativeAccess.ListContext.IsMetadata(item)) metadata.Add(item);
                else if (context.DecideOrdinary(item) == Access.Denied) deniedIds.Add(item.InternalId);
            }
            var ordinaryMs = ElapsedMs(started) - scanMs;
            phase = "metadata";
            var witnesses = new Dictionary<long, long>();
            var deniedMetadata = context.DeniedMetadata(metadata, CancellationToken.None, witnesses);
            deniedIds.UnionWith(deniedMetadata);
            var metadataMs = ElapsedMs(started) - scanMs - ordinaryMs;
            var denied = inventory.Select(item => item.InternalId).Where(deniedIds.Contains).Distinct().ToArray();
            deniedCount = denied.Length;
            var scope = new Scope(user, serviceToken, dto, denied, __2, __1.GetType().FullName == "Emby.Api.GetSuggestedItems", __1.GetType().FullName == "Emby.Api.UserLibrary.GetTags", libraries);
            scope.ForbiddenMetadata = deniedMetadata;
            scope.MetadataWitnesses = witnesses;
            scope.SourceStable = _ => context.AuthorityCurrent();
            if (sourceInventory != null)
            {
                scope.SourceStable = readFolders => sourceInventory.Current(_access!, readFolders) && context.AuthorityCurrent();
                scope.SourceVersion = sourceInventory.Version;
            }
            if (!scope.SourceStable(true)) throw new ResourceNotFoundException("Items not found.");
            if(scope.Tags) scope.TagItems = metadata.Where(item => item.GetType().FullName == "MediaBrowser.Controller.Entities.Tag").ToArray();
            __state = new Saved(Current.Value, scope); Current.Value = scope;
            // A server key keeps the request's own subject: native applies its
            // normal key semantics while the exclusions above still apply.
            if(user != null) subject?.SetValue(__1, scope.Libraries ? "" : subject.PropertyType == typeof(Guid) ? (object)user.Id : user.Id.ToString("N"));
            else if(scope.Libraries) subject?.SetValue(__1, "");
            var elapsed = ElapsedMs(started);
            if(elapsed > 1000) Diagnose(dto, "slow-prefix", auth, null, elapsed, scanned, deniedCount,
                FormattableString.Invariant($" scanMs={scanMs:0} ordinaryMs={ordinaryMs:0} metadataMs={metadataMs:0} metadataItems={metadata.Count} metadataQueryMs={context.MetadataQueryMs:0} metadataLinkMs={context.MetadataLinkMs:0} metadataSources={context.MetadataSources} metadataLinkReads={context.MetadataLinkReads}"));
            return true;
        }
        catch (Exception error)
        {
            Diagnose(dto, phase, auth, error, ElapsedMs(started), scanned, deniedCount);
            __result = Task.FromException<object>(new ResourceNotFoundException("Items not found.")); return false;
        }
    }
    private static double ElapsedMs(long started) => (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency;
    private static bool IsVerifiedServerKey(string? token)
    {
        if (string.IsNullOrWhiteSpace(token) || _authentications == null) return false;
        var matches = _authentications.Get(new AuthenticationInfoQuery { AccessToken = token, HasUser = false, IsActive = true })?.Items;
        return matches?.Length == 1 && matches[0].UserId == 0 && matches[0].IsActive
            && string.Equals(matches[0].AccessToken, token, StringComparison.Ordinal);
    }
    // Sanitized, rate-limited diagnostics: route DTO, phase, auth kind,
    // exception type, timing and counts. Never tokens, IDs, names, paths or
    // exception messages. Gate-generated denials are "denied", others "failed".
    private static void Diagnose(string dto, string phase, string auth, Exception? error, double elapsedMs, int scanned = -1, int denied = -1, string timing = "")
    {
        try
        {
            var outcome = error == null ? "info" : error is ResourceNotFoundException ? "denied" : "failed";
            var key = dto + "|" + phase + "|" + auth + "|" + outcome + "|" + error?.GetType().Name;
            var now = Stopwatch.GetTimestamp();
            var last = DiagnosticTimes.GetOrAdd(key, 0);
            if (last != 0 && now - last < Stopwatch.Frequency * 60) return;
            DiagnosticTimes[key] = now;
            YouTubeChannel.LogPublic(FormattableString.Invariant(
                $"[YT] Item-list gate {outcome}: dto={dto} phase={phase} auth={auth} error={error?.GetType().Name ?? "-"} elapsedMs={elapsedMs:0} scanned={scanned} denied={denied}{timing}"));
        }
        catch (Exception) { }
    }
    internal static BaseItem[] NativeScan(ILibraryManager library, InternalItemsQuery query)
    {
        InternalScan.Value++;
        try { return library.GetItemList(query); }
        finally { InternalScan.Value--; }
    }
    // Tag IDs with a currently visible, non-denied source that links them:
    // the same Genre/Studio/Tag source rule as the prefix. The query uses the
    // prefix result; the result and writer rechecks use a fresh storage
    // snapshot and native parent lookups, never the prefix's decisions.
    private static HashSet<long> VisibleTagIds(Scope scope, bool fresh, HashSet<long>? required = null)
    {
        var tags = required == null ? scope.TagItems : scope.TagItems.Where(item => required.Contains(item.InternalId)).ToArray();
        var all = tags.Select(item => item.InternalId).ToHashSet();
        if (!fresh) { all.ExceptWith(scope.ForbiddenMetadata); return all; }
        InternalScan.Value++;
        var started = Stopwatch.GetTimestamp();
        try
        {
            var hints = all.Where(scope.MetadataWitnesses.ContainsKey).Select(id => scope.MetadataWitnesses[id]).Distinct().ToArray();
            all.ExceptWith(_access!.CreateListContext(scope.User, NoInventory).DeniedMetadata(tags, scope.Request.CancellationToken, preferredSources: hints));
            return all;
        }
        finally
        {
            InternalScan.Value--;
            var elapsed = ElapsedMs(started);
            if(elapsed > 500) Diagnose(scope.Dto, "slow-visible-tags", AuthKind(scope), null, elapsed, scope.TagItems.Length);
        }
    }
    private static readonly IReadOnlyDictionary<long, BaseItem> NoInventory = new Dictionary<long, BaseItem>();
    // Concrete media item types. A query restricted to these cannot return a
    // Genre, Studio or Tag index record, so those IDs are excluded by the
    // query's own type filter and need not be repeated as SQL exclusions.
    private static readonly HashSet<string> MediaTypes = new(StringComparer.Ordinal) {
        "Movie", "Episode", "Series", "Season", "MusicAlbum", "Audio", "AudioBook", "MusicVideo", "Book",
        "Video", "BoxSet", "Trailer", "Photo", "PhotoAlbum", "Playlist" };
    private static void BeforeQuery(InternalItemsQuery __0, MethodBase __originalMethod)
    {
        var scope = Current.Value;
        if (scope == null || scope.Libraries || InternalScan.Value != 0) return;
        if (!scope.Active) throw new ResourceNotFoundException("Expired item-list context.");
        if (scope.SourceStable?.Invoke(false) == false) throw new ResourceNotFoundException("Native sources changed.");
        if (scope.User != null) __0.User = scope.User;
        // Only plain item queries; Genre/Studio/Tag aggregations return the
        // index records themselves whatever their source type filter is.
        var typeExcludesMetadata = scope.ForbiddenMetadata.Count > 0
            && __originalMethod.Name is "GetItemList" or "GetItemIds" or "GetItemsResult"
            && __0.IncludeItemTypes is { Length: > 0 } types && types.All(MediaTypes.Contains);
        var forbidden = typeExcludesMetadata ? scope.Forbidden.Where(id => !scope.ForbiddenMetadata.Contains(id)) : scope.Forbidden;
        __0.ExcludeItemIds = (__0.ExcludeItemIds ?? Array.Empty<long>()).Concat(forbidden)
            .Concat(_access!.DeniedRegisteredIds(scope.User)).Distinct().ToArray();
        if(scope.Tags && __originalMethod.Name == "GetTags")
        {
            // Native tags are global index records: excluding video IDs
            // does not exclude their tag IDs. Bind the actual metadata query
            // to links from currently visible, authorized native sources.
            var allowed = VisibleTagIds(scope, false);
            var existing = __0.ItemIds;
            if(existing?.Length > 0) allowed.IntersectWith(existing);
            __0.ItemIds = allowed.Count == 0 ? new long[] { -1 } : allowed.ToArray();
            if(scope.TagSourceStable != null) throw new ResourceNotFoundException("Items not found.");
            var query = __0;
            var applied = query.ItemIds.ToArray();
            scope.TagSourceStable = () => query.ItemIds?.SequenceEqual(applied) == true
                && allowed.IsSubsetOf(VisibleTagIds(scope, true, allowed));
        }
        scope.Coverage.Record(typeExcludesMetadata ? __0.ExcludeItemIds.Concat(scope.ForbiddenMetadata) : __0.ExcludeItemIds);
        Interlocked.Increment(ref _queries);
    }
    private static void BeforeViewSources(ref User __1, ref Folder[] __2)
    {
        var scope = Current.Value;
        if(scope == null || InternalScan.Value != 0) return;
        if(!scope.Active || __2 == null) throw new ResourceNotFoundException("Items not found.");
        if(scope.User != null) __1 = scope.User;
        // Filter the actual source array before view grouping/counts/DTOs.
        // Query exclusions alone do not cover this cached root-folder input.
        var exclusions = scope.Forbidden.Concat(_access!.DeniedRegisteredIds(scope.User)).ToHashSet();
        // Record exactly the exclusions applied to this source. A newer
        // denial read after filtering must not bless an already-kept folder.
        __2 = __2.Where(folder => !exclusions.Contains(folder.InternalId)
            && _access.DecideItem(folder, scope.User) != Access.Denied).ToArray();
        scope.Coverage.Record(exclusions);
        Interlocked.Increment(ref _viewSources);
    }
    private static void BeforeLibrarySources(ref User __0)
    {
        var scope = Current.Value;
        if(scope?.Libraries != true || InternalScan.Value != 0) return;
        if(!scope.Active) throw new ResourceNotFoundException("Items not found.");
        // Native user visibility consults this same library inventory. Read
        // the inventory once without that recursive user query, then apply
        // the authenticated account filter to the actual returned sources.
        __0 = null!;
    }
    private static void AfterLibrarySources(ref List<VirtualFolderInfo> __result)
    {
        var scope = Current.Value;
        if(scope?.Libraries != true || InternalScan.Value != 0) return;
        if(!scope.Active || __result == null) throw new ResourceNotFoundException("Items not found.");
        var exclusions = scope.Forbidden.Concat(_access!.DeniedRegisteredIds(scope.User)).ToHashSet();
        // This runs before the service computes total counts and pages. Return
        // a new list so filtering never changes a shared native collection.
        // Access resolution itself reads the native library inventory. Those
        // internal reads must not re-enter this response-source filter.
        InternalScan.Value++;
        try
        {
            __result = __result.Where(folder => !string.IsNullOrWhiteSpace(folder.ItemId)
                && (!long.TryParse(folder.ItemId, out var id) || !exclusions.Contains(id))
                && _access.DecideReference(folder.ItemId, scope.User) != Access.Denied).ToList();
        }
        finally { InternalScan.Value--; }
        scope.Coverage.Record(exclusions);
    }
    private static void AfterService(ref Task<object> __result, object? __state)
    {
        if (__state is not Saved saved) return;
        Current.Value = saved.Previous;
        __result = Finish(__result, saved.Created);
    }
    private static Exception? ServiceFailed(Exception? __exception, object? __state)
    {
        if(__exception == null || __state is not Saved saved) return __exception;
        Diagnose(saved.Created.Dto, "service", AuthKind(saved.Created), __exception, 0);
        if(ReferenceEquals(Current.Value, saved.Created)) Current.Value = saved.Previous;
        saved.Created.Active = false;
        return new ResourceNotFoundException("Items not found.");
    }
    private static string AuthKind(Scope scope) => scope.User != null ? "user" : "serverkey";
    // A server-key result is re-verified so a revoked key cannot finish.
    private static bool StillAuthorized(Scope scope) => scope.User != null || IsVerifiedServerKey(scope.ServiceToken);
    private static async Task<object> Finish(Task<object> result, Scope scope)
    {
        var phase = "native-result";
        try
        {
            var completed = await result.ConfigureAwait(false);
            phase = "coverage";
            try
            {
                if (!StillAuthorized(scope) || scope.SourceStable?.Invoke(true) == false || !scope.Coverage.Covers(_access!.DeniedRegisteredIds(scope.User))
                    || scope.Tags && scope.TagSourceStable?.Invoke() != true)
                    throw new ResourceNotFoundException("Items not found.");
            }
            catch (Exception) { throw new ResourceNotFoundException("Items not found."); }
            phase = "writer";
            // Suggestions returns its typed DTO rather than a native writer.
            // Serialize through the native factory before registering the
            // same final writer check used by the other audited list routes.
            if(scope.Suggestions && completed is QueryResult<BaseItemDto> suggestions)
                completed = _results!.GetResult(scope.Request, suggestions, new Dictionary<string, string>());
            if(scope.Tags && completed is not null && completed.GetType() == _tagResultType)
                completed = _tagFactory!.Invoke(_results, new object[] { scope.Request, completed, new Dictionary<string, string>() })
                    ?? throw new ResourceNotFoundException("Items not found.");
            if(scope.Libraries && completed is QueryResult<VirtualFolderInfo> libraries)
                completed = _results!.GetResult(scope.Request, libraries, new Dictionary<string, string>());
            else if(scope.Libraries && completed is VirtualFolderInfo[] libraryList)
                completed = _results!.GetResult(scope.Request, libraryList, new Dictionary<string, string>());
            if(completed is null) throw new ResourceNotFoundException("Items not found.");
            RegisterWriterWithSource(completed, scope.User?.Id ?? ServiceKeyOwner, () => StillAuthorized(scope)
                && scope.SourceStable?.Invoke(true) != false
                && scope.Coverage.Covers(_access!.DeniedRegisteredIds(scope.User))
                && (!scope.Tags || scope.TagSourceStable?.Invoke() == true),
                scope.SourceVersion.HasValue ? () => PersonalYouTubeNativeSourceBarrier.EnterRead(scope.SourceVersion.Value) : null,
                scope.SourceStable == null ? null : () => scope.SourceStable(false));
            return completed;
        }
        catch (Exception error) { Diagnose(scope.Dto, phase, AuthKind(scope), error, 0); throw; }
        finally { scope.Active = false; }
    }
    // Audited direct-reference metadata/download services share the verified
    // native writers and owner lease, with their own access predicate.
    internal static void RegisterWriter(object writer, Guid owner, Func<bool> allowed)
        => RegisterWriterWithSource(writer, owner, allowed, null, null);
    private static void RegisterWriterWithSource(object writer, Guid owner, Func<bool> allowed, Func<IDisposable>? sourceLease, Func<bool>? finalSourceCheck)
    {
        if (owner == Guid.Empty || writer?.GetType().FullName is not ("Emby.Server.Implementations.HttpServer.StreamWriter" or "Emby.Server.Implementations.HttpServer.FileWriter" or "Emby.Server.Implementations.Services.EmptyHttpResult")
            || !Snapshot().Installed) throw new ResourceNotFoundException("Items not found.");
        var context = new WriterContext(owner, allowed, sourceLease, finalSourceCheck);
        if (!ReferenceEquals(Writers.GetValue(writer, _ => context), context))
            throw new ResourceNotFoundException("Items not found.");
    }
    private static bool BeforeWrite(object __instance, IResponse __0, ref Task __result, out object? __state)
    {
        __state = null;
        if (!Writers.TryGetValue(__instance, out var scope)) return true;
        Interlocked.Increment(ref _writes);
        IDisposable? lease = null;
        try
        {
            lease = PersonalYouTubeTransferLease.Enter(_directory!, scope.Owner);
            if (scope.Allowed())
            {
                // Native source validation may perform lazy repository writes.
                // Complete it before taking the source reader lease; then
                // atomically verify its version and repeat only the memory/
                // authority checks, with no native I/O under that lease.
                if (scope.SourceLease != null) lease = PersonalYouTubeNativeSourceBarrier.Combine(lease, scope.SourceLease());
                if (scope.FinalSourceCheck?.Invoke() != false) { __state = lease; return true; }
            }
            Diagnose(__instance.GetType().Name, "write", scope.Owner == ServiceKeyOwner ? "serverkey" : "user", new ResourceNotFoundException("Items not found."), 0);
        }
        catch (Exception error) { Diagnose(__instance.GetType().Name, "write", scope.Owner == ServiceKeyOwner ? "serverkey" : "user", error, 0); }
        lease?.Dispose();
        Interlocked.Increment(ref _writesDenied);
        DiscardPrivateResult(__instance, __0);
        __result = Task.FromException(new ResourceNotFoundException("Items not found."));
        return false;
    }
    internal static void DiscardPrivateResult(object? result, IResponse response)
    {
        // Native writers normally dispose their content after writing. A
        // rejected writer never runs; release any already-open source here.
        try
        {
            var content = result?.GetType().FullName switch {
                "Emby.Server.Implementations.HttpServer.FileWriter" => _fileContent,
                "Emby.Server.Implementations.HttpServer.StreamWriter" => _streamContent,
                _ => null
            };
            if (content?.GetValue(result) is StreamHandler opened)
            { content.SetValue(result, null); opened.Dispose(); }
        }
        catch (Exception) { }
        // The native handler copies result headers before invoking the writer.
        // Its error path changes the body/status but retains those headers;
        // discard them so an expired result cannot disclose its filename,
        // validators, ranges, or other entity metadata in the denial response.
        // NetCoreResponse exposes a snapshot through Headers and its
        // AddHeader does not remove existing entries. Clear the verified
        // backing HttpResponse header dictionary instead.
        var nativeResponse = _nativeResponse!.GetValue(response)!;
        _clearNativeHeaders!.Invoke(_nativeHeaders!.GetValue(nativeResponse), null);
    }
    private static void AfterWrite(ref Task __result, object? __state)
    {
        if (__state is IDisposable lease) __result = PersonalYouTubeTransferLease.Complete(__result, lease);
    }
    private static Exception? WriteFailed(Exception? __exception, object? __state)
    {
        if (__exception != null && __state is IDisposable lease) lease.Dispose();
        return __exception;
    }
}
