"""Complete the fresh fixture wizard and keep credentials only on its host."""
import json
import pathlib
import secrets
import subprocess
import urllib.parse
import urllib.request

ROOT = pathlib.Path("/tmp/emby-youtube-alpha-verification")
BASE = "http://127.0.0.1:18097/emby/"

def call(path, body=None, token=None, form=False):
    headers = {}
    data = None
    if token:
        headers["X-Emby-Token"] = token
    if body is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded" if form else "application/json"
        data = (urllib.parse.urlencode(body) if form else json.dumps(body)).encode()
    headers["Authorization"] = 'MediaBrowser Client="Closed alpha Docker verification", Device="Isolated fixture", DeviceId="docker-alpha-fixture", Version="1"'
    with urllib.request.urlopen(urllib.request.Request(BASE + path, data=data, headers=headers), timeout=15) as response:
        value = response.read()
        return json.loads(value) if value else None

def main():
    manifest = json.loads((ROOT / "fixture.json").read_text())
    current = json.loads(subprocess.check_output(["docker", "inspect", manifest["Name"]]))[0]
    assert current["Id"] == manifest["ContainerId"]
    assert len(current["Mounts"]) == 1 and current["Mounts"][0]["Source"] == str(ROOT / "config")
    auth_path = ROOT / "auth.json"
    assert not auth_path.exists(), "Read existing authenticated fixture before repeating initialization"
    initial = call("Startup/User")
    assert initial["Name"] == "root", "This helper initializes only the fresh fixture"
    password = secrets.token_urlsafe(32)
    auth = dict(Username="closed-alpha-administrator", Password=password)
    auth_path.write_text(json.dumps(auth)); auth_path.chmod(0o600)
    call("Startup/User", dict(Name=auth["Username"], Password=password), form=True)
    call("Startup/RemoteAccess", dict(EnableAutomaticPortMapping="false"), form=True)
    call("Startup/Complete", {})
    session = call("Users/AuthenticateByName", dict(Username=auth["Username"], Pw=password))
    assert session["User"]["Policy"]["IsAdministrator"]
    auth.update(Token=session["AccessToken"], UserId=session["User"]["Id"])
    auth_path.write_text(json.dumps(auth)); auth_path.chmod(0o600)
    info = call("System/Info", token=auth["Token"])
    print(json.dumps(dict(Initialized=True, Version=info["Version"], ServerId=info["Id"], AdministratorVerified=True,
                         AutomaticPortMapping=call("System/Configuration", token=auth["Token"])["EnableUPnP"])))

if __name__ == "__main__":
    main()
