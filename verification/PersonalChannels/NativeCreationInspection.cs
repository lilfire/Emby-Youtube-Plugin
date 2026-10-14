using System.Reflection;
using System.Reflection.Emit;
using MediaBrowser.Controller.Library;

namespace PersonalChannelsFixture;

// Read-only diagnostics of the implementation actually loaded by isolated Emby.
internal static class NativeCreationInspection
{
    internal static object Read(ILibraryManager library)
    {
        var type = library.GetType();
        var pending = new Queue<(MethodBase Method, int Depth)>();
        foreach (var method in type.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            .Where(method => method.Name == "AddVirtualFolder")) pending.Enqueue((method, 0));
        var visited = new HashSet<MethodBase>();
        var result = new List<object>();
        var codes = typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static)
            .Where(field => field.FieldType == typeof(OpCode)).Select(field => (OpCode)field.GetValue(null)!)
            .ToDictionary(code => unchecked((ushort)code.Value));
        while (pending.Count != 0 && visited.Count < 24)
        {
            var (method, depth) = pending.Dequeue();
            if (!visited.Add(method)) continue;
            var bytes = method.GetMethodBody()?.GetILAsByteArray();
            if (bytes == null) continue;
            var instructions = new List<object>();
            for (var position = 0; position < bytes.Length;)
            {
                var offset = position;
                ushort value = bytes[position++];
                if (value == 0xfe) value = (ushort)(0xfe00 | bytes[position++]);
                var code = codes[value];
                var start = position;
                var size = code.OperandType switch {
                    OperandType.InlineNone => 0,
                    OperandType.ShortInlineBrTarget or OperandType.ShortInlineI or OperandType.ShortInlineVar => 1,
                    OperandType.InlineVar => 2,
                    OperandType.InlineI8 or OperandType.InlineR => 8,
                    OperandType.InlineSwitch => 4 + 4 * BitConverter.ToInt32(bytes, position),
                    _ => 4
                };
                position += size;
                string operand = size == 0 ? "" : Convert.ToHexString(bytes.AsSpan(start, size));
                if (code.OperandType is OperandType.InlineMethod or OperandType.InlineField or OperandType.InlineType or OperandType.InlineTok)
                {
                    var member = method.Module.ResolveMember(BitConverter.ToInt32(bytes, start),
                        method.DeclaringType?.GetGenericArguments(), method.IsGenericMethod ? method.GetGenericArguments() : null)!;
                    operand = member.DeclaringType?.FullName + "::" + member;
                    if (depth < 2 && member is MethodBase called && called.DeclaringType == type)
                        pending.Enqueue((called, depth + 1));
                }
                else if (code.OperandType == OperandType.InlineString)
                    operand = method.Module.ResolveString(BitConverter.ToInt32(bytes, start));
                instructions.Add(new { Offset = offset, Op = code.Name, Operand = operand });
            }
            result.Add(new { Method = method.ToString(), Depth = depth,
                BodyHash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)), Instructions = instructions });
        }
        return new { RuntimeType = type.FullName, Methods = result };
    }
}
