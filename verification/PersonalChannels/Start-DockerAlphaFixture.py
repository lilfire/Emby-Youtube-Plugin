"""Create a fresh alpha server from the host's installed Emby image.

Run on the existing Docker host. No production mounts or credentials are
copied. Keep the recorded root/container for follow-up verification.
"""
import json
import pathlib
import subprocess

ROOT = pathlib.Path("/tmp/emby-youtube-alpha-verification")
NAME = "emby-youtube-alpha-verification"

def docker(*args):
    return subprocess.check_output(["docker", *args], text=True).strip()

def main():
    source = json.loads(docker("inspect", "emby_backup"))[0]
    assert source["State"]["Running"], "Source image must belong to the running server"
    assert ROOT.resolve() == ROOT and ROOT.parent == pathlib.Path("/tmp")
    assert not ROOT.exists(), "Inspect existing alpha fixture before starting another"
    assert NAME not in docker("container", "ls", "-a", "--format", "{{.Names}}").splitlines()
    ROOT.mkdir(mode=0o700)
    (ROOT / "config").mkdir(mode=0o700)
    record = dict(Name=NAME, Root=str(ROOT), SourceImage=source["Image"],
                  Config=str(ROOT / "config"), Port=18097, ProductionMountsCopied=False)
    (ROOT / "fixture.json").write_text(json.dumps(record))
    identifier = docker("run", "--detach", "--name", NAME, "--restart", "no",
                        "--memory", "1536m", "--cpus", "2", "--label", "purpose=personal-youtube-alpha-verification",
                        "--publish", "127.0.0.1:18097:8096", "--volume", str(ROOT / "config") + ":/config",
                        "--env", "PUID=0", "--env", "PGID=0", "--env", "DOTNET_GCHeapHardLimit=0x40000000",
                        source["Image"])
    record["ContainerId"] = identifier
    (ROOT / "fixture.json").write_text(json.dumps(record))
    print(json.dumps(record))

if __name__ == "__main__":
    main()
