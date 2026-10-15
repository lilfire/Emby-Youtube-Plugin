"""Validate index availability, source attestations and the fresh bounded G run."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent


def load(relative):
    return json.loads((root / relative).read_text(encoding='utf-8-sig'))


checks = []


def check(label, passed):
    checks.append({'Check': label, 'Passed': bool(passed)})


manifest = load('verification/FollowUp/K/REGRESSION.json')
for case in manifest['Cases']:
    check(case['ID'] + ' selected evidence available', (root / case['Evidence']).is_file())

for item in load('verification/FollowUp/K/ARTIFACTS.json'):
    path = root / item['Artifact']
    check('indexed hash: ' + item['Artifact'], path.exists() and
          hashlib.sha256(path.read_bytes()).hexdigest().upper() == item['SHA256'])

# Actual current-source readback; DLL names/version strings alone are insufficient.
attestations = load('verification/FollowUp/E/SUMMARY.json')['Source']
attestations += load('verification/FollowUp/I/SOURCE-HASHES.json')
fresh = load('verification/FollowUp/K/bin/runtime-g/WINDOWS-EVIDENCE.json')
attestations += [{'File': key, 'SHA256': value} for key, value in fresh['Sources'].items()]
drift = []
for entry in attestations:
    path = root / entry['File']
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest().upper() != entry['SHA256'].upper():
        drift.append(entry['File'])
check('recorded E/I and fresh G production source hashes match', not drift)
check('fresh G completed with all 44 observations reproduced', fresh['Complete'] and
      len(fresh['Observations']) == 44 and all(r['Reproduced'] for r in fresh['Observations']))
check('fresh G fixture and child processes cleaned', all(fresh['Cleanup'].values()))
check('publication preflight has no unreviewed matches', not load('verification/FollowUp/K/PUBLICATION-AUDIT.json')['Findings'])
snapshot = load('verification/FollowUp/K/CLEANUP-READBACK.json')
check('no active local fixture process or listeners', snapshot['FixtureProcessCount'] == 0 and not snapshot['TestListeners'])
result = {'Checks': checks, 'SourceDrift': sorted(set(drift)),
          'FreshG': {'ProductionDLLSHA256': fresh['ProductionDLLSHA256'],
                     'Observations': len(fresh['Observations']),
                     'RequirementNotMet': sum(not r['RequirementMet'] for r in fresh['Observations']),
                     'Cleanup': fresh['Cleanup']},
          'Passed': all(r['Passed'] for r in checks),
          'Limit': 'Evidence integrity and bounded synthetic G rerun; no new native HTTP/client/Google or remote cleanup acceptance'}
(out / 'VERIFICATION.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'Checks': len(checks), 'Passed': result['Passed'], 'SourceDrift': result['SourceDrift'], 'FreshG': result['FreshG']}))
raise SystemExit(0 if result['Passed'] else 1)
