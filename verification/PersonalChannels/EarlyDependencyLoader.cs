using System.Reflection;
using System.Runtime.CompilerServices;

namespace PersonalChannelsFixture;

internal static class EarlyDependencyLoader
{
    private static Assembly? Dependency;
#pragma warning disable CA2255 // Isolated plugin deliberately initializes before server entry points.
    [ModuleInitializer]
    internal static void Load()
    {
        AppDomain.CurrentDomain.AssemblyResolve += (_, args) => new AssemblyName(args.Name).Name == "0Harmony" ? Dependency : null;
        Dependency = AppDomain.CurrentDomain.GetAssemblies().FirstOrDefault(assembly => assembly.GetName().Name == "0Harmony");
        if (Dependency != null) return;
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("PersonalChannelsFixture.Harmony.dll")
            ?? throw new InvalidOperationException("Missing embedded test dependency.");
        using var buffer = new MemoryStream();
        stream.CopyTo(buffer);
        Dependency = Assembly.Load(buffer.ToArray());
    }
#pragma warning restore CA2255
}
