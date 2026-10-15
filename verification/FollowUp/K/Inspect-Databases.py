"""Read-only fixture DB inspection. Outputs schema or aggregate counts, never identities."""
import json
import sqlite3
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[3] / 'verification/WatchState/bin/emby-isolated/data/data'
result = {}
for name in ('users.db', 'library.db'):
    path = root / name
    if not path.exists():
        result[name] = {'Available': False}
        continue
    with sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True) as db:
        db.execute('PRAGMA query_only=ON')
        tables = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")]
        if '--schema' in sys.argv:
            result[name] = {table: [r[1] for r in db.execute('PRAGMA table_info("' + table.replace('"', '""') + '")')]
                            for table in tables}
        elif name == 'users.db':
            records = [r[0] for r in db.execute('SELECT data FROM LocalUsersv2')]
            markers = ('native-privacy-fixture-', 'native-client-', 'followup-', 'PrivateNative', 'alpha-user-', 'personal-a', 'personal-b')
            result[name] = {'UsersTotal': len(records), 'SyntheticNameMatches': sum(
                any(m.lower() in (x.decode('utf-8', errors='replace') if isinstance(x, bytes) else str(x)).lower()
                    for m in markers) for x in records), 'Limit': 'Name-marker search plus historical native ID readback; not an identity inventory'}
        else:
            result[name] = {'SyntheticMediaMatches': db.execute(
                "SELECT count(*) FROM MediaItems WHERE Name LIKE 'PrivateNative%' OR Name LIKE 'JournalPending_%'").fetchone()[0],
                'SyncJobsRemaining': db.execute('SELECT count(*) FROM SyncJobs2').fetchone()[0],
                'SyncItemsRemaining': db.execute('SELECT count(*) FROM SyncJobItems2').fetchone()[0]}
if '--schema' not in sys.argv:
    (Path(__file__).resolve().parent / 'DATABASE-READBACK.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
