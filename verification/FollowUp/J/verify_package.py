"""Verify a closed-alpha ZIP without extracting or installing it.

Checks internal consistency only; a manifest shipped in the same ZIP does not
authenticate its publisher. Supply a separately trusted archive SHA256.
"""
import argparse
import hashlib
import json
import pathlib
import re
import zipfile

FILES = {"Emby.YouTubePlugin.dll", "thumb.png", "LICENSE", "INSTALL.md", "KNOWN-LIMITS.md"}
LIMIT = 64 * 1024 * 1024


def verify(path, trusted_sha256=None):
    path = pathlib.Path(path)
    if path.stat().st_size > LIMIT:
        raise ValueError("Archive too large")
    digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
    if trusted_sha256 and digest != trusted_sha256.upper():
        raise ValueError("Archive checksum mismatch")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)) or set(names) != FILES | {"manifest.json"}:
            raise ValueError("Unexpected, duplicate or missing archive entries")
        if any(entry.file_size > LIMIT or entry.flag_bits & 1 or
               (entry.external_attr >> 16) & 0o170000 == 0o120000 for entry in entries):
            raise ValueError("Unsafe archive entry")
        if sum(entry.file_size for entry in entries) > LIMIT:
            raise ValueError("Expanded archive too large")
        manifest = json.loads(archive.read("manifest.json").decode("utf-8-sig"))
        if not re.fullmatch(r"2\.0\.10-alpha\.[1-9][0-9]*", manifest["Version"]):
            raise ValueError("Unsupported prerelease version")
        if manifest["AssemblyVersion"] != "2.0.10.0" or manifest["Status"] not in (
                "candidate-not-approved", "closed-alpha-ready"):
            raise ValueError("Unsupported package metadata")
        rows = manifest["Files"]
        if len(rows) != len(FILES) or {row["Name"] for row in rows} != FILES:
            raise ValueError("Unexpected manifest entries")
        for row in rows:
            content = archive.read(row["Name"])
            if row["Bytes"] != len(content) or hashlib.sha256(content).hexdigest().upper() != row["SHA256"].upper():
                raise ValueError("Packaged file checksum or size mismatch")
    return dict(Version=manifest["Version"], Status=manifest["Status"], ArchiveSHA256=digest,
                TrustedArchiveHashChecked=bool(trusted_sha256), FilesVerified=len(rows),
                Limitation="No server startup, native cleanup, signature or actual assembly version validation")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    parser.add_argument("--sha256")
    options = parser.parse_args()
    print(json.dumps(verify(options.archive, options.sha256), indent=2))
