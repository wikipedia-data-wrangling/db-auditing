"""Refresh the direct request snapshot; preserve its historical version and hashes.

Run with ../20261001/wpp-analysis/python/.venv/bin/python.
Frozen dependent samples/models require their own rebuild (see repair log).
"""
from pathlib import Path
import hashlib
import json
import os
from datetime import datetime, timezone
import duckdb

root = Path(__file__).resolve().parent
path = root.parent/'20261001/wpp-analysis/data/interim/rfpp_request.parquet'
backup = path.with_name('rfpp_request.pre-intent-v2.parquet')
temporary = path.with_name('rfpp_request.intent-v2.tmp.parquet')
old_hash = 'c516207250f292445087d78d5926395a7385290725219cf3c943fc3d4aa41e35'
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
assert digest(path) == old_hash, 'Snapshot changed; reconcile before refresh'
assert not backup.exists() and not temporary.exists(), 'Preserve existing artifacts'
con = duckdb.connect()
con.execute('LOAD postgres')
con.execute("ATTACH 'service=wiki' AS pg (TYPE postgres, READ_ONLY)")
assert con.execute('SELECT status FROM pg.analysis.rfpp_intent_v2_run WHERE id=1').fetchone()[0] == 'applied'
query = "SELECT * EXCLUDE(matched_offset) FROM pg.analysis.rfpp_request WHERE page_namespace=0 AND outcome IN ('granted','denied')"
con.execute('COPY (' + query + ') TO ? (FORMAT PARQUET)', [str(temporary)])
count, unique, versioned = con.execute("SELECT count(*),count(DISTINCT rfpp_id),count(*) FILTER(WHERE requested_intent::JSON->>'version'='rfpp-intent-v2.0.0') FROM read_parquet(?)",[str(temporary)]).fetchone()
assert (count,unique,versioned)==(178110,178110,178110)
# Verify every exported classification against the reviewed stage, not just counts.
mismatches=con.execute("""SELECT count(*) FROM read_parquet(?) p
JOIN pg.analysis.rfpp_intent_v2_stage s USING(rfpp_id)
WHERE p.requested_action IS DISTINCT FROM (s.intent::JSON->>'action')
OR p.requested_level IS DISTINCT FROM (s.intent::JSON->>'tier')""",[str(temporary)]).fetchone()[0]
assert mismatches==0
# Hard-link the original file, then atomically replace the active pathname.
os.link(path,backup)
os.replace(temporary,path)
record={'recorded_at':datetime.now(timezone.utc).isoformat(),'query':query,
        'rows':count,'unique_ids':unique,'parser_version':'rfpp-intent-v2.0.0',
        'backup':str(backup),'old_sha256':digest(backup),'new_sha256':digest(path),
        'classification_mismatches':mismatches,
        'downstream_status':'Frozen samples, other caches and model outputs require review/rebuild; see database invalidation registry.'}
(root/'logs/issue-1-cache-refresh-20261010.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))
