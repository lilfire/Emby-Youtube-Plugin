using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Emby.YouTubePlugin;

// Private publisher input. Never return this snapshot as an HTTP response:
// publication must use Store.PublishIfCurrent and the native creation binding.
internal sealed class PersonalYouTubeCatalog
{
    internal sealed record Video(string Id, string Title, string Description);
    internal sealed record Page(Guid OwnerUserId, Guid CollectionId, Guid GenerationId,
        long Revision, long KeyRevision, string ChannelId, Video[] Videos, string? NextPageToken);
    private static readonly HttpClient Client = new(new HttpClientHandler { AllowAutoRedirect = false })
        { Timeout = TimeSpan.FromSeconds(30) };
    private readonly PersonalYouTubeStore _store;
    private readonly HttpClient _client;
    internal PersonalYouTubeCatalog(PersonalYouTubeStore store, HttpClient? client = null)
    { _store = store; _client = client ?? Client; }

    internal async Task<Page> ReadPageAsync(PersonalYouTubeStore.Prepared snapshot,
        string channelId, string? pageToken, CancellationToken cancellationToken)
    {
        // A copied snapshot cannot introduce a different key or channel list.
        var current = _store.Prepare(snapshot.OwnerUserId);
        if (!_store.IsCurrent(snapshot) || current.ApiKey != snapshot.ApiKey
            || !current.Channels.SequenceEqual(snapshot.Channels, StringComparer.Ordinal)
            || !current.Channels.Contains(channelId, StringComparer.Ordinal))
            throw new InvalidOperationException("Personal YouTube profile changed or channel unavailable.");
        if (string.IsNullOrWhiteSpace(current.ApiKey))
            throw new InvalidOperationException("Personal YouTube API key required.");
        if (pageToken != null && (pageToken.Length is 0 or > 2048 || pageToken.Any(char.IsControl)))
            throw new ArgumentException("Invalid YouTube page token.");

        // No global configuration, cache, in-flight coalescing, or fallback key.
        using var channel = await ReadAsync("channels?part=contentDetails&id="
            + Uri.EscapeDataString(channelId), current, cancellationToken).ConfigureAwait(false);
        var items = channel.RootElement.GetProperty("items");
        if (items.GetArrayLength() != 1 || items[0].GetProperty("id").GetString() != channelId)
            throw new InvalidDataException("YouTube channel unavailable.");
        var uploads = items[0].GetProperty("contentDetails").GetProperty("relatedPlaylists")
            .GetProperty("uploads").GetString();
        if (uploads == null || !Regex.IsMatch(uploads, @"\AUU[A-Za-z0-9_-]{22}\z"))
            throw new InvalidDataException("Invalid YouTube uploads playlist.");
        var query = "playlistItems?part=snippet,contentDetails&maxResults=50&playlistId="
            + Uri.EscapeDataString(uploads);
        if (pageToken != null) query += "&pageToken=" + Uri.EscapeDataString(pageToken);
        using var videos = await ReadAsync(query, current, cancellationToken).ConfigureAwait(false);
        var result = new List<Video>();
        foreach (var item in videos.RootElement.GetProperty("items").EnumerateArray())
        {
            var id = item.GetProperty("contentDetails").GetProperty("videoId").GetString();
            var snippet = item.GetProperty("snippet");
            if (id == null || !Regex.IsMatch(id, @"\A[A-Za-z0-9_-]{11}\z")
                || snippet.GetProperty("channelId").GetString() != channelId)
                throw new InvalidDataException("Invalid YouTube uploads item.");
            result.Add(new(id, snippet.GetProperty("title").GetString() ?? "",
                snippet.GetProperty("description").GetString() ?? ""));
        }
        var next = videos.RootElement.TryGetProperty("nextPageToken", out var token) ? token.GetString() : null;
        if (!_store.IsCurrent(current))
            throw new InvalidOperationException("Personal YouTube profile changed during retrieval.");
        return new(current.OwnerUserId, current.CollectionId, current.GenerationId, current.Revision,
            current.KeyRevision, channelId, result.ToArray(), next);
    }

    private async Task<JsonDocument> ReadAsync(string query, PersonalYouTubeStore.Prepared snapshot,
        CancellationToken cancellationToken)
    {
        if (!_store.IsCurrent(snapshot)) throw new InvalidOperationException("Personal YouTube profile changed.");
        try
        {
            using var response = await _client.GetAsync("https://www.googleapis.com/youtube/v3/" + query
                + "&key=" + Uri.EscapeDataString(snapshot.ApiKey!), HttpCompletionOption.ResponseHeadersRead,
                cancellationToken).ConfigureAwait(false);
            using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var buffer = new MemoryStream();
            var bytes = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(bytes.AsMemory(), cancellationToken).ConfigureAwait(false)) != 0)
            {
                if (buffer.Length + count > 4 * 1024 * 1024)
                    throw new InvalidDataException("Personal YouTube response too large.");
                buffer.Write(bytes, 0, count);
            }
            if(!response.IsSuccessStatusCode)
            {
                // Extract only known machine-readable reasons; provider messages
                // and request URLs can contain personal credentials.
                using var failure = JsonDocument.Parse(buffer.ToArray());
                var reasons = failure.RootElement.TryGetProperty("error", out var error) && error.TryGetProperty("errors", out var errors)
                    && errors.ValueKind == JsonValueKind.Array
                    ? errors.EnumerateArray().Select(value => value.TryGetProperty("reason", out var reason) ? reason.GetString() : null).ToArray()
                    : Array.Empty<string?>();
                if(error.ValueKind == JsonValueKind.Object && error.TryGetProperty("details", out var details) && details.ValueKind == JsonValueKind.Array)
                    reasons = reasons.Concat(details.EnumerateArray().Select(value => value.TryGetProperty("reason", out var reason) ? reason.GetString() : null)).ToArray();
                if(reasons.Any(reason => reason is "quotaExceeded" or "dailyLimitExceeded" or "rateLimitExceeded" or "QUOTA_EXCEEDED" or "RATE_LIMIT_EXCEEDED"))
                    throw new PersonalYouTubeJobFailure("YouTubeQuotaExceeded");
                if(reasons.Any(reason => reason is "keyInvalid" or "accessNotConfigured" or "ipRefererBlocked" or "forbidden"
                    or "API_KEY_INVALID" or "API_KEY_SERVICE_BLOCKED" or "API_KEY_IP_ADDRESS_BLOCKED" or "API_KEY_HTTP_REFERRER_BLOCKED" or "SERVICE_DISABLED"))
                    throw new PersonalYouTubeJobFailure("YouTubeKeyRejected");
                throw new PersonalYouTubeJobFailure("YouTubeRequestFailed");
            }
            return JsonDocument.Parse(buffer.ToArray());
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        // HTTP exceptions can contain the request URL and its API key.
        catch (Exception error) when (error is HttpRequestException or OperationCanceledException or JsonException)
        { throw new InvalidDataException("Personal YouTube request failed."); }
    }
}
