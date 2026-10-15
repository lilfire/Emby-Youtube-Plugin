"""Export portable evidence. Never treat an incomplete run or 400 as a pass."""
import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


summary = []
modes = ["Transport", "Hls", "Content", "Channel", "Key", "Accounts", "Lease", "BeforeWrite", "Public", "Abort"]
modes += [p.name.removesuffix("-results.json") for p in sorted((HERE / "bin").glob("Boundary-*-results.json"))]
for mode in modes:
    result_path = HERE / "bin" / f"{mode}-results.json"
    if not result_path.exists():
        summary.append({"Mode": mode, "Status": "not run; awaiting shared fixture turn"})
        continue
    result = read(result_path)
    cleanup = read(HERE / "bin" / f"{mode}-cleanup.json")
    clean = all(cleanup.get(k) for k in ("ServerStopped", "PortFree", "JournalGone", "ProfilesGone")) and all(
        cleanup["NativeCleanup"].get(k) for k in ("UsersGone", "LibrariesGone", "FixtureGone", "GuardGone", "MediaGone"))
    if not clean:
        raise RuntimeError(f"Cleanup incomplete for {mode}")
    observations = []
    for original in result["Observations"]:
        o = dict(original)
        # DResult's generic denial predicate was also used to record HLS owner
        # responses. Make that expectation explicit instead of counting an
        # authorized owner playlist as a failed isolation test.
        if re.match(r"D HLS a actual (master|variant)$", o["Label"]):
            o.pop("IsolationPass", None)
            o["OwnerPlaylistPass"] = o.get("Status") == 200 and o.get("Playlist") is True
        # Bare segment probes lack a positive owner control. Preserve the
        # observation, but do not convert a native 400/500 into a privacy claim.
        if o.get("Status") in (400, 500) and "D route" in o["Label"]:
            o["Support"] = "unverified: owner path unavailable; no isolation conclusion"
        if mode in ("Channel", "Key") and "change old A" in o["Label"]:
            o["ExpectationScope"] = "hypothesis: profile save revokes old binding; fixture uses direct Register, not publisher"
        if o["Label"] == "D actual native boundary HTTP result":
            if o["Mutation"] in ("Path", "Parent", "Journal"):
                o["BoundaryDenialPass"] = o["Status"] == 404 and o["EntityHeaderCount"] == 0 and o["GenericDenial"] and not o["MatchesA"] and not o["MatchesB"]
            elif o["Mutation"] == "Token":
                o["AdmittedTransferContinued"] = o["Status"] == 200 and o["MatchesA"]
            else:
                o["SourceContentProvenanceGap"] = o["Status"] == 200 and o["MatchesB"]
        o.pop("Route", None)
        observations.append(o)
    payload = {"Mode": mode, "Completed": result["Completed"], "Observations": observations, "Cleanup": cleanup}
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if re.search(r"(?i)X-Emby-Token|AccessToken|https?://|C:\\\\|Bearer\s", text):
        raise RuntimeError(f"Sensitive/local evidence field in {mode}")
    suffix = "EVIDENCE" if result["Completed"] else "INCOMPLETE"
    (HERE / f"{mode}-{suffix}.json").write_text(text, encoding="utf-8")
    if result["Completed"]:
        obsolete = HERE / f"{mode}-INCOMPLETE.json"
        if obsolete.exists():
            obsolete.unlink()
    summary.append({"Mode": mode, "Completed": result["Completed"], "Observations": len(observations),
                    "CleanupVerified": clean, "Commit": cleanup["Commit"], "PluginHash": cleanup["PluginHash"],
                    "FixtureHash": cleanup["FixtureHash"],
                    "Timeouts": sum(o.get("TransportTimeout") is True for o in observations)})

