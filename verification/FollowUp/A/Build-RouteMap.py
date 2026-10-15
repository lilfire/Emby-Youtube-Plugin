"""Generate a conservative route inventory; an untested route is never a pass."""
import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def array(value):
    return value if isinstance(value, list) else [value] if value is not None else []


audit = read(HERE / "bin/api-audit.json")
results = [read(HERE / "bin" / name) for name in ("private-results.json", "public-results.json")]
rows = []
for route in audit["Routes"]:
    dto = route["Request"]
    pattern = "^" + re.sub(r"\\\{.*?\\\}", r"[^/]+", re.escape(route["Path"].lstrip("/"))) + "$"
    evidence = []
    for run in results:
        for observation in run["Observations"]:
            path = observation.get("Route", "").split("?")[0]
            method = observation.get("Method", "Get").upper()
            verbs = [verb.strip() for verb in (route.get("Verbs") or "").split(",")]
            if re.match(pattern, path, re.I) and (not route.get("Verbs") or method in verbs):
                evidence.append(observation)
    # Playlist create/add and the administrative probes predate the Route field.
    labels = {
        "Emby.Api.CreatePlaylist": "playlist create",
        "Emby.Api.AddToPlaylist": "playlist add foreign",
        "Emby.Api.RefreshItem": "administrative Items/",
    }
    if dto in labels:
        evidence += [o for run in results for o in run["Observations"] if labels[dto] in o["Label"]
                     and (dto != "Emby.Api.RefreshItem" or "/Refresh?" in o["Label"])]
    methods = array(route["Methods"])
    references = [ref for method in methods for ref in array(method["References"]) + array(method["AsyncReferences"])]
    sources = [ref for ref in references if re.search(r"Library|Repository|DtoService|PlaylistManager|UserDataManager|GetUser", ref)]
    writers = [ref for ref in references if re.search(r"ToOptimized|ToCached|GetResult|WriteTo|Serialize", ref)]
    relevant = bool(re.search(r"UserLibrary|Library\.(Get|Delete)|Movies\.GetMovieRecommendations|Playlist|RefreshItem|UpdateItem|MarkPlayedItem|MarkUnplayedItem|UpdateUserData|Search", dto))
    if evidence:
        failures = [o for o in evidence if o.get("IsolationPass") is False]
        status = "åpent hull: observert avvik" if failures else "prøvd: avgrenset matrise"
        limitation = "HTTP/state assertions; inspect positive controls in REPORT.md"
    elif relevant:
        status = "åpent hull: manglende rutebevis"
        limitation = "Inventar/IL er ikke positiv eller negativ HTTP-kontroll"
    else:
        status = "ikke relevant for A"
        limitation = "Annet kapittel/serveradministrasjon; ingen skjermingsgodkjenning"
    rows.append({
        "Route": route["Path"], "Verbs": route.get("Verbs") or "ANY (attribute default)", "DTO": dto,
        "IdentityFields": "; ".join(array(route["Identity"])),
        "Methods": "; ".join(f'{m["Service"]}::{m["Signature"]}' for m in methods),
        "MethodHashes": "; ".join(m["BodyHash"] for m in methods),
        "NativeSourceReferences": " | ".join(sources),
        "ResultTypes": "; ".join(m["ReturnType"] for m in methods),
        "WriterFactoryReferences": " | ".join(writers) or "Ingen direkte IL-referanse; uverifisert",
        "Status": status, "EvidenceRows": len(evidence),
        "FailedAssertions": sum(o.get("IsolationPass") is False for o in evidence),
        "Limitation": limitation,
    })
with (HERE / "ROUTES.csv").open("w", newline="", encoding="utf-8-sig") as stream:
    writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)

summary = {"Routes": len(rows), "StatusCounts": {}, "Runs": []}
for row in rows:
    summary["StatusCounts"][row["Status"]] = summary["StatusCounts"].get(row["Status"], 0) + 1
for name, run in zip(("private", "public"), results):
    observations = run["Observations"]
    paging_checks = []
    for observation in observations:
        if " page/filter " in observation["Label"]:
            active = observation["Label"].startswith("Active ")
            actor = observation["Actor"]
            count = (2 if actor == "b" else 1) if name == "public" else (1 if actor == "b" or active else 0)
            query = observation["Label"].split(" page/filter ", 1)[1]
            if "ParentId=" in query:
                count = 1 if name == "public" and actor == "b" else 0
            size, total = count, count
            if "StartIndex=1" in query:
                size = min(1, max(count - 1, 0))
                total = count if size else 0
            elif "Limit=0" in query:
                size = 0
            elif "Limit=1" in query:
                size = min(1, count)
            names = array(observation.get("Names"))
            passed = observation["Status"] == 200 and observation.get("Total") == total and len(names) == size and not observation["ForeignContent"]
            observation["CountPagePass"] = passed
            paging_checks.append(passed)
        if observation.get("Mutation"):
            own_key = observation["Actor"] + observation["Target"]
            observation["OtherStateStable"] = all(
                observation["Before"].get(key) == observation["After"].get(key)
                for key in ("aa", "ab", "ba", "bb") if key != own_key)
    # Sanitized, portable evidence: omit raw bodies, absolute paths and identifiers.
    portable = [{key: o[key] for key in (
        "Label", "Status", "Actor", "Mutation", "Target", "Claim", "ExpectedAllowed", "Changed", "StateMatches", "OtherStateStable",
        "ForeignContent", "PrivateHeader", "EntityHeaders", "Total", "Names", "ServiceDelta", "QueryDelta",
        "Created", "Removed", "CreatedCount", "CountPagePass", "IsolationPass") if key in o} for o in observations]
    (HERE / f"{name.upper()}-EVIDENCE.json").write_text(json.dumps(portable, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary["Runs"].append({"Name": name, "Completed": run["Completed"], "Observations": len(observations),
                            "FailedAssertions": sum(o.get("IsolationPass") is False for o in observations),
                            "PagingChecks": len(paging_checks), "PagingFailures": paging_checks.count(False),
                            "AllowedPrivateOtherStateInvariant": all(o["OtherStateStable"] for o in observations if o.get("Mutation") and o.get("ExpectedAllowed")) if name == "private" else None,
                            "Cleanup": read(HERE / "bin" / f"{name}-cleanup.json")})
(HERE / "SUMMARY.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"Routes": summary["Routes"], "Statuses": summary["StatusCounts"]}, ensure_ascii=False))
