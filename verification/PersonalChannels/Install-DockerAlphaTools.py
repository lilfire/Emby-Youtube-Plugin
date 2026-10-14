"""Fetch official Linux tools into the isolated fixture, verifying SHA256."""
import hashlib
import json
import pathlib
import subprocess
import tarfile
import urllib.request

ROOT = pathlib.Path("/tmp/emby-youtube-alpha-verification")
TOOLS = ROOT / "config/personal-tools"

def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Emby-personal-YouTube-alpha-verification"})
    with urllib.request.urlopen(request, timeout=25) as response:
        return response.read(128 * 1024 * 1024)

def verified(url, digest):
    content = fetch(url)
    assert hashlib.sha256(content).hexdigest() == digest.lower(), "Official tool checksum mismatch"
    return content

def main():
    manifest = json.loads((ROOT / "fixture.json").read_text())
    current = json.loads(subprocess.check_output(["docker", "inspect", manifest["Name"]]))[0]
    assert current["Id"] == manifest["ContainerId"]
    assert len(current["Mounts"]) == 1 and current["Mounts"][0]["Source"] == str(ROOT / "config")
    TOOLS.mkdir(exist_ok=True)
    sums = fetch("https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt").decode()
    node_hash, node_name = next(line.split() for line in sums.splitlines() if line.endswith("-linux-x64.tar.xz"))
    archive = TOOLS / node_name
    archive.write_bytes(verified("https://nodejs.org/dist/latest-v24.x/" + node_name, node_hash))
    with tarfile.open(archive) as package:
        member = package.getmember(node_name.removesuffix(".tar.xz") + "/bin/node")
        assert member.isfile()
        with package.extractfile(member) as source:
            (TOOLS / "node").write_bytes(source.read())
    (TOOLS / "node").chmod(0o755)
    archive.unlink()
    release = json.loads(fetch("https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"))
    assets = {asset["name"]: asset["browser_download_url"] for asset in release["assets"]}
    ytdlp_hash, _ = next(line.split() for line in fetch(assets["SHA2-256SUMS"]).decode().splitlines() if line.endswith(" yt-dlp_linux"))
    (TOOLS / "yt-dlp").write_bytes(verified(assets["yt-dlp_linux"], ytdlp_hash))
    (TOOLS / "yt-dlp").chmod(0o755)
    versions = {}
    for tool, flag in (("node", "--version"), ("yt-dlp", "--version")):
        versions[tool] = subprocess.check_output(["docker", "exec", manifest["Name"], "/config/personal-tools/" + tool, flag], text=True).strip()
    report = dict(Tools=versions, NodeArchive=node_name, NodeSHA256=node_hash, YtDlpRelease=release["tag_name"], YtDlpSHA256=ytdlp_hash,
                  ContainerPaths=dict(Node="/config/personal-tools/node", Downloader="/config/personal-tools/yt-dlp", Ffmpeg="/app/emby/bin/ffmpeg"))
    (ROOT / "tools.json").write_text(json.dumps(report))
    print(json.dumps(report))

if __name__ == "__main__":
    main()
