using System.Reflection;
using System.Security.Cryptography;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

[Route("/PersonalChannelsFixture/ApiAudit", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class ApiAudit : IReturn<object> { }

[Route("/PersonalChannelsFixture/AUserData", "GET")]
[Authenticated(Roles = "Admin")]
public sealed class AUserData : IReturn<object>
{
    public string UserId { get; set; } = "";
    public long ItemId { get; set; }
}

[Route("/PersonalChannelsFixture/ACleanupPlaylists", "POST")]
[Authenticated(Roles = "Admin")]
public sealed class ACleanupPlaylists : IReturn<object> { }

public sealed partial class FixtureService
{
    public object Post(ACleanupPlaylists request)
    {
        var playlists = _library.GetItemList(new InternalItemsQuery { Recursive = true, IncludeItemTypes = new[] { "Playlist" } })
            .Where(item => item.Name.StartsWith("A-audit-", StringComparison.Ordinal)).ToArray();
        foreach (var item in playlists)
        {
            if (item.Name is not ("A-audit-a-a" or "A-audit-a-b" or "A-audit-a-mixed" or "A-audit-b-a" or "A-audit-b-b" or "A-audit-b-mixed"))
                throw new ArgumentException("Unexpected audit playlist");
            var expected = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(FixturePlugin.StatePath)!, "userplaylists")) + Path.DirectorySeparatorChar;
            if (string.IsNullOrEmpty(item.Path) || !Path.GetFullPath(item.Path).StartsWith(expected, StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("Unexpected audit playlist path");
            for (var directory = new DirectoryInfo(Path.GetDirectoryName(item.Path)!); directory != null && directory.FullName.StartsWith(expected.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase); directory = directory.Parent)
                if ((directory.Attributes & FileAttributes.ReparsePoint) != 0) throw new ArgumentException("Audit playlist reparse point");
            _library.DeleteItem(item, new DeleteOptions { DeleteFileLocation = true });
        }
        return new { Removed = playlists.Length };
    }
    public object Get(AUserData request)
    {
        var user = _users.GetUserById(request.UserId);
        var item = _library.GetItemById(request.ItemId);
        if (user?.Name is not ("native-privacy-fixture-a" or "native-privacy-fixture-b")
            || user.Policy.IsAdministrator || item?.Name is not ("PrivateNativeVideo_a_client" or "PrivateNativeVideo_b_client"))
            throw new ArgumentException("Synthetic A sources only");
        var getter = typeof(IUserDataManager).GetMethods().Single(method => method.Name == "GetUserData"
            && method.GetParameters().Select(parameter => parameter.ParameterType).SequenceEqual(new[] { typeof(User), typeof(BaseItem), typeof(CancellationToken) }));
        var data = getter.Invoke(_historyData, new object[] { user, item, CancellationToken.None })!;
        return new[] { "Played", "PlayCount", "PlaybackPositionTicks", "IsFavorite", "Rating" }
            .ToDictionary(name => name, name => data.GetType().GetProperty(name)?.GetValue(data) ?? data.GetType().GetField(name)?.GetValue(data));
    }

    public object Get(ApiAudit request)
    {
        var types = AppDomain.CurrentDomain.GetAssemblies()
            .Where(assembly => assembly.GetName().Name?.StartsWith("Emby.", StringComparison.Ordinal) == true
                || assembly.GetName().Name?.StartsWith("MediaBrowser.", StringComparison.Ordinal) == true
                || assembly.GetName().Name == "MultiMediaServices")
            .SelectMany(assembly => assembly.GetTypes()).ToArray();
        var handlers = types.Where(type => typeof(IService).IsAssignableFrom(type))
            .SelectMany(type => type.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly))
            .Where(method => method.GetParameters().Length == 1 && method.Name is "Get" or "Post" or "Delete" or "Put" or "Head" or "Any")
            .ToLookup(method => method.GetParameters()[0].ParameterType);
        object Method(MethodInfo method) => new {
            Service = method.DeclaringType!.FullName, method.Name, Signature = method.ToString(),
            ReturnType = method.ReturnType.ToString(),
            BodyHash = method.GetMethodBody()?.GetILAsByteArray() is byte[] bytes ? Convert.ToHexString(SHA256.HashData(bytes)) : "",
            References = ReferencedMethods(method),
            AsyncReferences = method.GetCustomAttribute<System.Runtime.CompilerServices.AsyncStateMachineAttribute>()?.StateMachineType
                .GetMethod("MoveNext", BindingFlags.Instance | BindingFlags.NonPublic) is MethodInfo move ? ReferencedMethods(move) : Array.Empty<string>()
        };
        return new {
            UserDataMembers = typeof(IUserDataManager).GetMethods().Where(method => method.Name == "GetUserData")
                .SelectMany(method => method.ReturnType.GetMembers(BindingFlags.Instance | BindingFlags.Public))
                .Where(member => member.MemberType is MemberTypes.Property or MemberTypes.Field).Select(member => member.ToString()).Distinct().ToArray(),
            Routes = types.SelectMany(type => type.CustomAttributes.Where(attribute => attribute.AttributeType.Name == "RouteAttribute")
                .Select(attribute => new {
                    Request = type.FullName,
                    Path = attribute.ConstructorArguments.FirstOrDefault().Value?.ToString(),
                    Verbs = attribute.ConstructorArguments.Skip(1).FirstOrDefault().Value?.ToString(),
                    Identity = type.GetProperties().Where(property => property.Name is "UserId" or "Id" or "ItemId" or "Ids" or "Name")
                        .Select(property => property.Name + ":" + property.PropertyType).ToArray(),
                    Attributes = type.CustomAttributes.Select(attribute => attribute.AttributeType.Name).ToArray(),
                    Methods = handlers[type].Select(Method).ToArray()
                })).ToArray()
        };
    }
}
