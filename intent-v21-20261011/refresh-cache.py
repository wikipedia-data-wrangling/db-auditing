"""Refresh only the direct cache, with a preserved predecessor and staged checks."""
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import duckdb

ROOT=Path(__file__).resolve().parent
path=Path('/home/simone/githubRepos/wikipediaData/20261001/wpp-analysis/data/interim/rfpp_request.parquet')
backup=path.with_name('rfpp_request.pre-intent-v21.parquet')
temporary=path.with_name('rfpp_request.intent-v21.tmp.parquet')
expected='6ca806a9b24de8bdea86c790206f4e2cc6582a3dfd56b6f39e2cefd792b03aa2'
def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
assert digest(path)==expected, 'Predecessor cache changed; reconcile'
assert not backup.exists() and not temporary.exists(), 'Preserve existing artifacts'
con=duckdb.connect()
con.execute('LOAD postgres')
con.execute("ATTACH 'service=wiki' AS pg (TYPE postgres, READ_ONLY)")
assert con.execute('SELECT status FROM pg.analysis.rfpp_intent_v21_run WHERE id=1').fetchone()[0]=='applied'
query="SELECT * EXCLUDE(matched_offset) FROM pg.analysis.rfpp_request WHERE page_namespace=0 AND outcome IN ('granted','denied')"
con.execute('COPY ('+query+') TO ? (FORMAT PARQUET)',[str(temporary)])
counts=con.execute("SELECT count(*),count(DISTINCT rfpp_id),count(*) FILTER(WHERE requested_intent::JSON->>'version'='rfpp-intent-v2.1.0') FROM read_parquet(?)",[str(temporary)]).fetchone()
assert counts==(178110,178110,178110), counts
mismatches=con.execute("""SELECT count(*) FROM read_parquet(?) p
FULL JOIN (SELECT s.* FROM pg.analysis.rfpp_intent_v21_stage s
JOIN pg.analysis.rfpp_request r USING(rfpp_id)
WHERE r.page_namespace=0 AND r.outcome IN ('granted','denied')) s USING(rfpp_id)
WHERE p.rfpp_id IS NULL OR s.rfpp_id IS NULL
OR p.requested_action IS DISTINCT FROM (s.intent::JSON->>'action')
OR p.requested_level IS DISTINCT FROM (s.intent::JSON->>'tier')
OR p.requested_intent::JSON IS DISTINCT FROM s.intent::JSON""",[str(temporary)]).fetchone()[0]
assert mismatches==0,mismatches
assert digest(path)==expected, 'Cache changed during refresh'
os.link(path,backup)
os.replace(temporary,path)
report=dict(recorded_at=datetime.now(timezone.utc).isoformat(),query=query,rows=counts[0],unique_ids=counts[1],
            version='rfpp-intent-v2.1.0',classification_mismatches=mismatches,backup=str(backup),
            old_sha256=digest(backup),new_sha256=digest(path),downstream_status='21 frozen products remain invalidated')
(ROOT/'cache-refresh.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
