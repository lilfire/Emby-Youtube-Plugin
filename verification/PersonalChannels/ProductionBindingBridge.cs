using System.Reflection;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;

namespace PersonalChannelsFixture;

// Isolated adapter to the already-loaded production assembly. The fixture's
// Harmony hooks remain experimental; this does not install production hooks.
internal static class ProductionBindingBridge
{
    internal static string ModePath => FixturePlugin.StatePath + ".production-bindings-mode";
    internal static bool Enabled = File.Exists(ModePath);
    private static readonly BindingFlags InstanceFlags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
    private static Assembly Production => AppDomain.CurrentDomain.GetAssemblies().Single(assembly => assembly.GetName().Name == "Emby.YouTubePlugin");
    private static object Create(string name) => Activator.CreateInstance(Production.GetType("Emby.YouTubePlugin." + name, true)!, InstanceFlags, null,
        new object[] { Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal") }, null)!;
    private static object? Invoke(object target, string method, params object[] args)
        => target.GetType().GetMethod(method, InstanceFlags)!.Invoke(target, args);
    internal static object CreationGuardStatus() => Production.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeCreationHook", true)!
        .GetMethod("Snapshot", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, null)!;
    internal static object ServiceGateStatus() => Production.GetType("Emby.YouTubePlugin.PersonalYouTubeServiceReferenceGate", true)!
        .GetMethod("Snapshot", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, null)!;
    internal static object ItemListStatus() => Production.GetType("Emby.YouTubePlugin.PersonalYouTubeItemListGate", true)!
        .GetMethod("Snapshot", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, null)!;
    internal static object TransferStatus(Guid owner) => Production.GetType("Emby.YouTubePlugin.PersonalYouTubeTransferLease", true)!
        .GetMethod("Snapshot", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null,
            new object[] { Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal"), owner })!;
    internal static object DecideRequest(MediaBrowser.Model.Services.IRequest request, MediaBrowser.Controller.Net.IAuthorizationContext authorization,
        ILibraryManager library, string reference)
    {
        var access = Activator.CreateInstance(Production.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeAccess", true)!, InstanceFlags, null,
            new object[] { Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal"), library }, null)!;
        return new { Decision = Invoke(access, "DecideRequest", request, authorization, reference)!.ToString() };
    }
    internal static object DecideWithoutUser(ILibraryManager library, string reference)
    {
        var access = Activator.CreateInstance(Production.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeAccess", true)!, InstanceFlags, null,
            new object[] { Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal"), library }, null)!;
        return new { Decision = Invoke(access, "DecideReference", reference, null!)!.ToString() };
    }
    internal static object VerifyCreationGuardRequirement(ILibraryManager library)
    {
        try {
            Production.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeCreationHook", true)!
                .GetMethod("RequireAvailable", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, new object[] { library });
            return new { Available = true };
        } catch (TargetInvocationException error) when (error.InnerException is InvalidOperationException) {
            return new { Available = false };
        }
    }
    internal static object CreateNativeWithContext(ILibraryManager library, IUserManager users, string ownerId, string name)
    {
        Production.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeCreationHook", true)!
            .GetMethod("RequireAvailable", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, new object[] { library });
        var owner = users.GetUserById(ownerId);
        if (owner == null || owner.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator)
            throw new ArgumentException("Only controlled synthetic A creation.");
        var snapshot = Invoke(Create("PersonalYouTubeStore"), "Prepare", owner.Id)!;
        var publisher = Activator.CreateInstance(Production.GetType("Emby.YouTubePlugin.PersonalYouTubeNativePublisher", true)!, InstanceFlags, null,
            new object[] { Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal"), library }, null)!;
        var result = Invoke(publisher, "CreatePreparingLibrary", snapshot, name)!;
        var pair = result.GetType().GetProperty("Root")!.GetValue(result)!;
        return new { Exists = true, InternalId = (long)pair.GetType().GetProperty("InternalId")!.GetValue(pair)!,
            Guid = ((Guid)pair.GetType().GetProperty("ItemId")!.GetValue(pair)!).ToString("N") };
    }
    internal static void ReserveCreatingRoot(string name, Guid rootId)
    {
        var generation = Guid.ParseExact(name.Substring("JournalPending_".Length), "N");
        var journal = Create("PersonalYouTubePublicationJournal");
        var pending = ((System.Collections.IEnumerable)Invoke(journal, "Pending")!).Cast<object>()
            .Single(entry => (Guid)entry.GetType().GetProperty("GenerationId")!.GetValue(entry)! == generation);
        var owner = (Guid)pending.GetType().GetProperty("OwnerUserId")!.GetValue(pending)!;
        var snapshot = Invoke(Create("PersonalYouTubeStore"), "Prepare", owner)!;
        if (!(bool)Invoke(journal, "ReserveRootIdentity", snapshot, rootId)!) throw new InvalidOperationException("Creation snapshot became stale");
    }
    internal static object Register(ILibraryManager library, IUserManager users, long rootKey, string ownerId)
    {
        var root = library.GetItemById(rootKey);
        var owner = users.GetUserById(ownerId);
        var suffix = root?.Name == "Private Native Fixture a" ? "a" : root?.Name == "Private Native Fixture b" ? "b" : null;
        if (suffix == null || root is not Folder || owner == null || owner.Name != "native-privacy-fixture-" + suffix
            || owner.Policy.IsAdministrator || owner.Policy.EnableAllFolders
            || !owner.Policy.EnabledFolders.Contains(root.Id.ToString("N")))
            throw new ArgumentException("Only matched isolated native fixture identities can be registered.");
        var items = library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { root.InternalId }, Recursive = true }).Append(root)
            .GroupBy(item => item.InternalId).Select(group => group.Single()).ToArray();
        var video = items.OfType<Video>().SingleOrDefault(item => item.Name == "PrivateNativeVideo_" + suffix + "_client");
        var expectedSuffix = Path.Combine("verification", "PersonalChannels", "bin", "native-client", suffix, "PrivateNativeVideo_" + suffix + "_client.mp4");
        if (video == null || string.IsNullOrEmpty(video.Path)
            || !Path.GetFullPath(video.Path).EndsWith(Path.DirectorySeparatorChar + expectedSuffix, StringComparison.OrdinalIgnoreCase)
            || items.Any(item => item.InternalId != root.InternalId && item.InternalId != video.InternalId
                && !(item is Video && suffix == "a" && item.Name == "PrivateNativeVideo_a_grown"
                    && Path.GetFullPath(item.Path) == Path.Combine(Path.GetDirectoryName(Path.GetFullPath(video.Path))!, "PrivateNativeVideo_a_grown.mp4"))
                && !(item is Photo && item.Name == "fixture-primary-" + suffix
                    && Path.GetFullPath(item.Path) == Path.Combine(Path.GetDirectoryName(Path.GetFullPath(video.Path))!, "fixture-primary-" + suffix + ".png"))
                && (item is not Folder || string.IsNullOrEmpty(item.Path)
                    || Path.GetFullPath(item.Path) != Path.GetDirectoryName(Path.GetFullPath(video.Path)))))
            return new { Registered = false, UnexpectedMember = true,
                VideoPresent = video != null,
                Members = items.Select(item => new { item.Name, Type = item.GetType().FullName }).ToArray() };
        var profiles = Create("PersonalYouTubeStore");
        var snapshot = Invoke(profiles, "Prepare", owner.Id)!;
        var ledger = Create("PersonalYouTubeNativeBindings");
        var itemType = ledger.GetType().GetNestedType("NativeItem", BindingFlags.NonPublic)!;
        var references = Array.CreateInstance(itemType, items.Length);
        for (var index = 0; index < items.Length; index++)
            references.SetValue(Activator.CreateInstance(itemType, new object[] { items[index].InternalId, items[index].Id }), index);
        bool registered;
        try { registered = (bool)Invoke(ledger, "Register", snapshot, references)!; }
        catch (TargetInvocationException error) when (error.InnerException is InvalidOperationException)
        { return new { Registered = false, IdentityConflict = true }; }
        return new { Registered = registered, NativeCount = items.Length, References = items.Select(item => new { InternalId = item.InternalId, Guid = item.Id.ToString("N") }).ToArray() };
    }
    internal static object Enable()
    {
        File.WriteAllBytes(ModePath, new byte[] { 1 });
        if (File.ReadAllBytes(ModePath).Length != 1) throw new IOException("Mode marker did not verify.");
        Enabled = true;
        return new { Enabled };
    }
    internal static object Publication(ILibraryManager library, IUserManager users, long rootKey, string ownerId, string action)
    {
        if (action == "ReserveNew")
        {
            var reservedOwner = users.GetUserById(ownerId);
            if (reservedOwner == null || reservedOwner.Name != "native-privacy-fixture-a" || reservedOwner.Policy.IsAdministrator)
                throw new ArgumentException("Only the isolated A account can reserve a new test root.");
            var reservedSnapshot = Invoke(Create("PersonalYouTubeStore"), "Prepare", reservedOwner.Id)!;
            var reservedJournal = Create("PersonalYouTubePublicationJournal");
            var reserved = Invoke(reservedJournal, "Begin", reservedSnapshot)!;
            return new { State = reserved.GetType().GetProperty("State")!.GetValue(reserved)?.ToString(),
                MediaPath = (string)Invoke(reservedJournal, "MediaPath", reserved)!,
                GenerationId = reserved.GetType().GetProperty("GenerationId")!.GetValue(reserved) };
        }
        var nativeRoot = library.GetItemById(rootKey);
        var owner = users.GetUserById(ownerId);
        if (action is "RegisterNew" or "ActivateNew")
        {
            if (nativeRoot is not Folder || owner == null || owner.Name != "native-privacy-fixture-a" || owner.Policy.IsAdministrator)
                throw new ArgumentException("Only the new isolated journal root.");
            var newSnapshot = Invoke(Create("PersonalYouTubeStore"), "Prepare", owner.Id)!;
            var newJournal = Create("PersonalYouTubePublicationJournal");
            var newEntry = Invoke(newJournal, "Begin", newSnapshot)!;
            var generation = (Guid)newEntry.GetType().GetProperty("GenerationId")!.GetValue(newEntry)!;
            var media = (string)Invoke(newJournal, "MediaPath", newEntry)!;
            var info = library.GetVirtualFolders().Single(folder => folder.ItemId == rootKey.ToString());
            if (nativeRoot.Name != "JournalPending_" + generation.ToString("N") || info.Locations.Count() != 1
                || Path.GetFullPath(info.Locations.Single()) != Path.GetFullPath(media)) throw new ArgumentException("New root source mismatch.");
            var newNativeType = Production.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeBindings", true)!.GetNestedType("NativeItem", BindingFlags.NonPublic)!;
            object Pair(BaseItem item) => Activator.CreateInstance(newNativeType, new object[] { item.InternalId, item.Id })!;
            if (action == "ActivateNew") return new { Activated = (bool)Invoke(newJournal, "Activate", newSnapshot, Pair(nativeRoot))! };
            var members = library.GetItemList(new InternalItemsQuery { AncestorIds = new[] { rootKey }, Recursive = true }).Append(nativeRoot).ToArray();
            if (members.Any(item => item.InternalId != rootKey && (string.IsNullOrEmpty(item.Path)
                || !Path.GetFullPath(item.Path).StartsWith(Path.GetFullPath(media) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                    && Path.GetFullPath(item.Path) != Path.GetFullPath(media)))) throw new ArgumentException("Unexpected new root member.");
            var pairs = Array.CreateInstance(newNativeType, members.Length);
            for (var index = 0; index < members.Length; index++) pairs.SetValue(Pair(members[index]), index);
            return new { Registered = (bool)Invoke(Create("PersonalYouTubeNativeBindings"), "Register", newSnapshot, pairs)!, NativeCount = members.Length };
        }
        var suffix = nativeRoot?.Name == "Private Native Fixture a" ? "a" : nativeRoot?.Name == "Private Native Fixture b" ? "b" : null;
        if (suffix == null || nativeRoot is not Folder || owner == null || owner.Policy.IsAdministrator
            || owner.Name != "native-privacy-fixture-" + suffix || owner.Policy.EnableAllFolders
            || !owner.Policy.EnabledFolders.Contains(nativeRoot.Id.ToString("N")))
            throw new ArgumentException("Only matched isolated publication identities.");
        var snapshot = Invoke(Create("PersonalYouTubeStore"), "Prepare", owner.Id)!;
        var journal = Create("PersonalYouTubePublicationJournal");
        if (action == "Begin")
        {
            var entry = Invoke(journal, "Begin", snapshot)!;
            return new { State = entry.GetType().GetProperty("State")!.GetValue(entry)?.ToString() };
        }
        if (action != "Activate") throw new ArgumentException("Unknown publication action.");
        var nativeType = Production.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeBindings", true)!.GetNestedType("NativeItem", BindingFlags.NonPublic)!;
        var root = Activator.CreateInstance(nativeType, new object[] { nativeRoot.InternalId, nativeRoot.Id })!;
        return new { Activated = (bool)Invoke(journal, "Activate", snapshot, root)! };
    }
    internal static long? FindOwner(string reference, IUserManager users, ILibraryManager library)
    {
        if (!Enabled) return null;
        var ledger = Create("PersonalYouTubeNativeBindings");
        var canonical = Guid.TryParse(reference, out var aliasGuid) ? aliasGuid.ToString("N")
            : long.TryParse(reference, out var aliasNumber) && aliasNumber > 0 ? aliasNumber.ToString(System.Globalization.CultureInfo.InvariantCulture) : reference;
        var binding = Invoke(ledger, "Find", canonical);
        var owner = binding == null ? Guid.Empty : (Guid)binding.GetType().GetProperty("OwnerUserId")!.GetValue(binding)!;
        var access = Activator.CreateInstance(Production.GetType("Emby.YouTubePlugin.PersonalYouTubeNativeAccess", true)!, InstanceFlags, null,
            new object[] { Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "youtube-personal"), library }, null)!;
        var decision = Invoke(access, "DecideReference", reference, users.GetUserById(owner.ToString("N"))!);
        if (decision!.ToString() == "Unknown") return null;
        if (decision.ToString() != "Allowed") return -1;
        return users.GetUserById(owner.ToString("N"))?.InternalId ?? -1;
    }
}
