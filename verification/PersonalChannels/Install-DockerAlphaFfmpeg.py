"""Install the yt-dlp project's Linux FFmpeg build in the fixture only."""
import hashlib
import io
import json
import pathlib
import subprocess
import tarfile
import urllib.request

ROOT = pathlib.Path("/tmp/emby-youtube-alpha-verification")

def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Emby-alpha-test"}), timeout=25) as response:
        return response.read(256 * 1024 * 1024)

def main():
    manifest = json.loads((ROOT / "fixture.json").read_text())
    container = json.loads(subprocess.check_output(["docker", "inspect", manifest["Name"]]))[0]
    assert container["Id"] == manifest["ContainerId"]
    assert len(container["Mounts"]) == 1 and container["Mounts"][0]["Source"] == str(ROOT / "config")
    release = json.loads(fetch("https://api.github.com/repos/yt-dlp/FFmpeg-Builds/releases/latest"))
    asset = next(asset for asset in release["assets"] if asset["name"].endswith("-linux64-gpl.tar.xz"))
    assert asset["digest"].startswith("sha256:")
    content = fetch(asset["browser_download_url"])
    digest = hashlib.sha256(content).hexdigest()
    assert digest == asset["digest"].split(":", 1)[1]
    directory = ROOT / "config/personal-tools"
    with tarfile.open(fileobj=io.BytesIO(content)) as archive:
        for name in ("ffmpeg", "ffprobe"):
            member = next(member for member in archive.getmembers() if member.name.endswith("/bin/" + name))
            assert member.isfile()
            with archive.extractfile(member) as source:
                (directory / name).write_bytes(source.read())
            (directory / name).chmod(0o755)
        for member in archive.getmembers():
            if member.isfile() and pathlib.PurePosixPath(member.name).name.startswith(("LICENSE", "COPYING")):
                with archive.extractfile(member) as source:
                    (directory / pathlib.PurePosixPath(member.name).name).write_bytes(source.read())
    version = subprocess.check_output(["docker", "exec", manifest["Name"], "/config/personal-tools/ffmpeg", "-version"], text=True).splitlines()[0]
    report = dict(Release=release["tag_name"], Asset=asset["name"], SHA256=digest, Version=version)
    (ROOT / "ffmpeg.json").write_text(json.dumps(report))
    print(json.dumps(report))

if __name__ == "__main__":
    main()
