"""Apply the reviewed repair, update its source/tests, refresh the direct cache.

All inputs must be finalized and the SQL rehearsal must have passed first.
Database changes are independently reversible with rollback.sql. Source and
cache predecessors are preserved. No GitHub messages or model rebuilds occur.
"""
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parent
REPO=Path('/home/simone/githubRepos/wikipediaData')
parser=REPO/'20261001/wpp-analysis/sql/04a_rfpp_intent_parser.sql'
tests=REPO/'db-auditing/test_rfpp_intent_v2.py'
readme=REPO/'db-auditing/README.md'
archive=REPO/'db-auditing/intent-v21-20261011'
def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
def run(command,log):
    with (ROOT/log).open('w') as output:
        subprocess.run(command,check=True,stdout=output,stderr=subprocess.STDOUT)
def replace_file(source,destination):
    temporary=destination.with_name(destination.name+'.intent-v21.tmp')
    assert not temporary.exists()
    shutil.copyfile(source,temporary)
    os.replace(temporary,destination)

assert parser.read_bytes()==(ROOT/'parser-before.sql').read_bytes(), 'Parser source changed'
assert tests.read_bytes()==(ROOT/'tests-before.py').read_bytes(), 'Test source changed'
assert readme.read_bytes()==(ROOT/'README-before.md').read_bytes(), 'README changed'
assert not archive.exists(), 'Preserve existing archive'
assert 'ROLLBACK' in (ROOT/'rehearsal.log').read_text(), 'Rehearsal not complete'
manifest=json.loads((ROOT/'reviewed-inputs.json').read_text())
assert all(digest(ROOT/name)==sha for name,sha in manifest.items()), 'Reviewed inputs changed'

run(['psql','-X','service=wiki','-v','commit_repair=1','-f',str(ROOT/'apply.sql')],'apply.log')
replace_file(ROOT/'parser-source.sql',parser)
replace_file(ROOT/'test-source.py',tests)
run([str(REPO/'official-dump/.venv/bin/python'),str(tests)],'tests-applied.log')
run(['psql','-X','service=wiki','-f',str(ROOT/'verify.sql')],'verify.log')
run(['psql','-X','service=wiki','-f',str(ROOT/'rollback.sql')],'rollback-rehearsal.log')
run([str(REPO/'20261001/wpp-analysis/python/.venv/bin/python'),str(ROOT/'refresh-cache.py')],'cache-refresh.log')
run(['psql','-X','service=wiki','-c','COPY analysis.rfpp_intent_v21_changes TO STDOUT WITH CSV HEADER'],'changed-records.csv')
replace_file(ROOT/'README-after.md',readme)
report=ROOT/'repair-report.org'
report.write_text(report.read_text().replace('Status: prepared; deployment pending.',
    'Status: applied; active source/tests and direct cache updated; database verification and rollback rehearsal passed.'))
archive.mkdir()
for source in ROOT.iterdir():
    if source.is_file() and source.name not in ('stage-review-initial.jsonl','restage.log'):
        shutil.copyfile(source,archive/source.name)
print(json.dumps({'status':'applied','parser':str(parser),'audit':str(archive),
                  'cache_refresh':json.loads((ROOT/'cache-refresh.json').read_text())},indent=2))
