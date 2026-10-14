using System.Reflection;
using HarmonyLib;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

// A feasibility experiment, not a complete production security boundary.
// It deliberately guards only this fixture's synthetic library items.
internal static class PrivacyGuard
{
    internal static void DisableForProductionServiceVerification()
    {
        lock (Sync) { Enabled = false; Ready = true; }
    }
    private static readonly object Sync = new();
    private static readonly Dictionary<string, long> Owners = new(StringComparer.OrdinalIgnoreCase);
    private static readonly Dictionary<string, long> LiveStreamOwners = new(StringComparer.Ordinal);
    private static readonly Dictionary<string, long> OpenTokenOwners = new(StringComparer.Ordinal);
    private static readonly Dictionary<string, string> PersistedTokenOwners = new(StringComparer.Ordinal);
    private sealed record TokenLedger(int Version, Dictionary<string, string> Owners);
    private static string TokenLedgerPath => FixturePlugin.StatePath + ".open-token-owners.json";
    private static string TokenHash(string token) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(token)));
    private static void LoadTokenOwners() {
        OpenTokenOwners.Clear();
        PersistedTokenOwners.Clear();
        if (!File.Exists(TokenLedgerPath)) return;
        var ledger = System.Text.Json.JsonSerializer.Deserialize<TokenLedger>(File.ReadAllText(TokenLedgerPath))
            ?? throw new InvalidOperationException("Invalid token ownership ledger.");
        if (ledger.Version != 1) throw new InvalidOperationException("Unsupported token ownership ledger.");
        foreach (var pair in ledger.Owners) {
            if (!System.Text.RegularExpressions.Regex.IsMatch(pair.Key, "^[A-F0-9]{64}$")
                || (pair.Value != "-1" && !Guid.TryParseExact(pair.Value, "N", out _)))
                throw new InvalidOperationException("Invalid token ownership entry.");
            PersistedTokenOwners[pair.Key] = pair.Value;
            OpenTokenOwners[pair.Key] = pair.Value == "-1" ? -1 : Users!.GetUserById(pair.Value)?.InternalId ?? -1;
        }
    }
    private static void SaveTokenOwners() {
        var json = System.Text.Json.JsonSerializer.Serialize(new TokenLedger(1, new(PersistedTokenOwners)));
        File.WriteAllText(TokenLedgerPath + ".tmp", json);
        File.Move(TokenLedgerPath + ".tmp", TokenLedgerPath, true);
        var readback = System.Text.Json.JsonSerializer.Deserialize<TokenLedger>(File.ReadAllText(TokenLedgerPath));
        if (readback?.Version != 1 || readback.Owners.Count != PersistedTokenOwners.Count
            || PersistedTokenOwners.Any(pair => !readback.Owners.TryGetValue(pair.Key, out var owner) || owner != pair.Value))
            throw new InvalidOperationException("Token ownership write did not verify.");
    }
    private static bool LiveStreamBindingInstalled;
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, long> HistoricalOwners = new(StringComparer.OrdinalIgnoreCase);
    private static bool LibraryEventsInstalled;
    private static bool NativeSyncObserverInstalled;
    private static long NativeSyncSequence;
    private static long[]? NativeSyncTargets;
    private static readonly Dictionary<long, long> ActiveNativeSyncSubjects = new();
    private static long NativeSyncCrossSubjectOverlaps;
    private static bool VisibilityObservationInstalled;
    private static readonly List<object> VisibilityObservations = new();
    private static void ObserveNativeVisibility(MediaBrowser.Controller.Entities.BaseItem __instance,
        MediaBrowser.Controller.Entities.User __0, MethodBase __originalMethod, bool __result) {
        if (!__instance.Name.StartsWith("PrivateNativeVideo_", StringComparison.Ordinal)) return;
        lock (Sync) VisibilityObservations.Add(new { ItemKey=__instance.InternalId,
            UserKey=__0?.InternalId, Method=__originalMethod.Name, Allowed=__result });
    }
    internal static object NativeVisibilitySnapshot(bool reset) {
        lock (Sync) {
            if (!VisibilityObservationInstalled) {
                var types = new[] { typeof(MediaBrowser.Controller.Entities.BaseItem), typeof(MediaBrowser.Controller.Entities.Video) };
                foreach (var method in types.SelectMany(type => type.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly))
                    .Where(method => method.Name is "IsVisible" or "IsVisibleStandalone")
                    .Where(method => method.GetParameters().Length == 1).Distinct())
                    Harmony!.Patch(method, postfix: new HarmonyMethod(typeof(PrivacyGuard), nameof(ObserveNativeVisibility)));
                VisibilityObservationInstalled = true;
            }
            if (reset) VisibilityObservations.Clear();
            return new { Installed=VisibilityObservationInstalled, Calls=VisibilityObservations.ToArray() };
        }
    }
    private static readonly Dictionary<string, long> ChannelOwners = new(StringComparer.Ordinal);
    private static long TrustedFixtureDeleteRoot;
    internal static object ApproveFixtureRootDelete(long rootKey) {
        lock (Sync) {
            var root = Library!.GetItemById(rootKey);
            if (!Enabled || !Ready || root is not MediaBrowser.Controller.Entities.Folder
                || root.Name != "Private Native Fixture a" || !FindOwner(rootKey.ToString()).HasValue)
                throw new ArgumentException("Only the registered synthetic A root");
            TrustedFixtureDeleteRoot = rootKey;
            var grown = Library.GetItemList(new MediaBrowser.Controller.Entities.InternalItemsQuery { AncestorIds = new[] { rootKey }, Recursive = true })
                .SingleOrDefault(item => item.Name == "PrivateNativeVideo_a_grown");
            return new { Approved = true, RootGuidReference = root.Id.ToString("N"), GrownGuidReference = grown?.Id.ToString("N") ?? "" };
        }
    }
    private static IAuthorizationContext? Authorization;
    private static IUserManager? Users;
    private static ILibraryManager? Library;
    private static long? DefaultOwner;
    private static MediaBrowser.Controller.Session.ISessionManager? Sessions;
    private static Harmony? Harmony;
    internal static volatile bool Enabled;
    internal static volatile bool Ready;
    internal static volatile bool Installed;
    internal static readonly string BootId = Guid.NewGuid().ToString("N");
    internal static long StartupDenials;
    internal static long UrlChecks;
    internal static long DtoChecks;
    internal static long Denials;
    internal static string SessionResponseShape = "";
    internal static readonly List<string> MetadataIdentities = new();
    private static readonly AsyncLocal<long?> CurrentSyncSubject = new();
    private static readonly AsyncLocal<string[]?> CurrentStaleSyncCacheIds = new();
    private sealed record ServiceScope(MetadataScope? Metadata, long? SyncSubject, string[]? StaleCacheIds, long? StreamSubject);
    private static readonly AsyncLocal<long?> CurrentStreamSubject = new();
    internal static void AuthorizeFixtureStream(MediaBrowser.Controller.Entities.BaseItem item) {
        if (!Enabled) return;
        if (!Ready) throw new ResourceNotFoundException("Item not found.");
        lock (Sync) {
            var owner = FindOwner(item.InternalId.ToString());
            if (!owner.HasValue || owner != CurrentStreamSubject.Value) {
                FixtureLiveActivity.SourceDenials.AddOrUpdate(item.Name, 1, (_, count) => count + 1);
                throw new ResourceNotFoundException("Item not found.");
            }
        }
    }
    private sealed record MetadataScope(long? UserId, long[] ForbiddenIds, MetadataPaging? LibraryPaging = null, MetadataPaging? SoapPaging = null);
    private sealed record MetadataPaging(int? StartIndex, int? Limit);
    private static readonly AsyncLocal<MetadataScope?> CurrentMetadata = new();
    private static readonly AsyncLocal<int> InternalScanDepth = new();
    private static readonly AsyncLocal<bool> SoapPrepared = new();
    private static readonly AsyncLocal<MetadataPaging?> PreparedSoapPaging = new();
    private static bool MetadataHooksInstalled;
    internal static long MetadataQueries;

    internal sealed record FeatureCheck(string Feature, bool Allowed, DateTimeOffset CheckedUtc);
    private static readonly List<FeatureCheck> FeatureChecks = new();
    private static bool FeatureObservationInstalled;
    internal static FeatureCheck[] ObserveSyncFeatures(object security) {
        lock (Sync) {
            if (!FeatureObservationInstalled) {
                var mapping = security.GetType().GetInterfaceMap(typeof(MediaBrowser.Common.Security.ISecurityManager));
                var index = Array.FindIndex(mapping.InterfaceMethods, method => method.Name == "IsFeatureAllowed"
                    && method.GetParameters().Select(parameter => parameter.ParameterType).SequenceEqual(new[] { typeof(string), typeof(CancellationToken) }));
                if (index < 0) throw new InvalidOperationException("Feature check interface method missing");
                var method = mapping.TargetMethods[index];
                Harmony!.Patch(method, postfix: new HarmonyMethod(typeof(PrivacyGuard), nameof(ObserveFeatureResult)));
                FeatureObservationInstalled = true;
            }
            return FeatureChecks.ToArray();
        }
    }
    private static void ObserveFeatureResult(string __0, ref Task<bool> __result) => __result = RecordFeatureResult(__0, __result);
    private static async Task<bool> RecordFeatureResult(string feature, Task<bool> result) {
        var allowed = await result.ConfigureAwait(false);
        lock (Sync) FeatureChecks.Add(new FeatureCheck(feature, allowed, DateTimeOffset.UtcNow));
        return allowed;
    }
    internal static void Prepare(IHttpServer server, bool enabled)
    {
        lock (Sync)
        {
            Enabled = enabled;
            Ready = !enabled;
            if (Harmony != null) return;
            var handler = server.GetType().GetMethod("RequestHandler", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                ?? throw new InvalidOperationException("No HTTP request handler.");
            Harmony = new Harmony("isolated-personal-fixture-privacy");
            Harmony.Patch(handler, prefix: new HarmonyMethod(typeof(PrivacyGuard), nameof(CheckUrl)));
            var controller = server.GetType().Assembly.GetType("Emby.Server.Implementations.Services.ServiceController")!;
            var execute = controller.GetMethod("Execute", BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)!;
            Harmony.Patch(execute, prefix: new HarmonyMethod(typeof(PrivacyGuard), nameof(CheckService)),
                postfix: new HarmonyMethod(typeof(PrivacyGuard), nameof(FilterService)));
            var socket = server.GetType().Assembly.GetType("Emby.Server.Implementations.HttpServer.WebSocketConnection")!;
            Harmony.Patch(socket.GetMethod("SendAsync", new[] { typeof(ReadOnlyMemory<byte>), typeof(CancellationToken) })!,
                prefix: new HarmonyMethod(typeof(PrivacyGuard), nameof(FilterSocketBytes)));
            Harmony.Patch(socket.GetMethod("SendAsync", new[] { typeof(ReadOnlyMemory<char>), typeof(CancellationToken) })!,
                prefix: new HarmonyMethod(typeof(PrivacyGuard), nameof(FilterSocketChars)));
            Installed = true;
        }
    }

    internal static void Enable(IHttpServer server, IAuthorizationContext authorization,
        ILibraryManager library, IUserManager users, MediaBrowser.Controller.Session.ISessionManager sessions, string ownerId,
        Dictionary<string, string>? ownerUserIds = null, Dictionary<string, string>? rootOwnerUserIds = null)
    {
        if (!Installed) throw new InvalidOperationException("Privacy hooks are unavailable.");
        var owner = users.GetUserById(ownerId) ?? throw new ArgumentException("Unknown owner");
#if LEGACY_NATIVE_ROOT
        // Compile-time control for the isolated root-deletion counterexample.
        var nativeReferences = new Dictionary<string, long>();
#else
        var nativeReferences = NativeReferenceLedger.Reconcile(library, users, rootOwnerUserIds);
#endif
        var roots = library.GetItemList(new MediaBrowser.Controller.Entities.InternalItemsQuery { IsFolder = true, Recursive = true })
            .OfType<MediaBrowser.Controller.Channels.Channel>()
            .Where(channel => channel.Name.StartsWith("Personal Fixture ", StringComparison.Ordinal))
            .Cast<MediaBrowser.Controller.Entities.BaseItem>().ToList();
        var assignedRoots = new Dictionary<long, long>();
        foreach (var pair in rootOwnerUserIds ?? new Dictionary<string, string>())
        {
            var root = library.GetItemById(long.Parse(pair.Key));
            if (root == null) {
#if LEGACY_NATIVE_ROOT
                throw new ArgumentException("Unknown private library root");
#else
                continue; // Missing private identity was verified by the durable ledger.
#endif
            }
            if (root is not MediaBrowser.Controller.Entities.Folder || !root.Name.StartsWith("Private Native Fixture ", StringComparison.Ordinal))
                throw new ArgumentException("Only synthetic native fixture roots are supported");
            // Isolated experiment: an orphaned native root remains private,
            // with no authenticated subject able to match the sentinel owner.
            assignedRoots[root.InternalId] = users.GetUserById(pair.Value)?.InternalId ?? -1;
            roots.Add(root);
        }
        lock (Sync)
        {
            Owners.Clear();
            ChannelOwners.Clear();
            foreach (var pair in ownerUserIds ?? new Dictionary<string, string>())
                ChannelOwners["Personal Fixture " + pair.Key] = (users.GetUserById(pair.Value) ?? throw new ArgumentException("Unknown profile owner")).InternalId;
            foreach (var root in roots)
            {
                var itemOwner = assignedRoots.TryGetValue(root.InternalId, out var explicitOwner) ? explicitOwner
                    : ChannelOwners.TryGetValue(root.Name, out var assigned) ? assigned : owner.InternalId;
                foreach (var item in library.GetItemList(new MediaBrowser.Controller.Entities.InternalItemsQuery {
                    AncestorIds = new[] { root.InternalId }, Recursive = true }).Append(root))
                {
                    Owners[item.InternalId.ToString()] = itemOwner;
                    Owners[item.Id.ToString("N")] = itemOwner;
                    HistoricalOwners[item.InternalId.ToString()] = itemOwner;
                    HistoricalOwners[item.Id.ToString("N")] = itemOwner;
                }
            }
            // Durable native tombstones override the live scan; a reused native
            // identity must never erase the old private classification.
            foreach (var pair in nativeReferences) {
                Owners[pair.Key] = pair.Value;
                HistoricalOwners[pair.Key] = pair.Value;
            }
            Authorization = authorization;
            Users = users;
            LoadTokenOwners();
            Library = library;
            DefaultOwner = owner.InternalId;
            Sessions = sessions;
            if (!MetadataHooksInstalled)
            {
                foreach (var method in library.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                    .Where(method => method.Name is "GetGenres" or "GetAllGenres" or "GetMusicGenres" or "GetGameGenres" or "GetStudios" or "GetTags")
                    .Where(method => method.GetParameters().FirstOrDefault()?.ParameterType == typeof(MediaBrowser.Controller.Entities.InternalItemsQuery)))
                    Harmony!.Patch(method, prefix: new HarmonyMethod(typeof(PrivacyGuard), nameof(ScopeMetadataQuery)),
                        postfix: new HarmonyMethod(typeof(PrivacyGuard), nameof(FilterMetadataQuery)));
                MetadataHooksInstalled = true;
                foreach (var method in library.GetType().GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                    .Where(method => method.Name is "GetItemList" or "GetItemIds" or "GetItemsResult" or "GetItemTypes")
                    .Where(method => method.GetParameters().FirstOrDefault()?.ParameterType == typeof(MediaBrowser.Controller.Entities.InternalItemsQuery)))
                    Harmony!.Patch(method, prefix: new HarmonyMethod(typeof(PrivacyGuard), nameof(ScopeItemQuery)));
            }
            if (!LibraryEventsInstalled) {
                library.ItemAdded += TrackNativeOwnership;
                library.ItemUpdated += TrackNativeOwnership;
                library.ItemRemoved += TrackNativeRemovedOwnership;
                LibraryEventsInstalled = true;
            }
            if (!NativeSyncObserverInstalled) {
                var syncType = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Sync.SyncManager")).First(type => type != null)!;
                var method = syncType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                    .Single(method => method.Name == "SyncData" && method.GetParameters().Length == 2);
                Harmony!.Patch(method, prefix: new HarmonyMethod(typeof(PrivacyGuard), nameof(ObserveNativeSyncInput)),
                    postfix: new HarmonyMethod(typeof(PrivacyGuard), nameof(ObserveNativeSyncCompletion)),
                    finalizer: new HarmonyMethod(typeof(PrivacyGuard), nameof(ObserveNativeSyncFailure)));
                var itemsMethod = syncType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                    .Single(method => method.Name == "GetJobItems");
                Harmony.Patch(itemsMethod, postfix: new HarmonyMethod(typeof(PrivacyGuard), nameof(FilterNativeSyncItems)));
                NativeSyncObserverInstalled = true;
            }
            if (!LiveStreamBindingInstalled) {
                var type = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Implementations.Library.MediaSourceManager")).First(type => type != null)!;
                var method = type.GetMethods(BindingFlags.Public | BindingFlags.Instance)
                    .Single(method => method.Name == "OpenLiveStream" && method.GetParameters().Length == 2);
                Harmony!.Patch(method, postfix: new HarmonyMethod(typeof(PrivacyGuard), nameof(BindOpenedLiveStream)));
                var dynamicSources = type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                    .Single(candidate => candidate.Name == "GetDynamicMediaSources" && candidate.GetParameters().Length == 3
                        && candidate.GetParameters()[1].ParameterType == typeof(IMediaSourceProvider));
                Harmony.Patch(dynamicSources, postfix: new HarmonyMethod(typeof(PrivacyGuard), nameof(BindOpenTokens)));
                LiveStreamBindingInstalled = true;
            }
            Enabled = true;
            Ready = true;
        }
    }

    private static void BindOpenedLiveStream(object __0, ref Task<MediaBrowser.Model.MediaInfo.LiveStreamResponse> __result) {
        if (Enabled && Ready) __result = BindOpenedLiveStreamAsync(__0, __result);
    }
    private static void BindOpenTokens(MediaBrowser.Controller.Entities.BaseItem __0,
        ref Task<IEnumerable<MediaBrowser.Model.Dto.MediaSourceInfo>> __result) {
        if (Enabled && Ready) __result = BindOpenTokensAsync(__0, __result);
    }
    private static async Task<IEnumerable<MediaBrowser.Model.Dto.MediaSourceInfo>> BindOpenTokensAsync(
        MediaBrowser.Controller.Entities.BaseItem item, Task<IEnumerable<MediaBrowser.Model.Dto.MediaSourceInfo>> task) {
        var sources = (await task.ConfigureAwait(false)).ToArray();
        lock (Sync) {
            var owner = FindOwner(item.InternalId.ToString());
            if (!owner.HasValue) return sources;
            foreach (var source in sources.Where(source => !string.IsNullOrEmpty(source.OpenToken))) {
                var key = TokenHash(source.OpenToken);
                var assigned = source.Path == item.Path ? owner.Value : -1;
                if (OpenTokenOwners.TryGetValue(key, out var previous) && previous != assigned) assigned = -1;
                OpenTokenOwners[key] = assigned;
                PersistedTokenOwners[key] = assigned == -1 ? "-1" : Users!.GetUserById(assigned)?.Id.ToString("N") ?? "-1";
            }
            SaveTokenOwners();
        }
        return sources;
    }
    private static async Task<MediaBrowser.Model.MediaInfo.LiveStreamResponse> BindOpenedLiveStreamAsync(object request,
        Task<MediaBrowser.Model.MediaInfo.LiveStreamResponse> task) {
        var probe = FixtureLiveActivity.Begin(CurrentStreamSubject.Value);
        try {
        var response = await task.ConfigureAwait(false);
        var source = response.MediaSource;
        var requestedId = request.GetType().GetProperty("ItemId")?.GetValue(request)?.ToString();
        long? requestedOwner;
        lock (Sync) requestedOwner = requestedId == null ? null : FindOwner(requestedId);
        // For this isolated local-video experiment, identify the actual source
        // independently of a caller-controlled ItemId. Do not relabel a foreign
        // source as belonging to the owner of the submitted item.
        var matches = Library!.GetItemList(new MediaBrowser.Controller.Entities.InternalItemsQuery {
            Recursive = true, IncludeItemTypes = new[] { "Video" }
        }).Where(item => !string.IsNullOrEmpty(source?.Path) && item.Path == source.Path).ToArray();
        long[] actualOwners;
        lock (Sync) actualOwners = matches.Select(item => FindOwner(item.InternalId.ToString()))
            .Where(owner => owner.HasValue).Select(owner => owner!.Value).Distinct().ToArray();
        if (!requestedOwner.HasValue && actualOwners.Length == 0) return response;
        var assigned = actualOwners.Length == 1 ? actualOwners[0] : -1;
        if (string.IsNullOrEmpty(source?.LiveStreamId)) throw new ResourceNotFoundException("Unbound private stream.");
        lock (Sync) {
            if (LiveStreamOwners.TryGetValue(source.LiveStreamId, out var previous) && previous != assigned) assigned = -1;
            LiveStreamOwners[source.LiveStreamId] = assigned;
        }
        if (requestedOwner != assigned) throw new ResourceNotFoundException("Item not found.");
        return response;
        } finally { FixtureLiveActivity.End(probe); }
    }

    private static void ObserveNativeSyncInput(object __0, out long __state)
    {
        __state = 0;
        if (!Enabled || !Ready) return;
        lock (Sync) {
            NativeSyncSequence++;
            NativeSyncTargets = (__0.GetType().GetProperty("InternalTargetIds")?.GetValue(__0) as long[])?.ToArray();
            if (CurrentSyncSubject.Value is long subject) {
                __state = NativeSyncSequence;
                if (ActiveNativeSyncSubjects.Values.Any(active => active != subject)) NativeSyncCrossSubjectOverlaps++;
                ActiveNativeSyncSubjects[__state] = subject;
            }
        }
    }
    private static void FinishNativeSyncObservation(long invocation) {
        if (invocation == 0) return;
        lock (Sync) ActiveNativeSyncSubjects.Remove(invocation);
    }
    private static void ObserveNativeSyncCompletion(object __result, long __state) {
        var invocation = __state;
        if (__result is Task task && !task.IsCompleted)
            _ = task.ContinueWith(_ => FinishNativeSyncObservation(invocation), CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        else FinishNativeSyncObservation(invocation);
    }
    private static void ObserveNativeSyncFailure(Exception? __exception, long __state) {
        if (__exception != null) FinishNativeSyncObservation(__state);
    }
    private static void FilterNativeSyncItems(object __instance, object __result)
    {
        var subject = CurrentSyncSubject.Value;
        if (!Enabled || !Ready || !subject.HasValue) return;
        var property = __result.GetType().GetProperty("Items");
        if (property?.CanWrite != true || property.GetValue(__result) is not Array items)
            throw new ResourceNotFoundException("Cannot scope native Sync query.");
        var getJob = __instance.GetType().GetMethod("GetJob", new[] { typeof(long), typeof(CancellationToken) })!;
        var kept = items.Cast<object>().Where(item => {
            var source = item.GetType().GetProperty("ItemId")?.GetValue(item)?.ToString();
            var owner = source == null ? null : FindOwner(source);
            if (!owner.HasValue) return true; // Preserve public/non-fixture native items.
            if (owner != subject) return false;
            var jobId = Convert.ToInt64(item.GetType().GetProperty("JobId")!.GetValue(item));
            var job = getJob.Invoke(__instance, new object[] { jobId, CancellationToken.None });
            return job != null && Convert.ToInt64(job.GetType().GetProperty("UserId")!.GetValue(job)) == subject.Value;
        }).ToArray();
        if (kept.Length == items.Length) return;
        var filtered = Array.CreateInstance(items.GetType().GetElementType()!, kept.Length);
        Array.Copy(kept, filtered, kept.Length);
        property.SetValue(__result, filtered);
        __result.GetType().GetProperty("TotalRecordCount")?.SetValue(__result, kept.Length);
    }    internal static object NativeSyncInputSnapshot()
    {
        lock (Sync) return new { Sequence = NativeSyncSequence, HasExplicitTargets = NativeSyncTargets != null,
            InternalTargetIds = NativeSyncTargets?.ToArray() ?? Array.Empty<long>(),
            CrossSubjectOverlaps = NativeSyncCrossSubjectOverlaps, ActiveCalls = ActiveNativeSyncSubjects.Count };
    }
    // Test whether explicit native device policy can also protect Sync targets.
    // Broad EnableAllDevices permissions are deliberately not interpreted as ownership.
    private static bool SyncTargetAllowed(string targetId, long? userId)
    {
        var user = userId.HasValue ? Users!.GetUserById(userId.Value) : null;
        return user != null && (user.Policy.EnableAllDevices
            || (user.Policy.EnabledDevices ?? Array.Empty<string>()).Contains(targetId, StringComparer.Ordinal));
    }

    private static void EnforceSyncTarget(IRequest request, string? targetId)
    {
        if (!string.IsNullOrEmpty(targetId)
            && !SyncTargetAllowed(targetId, Authorization!.GetAuthorizationInfo(request).User?.InternalId))
            throw new ResourceNotFoundException("Item not found.");
    }
    private static void NormalizeLocalSyncCache(IRequest request, object dto)
    {
        if (dto.GetType().Name != "SyncData" || dto.GetType().GetProperty("LocalItemIds") is not { CanWrite: true } property
            || property.GetValue(dto) is not string[] ids) return;
        var userId = Authorization!.GetAuthorizationInfo(request).User?.InternalId;
        var active = new List<string>();
        var stale = new List<string>();
        foreach (var id in ids) {
            var supported = long.TryParse(id, out _) || Guid.TryParse(id, out _);
            if (supported && (ResolveItem(id) == null || !Allowed(id, userId))) stale.Add(id);
            else active.Add(id);
        }
        property.SetValue(dto, active.ToArray());
        CurrentStaleSyncCacheIds.Value = stale.ToArray();
    }
    private static void EnforceInternalSyncTargets(IRequest request, object dto)
    {
        var property = dto.GetType().GetProperty("InternalTargetIds");
        if (property == null) return;
        var requested = property.GetValue(dto) as long[];
        var implicitTargets = requested == null || requested.Length == 0;
        if (implicitTargets && (dto.GetType().Name != "SyncData"
            || !string.IsNullOrWhiteSpace(dto.GetType().GetProperty("TargetId")?.GetValue(dto)?.ToString()))) return;
        var user = Authorization!.GetAuthorizationInfo(request).User;
        if (user == null) throw new ResourceNotFoundException("Item not found.");
        if (user.Policy.EnableAllDevices) return; // Still broad native permission, not an ownership proof.
        var type = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Sync.SyncManager")).FirstOrDefault(type => type != null);
        var manager = type?.GetField("Current", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(null);
        var lookup = type?.GetMethod("GetInternalTargetId", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            null, new[] { typeof(string), typeof(bool), typeof(CancellationToken) }, null);
        if (manager == null || lookup == null) throw new ResourceNotFoundException("Item not found.");
        var allowed = new HashSet<long>();
        foreach (var device in user.Policy.EnabledDevices ?? Array.Empty<string>()) {
            try {
                // Lookup must not create a target record as a side effect of validation.
                var id = Convert.ToInt64(lookup.Invoke(manager, new object[] { device, false, CancellationToken.None }));
                if (id > 0) allowed.Add(id);
            } catch { throw new ResourceNotFoundException("Item not found."); }
        }
        if (implicitTargets) {
            if (allowed.Count == 0 || !property.CanWrite) throw new ResourceNotFoundException("Item not found.");
            property.SetValue(dto, allowed.ToArray());
        } else if (requested!.Any(id => !allowed.Contains(id))) throw new ResourceNotFoundException("Item not found.");
    }
    private static void EnforceSyncReferences(IRequest request)
    {
        var parts = request.PathInfo.Replace("/emby/", "/", StringComparison.OrdinalIgnoreCase).Trim('/').Split('/');
        if (parts.Length < 2 || !parts[0].Equals("Sync", StringComparison.OrdinalIgnoreCase)) return;
        var managerType = AppDomain.CurrentDomain.GetAssemblies().Select(assembly => assembly.GetType("Emby.Server.Sync.SyncManager")).FirstOrDefault(type => type != null)
            ?? throw new ResourceNotFoundException("Item not found.");
        var manager = managerType.GetField("Current", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)?.GetValue(null)
            ?? throw new ResourceNotFoundException("Item not found.");
        var subject = Authorization!.GetAuthorizationInfo(request).User?.InternalId;
        EnforceSyncTarget(request, request.QueryString["TargetId"]);
        // This installed API returns an empty progress object even for missing content.
        // Check the original content here so forbidden and nonexistent references share
        // the same HTTP response, before the DTO service exception formatter runs.
        if (parts.Length == 3 && parts[2].Equals("Status", StringComparison.OrdinalIgnoreCase)) {
            if (ResolveItem(parts[1]) == null) throw new ResourceNotFoundException("Item not found.");
            Enforce(request, new[] { parts[1] });
        }
        object? Lookup(string name, string value) {
            if (!long.TryParse(value, out var id)) throw new ResourceNotFoundException("Item not found.");
            var method = managerType.GetMethod(name, new[] { typeof(long), typeof(CancellationToken) })!;
            return method.Invoke(manager, new object[] { id, CancellationToken.None });
        }
        void CheckJob(string id) {
            var job = Lookup("GetJob", id) ?? throw new ResourceNotFoundException("Item not found.");
            var itemId = job.GetType().GetProperty("ItemId")?.GetValue(job)?.ToString();
            var ids = new List<string>();
            if (itemId != null) ids.Add(itemId);
            if (job.GetType().GetProperty("RequestedItemIds")?.GetValue(job) is System.Collections.IEnumerable requested)
                foreach (var value in requested) if (value != null) ids.Add(value.ToString()!);
            Enforce(request, ids);
            if (ids.Any(id => FindOwner(id).HasValue) && job.GetType().GetProperty("UserId")?.GetValue(job)?.ToString() != subject?.ToString())
                throw new ResourceNotFoundException("Item not found.");
        }
        if (parts.Length > 2 && parts[1].Equals("Jobs", StringComparison.OrdinalIgnoreCase)) CheckJob(parts[2]);
        if (parts.Length > 2 && parts[1].Equals("JobItems", StringComparison.OrdinalIgnoreCase)) {
            var item = Lookup("GetJobItem", parts[2]) ?? throw new ResourceNotFoundException("Item not found.");
            CheckJob(item.GetType().GetProperty("JobId")!.GetValue(item)!.ToString()!);
        }
        if (!string.IsNullOrEmpty(request.QueryString["JobId"])) CheckJob(request.QueryString["JobId"]);
        if (request.Verb.Equals("GET", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrEmpty(request.QueryString["UserId"])
            && Users!.GetUserById(request.QueryString["UserId"])?.InternalId != subject)
            throw new ResourceNotFoundException("Item not found.");
    }
    private static bool IsListFilter(string name) => name.Equals("Ids", StringComparison.OrdinalIgnoreCase)
        || name.Equals("ParentId", StringComparison.OrdinalIgnoreCase);
    private static bool IsItemListRead(IRequest request)
    {
        if (!request.Verb.Equals("GET", StringComparison.OrdinalIgnoreCase) && !request.Verb.Equals("HEAD", StringComparison.OrdinalIgnoreCase)) return false;
        var path = request.PathInfo.Trim('/');
        if (path.StartsWith("emby/", StringComparison.OrdinalIgnoreCase)) path = path[5..];
        var parts = path.Split('/');
        return path.Equals("Items", StringComparison.OrdinalIgnoreCase)
            || (parts.Length == 3 && parts[0].Equals("Users", StringComparison.OrdinalIgnoreCase)
                && parts[2].Equals("Items", StringComparison.OrdinalIgnoreCase));
    }
    private static bool CheckUrl(IRequest __0, ref Task __result)
    {
        Interlocked.Increment(ref UrlChecks);
        if (!Enabled) return true;
        if (!Ready)
        {
            Interlocked.Increment(ref StartupDenials);
            __0.Response.StatusCode = 503;
            __result = __0.Response.CompleteAsync();
            return false;
        }
        var syncRequest = __0.PathInfo.Contains("/Sync/", StringComparison.OrdinalIgnoreCase);
        var candidates = syncRequest ? new List<string>() : __0.PathInfo.Split('/', StringSplitOptions.RemoveEmptyEntries).ToList();
        foreach (var key in __0.QueryString.Keys.Where(key => (syncRequest ? IsSyncItemReference(key) : IsItemReference(key)) && !(IsItemListRead(__0) && IsListFilter(key))))
        {
            var value = __0.QueryString[key];
            if (!string.IsNullOrEmpty(value)) candidates.AddRange(value.Split(','));
        }
        try
        {
            EnforceMetadataName(__0);
            EnforceSyncReferences(__0);
            // Close the global-search bypass where a caller supplies another user's ID.
            var path = __0.PathInfo.Trim('/');
            if (path.StartsWith("emby/", StringComparison.OrdinalIgnoreCase)) path = path[5..];
            var parts = path.Split('/');
            // Missing and inaccessible individual resources share the same boundary response.
            var read = __0.Verb.Equals("GET", StringComparison.OrdinalIgnoreCase)
                || __0.Verb.Equals("HEAD", StringComparison.OrdinalIgnoreCase);
            var playbackPost = __0.Verb.Equals("POST", StringComparison.OrdinalIgnoreCase)
                && parts.Length == 3 && parts[0].Equals("Items", StringComparison.OrdinalIgnoreCase)
                && parts[2].Equals("PlaybackInfo", StringComparison.OrdinalIgnoreCase);
            string? resourceId = playbackPost ? parts[1] : null;
            if (read && parts.Length >= 3 && (parts[0].Equals("Videos", StringComparison.OrdinalIgnoreCase)
                || (parts[0].Equals("Items", StringComparison.OrdinalIgnoreCase)
                    && (parts[2].Equals("PlaybackInfo", StringComparison.OrdinalIgnoreCase) || parts[2].Equals("Download", StringComparison.OrdinalIgnoreCase))))) resourceId = parts[1];
            if (read && parts.Length == 4 && parts[0].Equals("Users", StringComparison.OrdinalIgnoreCase)
                && parts[2].Equals("Items", StringComparison.OrdinalIgnoreCase)) resourceId = parts[3];
            if (resourceId != null && (long.TryParse(resourceId, out _) || Guid.TryParse(resourceId, out _)) && ResolveItem(resourceId) == null)
                throw new ResourceNotFoundException("Item not found.");
            if (parts[0].Equals("Items", StringComparison.OrdinalIgnoreCase)
                || parts[0].Equals("Channels", StringComparison.OrdinalIgnoreCase)
                || parts[0].Equals("Search", StringComparison.OrdinalIgnoreCase)
                || parts[0].Equals("Genres", StringComparison.OrdinalIgnoreCase)
                || parts[0].Equals("Studios", StringComparison.OrdinalIgnoreCase)
                || parts[0].Equals("Tags", StringComparison.OrdinalIgnoreCase)
                || (parts.Length > 2 && parts[0].Equals("Users", StringComparison.OrdinalIgnoreCase)
                    && (parts[2].Equals("Items", StringComparison.OrdinalIgnoreCase) || parts[2].Equals("Views", StringComparison.OrdinalIgnoreCase))))
            {
                var actual = Authorization!.GetAuthorizationInfo(__0).User;
                var requestedUser = __0.QueryString["UserId"];
                if (parts.Length > 2 && parts[0].Equals("Users", StringComparison.OrdinalIgnoreCase)) requestedUser = parts[1];
                if (!string.IsNullOrEmpty(requestedUser) && Users!.GetUserById(requestedUser)?.InternalId != actual?.InternalId)
                {
                    Interlocked.Increment(ref Denials);
                    throw new ResourceNotFoundException("Item not found.");
                }
            }
            Enforce(__0, candidates);
        }
        catch (ResourceNotFoundException)
        {
            __0.Response.StatusCode = 404;
            __result = __0.Response.CompleteAsync();
            return false;
        }
        return true;
    }

    private static bool CheckService(object __1, IRequest __2, ref Task<object> __result, out object? __state,
        object? __instance, MethodBase __originalMethod, object[] __args)
    {
        __state = new ServiceScope(CurrentMetadata.Value, CurrentSyncSubject.Value, CurrentStaleSyncCacheIds.Value, CurrentStreamSubject.Value);
        Interlocked.Increment(ref DtoChecks);
        if (!Enabled) return true;
        CurrentStreamSubject.Value = Authorization!.GetAuthorizationInfo(__2).User?.InternalId;
        var path = __2.PathInfo.Replace("/emby/", "/", StringComparison.OrdinalIgnoreCase).Trim('/');
        if (path.Equals("Sync/Data", StringComparison.OrdinalIgnoreCase)) { CurrentSyncSubject.Value = Authorization!.GetAuthorizationInfo(__2).User?.InternalId; CurrentStaleSyncCacheIds.Value = null; }
        var dlnaControl = path.StartsWith("Dlna/", StringComparison.OrdinalIgnoreCase)
            && path.EndsWith("/contentdirectory/control", StringComparison.OrdinalIgnoreCase);
        MetadataPaging? soapPaging = null;
        if (dlnaControl)
        {
            if (!SoapPrepared.Value) {
                __result = ExecuteSoapAsync(__1, __2, __instance, __originalMethod, __args);
                return false;
            }
            soapPaging = PreparedSoapPaging.Value;
        }
        if ((__2.Verb.Equals("GET", StringComparison.OrdinalIgnoreCase) || __2.Verb.Equals("HEAD", StringComparison.OrdinalIgnoreCase) || dlnaControl)
            && !path.StartsWith("PersonalChannelsFixture", StringComparison.OrdinalIgnoreCase))
        {
            var subject = Authorization!.GetAuthorizationInfo(__2).User?.InternalId;
            // Inventory before entering service/library transactions. Never open a second
            // database scan from a nested query hook that may already hold a data context.
            var forbidden = RawItems(new MediaBrowser.Controller.Entities.InternalItemsQuery { Recursive = true })
                .Where(item => FindOwner(item.InternalId.ToString()) is long owner && owner != subject)
                .Select(item => item.InternalId).ToArray();
            MetadataPaging? outputPaging = null;
            if (IsItemListRead(__2) || path.Equals("Library/VirtualFolders/Query", StringComparison.OrdinalIgnoreCase)
                || path.Equals("Sync/Jobs", StringComparison.OrdinalIgnoreCase)
                || path.Equals("Sync/JobItems", StringComparison.OrdinalIgnoreCase))
            {
                var start = __1.GetType().GetProperty("StartIndex");
                var limit = __1.GetType().GetProperty("Limit");
                outputPaging = new MetadataPaging((int?)start?.GetValue(__1), (int?)limit?.GetValue(__1));
                start?.SetValue(__1, null);
                limit?.SetValue(__1, null);
            }
            CurrentMetadata.Value = new MetadataScope(subject, forbidden, outputPaging, soapPaging);
        }
        if (__2.PathInfo.Contains("Genres") || __2.PathInfo.Contains("Studios") || __2.PathInfo.Contains("Tags"))
            lock (MetadataIdentities) MetadataIdentities.Add(__2.PathInfo + " requested=" + __2.QueryString["UserId"]
                + " authenticated=" + Authorization!.GetAuthorizationInfo(__2).User?.InternalId);
        var candidates = new List<string>();
        try {
            if (path.StartsWith("Sync/", StringComparison.OrdinalIgnoreCase)) {
                var inputs = __1 is System.Collections.IEnumerable batch && __1 is not string
                    ? batch.Cast<object>().ToArray() : new[] { __1 };
                foreach (var input in inputs) {
                EnforceSyncTarget(__2, input.GetType().GetProperty("TargetId")?.GetValue(input)?.ToString());
                EnforceInternalSyncTargets(__2, input);
                NormalizeLocalSyncCache(__2, input);
                if (input.GetType().Name == "CreateSyncJob" && string.IsNullOrWhiteSpace(input.GetType().GetProperty("TargetId")?.GetValue(input)?.ToString()))
                    throw new ResourceNotFoundException("Item not found.");
                foreach (var property in input.GetType().GetProperties().Where(property => IsSyncItemReference(property.Name))) {
                    var value = property.GetValue(input);
                    if (value is System.Collections.IEnumerable values && value is not string) {
                        foreach (var id in values) if (id != null) candidates.Add(id.ToString()!);
                    } else if (value != null) candidates.AddRange(value.ToString()!.Split(','));
                }
                if (input.GetType().Name == "CreateSyncJob") {
                    var originalSources = new List<string>();
                    if (input.GetType().GetProperty("ItemIds")?.GetValue(input) is System.Collections.IEnumerable selected)
                        foreach (var id in selected) if (id != null) originalSources.Add(id.ToString()!);
                    var parent = input.GetType().GetProperty("ParentId")?.GetValue(input)?.ToString();
                    if (!string.IsNullOrEmpty(parent) && parent != "0") originalSources.Add(parent);
                    if (originalSources.Any(id => string.IsNullOrEmpty(id) || ResolveItem(id) == null))
                        throw new ResourceNotFoundException("Item not found.");
                }
                var requestedUser = input.GetType().GetProperty("UserId")?.GetValue(input)?.ToString();
                var actual = Authorization!.GetAuthorizationInfo(__2).User;
                if (!string.IsNullOrEmpty(requestedUser) && requestedUser != "0" && requestedUser != actual?.InternalId.ToString()
                    && Users!.GetUserById(requestedUser)?.InternalId != actual?.InternalId)
                    throw new ResourceNotFoundException("Item not found.");
                }
            } else CollectReferences(__1, candidates, 0, IsItemListRead(__2));
            if (__1.GetType().Name == "OpenMediaSource") {
                var itemKey = __1.GetType().GetProperty("ItemId")?.GetValue(__1)?.ToString();
                var token = __1.GetType().GetProperty("OpenToken")?.GetValue(__1) as string;
                lock (Sync) {
                    var owner = itemKey == null ? null : FindOwner(itemKey);
                    if (owner.HasValue && (string.IsNullOrEmpty(token)
                        || !OpenTokenOwners.TryGetValue(TokenHash(token), out var tokenOwner) || tokenOwner != owner))
                        throw new ResourceNotFoundException("Item not found.");
                }
            }
            Enforce(__2, candidates);
        }
        catch (ResourceNotFoundException error)
        {
            __result = Task.FromException<object>(error);
            return false;
        }
        return true;
    }

    private static void FilterService(IRequest __2, ref Task<object> __result, object? __state)
    {
        var outputPaging = CurrentMetadata.Value?.LibraryPaging;
        var staleCacheIds = CurrentStaleSyncCacheIds.Value;
        var soapPaging = CurrentMetadata.Value?.SoapPaging;
        CurrentMetadata.Value = (__state as ServiceScope)?.Metadata;
        CurrentSyncSubject.Value = (__state as ServiceScope)?.SyncSubject;
        CurrentStaleSyncCacheIds.Value = (__state as ServiceScope)?.StaleCacheIds;
        CurrentStreamSubject.Value = (__state as ServiceScope)?.StreamSubject;
        if (!Enabled || !Ready) return;
        if (__2.PathInfo.Contains("Genres") || __2.PathInfo.Contains("Studios") || __2.PathInfo.Contains("Tags"))
            lock (MetadataIdentities) MetadataIdentities.Add("after " + __2.PathInfo + " authenticated=" + Authorization!.GetAuthorizationInfo(__2).User?.InternalId);
        var callerToken = __2.Headers["X-Emby-Token"] ?? __2.QueryString["api_key"];
        __result = FilterResult(__result, Authorization!.GetAuthorizationInfo(__2).User?.InternalId, __2.PathInfo, outputPaging, callerToken, __2.Headers["Host"], soapPaging, staleCacheIds);
    }

    private static async Task<object> ExecuteSoapAsync(object dto, IRequest request, object? controller, MethodBase method, object[] args)
    {
        var oldPrepared = SoapPrepared.Value;
        var oldPaging = PreparedSoapPaging.Value;
        PreparedSoapPaging.Value = await PrepareSoapAsync(dto, request).ConfigureAwait(false);
        SoapPrepared.Value = true;
        try {
            var task = (Task<object>)method.Invoke(controller, args)!;
            return await task.ConfigureAwait(false);
        }
        finally { SoapPrepared.Value = oldPrepared; PreparedSoapPaging.Value = oldPaging; }
    }

    private static async Task<MetadataPaging?> PrepareSoapAsync(object dto, IRequest request)
    {
        var property = dto.GetType().GetProperty("RequestStream");
        if (property?.CanWrite != true || property.GetValue(dto) is not Stream source)
            throw new ResourceNotFoundException("Cannot verify SOAP input.");
        var originalPosition = source.CanSeek ? source.Position : 0;
        using var bytes = new MemoryStream();
        var buffer = new byte[4096];
        int count;
        while ((count = await source.ReadAsync(buffer.AsMemory()).ConfigureAwait(false)) > 0) {
            if (bytes.Length + count > 65536) throw new ResourceNotFoundException("SOAP input exceeds fixture limit.");
            bytes.Write(buffer, 0, count);
        }
        if (source.CanSeek) source.Position = originalPosition;
        bytes.Position = 0;
        using var reader = System.Xml.XmlReader.Create(bytes, new System.Xml.XmlReaderSettings {
            DtdProcessing = System.Xml.DtdProcessing.Prohibit, XmlResolver = null });
        var document = System.Xml.Linq.XDocument.Load(reader);
        var references = document.Descendants().Where(node => node.Name.LocalName == "ObjectID").ToArray();
        try { Enforce(request, references.Select(node => node.Value)); }
        catch (ResourceNotFoundException) {
            // Let the native SOAP handler produce its ordinary missing-object fault.
            // A distinct HTTP denial would otherwise reveal that the hidden ID exists.
            const long missingObject = 999999999;
            if (Library!.GetItemById(missingObject) != null) throw new ResourceNotFoundException("No safe missing fixture ID.");
            foreach (var reference in references) reference.Value = missingObject.ToString();
        }
        MetadataPaging? paging = null;
        var action = document.Descendants().FirstOrDefault(node => node.Name.LocalName == "Browse");
        if (action?.Elements().FirstOrDefault(node => node.Name.LocalName == "BrowseFlag")?.Value == "BrowseDirectChildren") {
            var start = action.Elements().First(node => node.Name.LocalName == "StartingIndex");
            var limit = action.Elements().First(node => node.Name.LocalName == "RequestedCount");
            if (!int.TryParse(start.Value, out var offset) || !int.TryParse(limit.Value, out var size) || offset < 0 || size < 0)
                throw new ResourceNotFoundException("Unsupported SOAP page.");
            paging = new MetadataPaging(offset, size == 0 ? null : size);
            start.Value = "0";
            limit.Value = "0";
        }
        property.SetValue(dto, new MemoryStream(System.Text.Encoding.UTF8.GetBytes(document.ToString(System.Xml.Linq.SaveOptions.DisableFormatting)), false));
        return paging;
    }

    private static void ScopeMetadataQuery(MediaBrowser.Controller.Entities.InternalItemsQuery __0, out object? __state)
    {
        __state = null;
        var scope = CurrentMetadata.Value;
        if (scope == null || !Enabled || !Ready) return;
        __state = new MetadataPaging(__0.StartIndex, __0.Limit);
        __0.StartIndex = null;
        __0.Limit = null;
        Interlocked.Increment(ref MetadataQueries);
        var forbidden = scope.ForbiddenIds;
        lock (MetadataIdentities) MetadataIdentities.Add("query user=" + scope.UserId + " ids=" + string.Join(',', forbidden));
        __0.ExcludeItemIds = (__0.ExcludeItemIds ?? Array.Empty<long>()).Concat(forbidden).Distinct().ToArray();
        if (scope.UserId.HasValue) __0.User = Users!.GetUserById(scope.UserId.Value);
    }

    // Exclude inaccessible source items before the database computes pages and totals.
    // The internal inventory must remain unscoped so it can discover forbidden descendants.
    private static MediaBrowser.Controller.Entities.BaseItem[] RawItems(MediaBrowser.Controller.Entities.InternalItemsQuery query)
    {
        InternalScanDepth.Value++;
        try { return Library!.GetItemList(query); }
        finally { InternalScanDepth.Value--; }
    }

    private static void ScopeItemQuery(MediaBrowser.Controller.Entities.InternalItemsQuery __0)
    {
        var scope = CurrentMetadata.Value;
        if (scope == null || InternalScanDepth.Value != 0 || !Enabled || !Ready) return;
        __0.ExcludeItemIds = (__0.ExcludeItemIds ?? Array.Empty<long>()).Concat(scope.ForbiddenIds).Distinct().ToArray();
        if (scope.UserId.HasValue) __0.User = Users!.GetUserById(scope.UserId.Value);
    }

    private static void FilterMetadataQuery(MediaBrowser.Controller.Entities.InternalItemsQuery __0, MethodBase __originalMethod,
        ref MediaBrowser.Model.Querying.QueryResult<Tuple<MediaBrowser.Controller.Entities.BaseItem, MediaBrowser.Model.Dto.ItemCounts>> __result, object? __state)
    {
        var scope = CurrentMetadata.Value;
        if (scope == null || !Enabled || !Ready) return;
        var paging = __state as MetadataPaging;
        if (paging != null) { __0.StartIndex = paging.StartIndex; __0.Limit = paging.Limit; }
        var kept = new List<Tuple<MediaBrowser.Controller.Entities.BaseItem, MediaBrowser.Model.Dto.ItemCounts>>();
        var typeName = __originalMethod.Name.Contains("Genre") ? "Genres" : __originalMethod.Name.Contains("Studio") ? "Studios" : "Tags";
        if (!Enum.TryParse<MediaBrowser.Controller.Library.ItemLinkType>(typeName, out var linkType)) throw new InvalidOperationException("Unknown metadata link type.");
        var all = RawItems(new MediaBrowser.Controller.Entities.InternalItemsQuery { Recursive = true });
        var nativeVisible = RawItems(new MediaBrowser.Controller.Entities.InternalItemsQuery { Recursive = true, User = __0.User })
            .Select(item => item.InternalId).ToHashSet();
        var sources = all.Where(item => Allowed(item.InternalId.ToString(), scope.UserId)
            && (FindOwner(item.InternalId.ToString()).HasValue || nativeVisible.Contains(item.InternalId)))
            .Select(item => (Item: item, Links: Library!.GetItemLinks(item.InternalId, new List<MediaBrowser.Controller.Library.ItemLinkType> { linkType }, CancellationToken.None))).ToArray();
        foreach (var pair in __result.Items)
        {
            var visible = sources.Where(source => source.Links.Any(link => link.Item3 == pair.Item1.InternalId)).Select(source => source.Item).ToArray();
            if (visible.Length == 0) continue;
            // Do not retain counts that include someone else's private videos.
            var counts = new MediaBrowser.Model.Dto.ItemCounts();
            foreach (var property in counts.GetType().GetProperties().Where(property => property.CanWrite && property.PropertyType == typeof(int)))
            {
                var countType = property.Name.EndsWith("Count") ? property.Name[..^5] : "";
                var count = countType is "Item" or "Total" ? visible.Length : visible.Count(item => item.GetType().Name == countType);
                property.SetValue(counts, count);
            }
            kept.Add(Tuple.Create(pair.Item1, counts));
        }
        __result.TotalRecordCount = kept.Count;
        IEnumerable<Tuple<MediaBrowser.Controller.Entities.BaseItem, MediaBrowser.Model.Dto.ItemCounts>> page = kept.Skip(paging?.StartIndex ?? 0);
        if (paging?.Limit != null) page = page.Take(paging.Limit.Value);
        __result.Items = page.ToArray();
    }

    private static async Task<object> FilterResult(Task<object> task, long? userId, string path, MetadataPaging? outputPaging = null,
        string? callerToken = null, string? authority = null, MetadataPaging? soapPaging = null, string[]? staleCacheIds = null)
    {
        var result = await task.ConfigureAwait(false);
        if (staleCacheIds is { Length: > 0 } && result?.GetType().GetProperty("ItemIdsToRemove") is { CanWrite: true } removalProperty) {
            var native = removalProperty.GetValue(result) as string[] ?? Array.Empty<string>();
            // Echo only cache tokens already supplied by this caller. Never return a hidden alias.
            removalProperty.SetValue(result, native.Concat(staleCacheIds).Distinct(StringComparer.Ordinal).ToArray());
        }
        if (result?.GetType().GetProperty("Targets") is { } targetProperty
            && targetProperty.GetValue(result) is System.Collections.IList targets) {
            if (targets is Array targetArray && targetProperty.CanWrite) {
                var kept = targetArray.Cast<object>().Where(item => ResponseObjectAllowed(item, userId)).ToArray();
                var filteredTargets = Array.CreateInstance(targetArray.GetType().GetElementType()!, kept.Length);
                Array.Copy(kept, filteredTargets, kept.Length);
                targetProperty.SetValue(result, filteredTargets);
            } else if (!targets.IsReadOnly) {
                for (var index = targets.Count - 1; index >= 0; index--)
                    if (targets[index] is object target && !ResponseObjectAllowed(target, userId)) targets.RemoveAt(index);
            }
        }
        // Some native services return a QueryResult DTO directly, before HTTP serialization.
        // Filtering StreamWriter alone does not cover that result shape.
        if (result != null && result.GetType().GetProperty("Items") is { CanWrite: true } itemsProperty
            && itemsProperty.GetValue(result) is Array queryItems)
        {
            var kept = queryItems.Cast<object>().Where(item => ResponseObjectAllowed(item, userId)).ToArray();
            if (kept.Length != queryItems.Length || outputPaging != null)
                result.GetType().GetProperty("TotalRecordCount")?.SetValue(result, kept.Length);
            IEnumerable<object> page = kept;
            if (outputPaging != null) {
                page = page.Skip(outputPaging.StartIndex ?? 0);
                if (outputPaging.Limit.HasValue) page = page.Take(outputPaging.Limit.Value);
            }
            var pageItems = page.ToArray();
            var filtered = Array.CreateInstance(queryItems.GetType().GetElementType()!, pageItems.Length);
            Array.Copy(pageItems, filtered, pageItems.Length);
            itemsProperty.SetValue(result, filtered);
        }
        if (path.Trim('/').EndsWith("Sessions", StringComparison.OrdinalIgnoreCase) && result != null)
            SessionResponseShape = result.GetType().FullName + " " + string.Join(";", result.GetType().GetProperties().Select(property => property.Name + ":" + property.PropertyType.FullName));
        if (result is Array sessions)
        {
            var kept = sessions.Cast<object>().Where(session => {
                if (!ResponseObjectAllowed(session, userId)) return false;
                var playing = session.GetType().GetProperty("NowPlayingItem")?.GetValue(session);
                var id = playing?.GetType().GetProperty("Id")?.GetValue(playing)?.ToString();
                return id == null || Allowed(id, userId);
            }).ToArray();
            var filtered = Array.CreateInstance(result.GetType().GetElementType()!, kept.Length);
            Array.Copy(kept, filtered, kept.Length);
            return filtered;
        }
        // Ready-to-transfer Sync responses are List<SyncedItem>, rather than an
        // array or QueryResult. Remove the complete envelope, including job name
        // and file references, when its nested media belongs to another user.
        if (result is System.Collections.IList list && result is not Array) {
            for (var index = list.Count - 1; index >= 0; index--) {
                if (list[index] is not object entry || ResponseObjectAllowed(entry, userId)) continue;
                if (list.IsReadOnly || list.IsFixedSize) throw new ResourceNotFoundException("Cannot scope response.");
                list.RemoveAt(index);
            }
        }
        if (result?.GetType().FullName == "Emby.Server.Implementations.HttpServer.StreamWriter")
        {
            var bytesField = result.GetType().GetField("SourceBytes", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)!;
            var headers = result.GetType().GetProperty("Headers")?.GetValue(result) as IDictionary<string, string>;
            var declaredType = headers?.FirstOrDefault(pair => pair.Key.Equals("Content-Type", StringComparison.OrdinalIgnoreCase)).Value;
            var metadata = declaredType?.Contains("json", StringComparison.OrdinalIgnoreCase) == true
                || declaredType?.Contains("xml", StringComparison.OrdinalIgnoreCase) == true;
            if (!string.IsNullOrEmpty(declaredType) && !metadata) return result;
            var streamField = result.GetType().GetField("SourceStream", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)!;
            if (metadata && bytesField.GetValue(result) is ReadOnlyMemory<byte> empty && empty.IsEmpty
                && streamField.GetValue(result) is MediaBrowser.Model.IO.StreamHandler handler && handler.Stream != null)
            {
                byte[] materialized;
                if (handler.Stream is MemoryStream memory) materialized = memory.ToArray();
                else { using var copy = new MemoryStream(); await handler.Stream.CopyToAsync(copy).ConfigureAwait(false); materialized = copy.ToArray(); }
                bytesField.SetValue(result, new ReadOnlyMemory<byte>(materialized));
                streamField.SetValue(result, null);
                handler.Dispose();
            }
            if (bytesField.GetValue(result) is ReadOnlyMemory<byte> bytes && bytes.Length > 0)
            {
                var encoding = headers?.FirstOrDefault(pair => pair.Key.Equals("Content-Encoding", StringComparison.OrdinalIgnoreCase)).Value;
                var raw = bytes.ToArray();
                if (encoding is "gzip" or "br" or "deflate")
                {
                    using var source = new MemoryStream(raw);
                    using Stream decoder = encoding == "gzip" ? new System.IO.Compression.GZipStream(source, System.IO.Compression.CompressionMode.Decompress)
                        : encoding == "br" ? new System.IO.Compression.BrotliStream(source, System.IO.Compression.CompressionMode.Decompress)
                        : new System.IO.Compression.DeflateStream(source, System.IO.Compression.CompressionMode.Decompress);
                    using var decoded = new MemoryStream();
                    decoder.CopyTo(decoded);
                    raw = decoded.ToArray();
                }
                if (raw.Length == 0) return result;
                var payload = System.Text.Encoding.UTF8.GetString(raw).TrimStart('\uFEFF', ' ', '\r', '\n', '\t');
                byte[] replacement;
                if (payload.StartsWith('{') || payload.StartsWith('['))
                {
                    var node = System.Text.Json.Nodes.JsonNode.Parse(payload);
                    var filtered = Scrub(node, userId);
                    if (filtered == null) throw new ResourceNotFoundException("Item not found.");
                    if (outputPaging != null && filtered is System.Text.Json.Nodes.JsonObject pageResult
                        && pageResult["Items"] is System.Text.Json.Nodes.JsonArray allItems) {
                        pageResult["TotalRecordCount"] = allItems.Count;
                        IEnumerable<System.Text.Json.Nodes.JsonNode?> page = allItems.Skip(outputPaging.StartIndex ?? 0);
                        if (outputPaging.Limit.HasValue) page = page.Take(outputPaging.Limit.Value);
                        pageResult["Items"] = new System.Text.Json.Nodes.JsonArray(page.Select(item => item == null
                            ? null : System.Text.Json.Nodes.JsonNode.Parse(item.ToJsonString())).ToArray());
                    }
                    replacement = System.Text.Encoding.UTF8.GetBytes(filtered.ToJsonString());
                }
                else if (payload.StartsWith('<') && headers != null
                    && headers.TryGetValue("Content-Type", out var contentType) && contentType.Contains("xml", StringComparison.OrdinalIgnoreCase))
                {
                    using var reader = System.Xml.XmlReader.Create(new StringReader(payload), new System.Xml.XmlReaderSettings {
                        DtdProcessing = System.Xml.DtdProcessing.Prohibit, XmlResolver = null });
                    var document = System.Xml.Linq.XDocument.Load(reader);
                    if (document.Root == null || !ScrubXml(document.Root, userId, callerToken: callerToken, authority: authority, soapPaging: soapPaging)) throw new ResourceNotFoundException("Item not found.");
                    if (outputPaging != null && document.Root.Elements().FirstOrDefault(element => element.Name.LocalName == "Items") is { } allItems) {
                        var entries = allItems.Elements().ToArray();
                        var total = document.Root.Elements().FirstOrDefault(element => element.Name.LocalName == "TotalRecordCount");
                        if (total != null) total.Value = entries.Length.ToString();
                        IEnumerable<System.Xml.Linq.XElement> page = entries.Skip(outputPaging.StartIndex ?? 0);
                        if (outputPaging.Limit.HasValue) page = page.Take(outputPaging.Limit.Value);
                        var retained = page.ToHashSet();
                        foreach (var entry in entries) if (!retained.Contains(entry)) entry.Remove();
                    }
                    replacement = System.Text.Encoding.UTF8.GetBytes(document.ToString(System.Xml.Linq.SaveOptions.DisableFormatting));
                }
                else return result;
                if (encoding is "gzip" or "br" or "deflate")
                {
                    using var encoded = new MemoryStream();
                    using (Stream encoder = encoding == "gzip" ? new System.IO.Compression.GZipStream(encoded, System.IO.Compression.CompressionLevel.Fastest, true)
                        : encoding == "br" ? new System.IO.Compression.BrotliStream(encoded, System.IO.Compression.CompressionLevel.Fastest, true)
                        : new System.IO.Compression.DeflateStream(encoded, System.IO.Compression.CompressionLevel.Fastest, true)) encoder.Write(replacement);
                    replacement = encoded.ToArray();
                }
                bytesField.SetValue(result, new ReadOnlyMemory<byte>(replacement));
                headers?.Remove("Content-Length");
            }
        }
        return result!;
    }

    private static bool ResponseObjectAllowed(object item, long? userId) {
        if (item.GetType().Name == "SyncTarget" && !SyncTargetAllowed(item.GetType().GetProperty("Id")?.GetValue(item)?.ToString() ?? "", userId)) return false;
        foreach (var nestedName in new[] { "Item", "NowPlayingItem" }) {
            var nested = item.GetType().GetProperty(nestedName)?.GetValue(item);
            var nestedId = nested?.GetType().GetProperty("Id")?.GetValue(nested)?.ToString();
            if (nestedId != null && !Allowed(nestedId, userId)) return false;
        }
        return (item.GetType().FullName?.Contains(".Sync.", StringComparison.Ordinal) == true
            ? new[] { "ItemId", "ParentId" } : new[] { "Id", "ItemId", "ParentId", "ChannelId" })
            .All(name => item.GetType().GetProperty(name)?.GetValue(item)?.ToString() is not string id || Allowed(id, userId));
    }

    private static bool Allowed(string id, long? userId)
    {
        lock (Sync)
        {
            var owner = FindOwner(id);
            if (owner.HasValue) return owner == userId;
            var item = ResolveItem(id);
            var kind = item?.GetType().Name;
            if (kind is "Genre" or "Studio" or "Tag")
                return MetadataNameAllowed(kind + "s", item!.Name, userId);
            return true;
        }
    }

    private static MediaBrowser.Controller.Entities.BaseItem? ResolveItem(string candidate) =>
        long.TryParse(candidate, out var numeric) ? Library!.GetItemById(numeric)
        : Guid.TryParse(candidate, out var guid) ? Library!.GetItemById(guid) : null;

    private static bool MetadataNameAllowed(string category, string name, long? userId)
    {
        if (!userId.HasValue || !Enum.TryParse<MediaBrowser.Controller.Library.ItemLinkType>(category, true, out var linkType)) return false;
        var nativeIds = RawItems(new MediaBrowser.Controller.Entities.InternalItemsQuery {
            Recursive = true, User = Users!.GetUserById(userId.Value) }).Select(item => item.InternalId).ToHashSet();
        foreach (var source in RawItems(new MediaBrowser.Controller.Entities.InternalItemsQuery { Recursive = true }))
        {
            var owner = FindOwner(source.InternalId.ToString());
            if (owner.HasValue ? owner != userId : !nativeIds.Contains(source.InternalId)) continue;
            var links = Library!.GetItemLinks(source.InternalId, new List<MediaBrowser.Controller.Library.ItemLinkType> { linkType }, CancellationToken.None);
            if (links.Any(link => link.Item2.Equals(name, StringComparison.OrdinalIgnoreCase))) return true;
        }
        return false;
    }

    private static void EnforceMetadataName(IRequest request)
    {
        var segments = request.PathInfo.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var index = Array.FindIndex(segments, segment => segment.Equals("Genres", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("Studios", StringComparison.OrdinalIgnoreCase) || segment.Equals("Tags", StringComparison.OrdinalIgnoreCase));
        if (index < 0 || index + 1 >= segments.Length) return;
        var actual = Authorization!.GetAuthorizationInfo(request).User?.InternalId;
        if (!MetadataNameAllowed(segments[index], Uri.UnescapeDataString(segments[index + 1]), actual))
            throw new ResourceNotFoundException("Item not found.");
    }

    private static bool IsOutputReference(string key) => IsItemReference(key)
        || key is "ItemsAdded" or "ItemsUpdated" or "ItemsRemoved" or "FoldersAddedTo" or "FoldersRemovedFrom" or "CollectionFolders";

    private static bool ScrubXml(System.Xml.Linq.XElement element, long? userId, string? referenceContext = null,
        string? callerToken = null, string? authority = null, MetadataPaging? soapPaging = null)
    {
        foreach (var attribute in element.Attributes().Where(attribute => IsOutputReference(attribute.Name.LocalName)))
            if (!Allowed(attribute.Value, userId)) return false;
        // UPnP SOAP encodes DIDL-Lite as XML text inside Result, rather than child nodes.
        // Parse that document explicitly; checking only the SOAP envelope misses its items.
        if (element.Name.LocalName == "Result" && !element.HasElements && element.Value.TrimStart().StartsWith('<'))
        {
            using var reader = System.Xml.XmlReader.Create(new StringReader(element.Value), new System.Xml.XmlReaderSettings {
                DtdProcessing = System.Xml.DtdProcessing.Prohibit, XmlResolver = null });
            var embedded = System.Xml.Linq.XDocument.Load(reader);
            if (embedded.Root?.Name.LocalName == "DIDL-Lite")
            {
                var before = embedded.Root.Elements().Count();
                if (!ScrubXml(embedded.Root, userId, callerToken: callerToken, authority: authority)) return false;
                var after = embedded.Root.Elements().Count();
                if ((after != before || soapPaging != null) && element.Parent != null)
                {
                    var total = element.Parent.Elements().FirstOrDefault(sibling => sibling.Name.LocalName == "TotalMatches");
                    // The whole visible total can only be derived from a complete result.
                    // A page needs source-side scoping; never report its length as the global total.
                    if (total != null && total.Value != before.ToString())
                        throw new ResourceNotFoundException("Cannot safely filter paged SOAP result.");
                    if (total != null) total.Value = after.ToString();
                    if (soapPaging != null) {
                        var all = embedded.Root.Elements().ToArray();
                        IEnumerable<System.Xml.Linq.XElement> page = all.Skip(soapPaging.StartIndex ?? 0);
                        if (soapPaging.Limit.HasValue) page = page.Take(soapPaging.Limit.Value);
                        var keep = page.ToHashSet();
                        foreach (var item in all.Where(item => !keep.Contains(item))) item.Remove();
                    }
                    var returned = element.Parent.Elements().FirstOrDefault(sibling => sibling.Name.LocalName == "NumberReturned");
                    if (returned != null) returned.Value = embedded.Root.Elements().Count().ToString();
                }
                element.Value = embedded.ToString(System.Xml.Linq.SaveOptions.DisableFormatting);
            }
        }
        var children = element.Elements().ToArray();
        if (children.Length == 0 && Uri.TryCreate(element.Value, UriKind.Absolute, out var resource)
            && resource.Scheme is "http" or "https" && resource.Authority.Equals(authority, StringComparison.OrdinalIgnoreCase)
            && resource.AbsolutePath.StartsWith("/emby/", StringComparison.OrdinalIgnoreCase))
        {
            var query = resource.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries);
            if (query.Any(part => part.Split('=', 2)[0].Equals("api_key", StringComparison.OrdinalIgnoreCase)))
            {
                var builder = new UriBuilder(resource);
                var kept = query.Where(part => !part.Split('=', 2)[0].Equals("api_key", StringComparison.OrdinalIgnoreCase)).ToList();
                if (userId.HasValue && !string.IsNullOrEmpty(callerToken)) kept.Add("api_key=" + Uri.EscapeDataString(callerToken));
                builder.Query = string.Join('&', kept);
                element.Value = builder.Uri.AbsoluteUri;
            }
        }
        var targetId = children.FirstOrDefault(child => child.Name.LocalName == "Id")?.Value;
        if (referenceContext == "Targets" && targetId != null && !SyncTargetAllowed(targetId, userId)) return false;
        foreach (var child in children.Where(child => child.Name.LocalName is "Id" or "ItemId" or "ParentId" or "ChannelId"))
            if (!Allowed(child.Value, userId)) return false;
        var playing = children.FirstOrDefault(child => child.Name.LocalName == "NowPlayingItem");
        var playingId = playing?.Elements().FirstOrDefault(child => child.Name.LocalName == "Id")?.Value;
        if (playingId != null && !Allowed(playingId, userId)) return false;
        var nestedItemId = children.FirstOrDefault(child => child.Name.LocalName == "Item")?.Elements().FirstOrDefault(child => child.Name.LocalName == "Id")?.Value;
        if (nestedItemId != null && !Allowed(nestedItemId, userId)) return false;
        if (children.Length == 0 && referenceContext != null && IsOutputReference(referenceContext) && !Allowed(element.Value, userId)) return false;
        foreach (var child in children)
        {
            var key = child.Name.LocalName;
            var before = child.Elements().Count();
            if (!ScrubXml(child, userId, (IsOutputReference(key) || key == "Targets") ? key : referenceContext, callerToken, authority, soapPaging)) child.Remove();
            if (key == "Items" && before != child.Elements().Count())
            {
                var count = element.Elements().FirstOrDefault(sibling => sibling.Name.LocalName == "TotalRecordCount");
                if (count != null) count.Value = child.Elements().Count().ToString();
            }
        }
        return true;
    }

    private static System.Text.Json.Nodes.JsonNode? Scrub(System.Text.Json.Nodes.JsonNode? node, long? userId, string? referenceContext = null)
    {
        if (node is System.Text.Json.Nodes.JsonObject item)
        {
            if (referenceContext == "Targets" && item["Id"] is System.Text.Json.Nodes.JsonValue targetId
                && !SyncTargetAllowed(targetId.ToString(), userId)) return null;
            foreach (var key in new[] { "Id", "ItemId", "ParentId", "ChannelId" })
                if (item[key] is System.Text.Json.Nodes.JsonValue value && !Allowed(value.ToString(), userId)) return null;
            var playingId = item["NowPlayingItem"]?["Id"]?.ToString();
            if (playingId != null && !Allowed(playingId, userId)) return null;
            var nestedItemId = item["Item"]?["Id"]?.ToString();
            if (nestedItemId != null && !Allowed(nestedItemId, userId)) return null;
            foreach (var key in item.Select(property => property.Key).ToArray())
            {
                var child = item[key];
                var oldCount = child is System.Text.Json.Nodes.JsonArray oldArray ? oldArray.Count : -1;
                var filtered = Scrub(child, userId, key);
                if (!ReferenceEquals(child, filtered)) item[key] = filtered;
                if (key == "Items" && filtered is System.Text.Json.Nodes.JsonArray array && array.Count != oldCount && item.ContainsKey("TotalRecordCount"))
                    item["TotalRecordCount"] = array.Count;
            }
        }
        else if (node is System.Text.Json.Nodes.JsonArray values)
        {
            for (var index = values.Count - 1; index >= 0; index--)
                if (Scrub(values[index], userId, referenceContext) == null) values.RemoveAt(index);
        }
        else if (node is System.Text.Json.Nodes.JsonValue reference && referenceContext != null
            && IsOutputReference(referenceContext)
            && !Allowed(reference.ToString(), userId)) return null;
        return node;
    }

    private static bool FilterSocketBytes(IWebSocketConnection __instance, ref ReadOnlyMemory<byte> __0, ref Task __result)
    {
        if (!Enabled) return true;
        var filtered = FilterSocket(__instance, System.Text.Encoding.UTF8.GetString(__0.Span));
        if (filtered == null) { __result = Task.CompletedTask; return false; }
        __0 = System.Text.Encoding.UTF8.GetBytes(filtered);
        return true;
    }

    private static bool FilterSocketChars(IWebSocketConnection __instance, ref ReadOnlyMemory<char> __0, ref Task __result)
    {
        if (!Enabled) return true;
        var filtered = FilterSocket(__instance, new string(__0.Span));
        if (filtered == null) { __result = Task.CompletedTask; return false; }
        __0 = filtered.AsMemory();
        return true;
    }

    private static string? FilterSocket(IWebSocketConnection connection, string text)
    {
        if (!Ready) return null;
        var token = connection.QueryString["api_key"];
        var session = Sessions!.GetSessionByAuthenticationToken(token, connection.QueryString["deviceId"], connection.RemoteAddress, null);
        var user = Users!.GetUserById(session.UserId);
        var node = Scrub(System.Text.Json.Nodes.JsonNode.Parse(text), user.InternalId);
        if (node is System.Text.Json.Nodes.JsonObject message
            && message["MessageType"]?.GetValue<string>() == "LibraryChanged"
            && message["Data"] is System.Text.Json.Nodes.JsonObject data)
        {
            var fields = new[] { "ItemsAdded", "ItemsUpdated", "ItemsRemoved", "FoldersAddedTo", "FoldersRemovedFrom", "CollectionFolders" };
            if (!fields.Any(field => data[field] is System.Text.Json.Nodes.JsonArray items && items.Count != 0)) return null;
        }
        return node?.ToJsonString();
    }
    private static void CollectReferences(object dto, List<string> candidates, int depth, bool ignoreListFilters = false)
    {
        if (depth > 4) throw new ResourceNotFoundException("Item not found.");
        foreach (var property in dto.GetType().GetProperties().Where(property => IsItemReference(property.Name) && !(ignoreListFilters && IsListFilter(property.Name))))
        {
            var value = property.GetValue(dto);
            if (value is string text) candidates.AddRange(text.Split(','));
            else if (value is IEnumerable<string> strings) candidates.AddRange(strings);
            else if (value is long number) candidates.Add(number.ToString());
            else if (value is IEnumerable<long> numbers) candidates.AddRange(numbers.Select(n => n.ToString()));
        }
        foreach (var key in new[] { "NowPlayingQueue", "Item", "Items" })
        {
            var value = dto.GetType().GetProperty(key)?.GetValue(dto);
            if (value is System.Collections.IEnumerable values && value is not string)
                foreach (var child in values) { if (child != null) CollectReferences(child, candidates, depth + 1); }
            else if (value != null) CollectReferences(value, candidates, depth + 1);
        }
    }

    private static bool IsSyncItemReference(string key) => key is "ItemId" or "ItemIds" or "RequestedItemIds" or "ParentId";

    private static bool IsItemReference(string key) =>
        (key == "OpenToken" || key.EndsWith("Id", StringComparison.OrdinalIgnoreCase) || key.EndsWith("Ids", StringComparison.OrdinalIgnoreCase)
            || key.Equals("AdjacentTo", StringComparison.OrdinalIgnoreCase))
        && key is not ("UserId" or "SessionId" or "PlaySessionId" or "DeviceId" or "MediaSourceId");

    private static void Enforce(IRequest request, IEnumerable<string> candidates)
    {
        long[] requiredOwners;
        lock (Sync) requiredOwners = candidates.Select(FindOwner).Where(owner => owner.HasValue)
            .Select(owner => owner!.Value).Distinct().ToArray();
        var metadata = candidates.Select(ResolveItem).Where(item => item?.GetType().Name is "Genre" or "Studio" or "Tag").ToArray();
        if (requiredOwners.Length == 0 && metadata.Length == 0) return;
        // Use the authenticated token's subject, never the UserId in the URL or body.
        var user = Authorization!.GetAuthorizationInfo(request).User;
        var actual = user?.InternalId;
        var path = request.PathInfo.Replace("/emby/", "/", StringComparison.OrdinalIgnoreCase).Trim('/');
        var references = candidates.ToArray();
        // Narrow isolated-test admin policy: allow the actual native deletion
        // of exactly one preapproved synthetic root without an ownership change
        // or another ledger snapshot. Native admin authentication remains active.
        if (user?.Policy.IsAdministrator == true && request.Verb.Equals("POST", StringComparison.OrdinalIgnoreCase)
            && path.Equals("Library/VirtualFolders/Delete", StringComparison.OrdinalIgnoreCase)
            && TrustedFixtureDeleteRoot > 0 && references.Length == 1
            && references[0] == TrustedFixtureDeleteRoot.ToString()) return;
        if (requiredOwners.Any(owner => actual != owner) || metadata.Any(item => !MetadataNameAllowed(item!.GetType().Name + "s", item.Name, actual)))
        {
            Interlocked.Increment(ref Denials);
            throw new ResourceNotFoundException("Item not found.");
        }
        new AuthenticatedAttribute().RequestFilter(request, request.Response, new object());
    }

    private static void TrackNativeOwnership(object? sender, ItemChangeEventArgs change)
        => TrackNativeOwnershipCore(change, false);
    private static void TrackNativeRemovedOwnership(object? sender, ItemChangeEventArgs change)
        => TrackNativeOwnershipCore(change, true);
    private static void TrackNativeOwnershipCore(ItemChangeEventArgs change, bool removed)
    {
        if (!Enabled || Library == null) return;
        lock (Sync) {
            var item = change.Item;
            var candidates = change.CollectionFolders is { Length: > 0 }
                ? change.CollectionFolders : Library.GetCollectionFolders(item).Cast<MediaBrowser.Controller.Entities.BaseItem>().ToArray();
            var roots = candidates.Where(root => root.Name.StartsWith("Private Native Fixture ", StringComparison.Ordinal)).ToArray();
            if (roots.Length == 0 && item is MediaBrowser.Controller.Entities.Folder && item.Name.StartsWith("Private Native Fixture ", StringComparison.Ordinal))
                roots = new[] { item };
            // A removed item's parents may already be gone. The ledger can still
            // locate its collection from references recorded while it existed.
            var persisted = NativeReferenceLedger.RecordChange(item, roots, removed, Users!);
            foreach (var pair in persisted) {
                Owners[pair.Key] = pair.Value;
                HistoricalOwners[pair.Key] = pair.Value;
            }
            if (roots.Length == 0) return;
            var owners = roots.Select(root => Owners.TryGetValue(root.InternalId.ToString(), out var owner) ? owner : -1).Distinct().ToArray();
            var assigned = owners.Length == 1 ? owners[0] : -1;
            if (persisted.TryGetValue(item.InternalId.ToString(), out var durable)) assigned = durable;
            HistoricalOwners[item.InternalId.ToString()] = assigned;
            HistoricalOwners[item.Id.ToString("N")] = assigned;
        }
    }

    private static long? FindOwner(string candidate)
    {
        if (LiveStreamOwners.TryGetValue(candidate, out var streamOwner)) return streamOwner;
        if (OpenTokenOwners.TryGetValue(TokenHash(candidate), out var tokenOwner)) return tokenOwner;
        var productionOwner = ProductionBindingBridge.FindOwner(candidate, Users!, Library!);
        if (productionOwner.HasValue) return productionOwner;
        if (Owners.TryGetValue(candidate, out var known)) return known;
        if (HistoricalOwners.TryGetValue(candidate, out known)) return known;
        MediaBrowser.Controller.Entities.BaseItem? item = null;
        if (long.TryParse(candidate, out var numericId)) item = Library!.GetItemById(numericId);
        else if (Guid.TryParse(candidate, out var guid)) item = Library!.GetItemById(guid);
        if (item is MediaBrowser.Controller.Entities.Video) {
            var privateRoots = Library!.GetCollectionFolders(item)
                .Where(root => root.Name.StartsWith("Private Native Fixture ", StringComparison.Ordinal)).ToArray();
            if (privateRoots.Length != 0) {
                var owners = privateRoots.Select(root => Owners.TryGetValue(root.InternalId.ToString(), out var assigned) ? assigned : -1).Distinct().ToArray();
                return owners.Length == 1 ? owners[0] : -1;
            }
        }
        var visited = new HashSet<long>();
        while (item != null && visited.Add(item.InternalId))
        {
            if (Owners.TryGetValue(item.InternalId.ToString(), out known)) return known;
            if (item is MediaBrowser.Controller.Channels.Channel channel && channel.Name.StartsWith("Personal Fixture ", StringComparison.Ordinal))
                return ChannelOwners.TryGetValue(channel.Name, out var assigned) ? assigned : DefaultOwner ?? throw new ResourceNotFoundException("Unknown private owner.");
            // The fixture marks synthetic private videos at creation, independently of virtual-root ancestry.
            if (item is MediaBrowser.Controller.Entities.Video && item.Name.StartsWith("PrivateNativeVideo_", StringComparison.Ordinal))
                return -1;
            // Synthetic private roots must stay inaccessible until their owner is registered.
            if (item is MediaBrowser.Controller.Entities.Folder && item.Name.StartsWith("Private Native Fixture ", StringComparison.Ordinal))
                return -1;
            item = item.ParentId == 0 ? null : Library!.GetItemById(item.ParentId);
        }
        return null;
    }
    internal static object ReferenceStatus(string candidate) {
        if (!long.TryParse(candidate, out var numeric) || numeric <= 0) throw new ArgumentException("Only numeric fixture references");
        lock (Sync) {
            var owner = FindOwner(candidate);
            return new { KnownPrivate = owner.HasValue, Quarantined = owner == -1, NativeItemExists = Library!.GetItemById(numeric) != null };
        }
    }
    internal static bool IsKnownPrivateFixtureReference(string candidate) {
        lock (Sync) return FindOwner(candidate).HasValue;
    }
}

[Route("/PersonalChannelsFixture/Guard", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class EnablePrivacyGuard : IReturn<object>
{
    public string OwnerUserId { get; set; } = "";
    public Dictionary<string, string> OwnerUserIds { get; set; } = new();
    public Dictionary<string, string> RootOwnerUserIds { get; set; } = new();
}

[Route("/PersonalChannelsFixture/Guard", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class GetPrivacyGuard : IReturn<object> { }

public sealed class PrivacyGuardService : IService
{
    private readonly IHttpServer _server;
    private readonly IAuthorizationContext _authorization;
    private readonly ILibraryManager _library;
    private readonly IUserManager _users;
    private readonly MediaBrowser.Controller.Session.ISessionManager _sessions;
    public PrivacyGuardService(IHttpServer server, IAuthorizationContext authorization, ILibraryManager library, IUserManager users, MediaBrowser.Controller.Session.ISessionManager sessions)
        { _server = server; _authorization = authorization; _library = library; _users = users; _sessions = sessions; }
    public object Post(EnablePrivacyGuard request)
    {
        PrivacyGuard.Enable(_server, _authorization, _library, _users, _sessions, request.OwnerUserId, request.OwnerUserIds, request.RootOwnerUserIds);
        File.WriteAllText(FixturePlugin.StatePath + ".guard.json", System.Text.Json.JsonSerializer.Serialize(request));
        return Get(new GetPrivacyGuard());
    }
    public object Get(GetPrivacyGuard request) => new { PrivacyGuard.BootId, PrivacyGuard.Installed, PrivacyGuard.Enabled, PrivacyGuard.Ready, PrivacyGuard.StartupDenials, PrivacyGuard.UrlChecks, PrivacyGuard.DtoChecks, PrivacyGuard.Denials, PrivacyGuard.SessionResponseShape, PrivacyGuard.MetadataIdentities, PrivacyGuard.MetadataQueries };
}
