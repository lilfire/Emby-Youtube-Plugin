using System.Security.Cryptography;

namespace Emby.YouTubePlugin;

// Content, not timestamps/TTL. Includes the account profile because a native
// source version cannot observe revocation, journal edits or restored files.
internal static class PersonalYouTubeSourceAuthorityStamp
{
    internal static string Read(string directory, Guid? owner)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var files = new[] { "native-reference-bindings.json", "native-reference-bindings.required", "publication-journal.json",
            "publication-journal.required", "private-source-scopes.json", "private-source-scopes.required" }
            .Concat(owner.HasValue ? new[] { owner.Value.ToString("N") + ".json" } : Array.Empty<string>());
        foreach (var name in files)
        {
            var path = Path.Combine(directory, name);
            if (!File.Exists(path)) { hash.AppendData(new byte[] { 0 }); continue; }
            var bytes = File.ReadAllBytes(path);
            hash.AppendData(new byte[] { 1 }); hash.AppendData(BitConverter.GetBytes(bytes.Length)); hash.AppendData(bytes);
        }
        hash.AppendData(new[] { (byte)(Directory.Exists(Path.Combine(directory, "media")) ? 1 : 0) });
        return Convert.ToHexString(hash.GetHashAndReset());
    }
}
