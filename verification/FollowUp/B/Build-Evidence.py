"""Export only allowlisted, portable evidence. Raw responses and secrets excluded."""
import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent


def read(name):
    return json.loads((HERE / 'bin' / name).read_text(encoding='utf-8-sig'))


def write(name, value):
    (HERE / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


summary = {'Scope': 'B investigation; completed runs do not prove full isolation', 'Runs': []}
for kind in ('private', 'public'):
    data = read(kind + '-results.json')
    cleanup = read(kind + '-cleanup.json')
    assert data['Completed'], f'{kind} did not complete'
    assert all(cleanup[x] for x in ('ServerStopped', 'JournalGone', 'FixtureGone', 'ProfilesGone', 'RecordedOutputsGone'))
    assert all(cleanup['NativeCleanup'][x] for x in ('UsersGone', 'LibrariesGone', 'MediaGone', 'FixtureGone', 'GuardGone'))
    observations = data['Observations']
    write(kind.upper() + '-EVIDENCE.json', {
        'Completed': data['Completed'], 'PublicSourceA': kind == 'public',
        'Observations': observations, 'Cleanup': cleanup,
    })
    summary['Runs'].append({
        'Kind': kind, 'Observations': len(observations),
        'FailedAssertions': sum(x.get('IsolationPass') is False for x in observations),
        'UnverifiedDlnaProbes': sum(x.get('Kind') == 'BDlna' and not x.get('BrowseResponse') for x in observations),
        'ConvertedOutputs': [x for x in observations if x.get('Kind') == 'BConverted'],
    })

collisions = []
for kind in ('fresh', 'reused'):
    data = read('collision-' + kind + '.json')
    cleanup = read('collision-' + kind + '-cleanup.json')
    assert data['Completed'] and data['RestartVerified'] and cleanup['ServerStopped']
    assert all(cleanup['NativeCleanup'][x] for x in ('UsersGone', 'LibrariesGone', 'MediaGone', 'FixtureGone', 'GuardGone'))
    fields = ('Label', 'Status', 'Expected', 'MatchesExpectation', 'CorrectOwnMarker',
              'ContainsOldA', 'ContainsRecreatedB', 'KnownPrivate', 'Quarantined',
              'ParentKnownPrivate', 'ParentQuarantined', 'NativeVisible', 'NativeStandalone',
              'CorrectOwnSource', 'PayloadBytes', 'MatchesRecreatedSource')
    rows = [{k: x[k] for k in fields if k in x} for x in data['Observations']]
    for row in rows:
        row['Label'] = re.sub(r'\b(?:[0-9a-fA-F]{32}|\d{4,})\b', '{reference}', row['Label'])
    identity = {k: v for k, v in data['Identity'].items() if k.startswith('Same')}
    collisions.append({'Kind': kind, 'Completed': True, 'RestartVerified': True, 'Identity': identity,
                       'Observations': rows, 'Cleanup': cleanup,
                       'Scope': 'Experimental PrivacyGuard, native library recreation; not production integration'})
write('COLLISION-EVIDENCE.json', collisions)
summary['CollisionRuns'] = [{'Kind': x['Kind'], 'Identity': x['Identity'],
                            'Observations': len(x['Observations']),
                            'ExpectationMismatches': sum(r.get('MatchesExpectation') is False for r in x['Observations'])}
                           for x in collisions]

audit = read('api-audit.json')
route_rows = []
for route in audit['Routes']:
    path = route['Path']
    if not re.search(r'^/(Sync|LiveStreams|Dlna|Sessions)(/|$)', path, re.I):
        continue
    methods = route['Methods'] if isinstance(route['Methods'], list) else [route['Methods']]
    methods = [m for m in methods if m]
    family = path.split('/')[1]
    tested = path in ('/Sync/Jobs', '/Sync/Jobs/{Id}', '/Sync/JobItems', '/Sync/JobItems/{Id}/File',
                      '/Sync/Items/Ready', '/LiveStreams/Open', '/LiveStreams/MediaInfo', '/LiveStreams/Close')
    status = 'prøvd: observerte avvik; se paret eier/fremmed i rapport' if tested else 'åpent: manglende rutebevis'
    if family.lower() == 'dlna':
        status = 'uverifisert: SOAP mangler positiv eierkontroll'
    route_rows.append({'Route': path, 'Verbs': route.get('Verbs') or 'ANY (declared)',
                       'DTO': route['Request'], 'IdentityFields': '; '.join(route['Identity']),
                       'Methods': '; '.join(m['Service'] + '::' + m['Signature'] for m in methods),
                       'MethodHashes': '; '.join(m['BodyHash'] for m in methods),
                       'Status': status,
                       'Limitation': 'Declared route and direct IL; not transitive/runtime proof'})
with (HERE / 'ROUTES.csv').open('w', newline='', encoding='utf-8-sig') as output:
    writer = csv.DictWriter(output, fieldnames=route_rows[0].keys())
    writer.writeheader()
    writer.writerows(route_rows)
summary['DeclaredRelevantRoutes'] = len(route_rows)
write('SUMMARY.json', summary)
print(json.dumps(summary, ensure_ascii=False, indent=2))
