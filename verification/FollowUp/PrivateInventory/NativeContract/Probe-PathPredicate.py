"""Execute the lexical SQLite predicate observed in the local native IL.

This checks the predicate, not whether Emby can persist an unnormalized path.
No Emby database, media file, network connection or token is used.
"""
import json
import ntpath
import sqlite3
from pathlib import Path

root = r"C:\isolated\youtube-personal\media"
rows = [
    (1, root + r"\direct.mp4"),
    (2, r"C:\isolated\youtube-personal\ordinary\..\media\alias.mp4"),
    (3, r"C:\isolated\youtube-personal\public\movie.mp4"),
]
with sqlite3.connect(":memory:") as database:
    database.execute("CREATE TABLE Items (Id INTEGER, Path TEXT)")
    database.executemany("INSERT INTO Items VALUES (?, ?)", rows)
    matched = [row[0] for row in database.execute(
        "SELECT Id FROM Items WHERE Path COLLATE NOCASE LIKE ?", (root + "\\%",)
    )]
canonical = [identity for identity, path in rows
             if ntpath.normpath(path).lower().startswith(root.lower() + "\\")]
observations = [
    {"Name": "Native-shaped prefix matches the direct private path", "Pass": 1 in matched},
    {"Name": "Native-shaped prefix excludes the ordinary public path", "Pass": 3 not in matched},
    {"Name": "Canonical private alias is omitted by the lexical predicate", "Pass": 2 in canonical and 2 not in matched},
]
assert all(row["Pass"] for row in observations)
evidence = {
    "Scope": "SQLite in-memory predicate reproduction; no executed Emby query or native path-persistence proof.",
    "SQLiteVersion": sqlite3.sqlite_version,
    "MatchedIds": matched,
    "CanonicalPrivateIds": canonical,
    "Observations": observations,
}
output = Path(__file__).resolve().parent.parent / "SQLITE-PATH-EVIDENCE.json"
output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
print("SQLite path predicate: 3/3 observations; canonical alias missed.")
