using System.Security.Cryptography;
using System.Text.Json;
using Mono.Cecil;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;
using ModuleDefinition = Mono.Cecil.ModuleDefinition;
using TypeDefinition = Mono.Cecil.TypeDefinition;
using MethodDefinition = Mono.Cecil.MethodDefinition;

// Read local native IL without loading or running Emby assemblies. Keep call
// offsets so event/write ordering can be assessed; this is not a runtime proof.
var repository = Path.GetFullPath(args.Length > 0 ? args[0] : ".");
var file = Path.Combine(repository, "verification/WatchState/bin/emby-isolated/server/system/Emby.Server.Implementations.dll");
using var module = ModuleDefinition.ReadModule(file);
var library = module.Types.Single(type => type.FullName == "Emby.Server.Implementations.Library.LibraryManager");
var names = new HashSet<string> { "CreateItem", "CreateItems", "UpdateItem", "UpdateItems", "DeleteItem", "DeleteItems", "TriggerItemAdded", "GetItemList", "GetInternalItemIds", "SetUserAndParents" };
var mutations = library.Methods.Where(method => names.Contains(method.Name) && method.HasBody).Select(method => new {
    Method = method.FullName,
    Calls = method.Body.Instructions.Where(instruction => instruction.Operand is MethodReference or FieldReference)
        .Select(instruction => new { instruction.Offset, Operation = instruction.OpCode.Name, Member = instruction.Operand.ToString() }).ToArray()
}).ToArray();
IEnumerable<TypeDefinition> AllTypes(IEnumerable<TypeDefinition> types)
{
    foreach (var type in types) { yield return type; foreach (var nested in AllTypes(type.NestedTypes)) yield return nested; }
}
bool NearSourceFilter(MethodDefinition method, int offset)
    => method.Body.Instructions.Any(instruction => instruction.Operand is MethodReference called
        && called.Name is "get_PathStartsWith" or "get_ParentIds" or "get_AncestorIds"
        && Math.Abs(instruction.Offset - offset) <= 200);
var related = AllTypes(module.Types).SelectMany(type => type.Methods).Where(method => method.HasBody
    && (method.DeclaringType.FullName.Contains("LibraryManager") || method.DeclaringType.FullName.Contains("SqliteItemRepository")))
    .Where(method => method.Body.Instructions.Any(instruction => instruction.Operand is MethodReference called
        && called.Name is "get_PathStartsWith" or "get_ParentIds" or "get_AncestorIds"
        || instruction.Operand is FieldReference field && field.Name is "ItemAdded" or "ItemAdding" or "ItemUpdated" or "ItemRemoved"))
    .Select(method => new {
        Method = method.FullName,
        Constants = method.Body.Instructions.Where(instruction => instruction.Operand is string && NearSourceFilter(method, instruction.Offset))
            .Select(instruction => new { instruction.Offset, Value = (string)instruction.Operand }).ToArray(),
        Calls = method.Body.Instructions.Where(instruction => instruction.Operand is MethodReference or FieldReference
            && (method.Name != "GetWhereClauses" || NearSourceFilter(method, instruction.Offset)))
            .Select(instruction => new { instruction.Offset, Operation = instruction.OpCode.Name, Member = instruction.Operand.ToString() }).ToArray()
    }).ToArray();
var repositoryWriters = AllTypes(module.Types).SelectMany(type => type.Methods).Where(method => method.HasBody)
    .SelectMany(method => method.Body.Instructions.Where(instruction => instruction.Operand is MethodReference called
        && called.DeclaringType.Name is "IItemRepository" or "SqliteItemRepository"
        && called.Name is "SaveItems" or "DeleteItems")
        .Select(instruction => new { Caller = method.FullName, instruction.Offset, Writer = instruction.Operand.ToString() })).ToArray();
using var pe = new PEReader(File.OpenRead(file));
var metadata = pe.GetMetadataReader();
var nativeRepository = module.Types.Single(type => type.FullName == "Emby.Server.Implementations.Data.SqliteItemRepository");
var writerContracts = nativeRepository.Methods.Where(method => method.HasBody && method.Body.Instructions.Any(instruction => instruction.Operand is string sql
    && (sql.Contains("update ", StringComparison.OrdinalIgnoreCase) || sql.Contains("insert ", StringComparison.OrdinalIgnoreCase) || sql.Contains("delete ", StringComparison.OrdinalIgnoreCase))))
    .Select(method => new {
        method.Name, Signature = method.FullName,
        Hash = Convert.ToHexString(SHA256.HashData(pe.GetMethodBody(metadata.GetMethodDefinition((MethodDefinitionHandle)MetadataTokens.Handle(method.MetadataToken.ToInt32())).RelativeVirtualAddress).GetILBytes()!)),
        Statements = method.Body.Instructions.Where(instruction => instruction.Operand is string sql && (sql.Contains("update ", StringComparison.OrdinalIgnoreCase) || sql.Contains("insert ", StringComparison.OrdinalIgnoreCase) || sql.Contains("delete ", StringComparison.OrdinalIgnoreCase))).Select(instruction => (string)instruction.Operand).ToArray()
    }).ToArray();
