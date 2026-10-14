"""Install an exactly hashed artifact into the recorded isolated container."""
import hashlib
import json
import pathlib
import subprocess
import sys
import urllib.request

ROOT = pathlib.Path("/tmp/emby-youtube-alpha-verification")

def main():
    manifest = json.loads((ROOT / "fixture.json").read_text())
    current = json.loads(subprocess.check_output(["docker", "inspect", manifest["Name"]]))[0]
    assert current["Id"] == manifest["ContainerId"]
    assert current["Config"]["Labels"]["purpose"] == "personal-youtube-alpha-verification"
    assert len(current["Mounts"]) == 1 and current["Mounts"][0]["Source"] == str(ROOT / "config")
    with urllib.request.urlopen("http://10.0.10.17:18098/Emby.YouTubePlugin.dll", timeout=12) as response:
        content = response.read(8 * 1024 * 1024)
    digest = hashlib.sha256(content).hexdigest()
    assert digest == sys.argv[1].lower(), "Artifact hash mismatch"
    subprocess.run(["docker", "stop", "--time", "10", manifest["Name"]], check=True, stdout=subprocess.DEVNULL)
    directory = ROOT / "config/plugins"
    directory.mkdir(exist_ok=True)
    (directory / "Emby.YouTubePlugin.dll").write_bytes(content)
    manifest["PluginSHA256"] = digest
    (ROOT / "fixture.json").write_text(json.dumps(manifest))
    subprocess.run(["docker", "start", manifest["Name"]], check=True, stdout=subprocess.DEVNULL)
    print(json.dumps(dict(Installed=True, SHA256=digest, Bytes=len(content), Container=manifest["Name"])))

if __name__ == "__main__":
    main()
