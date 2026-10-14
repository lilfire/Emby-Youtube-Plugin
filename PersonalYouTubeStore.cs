using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Emby.YouTubePlugin;

// Server-owned profile storage. This does not publish or authorize native media.
internal sealed class PersonalYouTubeStore
{
    internal sealed record View(Guid OwnerUserId, Guid CollectionId, Guid GenerationId,
        long Revision, long KeyRevision, string State, string[] Channels, bool HasApiKey);
    internal sealed record Prepared(Guid OwnerUserId, Guid CollectionId, Guid GenerationId,
        long Revision, long KeyRevision, string[] Channels, string? ApiKey);
    internal sealed class Generation
    {
        public Guid CollectionId { get; set; }
        public Guid GenerationId { get; set; }
        public string State { get; set; } = "Draft";
        public long KeyRevision { get; set; }
        public string[] Channels { get; set; } = Array.Empty<string>();
        public string? EncryptedApiKey { get; set; }
    }
    internal sealed class Document
    {
        public int Version { get; set; } = 1;
        public Guid OwnerUserId { get; set; }
        public long Revision { get; set; }
        public Generation Current { get; set; } = new();
        public Generation[] Retired { get; set; } = Array.Empty<Generation>();
    }
    private static readonly ConcurrentDictionary<string, object> Gates = new(StringComparer.OrdinalIgnoreCase);
    private readonly string _root;
    private readonly object _gate;
    internal PersonalYouTubeStore(string directory)
    {
        _root = Path.GetFullPath(directory);
        _gate = Gates.GetOrAdd(_root, _ => new object());
    }
    private string ProfilePath(Guid owner)
    {
        if (owner == Guid.Empty) throw new ArgumentException("An authenticated owner is required.");
        return Path.Combine(_root, owner.ToString("N") + ".json");
    }
    private static bool ValidChannels(string[]? channels) => channels != null && channels.Length <= 100
        && channels.All(value => value != null && Regex.IsMatch(value, @"\AUC[A-Za-z0-9_-]{22}\z"))
        && channels.Distinct(StringComparer.Ordinal).Count() == channels.Length;
    private Document? Load(Guid owner)
    {
        var path = ProfilePath(owner);
        if (!File.Exists(path)) return null;
        Document doc;
        try { doc = JsonSerializer.Deserialize<Document>(File.ReadAllText(path)) ?? throw new InvalidDataException(); }
        catch (JsonException) { throw new InvalidDataException("Invalid personal YouTube profile."); }
        if (doc.Version != 1 || doc.OwnerUserId != owner || doc.Revision <= 0 || doc.Current == null
            || doc.Retired == null || doc.Current.CollectionId == Guid.Empty || doc.Current.GenerationId == Guid.Empty
            || doc.Current.State is not ("Draft" or "Deleted") || doc.Current.KeyRevision < 0
            || !ValidChannels(doc.Current.Channels)
            || doc.Current.EncryptedApiKey != null && (doc.Current.KeyRevision == 0 || doc.Current.State == "Deleted")
            || doc.Current.State == "Deleted" && doc.Current.Channels.Length != 0
            || doc.Retired.Any(value => value == null || value.CollectionId != doc.Current.CollectionId
                || value.GenerationId == Guid.Empty || value.State != "Deleted" || value.EncryptedApiKey != null
                || value.KeyRevision < 0 || value.Channels == null || value.Channels.Length != 0)
            || doc.Retired.Select(value => value.GenerationId).Append(doc.Current.GenerationId).Distinct().Count() != doc.Retired.Length + 1)
            throw new InvalidDataException("Invalid personal YouTube profile ownership or lifecycle.");
        return doc;
    }
    private static View PublicView(Document doc) => new(doc.OwnerUserId, doc.Current.CollectionId,
        doc.Current.GenerationId, doc.Revision, doc.Current.KeyRevision, doc.Current.State,
        doc.Current.Channels.ToArray(), doc.Current.EncryptedApiKey != null);
    internal View Read(Guid owner)
    {
        lock (_gate)
        {
            var doc = Load(owner);
            return doc == null ? new(owner, Guid.Empty, Guid.Empty, 0, 0, "Absent", Array.Empty<string>(), false) : PublicView(doc);
        }
    }
    internal View Save(Guid owner, long expectedRevision, string[] channels, string? apiKey, bool clearApiKey)
        => SaveCore(owner, expectedRevision, channels, apiKey, clearApiKey, false);
    internal View SaveForRefresh(Guid owner, long expectedRevision, string[] channels, string? apiKey, bool clearApiKey)
        => SaveCore(owner, expectedRevision, channels, apiKey, clearApiKey, true);
    private View SaveCore(Guid owner, long expectedRevision, string[] channels, string? apiKey, bool clearApiKey, bool replacePublished)
    {
        if (channels == null || channels.Length > 100 || channels.Any(value => value == null
            || !Regex.IsMatch(value, @"\AUC[A-Za-z0-9_-]{22}\z")))
            throw new ArgumentException("Expected canonical YouTube channel IDs.");
        if (apiKey != null && (apiKey.Length == 0 || apiKey.Length > 256 || apiKey.Any(value => value < 33 || value > 126))
            || clearApiKey && apiKey != null)
            throw new ArgumentException("Invalid API key update.");
        using var transfer = PersonalYouTubeTransferLease.Enter(_root, owner);
        lock (_gate)
        {
            var doc = Load(owner);
            if ((doc?.Revision ?? 0) != expectedRevision) throw new InvalidOperationException("Profile revision changed.");
            doc ??= new Document { OwnerUserId = owner, Current = new() { CollectionId = Guid.NewGuid(), GenerationId = Guid.NewGuid() } };
            if (doc.Current.State == "Deleted")
            {
                doc.Retired = doc.Retired.Append(doc.Current).ToArray();
                doc.Current = new() { CollectionId = doc.Current.CollectionId, GenerationId = Guid.NewGuid() };
            }
            else if(replacePublished && new PersonalYouTubePublicationJournal(_root).Entries().Any(entry => entry.GenerationId == doc.Current.GenerationId))
            {
                var key = apiKey == null && !clearApiKey ? Decrypt(doc) : null;
                var old = doc.Current;
                doc.Retired = doc.Retired.Append(new Generation { CollectionId = old.CollectionId, GenerationId = old.GenerationId, State = "Deleted", KeyRevision = old.KeyRevision }).ToArray();
                doc.Current = new Generation { CollectionId = old.CollectionId, GenerationId = Guid.NewGuid(), KeyRevision = old.KeyRevision };
                if(key != null) doc.Current.EncryptedApiKey = Encrypt(doc, key);
            }
            doc.Current.Channels = channels.Distinct(StringComparer.Ordinal).ToArray();
            if (clearApiKey || apiKey != null)
            {
                doc.Current.KeyRevision = checked(doc.Current.KeyRevision + 1);
                doc.Current.EncryptedApiKey = apiKey == null ? null : Encrypt(doc, apiKey);
            }
            doc.Revision = checked(doc.Revision + 1);
            Persist(doc);
            return PublicView(doc);
        }
    }
    internal View Delete(Guid owner, long expectedRevision)
    {
        using var transfer = PersonalYouTubeTransferLease.Enter(_root, owner);
        lock (_gate)
        {
            var doc = Load(owner) ?? throw new InvalidOperationException("Profile unavailable.");
            if (doc.Revision != expectedRevision) throw new InvalidOperationException("Profile revision changed.");
            if (doc.Current.State == "Deleted") return PublicView(doc);
            doc.Current.State = "Deleted";
            doc.Current.Channels = Array.Empty<string>();
            doc.Current.EncryptedApiKey = null;
            doc.Current.KeyRevision = checked(doc.Current.KeyRevision + 1);
            doc.Revision = checked(doc.Revision + 1);
            Persist(doc);
            return PublicView(doc);
        }
    }
    internal Prepared Prepare(Guid owner)
    {
        lock (_gate)
        {
            var doc = Load(owner) ?? throw new InvalidOperationException("Profile unavailable.");
            if (doc.Current.State != "Draft") throw new InvalidOperationException("Profile unavailable.");
            return new(owner, doc.Current.CollectionId, doc.Current.GenerationId, doc.Revision,
                doc.Current.KeyRevision, doc.Current.Channels.ToArray(), Decrypt(doc));
        }
    }
    internal bool IsCurrent(Prepared request)
    {
        lock (_gate)
        {
            return MatchesCurrent(request);
        }
    }
    private bool MatchesCurrent(Prepared request)
    {
        var doc = Load(request.OwnerUserId);
        return doc != null && doc.Current.State == "Draft" && doc.Revision == request.Revision
            && doc.Current.CollectionId == request.CollectionId && doc.Current.GenerationId == request.GenerationId
            && doc.Current.KeyRevision == request.KeyRevision;
    }
    // A short, synchronous server-owned publication runs in the same critical
    // section as Save/Delete. Never perform network work, await, or queue later
    // publication here. This serializes profile changes against publication;
    // it does not make other stores/native mutations crash-atomic or authorize
    // native media. Those consumers still need their own durable bindings.
    internal bool PublishIfCurrent(Prepared request, Action publish)
    {
        ArgumentNullException.ThrowIfNull(publish);
        lock (_gate)
        {
            if (!MatchesCurrent(request)) return false;
            publish();
            return true;
        }
    }
    private void Persist(Document doc)
    {
        Directory.CreateDirectory(_root);
        var key = Key(true);
        CryptographicOperations.ZeroMemory(key);
        var path = ProfilePath(doc.OwnerUserId);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(doc);
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { file.Write(bytes); file.Flush(true); }
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    private byte[] Key(bool create)
    {
        var path = Path.Combine(_root, "encryption.key");
        if (!File.Exists(path) && create)
        {
            Directory.CreateDirectory(_root);
            if (Directory.EnumerateFiles(_root, "*.json").Any())
                throw new InvalidDataException("Existing profile encryption key unavailable.");
            var bytes = RandomNumberGenerator.GetBytes(32);
            try
            {
                using var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                file.Write(bytes); file.Flush(true);
            }
            finally { CryptographicOperations.ZeroMemory(bytes); }
        }
        if (!File.Exists(path)) throw new InvalidDataException("Profile encryption key unavailable.");
        var key = File.ReadAllBytes(path);
        if (key.Length != 32) { CryptographicOperations.ZeroMemory(key); throw new InvalidDataException("Invalid profile encryption key."); }
        return key;
    }
    private static byte[] AssociatedData(Document doc) => Encoding.UTF8.GetBytes(FormattableString.Invariant(
        $"personal-youtube:v1:{doc.OwnerUserId:N}:{doc.Current.CollectionId:N}:{doc.Current.GenerationId:N}:{doc.Current.KeyRevision}"));
    private string Encrypt(Document doc, string secret)
    {
        var key = Key(true); var plain = Encoding.UTF8.GetBytes(secret);
        try
        {
            var nonce = RandomNumberGenerator.GetBytes(12); var cipher = new byte[plain.Length]; var tag = new byte[16];
            using var aes = new AesGcm(key);
            aes.Encrypt(nonce, plain, cipher, tag, AssociatedData(doc));
            return Convert.ToBase64String(nonce.Concat(tag).Concat(cipher).ToArray());
        }
        finally { CryptographicOperations.ZeroMemory(key); CryptographicOperations.ZeroMemory(plain); }
    }
    private string? Decrypt(Document doc)
    {
        if (doc.Current.EncryptedApiKey == null) return null;
        byte[] bytes;
        try { bytes = Convert.FromBase64String(doc.Current.EncryptedApiKey); }
        catch (FormatException) { throw new InvalidDataException("Invalid encrypted profile key."); }
        if (bytes.Length < 29 || bytes.Length > 284) throw new InvalidDataException("Invalid encrypted profile key.");
        var key = Key(false); var plain = new byte[bytes.Length - 28];
        try
        {
            using var aes = new AesGcm(key);
            aes.Decrypt(bytes.AsSpan(0, 12), bytes.AsSpan(28), bytes.AsSpan(12, 16), plain, AssociatedData(doc));
            return Encoding.UTF8.GetString(plain);
        }
        finally { CryptographicOperations.ZeroMemory(key); CryptographicOperations.ZeroMemory(plain); }
    }
}
