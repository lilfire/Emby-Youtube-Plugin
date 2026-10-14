using System.Net.WebSockets;
using System.Text.Json;

// Isolated feasibility gate. Never expose the upstream directly to clients.
var root = Path.GetFullPath(args.Single());
var authPath = Path.Combine(root, "test-auth.json");
using var auth = JsonDocument.Parse(File.ReadAllText(authPath));
var token = auth.RootElement.GetProperty("Token").GetString()!;
var builder = WebApplication.CreateBuilder(Array.Empty<string>());
builder.Logging.ClearProviders(); // Request URLs may contain authentication tokens.
builder.WebHost.UseUrls("http://127.0.0.1:18097");
var app = builder.Build();
app.UseWebSockets();
var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
var upstream = "http://127.0.0.1:18096";

async Task<string?> Ready(CancellationToken cancellation)
{
    try
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, upstream + "/emby/PersonalChannelsFixture/Guard");
        request.Headers.Add("X-Emby-Token", token);
        using var response = await http.SendAsync(request, cancellation);
        if (!response.IsSuccessStatusCode) return null;
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellation));
        var value = json.RootElement;
        return value.GetProperty("Installed").GetBoolean() && value.GetProperty("Enabled").GetBoolean() && value.GetProperty("Ready").GetBoolean()
            ? value.GetProperty("BootId").GetString() : null;
    }
    catch { return null; }
}

app.Run(async context =>
{
    var cancellation = context.RequestAborted;
    var generation = await Ready(cancellation);
    if (generation == null) { context.Response.StatusCode = 503; return; }
    if (context.WebSockets.IsWebSocketRequest)
    {
        using var socket = new ClientWebSocket();
        try
        {
            await socket.ConnectAsync(new Uri("ws://127.0.0.1:18096" + context.Request.Path + context.Request.QueryString), cancellation);
            if (generation != await Ready(cancellation)) { context.Response.StatusCode = 503; return; }
            using var client = await context.WebSockets.AcceptWebSocketAsync();
            using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            async Task Pump(WebSocket from, WebSocket to)
            {
                var buffer = new byte[65536];
                while (!lifetime.IsCancellationRequested)
                {
                    var message = await from.ReceiveAsync(buffer, lifetime.Token);
                    if (message.MessageType == WebSocketMessageType.Close) break;
                    if (generation != await Ready(lifetime.Token)) break;
                    await to.SendAsync(buffer.AsMemory(0, message.Count), message.MessageType, message.EndOfMessage, lifetime.Token);
                }
            }
            await Task.WhenAny(Pump(socket, client), Pump(client, socket));
            lifetime.Cancel();
            client.Abort();
        }
        catch { if (!context.Response.HasStarted) context.Response.StatusCode = 503; }
        return;
    }
    try
    {
        using var request = new HttpRequestMessage(new HttpMethod(context.Request.Method), upstream + context.Request.Path + context.Request.QueryString);
        if (context.Request.ContentLength > 0 || context.Request.Headers.ContainsKey("Transfer-Encoding")) request.Content = new StreamContent(context.Request.Body);
        foreach (var header in context.Request.Headers)
        {
            if (header.Key.Equals("Host", StringComparison.OrdinalIgnoreCase) || header.Key.Equals("Connection", StringComparison.OrdinalIgnoreCase)) continue;
            if (!request.Headers.TryAddWithoutValidation(header.Key, header.Value.ToArray())) request.Content?.Headers.TryAddWithoutValidation(header.Key, header.Value.ToArray());
        }
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellation);
        // Recheck before exposing any headers/bytes: refuse a restart between probe and request.
        if (generation != await Ready(cancellation)) { context.Response.StatusCode = 503; return; }
        context.Response.StatusCode = (int)response.StatusCode;
        foreach (var header in response.Headers.Concat(response.Content.Headers)) context.Response.Headers[header.Key] = header.Value.ToArray();
        context.Response.Headers.Remove("Transfer-Encoding");
        await response.Content.CopyToAsync(context.Response.Body, cancellation);
    }
    catch { if (!context.Response.HasStarted) context.Response.StatusCode = 503; }
});
await app.RunAsync();
