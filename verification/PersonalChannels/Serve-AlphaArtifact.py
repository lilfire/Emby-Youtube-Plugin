"""Temporary transport of one compiled public plugin artifact to the fixture."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ARTIFACT = Path(__file__).resolve().parents[2] / "bin/Release/net6.0/Emby.YouTubePlugin.dll"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/Emby.YouTubePlugin.dll":
            self.send_error(404)
            return
        body = ARTIFACT.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

# Exit after the single transfer; interrupting the parent shell does not
# reliably stop its Python child on Windows.
HTTPServer.allow_reuse_address = False
with HTTPServer(("10.0.10.17", 18098), Handler) as server:
    server.timeout = 60
    server.handle_request()
