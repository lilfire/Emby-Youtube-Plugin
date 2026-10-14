using System.Reflection;
using System.Security.Cryptography;
using MediaBrowser.Controller.Net;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

internal static class NativeBoundaryInspection
{
    internal static object Read(IHttpServer server, ILibraryManager library, IResponse response, IHttpResultFactory results)
    {
        var flags = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
        var controller = server.GetType().Assembly.GetType("Emby.Server.Implementations.Services.ServiceController", true)!;
        var writer = server.GetType().Assembly.GetType("Emby.Server.Implementations.HttpServer.StreamWriter", true)!;
        var emptyResult = server.GetType().Assembly.GetType("Emby.Server.Implementations.Services.EmptyHttpResult", true)!;
        var writerTypes = server.GetType().Assembly.GetTypes().Where(type => !type.IsAbstract && typeof(IAsyncStreamWriter).IsAssignableFrom(type)).ToArray();
        var methods = server.GetType().GetMethods(flags).Where(method => method.Name == "RequestHandler")
            .Concat(controller.GetMethods(flags).Where(method => method.Name == "Execute"))
            .Concat(library.GetType().GetMethods(flags).Where(method => method.Name is "GetItemList" or "GetItemIds" or "GetItemsResult" or "GetItemCount")
                .Where(method => method.GetParameters().FirstOrDefault()?.ParameterType == typeof(InternalItemsQuery)))
            .Concat(writerTypes.SelectMany(type => type.GetMethods(flags)).Where(method => method.Name.Contains("Write", StringComparison.Ordinal))).Distinct()
            .Concat(results.GetType().GetMethods(flags).Where(method => method.Name is "GetStaticResult" or "GetStaticFileResult"))
            .Select(method => new {
                DeclaringType = method.DeclaringType!.FullName, Method = method.ToString(), IsStatic = method.IsStatic,
                Parameters = method.GetParameters().Select(parameter => new { parameter.Name, Type = parameter.ParameterType.FullName }).ToArray(),
                BodyHash = method.GetMethodBody()?.GetILAsByteArray() is byte[] bytes ? Convert.ToHexString(SHA256.HashData(bytes)) : ""
            }).ToArray();
        var discoveryTypes = AppDomain.CurrentDomain.GetAssemblies().SelectMany(assembly => {
            try { return assembly.GetTypes(); }
            catch(ReflectionTypeLoadException error) { return error.Types.Where(type => type != null).Cast<Type>(); }
        }).Where(type => type.Name is "UserViewManager" or "UserViewsService" or "UserRootFolder" or "AggregateFolder")
            .Append(typeof(Folder)).Append(library.GetUserRootFolder().GetType()).Distinct().ToArray();
        var discovery = discoveryTypes.SelectMany(type => type.GetMethods(flags))
            .Where(method => method.Name is "GetChildren" or "GetUserViews" or "GetLatestMedia" or "GetCollectionFolders")
            .Distinct().Select(method => new { DeclaringType = method.DeclaringType!.FullName, Method = method.ToString(),
                ReturnType = method.ReturnType.FullName, Parameters = method.GetParameters().Select(parameter => new { parameter.Name, Type = parameter.ParameterType.FullName }).ToArray(),
                BodyHash = method.GetMethodBody()?.GetILAsByteArray() is byte[] bytes ? Convert.ToHexString(SHA256.HashData(bytes)) : "" }).ToArray();
        var routes = new List<object>();
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            Type[] types;
            try { types = assembly.GetTypes(); } catch (ReflectionTypeLoadException error) { types = error.Types.Where(type => type != null).Cast<Type>().ToArray(); }
            foreach (var type in types.Where(type => type.Namespace?.StartsWith("Emby.", StringComparison.Ordinal) == true
                && type.Namespace?.StartsWith("Emby.YouTubePlugin", StringComparison.Ordinal) != true
                || type.Namespace?.StartsWith("MediaBrowser.", StringComparison.Ordinal) == true))
            {
                var attributes = type.GetCustomAttributesData().Where(attribute => attribute.AttributeType.Name == "RouteAttribute").ToArray();
                if (attributes.Length == 0) continue;
                routes.Add(new {
                    Dto = type.FullName,
                    Routes = attributes.Select(attribute => new {
                        Path = attribute.ConstructorArguments.FirstOrDefault().Value?.ToString(),
                        Verbs = attribute.ConstructorArguments.Skip(1).FirstOrDefault().Value?.ToString()
                    }).ToArray(),
                    Properties = type.GetProperties(BindingFlags.Instance | BindingFlags.Public).Select(property => new {
                        property.Name, Type = property.PropertyType.FullName,
                        NativeReferenceCandidate = (property.Name.EndsWith("Id", StringComparison.OrdinalIgnoreCase)
                            || property.Name.EndsWith("Ids", StringComparison.OrdinalIgnoreCase) || property.Name == "AdjacentTo")
                            && property.Name is not ("UserId" or "SessionId" or "PlaySessionId" or "DeviceId" or "MediaSourceId")
                    }).ToArray(),
                    Interfaces = type.GetInterfaces().Select(value => value.FullName).ToArray()
                });
            }
        }
        return new { ServerType = server.GetType().FullName, Methods = methods, DiscoveryMethods = discovery, RouteDtos = routes,
            WriterInterfaces = writer.GetInterfaces().Select(type => new { type.FullName,
                Methods = type.GetMethods().Select(method => method.ToString()).ToArray() }).ToArray(),
            ResponseContract = typeof(IResponse).GetMembers(flags).Select(member => member.ToString()).ToArray(),
            ResultFactoryContract = typeof(IHttpResultFactory).GetMembers(flags).Select(member => member.ToString()).ToArray(),
            ResultFactoryType = results.GetType().FullName,
            StaticFileOptionsContract = typeof(StaticFileResultOptions).GetMembers(flags).Select(member => member.ToString()).ToArray(),
            HttpResultContract = typeof(IHttpResult).GetMembers(flags).Select(member => member.ToString()).ToArray(),
            MediaSourceContract = typeof(IMediaSourceManager).GetMembers(flags).Select(member => member.ToString()).ToArray(),
            ItemMediaSourceContract = typeof(BaseItem).GetMethods(flags).Where(method => method.Name.Contains("MediaSource", StringComparison.Ordinal)).Select(method => method.ToString()).ToArray(),
            ItemMediaSourceHashes = typeof(BaseItem).GetMethods(flags).Where(method => method.Name is "GetAllItemsForMediaSources" or "GetDefaultMediaSourceId")
                .Select(method => new { Method = method.ToString(), BodyHash = method.GetMethodBody()?.GetILAsByteArray() is byte[] body ? Convert.ToHexString(SHA256.HashData(body)) : "" }).ToArray(),
            EmptyResultContract = new { Interfaces = emptyResult.GetInterfaces().Select(type => type.FullName).ToArray(),
                Members = emptyResult.GetMembers(flags).Select(member => member.ToString()).ToArray() },
            ResponseHeadersContract = typeof(IResponse).GetProperty("Headers")!.PropertyType.GetMembers(flags).Select(member => member.ToString()).ToArray(),
            ConcreteResponseType = response.GetType().FullName,
            ConcreteResponseAssembly = response.GetType().Assembly.GetName().Name,
            ServerAssembly = server.GetType().Assembly.GetName().Name,
            ResponseBackingContract = response.GetType().GetField("response", flags) is FieldInfo backing ? new {
                FieldType = backing.FieldType.FullName,
                HeadersType = backing.FieldType.GetProperty("Headers")?.PropertyType.FullName,
                HeaderInterfaces = backing.FieldType.GetProperty("Headers")?.PropertyType.GetInterfaces().Select(type => type.ToString()).ToArray()
            } : null,
            ConcreteResponseContract = response.GetType().GetMembers(flags).Select(member => member.ToString()).ToArray(),
            WriterContracts = writerTypes.Select(type => new { type.FullName,
                Interfaces = type.GetInterfaces().Select(value => value.FullName).ToArray(),
                Fields = type.GetFields(flags).Select(field => field.ToString()).ToArray(),
                Properties = type.GetProperties(flags).Select(property => property.ToString()).ToArray() }).ToArray() };
    }
}
