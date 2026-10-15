"""Read-only evidence inventory and publication preflight; never prints matched values."""
import csv
import hashlib
import json
import re
import subprocess
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
TRACKED, IGNORED = set(), set()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def rel(path):
    return path.relative_to(ROOT).as_posix()


@lru_cache(maxsize=None)
def available(path):
    name = rel(path)
    if not path.exists():
        return 'missing'
    if name in IGNORED:
        return 'local-ignored'
    if name in TRACKED:
        return 'tracked'
    return 'untracked-publishable'


def collect_metadata(obj, values):
    if isinstance(obj, dict):
        for key, value in obj.items():
            if isinstance(value, str) and re.search(r'commit|hash|sha256|platform|transport|runtime|version', key, re.I):
                # Never copy arbitrary transport/provider text into a public index.
                if re.fullmatch(r'[0-9a-fA-F]{40}|[0-9a-fA-F]{64}', value):
                    values.add((key, value))
            collect_metadata(value, values)
    elif isinstance(obj, list):
        for value in obj:
            collect_metadata(value, values)


def main():
    global TRACKED, IGNORED
    reports = sorted((ROOT / 'verification/PersonalChannels').glob('*.md'))
    reports += sorted((ROOT / 'verification/FollowUp').glob('*/REPORT.md'))
    candidates = set(reports)
    candidates.update(p for p in (ROOT / 'verification/FollowUp').rglob('*') if p.is_file())
    for report in reports:
        for target in re.findall(r'\]\(([^)]+)\)', report.read_text(encoding='utf-8-sig')):
            if '://' not in target and not target.startswith('#'):
                path = (report.parent / target.split('#')[0]).resolve()
                if path.is_relative_to(ROOT):
                    candidates.add(path)
    TRACKED = set(git('ls-files').splitlines())
    ignore = subprocess.run(['git', 'check-ignore', '-z', '--stdin'], cwd=ROOT,
                            input='\0'.join(rel(p) for p in candidates) + '\0',
                            text=True, capture_output=True)
    if ignore.returncode not in (0, 1):
        raise RuntimeError('Git ignore inventory failed')
    IGNORED = set(ignore.stdout.strip('\0').split('\0'))
    rows, hashes, links = [], [], []
    environments = {
        'A': ('Native HTTP/query/writer + fixture publication', 'Windows Emby 4.10.1.0', 'Synthetic native sources; no Google'),
        'B': ('Native Sync/live/WebSocket + fixture publication', 'Windows Emby 4.10.1.0', 'Synthetic native sources/providers; no Google'),
        'C': ('Native asset HTTP/cache/writer', 'Windows Emby 4.10.1.0', 'Synthetic native source bytes; no Google'),
        'D': ('Native video HTTP/writer/TCP', 'Windows Emby 4.10.1.0', 'Synthetic native media and timing; no Google'),
        'E': ('Production components; native SDK adapter and process crashes', 'Windows/Linux .NET', 'Library adapter; no Emby server/downloader'),
        'F': ('Native HTTP/publication + separate store components', 'Windows Emby 4.10.1.0; Windows/Linux .NET store', 'Synthetic Google catalog; actual media download in native run'),
        'G': ('Production components and parent/child processes', 'Windows .NET', 'Synthetic HTTP/executables; no Google/native server'),
        'H': ('Actual web/AndroidTv + fixture publication and native HTTP', 'Windows Emby 4.10.1.0; AndroidTv 1.8.54g Android 12', 'Historical buffered YouTube sample; synthetic B; no Google catalog'),
        'I': ('Production browser DOM/controller + C# validation', 'Windows Edge 155.0.4283.45; .NET', 'Simulated Emby/API; no native server'),
        'J': ('Production components; offline IL; package validation', 'Windows/Linux x64 .NET', 'Synthetic executables/Harmony/shell; no native server or Google'),
        'K': ('Evidence/cleanup integrity and fresh G components', 'Local Windows/Docker/SQLite', 'Read-only inventory and synthetic G; no new native HTTP/Google'),
    }
    for report in reports:
        text = report.read_text(encoding='utf-8-sig')
        for target in re.findall(r'\]\(([^)]+)\)', text):
            if '://' in target or target.startswith('#'):
                continue
            path = (report.parent / target.split('#')[0]).resolve()
            if path.is_relative_to(ROOT):
                links.append({'Report': rel(report), 'Artifact': rel(path), 'Availability': available(path)})
        sha = sorted(set(re.findall(r'\b[0-9a-fA-F]{64}\b', text)))
        commits = sorted(set(re.findall(r'\b[0-9a-fA-F]{40}\b', text)))
        chapter = report.parent.name if report.parent.parent.name == 'FollowUp' else 'historical'
        test_type, platform, transport = environments.get(chapter, (
            'Historical record; inspect report before reuse', 'Not normalized; see report', 'Not normalized; see report'))
        rows.append({'Report': rel(report), 'Availability': available(report),
                     'ReportSHA256': hashlib.sha256(report.read_bytes()).hexdigest().upper(),
                     'RecordedCommits': ';'.join(commits) or 'not recorded in report',
                     'RecordedHashes': ';'.join(sha) or 'not recorded in report',
                     'Chapter': chapter, 'TestType': test_type, 'Platform': platform, 'Transport': transport})
    artifacts = sorted(p for p in (ROOT / 'verification/FollowUp').rglob('*')
                       if p.is_file() and p.suffix in {'.json', '.csv', '.md', '.txt', '.ps1', '.py', '.cs', '.csproj', '.mjs', '.js'}
                       and available(p) != 'local-ignored' and p.name not in {
                           'ARTIFACTS.json', 'REPORT-INDEX.csv', 'LINK-AVAILABILITY.json',
                           'PUBLICATION-AUDIT.json', 'VERIFICATION.json'})
    findings, reviewed = [], []
    patterns = {
        'google-key-shape': r'AIza[0-9A-Za-z_-]{35}',
        'bearer-value': r'Bearer\s+[0-9A-Za-z_.=-]{20,}',
        'credential-assignment': r'(?i)["\']?(?:access_token|refresh_token|X-Emby-Token|api_key|apikey|password)["\']?\s*[:=]\s*["\'][^"\'\s]{12,}["\']',
        'user-home-path': r'(?i)[A-Z]:[\\/]+Users[\\/]+(?!Public\b)[^\s"<>]+|' + '/' + r'home/[^\s"<>]+',
        'webhook-value': r'https?://[^\s"<>]+/api/webhook/[^\s"<>]+',
        'machine-workspace-path': r'(?i)[A-Z]:[\\/]+git[\\/][^\s"<>]+',
        'private-network-address': r'\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b',
    }
    for path in artifacts:
        source = path.read_text(encoding='utf-8-sig')
        values = set()
        if path.suffix == '.json':
            collect_metadata(json.loads(source), values)
        hashes.append({'Artifact': rel(path), 'Availability': available(path),
                       'SHA256': hashlib.sha256(path.read_bytes()).hexdigest().upper(),
                       'RecordedMetadata': sorted(values)})
        for number, line in enumerate(source.splitlines(), 1):
            for label, pattern in patterns.items():
                match = re.search(pattern, line)
                if match:
                    record = {'File': rel(path), 'Line': number, 'Category': label}
                    # Explicit synthetic fixture keys and string-concatenated runtime
                    # token lookup are not embedded credentials. Keep an audit trail.
                    if label == 'credential-assignment' and (
                            'synthetic-d-key-not-a-google-secret' in match[0] or
                            'synthetic-alpha-personal-key' in match[0] or
                            (match[0].split('=', 1)[-1].lstrip().startswith("'+") and '$subjects[' in match[0])):
                        record['Review'] = 'Synthetic fixture key or runtime expression; no literal secret'
                        reviewed.append(record)
                    else:
                        findings.append(record)
    with (OUT / 'REPORT-INDEX.csv').open('w', encoding='utf-8', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    for name, value in [('ARTIFACTS.json', hashes), ('LINK-AVAILABILITY.json', links),
                        ('PUBLICATION-AUDIT.json', {'Commit': git('rev-parse', 'HEAD'),
                          'Scope': 'Non-ignored FollowUp text artifacts and source; matched values never emitted',
                          'FilesChecked': len(artifacts), 'Findings': findings, 'ReviewedMatches': reviewed,
                          'Limit': 'Pattern preflight, not a guarantee; scripts require review before publishing'})]:
        (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'Reports': len(rows), 'Artifacts': len(artifacts), 'Findings': findings}, ensure_ascii=False))


if __name__ == '__main__':
    main()
