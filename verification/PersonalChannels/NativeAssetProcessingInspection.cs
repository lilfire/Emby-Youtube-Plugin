using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;

namespace PersonalChannelsFixture;

// Read-only IL of fixed native image/subtitle families; no runtime user values.
internal static class NativeAssetProcessingInspection
{
    internal static object Read(bool counts = false, bool metadata = false, bool search = false, bool history = false, bool libraries = false, bool videos = false)
    {
        var flags = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
        var types = AppDomain.CurrentDomain.GetAssemblies().SelectMany(assembly => {
            try { return assembly.GetTypes(); }
            catch (ReflectionTypeLoadException error) { return error.Types.Where(type => type != null).Cast<Type>().ToArray(); }
        }).Where(type => type.Namespace?.StartsWith("Emby.", StringComparison.Ordinal) == true
                || type.Namespace?.StartsWith("MediaBrowser.", StringComparison.Ordinal) == true)
            .Where(type => videos ? type.Name == "VideoService" || type.Namespace?.StartsWith("Emby.Server.MediaEncoding.Api", StringComparison.Ordinal) == true : libraries ? type.Name == "LibraryManager" || type.Namespace?.StartsWith("Emby.Api", StringComparison.Ordinal) == true : history ? type.Name is "UserLibraryService" or "UserService" or "ItemsService" or "UserDataManager" or "SqliteUserDataRepository" || type.Namespace?.StartsWith("Emby.Server.MediaEncoding.Api", StringComparison.Ordinal) == true
            : search ? type.Namespace == "Emby.Api.Obsolete" : metadata
            ? type.Name is "LibraryManager" or "SqliteItemRepository" or "ItemRepository" or "BaseItemsByNameService"
                or "GenresService" or "StudiosService" or "TagsService" or "GenreService" or "StudioService" or "TagService"
            : counts
            ? type.Name is "LibraryService" or "LibraryManager" or "SqliteItemRepository" or "ItemRepository"
            : type.Name is "ImageService" or "SubtitleService" or "ImageProcessor" or "SubtitleEncoder")
            .Where(type => type.Namespace?.StartsWith("Emby.", StringComparison.Ordinal) == true
                || type.Namespace?.StartsWith("MediaBrowser.", StringComparison.Ordinal) == true).ToArray();
        bool NativeFamily(Type? type) => type != null && (types.Contains(type) || NativeFamily(type.DeclaringType));
        var pending = new Queue<(MethodBase Method, int Depth)>();
        var digest = typeof(MediaBrowser.Common.Extensions.BaseExtensions).GetMethod("GetMD5", new[] { typeof(string) });
        if(!counts && !metadata && !search && !history && !libraries && digest != null) pending.Enqueue((digest, 0));
        var crypto = typeof(MediaBrowser.Common.Extensions.BaseExtensions).GetProperty("CryptographyProvider", BindingFlags.Static | BindingFlags.Public)?.GetValue(null);
        var nativeDigest = crypto?.GetType().GetMethod("GetMD5", new[] { typeof(string) });
        if(!counts && !metadata && !search && !history && !libraries && nativeDigest != null) pending.Enqueue((nativeDigest, 0));
        foreach (var type in types)
        foreach (var method in type.GetMethods(flags).Where(method => videos
            ? method.GetParameters().Any(parameter => parameter.ParameterType.FullName == "Emby.Server.MediaEncoding.Api.Progressive.GetVideoStream")
            : libraries
            ? method.Name == "GetVirtualFolders" || method.GetParameters().Any(parameter => parameter.ParameterType.Name is "GetVirtualFolders" or "GetVirtualFoldersResult")
            : history
            ? method.GetParameters().Any(parameter => parameter.ParameterType.FullName is "Emby.Api.UserLibrary.ReportItemsSearched" or "Emby.Api.ClearRecentlySearched" or "Emby.Server.MediaEncoding.Api.UpdateUserData")
            : search
            ? method.GetParameters().Any(parameter => parameter.ParameterType.FullName == "Emby.Api.Obsolete.GetSearchHints")
            : metadata
            ? method.Name is "GetGenres" or "GetAllGenres" or "GetStudios" or "GetTags"
                || method.GetParameters().Any(parameter => parameter.ParameterType.FullName is "Emby.Api.UserLibrary.GetGenres" or "Emby.Api.UserLibrary.GetStudios" or "Emby.Api.UserLibrary.GetTags")
            : counts
            ? method.GetParameters().Any(parameter => parameter.ParameterType.FullName == "Emby.Api.Library.GetItemCounts")
            : method.Name is "ProcessImage" or "GetSubtitles" or "GetResizedImageCachePath"
            || method.GetParameters().Any(parameter => parameter.ParameterType.FullName is "Emby.Api.Images.GetItemImage" or "Emby.Api.Subtitles.GetSubtitle")))
            pending.Enqueue((method, 0));
        var visited = new HashSet<MethodBase>();
        var methods = new List<object>();
        var codes = typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static)
            .Where(field => field.FieldType == typeof(OpCode)).Select(field => (OpCode)field.GetValue(null)!)
            .ToDictionary(code => unchecked((ushort)code.Value));
        while (pending.Count != 0 && visited.Count < 64)
        {
            var (method, depth) = pending.Dequeue();
            if (!visited.Add(method)) continue;
            var state = method.GetCustomAttribute<AsyncStateMachineAttribute>()?.StateMachineType;
            var move = state?.GetMethod("MoveNext", flags);
            if (move != null && depth < 4) pending.Enqueue((move, depth + 1));
            var bytes = method.GetMethodBody()?.GetILAsByteArray();
            if (bytes == null) continue;
            var instructions = new List<object>();
            for (var position = 0; position < bytes.Length;)
            {
                var offset = position;
                ushort value = bytes[position++];
                if (value == 0xfe) value = (ushort)(0xfe00 | bytes[position++]);
                var code = codes[value]; var start = position;
                var size = code.OperandType switch {
                    OperandType.InlineNone => 0,
                    OperandType.ShortInlineBrTarget or OperandType.ShortInlineI or OperandType.ShortInlineVar => 1,
                    OperandType.InlineVar => 2,
                    OperandType.InlineI8 or OperandType.InlineR => 8,
                    OperandType.InlineSwitch => 4 + 4 * BitConverter.ToInt32(bytes, position),
                    _ => 4
                };
                position += size;
                var operand = size == 0 ? "" : Convert.ToHexString(bytes.AsSpan(start, size));
                if (code.OperandType is OperandType.InlineMethod or OperandType.InlineField or OperandType.InlineType or OperandType.InlineTok)
                {
                    var member = method.Module.ResolveMember(BitConverter.ToInt32(bytes, start),
                        method.DeclaringType?.GetGenericArguments(), method.IsGenericMethod ? method.GetGenericArguments() : null)!;
                    operand = member.DeclaringType?.FullName + "::" + member;
                    if (depth < 4 && member is MethodBase called && NativeFamily(called.DeclaringType)) pending.Enqueue((called, depth + 1));
                }
                else if (code.OperandType == OperandType.InlineString) operand = method.Module.ResolveString(BitConverter.ToInt32(bytes, start));
                instructions.Add(new { Offset = offset, Op = code.Name, Operand = operand });
            }
            methods.Add(new { Type = method.DeclaringType!.FullName, Method = method.ToString(), Depth = depth,
                BodyHash = Convert.ToHexString(SHA256.HashData(bytes)), Instructions = instructions });
        }
        return new { Types = types.Select(type => type.FullName).ToArray(), Methods = methods, Truncated = pending.Count != 0 };
    }
}