var barrierContracts = nativeRepository.Methods.Where(method => method.HasBody && method.Name is "SaveItems" or "DeleteItems" or "UpdateValuesIfNeeded" or "SaveImages" or "DeleteObsoleteCollectionFolderAncestorIds" or "UpdatePeople" or "SetItemExtradata" or "ClearItemExtradata" or "SetNamedValue" or "ClearNamedValue")
    .Select(method => new { method.Name, method.IsStatic, Signature = method.FullName,
        Constants = method.Body.Instructions.Where(instruction => instruction.Operand is string).Select(instruction => (string)instruction.Operand).ToArray(),
        Members = method.Body.Instructions.Where(instruction => instruction.Operand is MethodReference or FieldReference).Select(instruction => instruction.Operand.ToString()).ToArray(),
        Hash = Convert.ToHexString(SHA256.HashData(pe.GetMethodBody(metadata.GetMethodDefinition((MethodDefinitionHandle)MetadataTokens.Handle(method.MetadataToken.ToInt32())).RelativeVirtualAddress).GetILBytes()!)) }).ToArray();
var libraryStructureContracts = library.Methods.Where(method => method.HasBody && (method.Name.Contains("VirtualFolder") || method.Name.Contains("LibraryOptions") || method.Name.Contains("MediaPath")))
    .Select(method => new { method.Name, method.IsStatic, Signature = method.FullName,
        Constants = method.Body.Instructions.Where(instruction => instruction.Operand is string).Select(instruction => (string)instruction.Operand).ToArray(),
        Members = method.Body.Instructions.Where(instruction => instruction.Operand is MethodReference or FieldReference).Select(instruction => instruction.Operand.ToString()).ToArray(),
        Hash = Convert.ToHexString(SHA256.HashData(pe.GetMethodBody(metadata.GetMethodDefinition((MethodDefinitionHandle)MetadataTokens.Handle(method.MetadataToken.ToInt32())).RelativeVirtualAddress).GetILBytes()!)) }).ToArray();
using var controller = ModuleDefinition.ReadModule(Path.Combine(Path.GetDirectoryName(file)!, "MediaBrowser.Controller.dll"));
using var controllerPe = new PEReader(File.OpenRead(Path.Combine(Path.GetDirectoryName(file)!, "MediaBrowser.Controller.dll")));
var controllerMetadata = controllerPe.GetMetadataReader();
var folderContracts = controller.Types.Single(type => type.Name == "CollectionFolder").Methods.Where(method => method.HasBody && method.Name is "UpdateLibraryOptions" or "SaveLibraryOptions")
    .Select(method => new { method.Name, method.IsStatic, Signature = method.FullName,
        Hash = Convert.ToHexString(SHA256.HashData(controllerPe.GetMethodBody(controllerMetadata.GetMethodDefinition((MethodDefinitionHandle)MetadataTokens.Handle(method.MetadataToken.ToInt32())).RelativeVirtualAddress).GetILBytes()!)) }).ToArray();
var evidence = new {
    Assembly = module.Assembly.Name.Name, Version = module.Assembly.Name.Version.ToString(),
    AssemblySHA256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))),
    Scope = "Static call/field inventory of the local native assembly. No executed native query, event timing, cache or write-barrier guarantee.",
    MutationAndQueryMethods = mutations, SourceFilterAndEventMethods = related, RepositoryWriters = repositoryWriters, WriterContracts = writerContracts, BarrierContracts = barrierContracts, LibraryStructureContracts = libraryStructureContracts, FolderContracts = folderContracts
};
var output = Path.Combine(repository, "verification/FollowUp/PrivateInventory/NATIVE-CONTRACT.json");
File.WriteAllText(output, JsonSerializer.Serialize(evidence, new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine($"Native {module.Assembly.Name.Version}: {mutations.Length} mutation/query methods and {related.Length} filter/event methods inspected.");