# Validate the concrete assertions that support the report. Expected privacy
# gaps and unsupported native paths are separate observations, never passes.
for mode in ("Transport", "Content", "Public", "Accounts", "BeforeWrite", "Lease", "Abort"):
    path = HERE / f"{mode}-EVIDENCE.json"
    if not path.exists():
        continue
    items = read(path)["Observations"]
    if mode in ("Accounts", "BeforeWrite", "Lease"):
        stale = [o for o in items if "old A" in o["Label"] and "Channel" not in o["Label"] and "Key" not in o["Label"]]
        if not stale or not all(o.get("IsolationPass") for o in stale):
            raise RuntimeError(f"Failed revoked static requests: {mode}")
    if mode in ("BeforeWrite", "Lease"):
        if not all(o.get("IsolationPass") for o in items if o["Label"] in (
            "D paused actual video response", "D deletion waiting on actual video owner lease", "D queued deletion saved after video finished")):
            raise RuntimeError(f"Video lease assertion failed: {mode}")
    if mode == "Abort":
        fields = {"D real large TCP transfer established": ("Status200", "Declared64MiB", "PrefixHashPass", "OwnerLeaseHeld"),
                  "D real client abort releases video lease": ("Released", "DeleteCompleted"),
                  "D queued deletion persisted after real client abort": ("Deleted",)}
        for label, keys in fields.items():
            found = [o for o in items if o["Label"] == label]
            if len(found) != 1 or not all(found[0].get(k) for k in keys):
                raise RuntimeError(f"Real abort assertion failed: {label}")
    if mode == "Public":
        expected = {"D public A to B full control": "OwnerHashPass", "D public regression private B to A negative control": "IsolationPass"}
        for label, key in expected.items():
            if not any(o["Label"] == label and o.get(key) is True for o in items):
                raise RuntimeError(f"Public regression missing: {label}")

(HERE / "SUMMARY.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
routes = []
with (HERE.parent / "A" / "ROUTES.csv").open(encoding="utf-8-sig", newline="") as stream:
    for row in csv.DictReader(stream):
        if re.search(r"MediaEncoding\.Api\.(Progressive\.|Hls\.|GetUniversalAudio)|GetDownload|GetPostedPlaybackInfo|GetPlaybackInfo", row["DTO"]):
            row["Status"] = "unverified: declared route only; see REPORT for tested concrete paths"
            row["EvidenceRows"] = "0"
            row["FailedAssertions"] = ""
            row["Limitation"] = "Inherited A IL inventory; no claim of complete transitive transport coverage"
            path, verbs = row["Route"], row["Verbs"]
            if verbs == "GET" and path in ("/Audio/{Id}/stream.{Container}", "/Audio/{Id}/stream", "/Audio/{Id}/{StreamFileName}"):
                row["Status"] = "tested: foreign complete private MP4 delivery"
                row["Limitation"] = "Static=true, mp4/no container/original; A/B SHA controls in Transport; other values unverified"
            elif verbs == "GET" and path in ("/Videos/{Id}/stream.{Container}", "/Videos/{Id}/stream", "/Videos/{Id}/{StreamFileName}"):
                row["Status"] = "tested: limited static/original owner/foreign matrix; content replacement hole"
                row["Limitation"] = "Static mp4/no container/original; dynamic mp4 denied for owner; no other codecs claim"
            elif verbs == "HEAD" and path == "/Videos/{Id}/stream.{Container}":
                row["Status"] = "tested: limited static mp4 owner/foreign HEAD"
            elif verbs == "GET" and path in ("/Videos/{Id}/master.m3u8", "/Audio/{Id}/master.m3u8", "/Videos/{Id}/main.m3u8", "/Audio/{Id}/main.m3u8"):
                row["Status"] = "tested: foreign native private playlist delivery; media bytes unverified"
            elif verbs == "GET" and ("/hls" in path or path.endswith("/live.m3u8") or path == "/Audio/{Id}/universal"):
                row["Status"] = "tested: owner unavailable; no bytes isolation conclusion"
            routes.append(row)
with (HERE / "ROUTES.csv").open("w", encoding="utf-8-sig", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=routes[0].keys())
    writer.writeheader()
    writer.writerows(routes)
print(json.dumps({"DeclaredRoutes": len(routes), "Runs": summary}, ensure_ascii=False))
