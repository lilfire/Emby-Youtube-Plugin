"""Configure only the recorded fresh fixture through Emby's plugin API."""
import json
import pathlib
import subprocess
import urllib.request

ROOT = pathlib.Path("/tmp/emby-youtube-alpha-verification")
PLUGIN = "B2C3D4E5-F6A7-4B5C-9D0E-1F2A3B4C5D6E"

def main():
    manifest = json.loads((ROOT / "fixture.json").read_text())
    current = json.loads(subprocess.check_output(["docker", "inspect", manifest["Name"]]))[0]
    assert current["Id"] == manifest["ContainerId"]
    assert len(current["Mounts"]) == 1 and current["Mounts"][0]["Source"] == str(ROOT / "config")
    auth = json.loads((ROOT / "auth.json").read_text())
    url = "http://127.0.0.1:18097/emby/Plugins/" + PLUGIN + "/Configuration"
    def call(body=None):
        headers = {"X-Emby-Token": auth["Token"], "Content-Type": "application/json"}
        request = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=headers)
        with urllib.request.urlopen(request, timeout=15) as response:
            value = response.read()
            return json.loads(value) if value else None
    configuration = call()
    configuration.update(PersonalYouTubeAlphaEnabled=True, PersonalYouTubeDownloaderPath="/config/personal-tools/yt-dlp",
                         PersonalYouTubeNodePath="/config/personal-tools/node", PersonalYouTubeFfmpegPath="/config/personal-tools/ffmpeg",
                         PersonalYouTubeMaxVideos=2, PersonalYouTubeMaxVideoBytes=256 * 1024 * 1024,
                         PersonalYouTubeMaxCollectionBytes=512 * 1024 * 1024, PersonalYouTubeMaxStorageBytes=2 * 1024 * 1024 * 1024,
                         ShowTrending=False, ShowCategories=False)
    call(configuration)
    persisted = call()
    for key in [key for key in configuration if key.startswith("PersonalYouTube")]:
        assert persisted[key] == configuration[key], "Plugin settings did not persist"
    subprocess.run(["docker", "restart", "--time", "10", manifest["Name"]], check=True, stdout=subprocess.DEVNULL)
    print(json.dumps(dict(SettingsReadback=True, Restarted=True, MaxVideos=2, StorageMiB=2048)))

if __name__ == "__main__":
    main()
