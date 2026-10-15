"""Exercise the actual candidate and deliberately malformed ZIP variants."""
import hashlib
import json
import pathlib
import sys
import tempfile
import zipfile
from verify_package import verify

source = pathlib.Path(sys.argv[1])
rows = []
with zipfile.ZipFile(source) as archive:
    originals = {entry.filename: archive.read(entry) for entry in archive.infolist()}
baseline = verify(source, hashlib.sha256(source.read_bytes()).hexdigest())
rows.append(dict(Label="Candidate with trusted SHA256 accepted", Observed=True))
with tempfile.TemporaryDirectory(prefix="youtube-j-package-") as work:
    for scenario in ("tamper", "traversal", "duplicate", "missing", "stable-version", "wrong-size", "wrong-archive-hash"):
        files = dict(originals)
        manifest = json.loads(files["manifest.json"].decode("utf-8-sig"))
        if scenario == "tamper": files["Emby.YouTubePlugin.dll"] += b"tamper"
        if scenario == "traversal": files["../escape.dll"] = b"escape"
        if scenario == "missing": del files["LICENSE"]
        if scenario == "stable-version": manifest["Version"] = "2.0.10"
        if scenario == "wrong-size": manifest["Files"][0]["Bytes"] += 1
        files["manifest.json"] = json.dumps(manifest).encode()
        target = pathlib.Path(work) / (scenario + ".zip")
        with zipfile.ZipFile(target, "w") as archive:
            for name, data in files.items(): archive.writestr(name, data)
            if scenario == "duplicate":
                import warnings
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    archive.writestr("LICENSE", files["LICENSE"])
        try:
            verify(target, "0" * 64 if scenario == "wrong-archive-hash" else None)
        except ValueError:
            rows.append(dict(Label=scenario + " rejected", Observed=True))
        else:
            raise AssertionError("Unexpected acceptance: " + scenario)
result = dict(Completed=True, Package=baseline, Observations=rows,
              Cleanup=dict(TemporaryVariantsGone=not pathlib.Path(work).exists()))
pathlib.Path(__file__).with_name("PACKAGE-EVIDENCE.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print("Package verification: 8 observations completed")
