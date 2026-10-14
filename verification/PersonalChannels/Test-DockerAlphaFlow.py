"""Real production flow on the fresh Docker fixture, with host-only secrets.

start creates ordinary test accounts and saves the real key through MyProfile.
poll reads the existing job; it never repeats the save or starts another job.
"""
import json
import pathlib
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET

ROOT = pathlib.Path("/tmp/emby-youtube-alpha-verification")
BASE = "http://127.0.0.1:18097/emby/"
SOURCE = pathlib.Path("/srv/dev-disk-by-uuid-f02cbf33-574c-4779-8aac-21508166ad72/appdata/emby/config/plugins/configurations/Emby.YouTubePlugin.xml")

def call(path, token, body=None):
    headers = {"X-Emby-Token": token, "Content-Type": "application/json",
               "Authorization": 'MediaBrowser Client="Closed alpha Docker flow", Device="Isolated", DeviceId="docker-alpha-flow", Version="1"'}
    request = urllib.request.Request(BASE + path, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            content = response.read()
            return json.loads(content) if content else None
    except urllib.error.HTTPError as error:
        raise RuntimeError("Fixture HTTP " + str(error.code) + " at " + path.split("?")[0]) from None

def save(state):
    path = ROOT / "flow-state.json"
    path.write_text(json.dumps(state)); path.chmod(0o600)

def video_ids(user, root):
    items = call("Users/" + user["UserId"] + "/Items?ParentId=" + str(root)
                 + "&Recursive=true&IncludeItemTypes=Video&Fields=Overview", user["Token"])
    return sorted(item["Id"] for item in items["Items"])

def assert_retired(state, admin, owner):
    libraries = call("Library/VirtualFolders/Query", admin["Token"])["Items"]
    assert str(state["RetiredRoot"]) not in [str(item["ItemId"]) for item in libraries]
    for video in state["RetiredVideos"]:
        request = urllib.request.Request(BASE + "Videos/" + video + "/stream.mp4?Static=true",
                                         headers={"X-Emby-Token": owner["Token"]})
        try:
            urllib.request.urlopen(request, timeout=10).close()
            raise AssertionError("Retired video remained usable")
        except urllib.error.HTTPError as error:
            assert error.code == 404

def verify_target():
    manifest = json.loads((ROOT / "fixture.json").read_text())
    container = json.loads(subprocess.check_output(["docker", "inspect", manifest["Name"]]))[0]
    assert container["Id"] == manifest["ContainerId"]
    assert len(container["Mounts"]) == 1 and container["Mounts"][0]["Source"] == str(ROOT / "config")
    return json.loads((ROOT / "auth.json").read_text())

def main():
    admin = verify_target()
    mode = sys.argv[1]
    if mode == "start":
        assert not (ROOT / "flow-state.json").exists(), "Read the existing flow instead of repeating setup"
        state = dict(Users={}, Stage="CreatingUsers", MainServerChanged=False)
        save(state)
        config = call("Plugins/B2C3D4E5-F6A7-4B5C-9D0E-1F2A3B4C5D6E/Configuration", admin["Token"])
        config.update(PersonalYouTubeMaxVideoBytes=256 * 1024 * 1024,
                      PersonalYouTubeMaxCollectionBytes=512 * 1024 * 1024, PersonalYouTubeMaxStorageBytes=2 * 1024 * 1024 * 1024)
        call("Plugins/B2C3D4E5-F6A7-4B5C-9D0E-1F2A3B4C5D6E/Configuration", admin["Token"], config)
        # The worker retains the configuration object owned by the plugin;
        # restart makes the new limits effective without relying on mutation.
        manifest = json.loads((ROOT / "fixture.json").read_text())
        subprocess.run(["docker", "restart", "--time", "10", manifest["Name"]], check=True, stdout=subprocess.DEVNULL)
        state["Stage"] = "AwaitingConfiguredServer"; save(state)
        print(json.dumps(dict(Prepared=True, NextAction="begin")))
        return
    state = json.loads((ROOT / "flow-state.json").read_text())
    if mode == "begin":
        assert state["Stage"] == "AwaitingConfiguredServer" and not state["Users"]
        status = call("YouTubePlugin/PersonalServerStatus", admin["Token"])
        assert status["WorkerRunning"] and status["MediaToolsAvailable"]
        for actor in ("a", "b"):
            name = "closed-alpha-" + actor
            user = call("Users/New", admin["Token"], dict(Name=name))
            state["Users"][actor] = dict(UserId=user["Id"], Name=name); save(state)
            policy = user["Policy"]
            policy.update(IsAdministrator=False, EnableAllFolders=actor == "b", EnabledFolders=[])
            call("Users/" + user["Id"] + "/Policy", admin["Token"], policy)
            session = call("Users/AuthenticateByName", admin["Token"], dict(Username=name, Pw=""))
            assert session["User"]["Id"] == user["Id"] and not session["User"]["Policy"]["IsAdministrator"]
            state["Users"][actor]["Token"] = session["AccessToken"]; save(state)
        key = ET.parse(SOURCE).getroot().findtext("ApiKey")
        channel = json.loads((ROOT / "google-catalog.json").read_text())["SampleChannel"]
        state["Stage"] = "SavingPersonalProfile"; save(state)
        profile = call("YouTubePlugin/MyProfile", state["Users"]["a"]["Token"], dict(ExpectedRevision=0, Channels=[channel], ApiKey=key))
        state.update(Stage="Running", Profile=profile); save(state)
        print(json.dumps(dict(OrdinaryUsersCreated=True, SavedPersonalKey=True, Channels=1, ProfileRevision=profile["Revision"])))
        return
    a = state["Users"]["a"]; b = state["Users"]["b"]
    if mode == "refresh":
        assert state["Stage"] == "ReadyVerified"
        profile = call("YouTubePlugin/MyProfile", a["Token"])
        state["RetiredRoot"] = state["Job"]["LibraryId"]
        state["RetiredVideos"] = video_ids(a, state["RetiredRoot"])
        state["Stage"] = "RequestingRefresh"; save(state)
        updated = call("YouTubePlugin/MyProfile", a["Token"],
                       dict(ExpectedRevision=profile["Revision"], Channels=profile["Channels"]))
        assert updated["HasApiKey"] and updated["KeyRevision"] == profile["KeyRevision"]
        state.update(Profile=updated, Stage="Refreshing"); save(state)
        print(json.dumps(dict(RefreshRequested=True, KeyRetained=True, NextAction="poll")))
        return
    if mode == "interrupt-buffering":
        assert state["Stage"] == "ReadyVerified"
        profile = call("YouTubePlugin/MyProfile", a["Token"])
        state["RetiredRoot"] = state["Job"]["LibraryId"]
        state["RetiredVideos"] = video_ids(a, state["RetiredRoot"])
        state["Stage"] = "RequestingInterruptWindow"; save(state)
        updated = call("YouTubePlugin/MyProfile", a["Token"],
                       dict(ExpectedRevision=profile["Revision"], Channels=profile["Channels"]))
        state.update(Profile=updated, Stage="AwaitingBufferingInterrupt"); save(state)
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            job = call("YouTubePlugin/MyJob", a["Token"])
            assert job["ProfileRevision"] == updated["Revision"]
            if job["State"] == "Buffering":
                manifest = json.loads((ROOT / "fixture.json").read_text())
                state.update(Stage="BufferingKillRequested", InterruptedJobState=job["State"]); save(state)
                subprocess.run(["docker", "kill", "--signal", "KILL", manifest["Name"]],
                               check=True, stdout=subprocess.DEVNULL)
                stopped = json.loads(subprocess.check_output(["docker", "inspect", manifest["Name"]]))[0]
                assert not stopped["State"]["Running"]
                persisted = json.loads((ROOT / "config/data/youtube-personal/jobs" / (a["UserId"] + ".json")).read_text())
                state.update(Stage="RecoveringInterruptedBuffering", ActualProcessKilled=True,
                             DurableInterruptedState=persisted["State"]); save(state)
                subprocess.run(["docker", "start", manifest["Name"]], check=True, stdout=subprocess.DEVNULL)
                assert persisted["State"] in ("Buffering", "Publishing"), "Job completed before kill; do not claim interrupted work"
                print(json.dumps(dict(ActualProcessKilled=True, ObservedState="Buffering",
                                      DurableInterruptedState=persisted["State"], NextAction="poll")))
                return
            assert job["State"] not in ("Failed", "Ready"), "Interrupt window missed; inspect existing job"
            time.sleep(0.05)
        raise RuntimeError("Buffering window not observed; inspect existing job instead of repeating save")
    if mode == "multiple-channels":
        assert state["Stage"] == "DeletedVerified"
        profile = call("YouTubePlugin/MyProfile", a["Token"])
        key = ET.parse(SOURCE).getroot().findtext("ApiKey")
        channels = [json.loads((ROOT / "google-catalog.json").read_text())["SampleChannel"],
                    "UC_x5XG1OV2P6uZZ5FSM9Ttw"]
        expected = {}
        for channel in channels:
            query = urllib.parse.urlencode(dict(part="snippet,contentDetails", maxResults=1,
                                                  playlistId="UU" + channel[2:], key=key))
            try:
                with urllib.request.urlopen("https://www.googleapis.com/youtube/v3/playlistItems?" + query,
                                            timeout=15) as response:
                    item = json.load(response)["items"][0]
                assert item["snippet"]["channelId"] == channel
                expected[item["contentDetails"]["videoId"]] = item["snippet"]["title"]
            except Exception:
                raise RuntimeError("Controlled multi-channel catalog lookup failed") from None
        assert len(expected) == 2
        state.update(Stage="SavingMultipleChannels", ExpectedMultiVideos=expected); save(state)
        updated = call("YouTubePlugin/MyProfile", a["Token"],
                       dict(ExpectedRevision=profile["Revision"], Channels=channels, ApiKey=key))
        assert len(updated["Channels"]) == 2 and updated["HasApiKey"]
        state.update(Stage="MultipleChannelsRunning", Profile=updated); save(state)
        print(json.dumps(dict(MultipleChannelsSaved=True, Channels=2, NextAction="poll")))
        return
    if mode == "restart":
        assert state["Stage"] == "ReadyVerified"
        state["RestartRoot"] = state["Job"]["LibraryId"]
        state["RestartVideos"] = video_ids(a, state["RestartRoot"])
        assert state["RestartVideos"]
        manifest = json.loads((ROOT / "fixture.json").read_text())
        current = json.loads(subprocess.check_output(["docker", "inspect", manifest["Name"]]))[0]
        state["BeforeRestartStartedAt"] = current["State"]["StartedAt"]
        state["Stage"] = "RestartRequested"; save(state)
        subprocess.run(["docker", "restart", "--time", "10", manifest["Name"]],
                       check=True, stdout=subprocess.DEVNULL)
        print(json.dumps(dict(RestartRequested=True, NextAction="poll")))
        return
    if mode == "delete":
        assert state["Stage"] == "ReadyVerified"
        profile = call("YouTubePlugin/MyProfile", a["Token"])
        state["RetiredRoot"] = state["Job"]["LibraryId"]
        state["RetiredVideos"] = video_ids(a, state["RetiredRoot"])
        generation = profile["GenerationId"].replace("-", "")
        collection = profile["CollectionId"].replace("-", "")
        state["RetiredMediaDirectory"] = str(ROOT / "config/data/youtube-personal/media"
                                              / a["UserId"] / collection / generation)
        state["RetiredBufferDirectory"] = str(ROOT / "config/data/youtube-personal/buffer"
                                               / a["UserId"] / collection / generation)
        state["Stage"] = "DeletingProfile"; save(state)
        deleted = call("YouTubePlugin/MyProfile/Delete", a["Token"],
                       dict(ExpectedRevision=profile["Revision"]))
        state["Profile"] = deleted; save(state)
        print(json.dumps(dict(DeleteRequested=True, NextAction="poll")))
        return
    if mode == "retry-quota":
        assert state["Stage"] == "RestoringKey" and state["Job"]["State"] == "Failed"
        assert state["Job"]["ErrorCode"] == "YouTubeQuotaExceeded"
        profile = call("YouTubePlugin/MyProfile", a["Token"])
        # Explicit action after quota reset. Poll never resubmits a profile.
        updated = call("YouTubePlugin/MyProfile", a["Token"],
                       dict(ExpectedRevision=profile["Revision"], Channels=profile["Channels"]))
        assert updated["KeyRevision"] == profile["KeyRevision"] and updated["HasApiKey"]
        state.update(Profile=updated, Stage="RestoringKey"); save(state)
        print(json.dumps(dict(RetryRequested=True, KeyRetained=True, NextAction="poll")))
        return
    if mode in ("reject-key", "restore-key"):
        assert state["Stage"] == ("ReadyVerified" if mode == "reject-key" else "RejectedKeyVerified")
        profile = call("YouTubePlugin/MyProfile", a["Token"])
        if mode == "reject-key":
            state["RetiredRoot"] = state["Job"]["LibraryId"]
            items = call("Users/" + a["UserId"] + "/Items?ParentId=" + str(state["RetiredRoot"]) + "&Recursive=true&IncludeItemTypes=Video", a["Token"])
            state["RetiredVideos"] = [item["Id"] for item in items["Items"]]
        key = "synthetic-invalid-alpha-key" if mode == "reject-key" else ET.parse(SOURCE).getroot().findtext("ApiKey")
        updated = call("YouTubePlugin/MyProfile", a["Token"], dict(ExpectedRevision=profile["Revision"], Channels=profile["Channels"], ApiKey=key))
        assert updated["KeyRevision"] > profile["KeyRevision"] and updated["HasApiKey"]
        state.update(Profile=updated, Stage="RejectingKey" if mode == "reject-key" else "RestoringKey")
        save(state)
        print(json.dumps(dict(KeyRevisionAdvanced=True, ProfileRevision=updated["Revision"], Stage=state["Stage"])))
        return
    assert mode == "poll", "Unknown flow action"
    job = call("YouTubePlugin/MyJob", a["Token"])
    assert job["OwnerUserId"].replace("-", "") == a["UserId"] and job["ProfileRevision"] == state["Profile"]["Revision"]
    other = call("YouTubePlugin/MyJob?OwnerUserId=" + a["UserId"], b["Token"])
    assert other["OwnerUserId"].replace("-", "") == b["UserId"] and other["LibraryId"] is None
    report = dict(State=job["State"], ErrorCode=job["ErrorCode"], CompletedVideos=job["CompletedVideos"],
                  TotalVideos=job["TotalVideos"], BOnlyOwnStatus=True, RealGoogle=True, NoTestAdapter=True)
    state["Job"] = job
    if state["Stage"] == "DeletingProfile" and job["State"] == "Deleted":
        assert_retired(state, admin, a)
        profile = call("YouTubePlugin/MyProfile", a["Token"])
        assert not profile["HasApiKey"] and not profile["Channels"]
        assert not pathlib.Path(state["RetiredMediaDirectory"]).exists()
        assert not pathlib.Path(state["RetiredBufferDirectory"]).exists()
        state["Stage"] = "DeletedVerified"
        report.update(DeletedProfileVerified=True, RetiredLibraryAndReferencesGone=True,
                      RetiredMediaAndBufferGone=True)
    request = urllib.request.Request(BASE + "YouTubePlugin/PersonalServerStatus", headers={"X-Emby-Token": b["Token"]})
    try:
        urllib.request.urlopen(request, timeout=10).close()
        raise AssertionError("Ordinary account obtained server diagnostics")
    except urllib.error.HTTPError as error:
        assert error.code == 403
        report["ServerDiagnosticsAdministratorOnly"] = True
    if state["Stage"] == "RejectingKey" and job["State"] == "Failed":
        report["KeyRejectionActionable"] = job["ErrorCode"] == "YouTubeKeyRejected"
        assert report["KeyRejectionActionable"], "Real invalid-key response needs a safe actionable error"
        libraries = call("Library/VirtualFolders/Query", admin["Token"])["Items"]
        assert str(state["RetiredRoot"]) not in [item["ItemId"] for item in libraries]
        for video in state["RetiredVideos"]:
            request = urllib.request.Request(BASE + "Videos/" + video + "/stream.mp4?Static=true", headers={"X-Emby-Token": a["Token"]})
            try:
                urllib.request.urlopen(request, timeout=10).close()
                raise AssertionError("Retired video remained usable after key change")
            except urllib.error.HTTPError as error:
                assert error.code == 404
        state["Stage"] = "RejectedKeyVerified"
        report["RetiredLibraryAndReferencesGone"] = True
    if job["State"] == "Ready":
        items = call("Users/" + a["UserId"] + "/Items?ParentId=" + str(job["LibraryId"]) + "&Recursive=true&IncludeItemTypes=Video&Fields=Path,Overview,MediaSources", a["Token"])
        assert len(items["Items"]) == job["TotalVideos"] and job["TotalVideos"] > 0
        own = call("Users/" + a["UserId"] + "/Views", a["Token"])
        foreign = call("Users/" + b["UserId"] + "/Views", b["Token"])
        assert str(job["LibraryId"]) in [item["Id"] for item in own["Items"]]
        assert str(job["LibraryId"]) not in [item["Id"] for item in foreign["Items"]]
        assert next(item["Name"] for item in own["Items"] if item["Id"] == str(job["LibraryId"])) == "YouTube"
        assert all(item["Name"] and item["Name"] != pathlib.Path(item.get("Path", "")).stem
                   for item in items["Items"])
        streams = []
        for item in items["Items"]:
            result = {}
            for actor, token in (("Owner", a["Token"]), ("Foreign", b["Token"])):
                request = urllib.request.Request(BASE + "Videos/" + item["Id"] + "/stream.mp4?Static=true", headers={"X-Emby-Token": token})
                try:
                    with urllib.request.urlopen(request, timeout=15) as response:
                        head = response.read(4096)
                        result[actor + "Status"] = response.status
                        result[actor + "Mp4"] = len(head) > 12 and head[4:8] == b"ftyp"
                except urllib.error.HTTPError as error:
                    result[actor + "Status"] = error.code
            assert result["OwnerStatus"] == 200 and result["OwnerMp4"] and result["ForeignStatus"] == 404
            source = item["MediaSources"][0]["Id"]
            for actor, token in (("OwnerOriginal", a["Token"]), ("ForeignOriginal", b["Token"])):
                request = urllib.request.Request(BASE + "Videos/" + item["Id"] + "/original.mp4?MediaSourceId="
                                                 + urllib.parse.quote(source, safe=""), headers={"X-Emby-Token": token})
                try:
                    with urllib.request.urlopen(request, timeout=15) as response:
                        head = response.read(4096)
                        result[actor + "Status"] = response.status
                        result[actor + "Mp4"] = len(head) > 12 and head[4:8] == b"ftyp"
                except urllib.error.HTTPError as error:
                    result[actor + "Status"] = error.code
            assert result["OwnerOriginalStatus"] == 200 and result["OwnerOriginalMp4"] and result["ForeignOriginalStatus"] == 404
            streams.append(result)
        report.update(OwnNativeLibrary=True, ForeignNativeLibraryAbsent=True, VideoStreams=streams)
        if state["Stage"] == "Refreshing":
            assert_retired(state, admin, a)
            report.update(FreshPublicationAfterRefresh=True, OldReferencesGone=True)
        report["PluginSHA256"] = json.loads((ROOT / "fixture.json").read_text())["PluginSHA256"]
        if state["Stage"] == "RecoveringInterruptedBuffering":
            assert state["ActualProcessKilled"] and state["InterruptedJobState"] == "Buffering"
            assert state["DurableInterruptedState"] in ("Buffering", "Publishing")
            assert_retired(state, admin, a)
            libraries = call("Library/VirtualFolders/Query", admin["Token"])["Items"]
            managed = [item for item in libraries if any(location.startswith("/config/data/youtube-personal/media/")
                       for location in item.get("Locations", []))]
            assert len(managed) == 1 and str(managed[0]["ItemId"]) == str(job["LibraryId"])
            assert len(items["Items"]) == 2
            report.update(ActualDockerProcessInterruption=True, ObservedInterruptedState=state["DurableInterruptedState"],
                          AutomaticRecoveryReady=True, OldReferencesGone=True, OnePersonalLibrary=True)
        if state["Stage"] == "MultipleChannelsRunning":
            actual = {pathlib.Path(item["Path"]).stem: item["Name"] for item in items["Items"]}
            assert actual == state["ExpectedMultiVideos"]
            report.update(MultipleChannelsVerified=True, Channels=2, OneVideoFromEachChannel=True,
                          NativeTitlesMatchGoogle=True)
        if state["Stage"] == "RestartRequested":
            manifest = json.loads((ROOT / "fixture.json").read_text())
            current = json.loads(subprocess.check_output(["docker", "inspect", manifest["Name"]]))[0]
            assert current["State"]["StartedAt"] != state["BeforeRestartStartedAt"]
            assert job["LibraryId"] == state["RestartRoot"]
            assert video_ids(a, job["LibraryId"]) == state["RestartVideos"]
            report.update(ActualDockerRestart=True, SameRootAndVideos=True)
        state["Stage"] = "ReadyVerified"
    save(state)
    (ROOT / "flow-results.json").write_text(json.dumps(report))
    history_path = ROOT / "flow-history.json"
    history = json.loads(history_path.read_text()) if history_path.exists() else []
    history.append(report); history_path.write_text(json.dumps(history))
    print(json.dumps(report))

if __name__ == "__main__":
    main()
