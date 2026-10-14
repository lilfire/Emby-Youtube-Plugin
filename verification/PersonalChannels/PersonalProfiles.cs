using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MediaBrowser.Common.Extensions;
using MediaBrowser.Controller.Net;
using MediaBrowser.Model.Services;

namespace PersonalChannelsFixture;

// Test-only profile prototype. Not a media authorization boundary.
[Route("/PersonalChannelsFixture/MyYouTube", "GET")]
[Authenticated]
public sealed class GetMyYouTube : IReturn<object> { }

// Synthetic request preparation probe; returns a digest, never the stored key.
[Route("/PersonalChannelsFixture/MyYouTube/PreparedRequest", "GET")]
[Authenticated]
public sealed class GetPreparedYouTubeRequest : IReturn<object> { }

[Route("/PersonalChannelsFixture/MyYouTube", "POST")]
[Authenticated]
public sealed class SetMyYouTube : IReturn<object> {
    public string[] Channels { get; set; } = Array.Empty<string>();
    public string? ApiKey { get; set; }
    public bool ClearApiKey { get; set; }
}

public sealed class PersonalProfilesService : IService, IRequiresRequest {
    private readonly IAuthorizationContext _authorization;
    public IRequest Request { get; set; } = null!;
    public PersonalProfilesService(IAuthorizationContext authorization) => _authorization=authorization;
    private string Owner() {
        var user=_authorization.GetAuthorizationInfo(Request).User;
        if (user == null || !user.Name.StartsWith("native-privacy-fixture-", StringComparison.Ordinal))
            throw new ResourceNotFoundException("Test profile unavailable.");
        return user.Id.ToString("N");
    }
    public object Get(GetMyYouTube request) => PersonalProfiles.Read(Owner());
    public object Post(SetMyYouTube request) => PersonalProfiles.Save(Owner(),request);
    public object Get(GetPreparedYouTubeRequest request) {
        var prepared=PersonalProfiles.PrepareRequest(Owner());
        return new { prepared.OwnerUserId, prepared.CollectionId, prepared.Channels,
            KeyFingerprint=prepared.ApiKey == null ? null : Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(prepared.ApiKey))) };
    }
}

internal static class PersonalProfiles {
    internal sealed record PreparedRequest(string OwnerUserId,string CollectionId,string[] Channels,string? ApiKey);
    private static readonly object Gate=new();
    private static string FilePath => FixturePlugin.StatePath+".profiles.json";
    private static string KeyPath => FixturePlugin.StatePath+".profiles.key";
    internal sealed class ProfileState {
        public string OwnerUserId { get; set; }="";
        public string CollectionId { get; set; }="";
        public string[] Channels { get; set; }=Array.Empty<string>();
        public string? EncryptedApiKey { get; set; }
    }
    private static Dictionary<string,ProfileState> Load() => File.Exists(FilePath)
        ? JsonSerializer.Deserialize<Dictionary<string,ProfileState>>(File.ReadAllText(FilePath))
            ?? throw new InvalidDataException("Invalid profile store.")
        : new(StringComparer.Ordinal);
    private static object View(ProfileState state) => new {
        state.OwnerUserId, state.CollectionId, Channels=state.Channels.ToArray(),
        HasApiKey=!string.IsNullOrEmpty(state.EncryptedApiKey)
    };
    internal static object Read(string owner) {
        lock (Gate) {
            var all=Load();
            if (!all.TryGetValue(owner,out var state))
                return new { OwnerUserId=owner, CollectionId="", Channels=Array.Empty<string>(), HasApiKey=false };
            if (state.OwnerUserId!=owner) throw new InvalidDataException("Profile owner mismatch.");
            return View(state);
        }
    }
    internal static object Save(string owner,SetMyYouTube input) {
        if (input.Channels == null || input.Channels.Length>100 || input.Channels.Any(value =>
            value == null || !System.Text.RegularExpressions.Regex.IsMatch(value,@"\AUC[A-Za-z0-9_-]{22}\z")))
            throw new ArgumentException("Expected canonical YouTube channel IDs.");
        if (input.ApiKey?.Length>256 || input.ApiKey!=null && string.IsNullOrWhiteSpace(input.ApiKey) || input.ClearApiKey && input.ApiKey!=null)
            throw new ArgumentException("Invalid key update.");
        lock (Gate) {
            var all=Load();
            if (!all.TryGetValue(owner,out var state)) state=new() { OwnerUserId=owner, CollectionId=Guid.NewGuid().ToString("N") };
            if (state.OwnerUserId!=owner) throw new InvalidDataException("Profile owner mismatch.");
            state.Channels=input.Channels.Distinct(StringComparer.Ordinal).ToArray();
            if (input.ClearApiKey) state.EncryptedApiKey=null;
            else if (input.ApiKey!=null) state.EncryptedApiKey=Encrypt(owner,input.ApiKey);
            all[owner]=state;
            var temporary=FilePath+".tmp";
            File.WriteAllText(temporary,JsonSerializer.Serialize(all));
            File.Move(temporary,FilePath,true);
            return View(state);
        }
    }
    internal static PreparedRequest PrepareRequest(string owner) {
        lock (Gate) {
            var all=Load();
            if (!all.TryGetValue(owner,out var state) || state.OwnerUserId!=owner)
                throw new ResourceNotFoundException("Test profile unavailable.");
            string? secret=null;
            if (state.EncryptedApiKey!=null) {
                var bytes=Convert.FromBase64String(state.EncryptedApiKey);
                if (bytes.Length<28) throw new InvalidDataException("Invalid encrypted key.");
                var plain=new byte[bytes.Length-28];
                using var aes=new AesGcm(File.ReadAllBytes(KeyPath));
                aes.Decrypt(bytes.AsSpan(0,12),bytes.AsSpan(28),bytes.AsSpan(12,16),plain,Encoding.UTF8.GetBytes(owner));
                try {secret=Encoding.UTF8.GetString(plain);} finally {CryptographicOperations.ZeroMemory(plain);}
            }
            return new(owner,state.CollectionId,state.Channels.ToArray(),secret);
        }
    }
    private static string Encrypt(string owner,string secret) {
        if (!File.Exists(KeyPath)) {
            var key=RandomNumberGenerator.GetBytes(32);
            using var file=new FileStream(KeyPath,FileMode.CreateNew,FileAccess.Write,FileShare.None);
            file.Write(key);file.Flush(true);
        }
        var bytes=Encoding.UTF8.GetBytes(secret);
        var nonce=RandomNumberGenerator.GetBytes(12);var cipher=new byte[bytes.Length];var tag=new byte[16];
        using var aes=new AesGcm(File.ReadAllBytes(KeyPath));
        aes.Encrypt(nonce,bytes,cipher,tag,Encoding.UTF8.GetBytes(owner));
        return Convert.ToBase64String(nonce.Concat(tag).Concat(cipher).ToArray());
    }
}
