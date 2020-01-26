#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
clang -fobjc-arc -framework Foundation "$here/main.m" -o /tmp/essential-errands
tmp=$(mktemp -d "${TMPDIR:-/tmp}/essential.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
printf '[{"id":"bread","name":"buy bread","minutes":5,"deadline":8},{"id":"mail","name":"mail parcel","minutes":3,"deadline":4},{"id":"tea","name":"find tea","minutes":2,"deadline":4}]' | /tmp/essential-errands - >"$tmp/out"
awk -F '\t' 'NR==2&&$1=="mail"&&$4==3&&$5==0{ok++} NR==3&&$1=="tea"&&$4==5&&$5==1{ok++} NR==4&&$1=="bread"&&$4==10&&$5==2{ok++} END{exit ok!=3}' "$tmp/out"
for bad in '[{"id":"x","name":"x","minutes":-1,"deadline":1}]' '[{"id":"x","name":"x","minutes":1,"deadline":1},{"id":"x","name":"y","minutes":1,"deadline":2}]' '{"id":"x"}' '[{"id":"x","name":"x","minutes":"1","deadline":1}]'; do if printf '%s' "$bad" | /tmp/essential-errands - >/dev/null 2>&1; then exit 1; fi; done
same=$(printf '[{"id":"a","name":"a","minutes":1,"deadline":5},{"id":"b","name":"b","minutes":2,"deadline":5}]' | /tmp/essential-errands -); test "$(printf '%s\n' "$same" | sed -n '2p' | cut -f1)" = a; test "$(printf '%s\n' "$same" | sed -n '3p' | cut -f1)" = b
from=$(printf '[{"id":"early","name":"early","minutes":1,"deadline":1},{"id":"late","name":"late","minutes":1,"deadline":99}]' | /tmp/essential-errands --from late -); test "$(printf '%s\n' "$from" | sed -n '2p' | cut -f1)" = late; test "$(printf '%s\n' "$from" | sed -n '3p' | cut -f1)" = early
if printf '[{"id":"a","name":"a","minutes":1,"deadline":1}]' | /tmp/essential-errands --from missing - >/dev/null 2>&1; then exit 1; fi
released=$(printf '[{"id":"late","name":"late","minutes":1,"deadline":2,"release":5},{"id":"now","name":"now","minutes":1,"deadline":99}]' | /tmp/essential-errands -); test "$(printf '%s\n' "$released" | sed -n '2p' | cut -f1)" = now; test "$(printf '%s\n' "$released" | sed -n '3p' | cut -f1)" = IDLE; test "$(printf '%s\n' "$released" | sed -n '4p' | cut -f1)" = late
from_release=$(printf '[{"id":"early","name":"early","minutes":1,"deadline":1},{"id":"future","name":"future","minutes":1,"deadline":99,"release":7}]' | /tmp/essential-errands --from future -); test "$(printf '%s\n' "$from_release" | sed -n '2p' | cut -f1)" = IDLE; test "$(printf '%s\n' "$from_release" | sed -n '3p' | cut -f1)" = future; test "$(printf '%s\n' "$from_release" | sed -n '4p' | cut -f1)" = early
interplay=$(printf '[{"id":"a","name":"a","minutes":1,"deadline":9,"release":3},{"id":"b","name":"b","minutes":1,"deadline":9}]' | /tmp/essential-errands --from a --break-after 1 --break-for 2 -); test "$(printf '%s\n' "$interplay" | sed -n '2p' | cut -f1)" = IDLE; test "$(printf '%s\n' "$interplay" | sed -n '3p' | cut -f1)" = a; test "$(printf '%s\n' "$interplay" | sed -n '4p' | cut -f1)" = BREAK; test "$(printf '%s\n' "$interplay" | sed -n '5p' | cut -f1)" = b
for bad_release in '[{"id":"x","name":"x","minutes":1,"deadline":1,"release":-1}]' '[{"id":"x","name":"x","minutes":1,"deadline":1,"release":1000001}]' '[{"id":"x","name":"x","minutes":1,"deadline":1,"release":"2"}]'; do if printf '%s' "$bad_release" | /tmp/essential-errands - >/dev/null 2>&1; then exit 1; fi; done
printf '[{"id":"a","name":"a","minutes":2,"deadline":9},{"id":"b","name":"b","minutes":0,"deadline":9},{"id":"c","name":"c","minutes":1,"deadline":9}]' >"$tmp/file.json"
/tmp/essential-errands --start 5 --break-after 2 --break-for 4 "$tmp/file.json" >"$tmp/options"
test "$(sed -n '2p' "$tmp/options" | cut -f1-5)" = 'a	a	5	7	0'
test "$(sed -n '3p' "$tmp/options" | cut -f1-5)" = 'BREAK	break	7	11	0'
test "$(sed -n '4p' "$tmp/options" | cut -f1-5)" = 'b	b	11	11	2'
test "$(sed -n '5p' "$tmp/options" | cut -f1-5)" = 'c	c	11	12	3'
if printf '[]' | /tmp/essential-errands --break-after 0 --break-for 1 - >/dev/null 2>&1; then exit 1; fi
if printf '[]' | /tmp/essential-errands --break-after 1 - >/dev/null 2>&1; then exit 1; fi
if printf '[]' | /tmp/essential-errands - - >/dev/null 2>&1; then exit 1; fi
if printf '[]' | /tmp/essential-errands --start huge - >/dev/null 2>&1; then exit 1; fi
json=$(printf '[{"id":"é","name":"café-run","minutes":2,"deadline":9}]' | /tmp/essential-errands --json -)
JSON_RESULT="$json" python3 - <<'PY'
import json, os
r=json.loads(os.environ['JSON_RESULT'])
assert r['schema_version']==1 and len(r['events'])==1
assert r['events'][0]['id']=='é' and r['events'][0]['name']=='café-run'
assert r['total_service']==2 and r['finish']==2 and r['max_lateness']==0
PY
json=$(printf '[{"id":"late","name":"late","minutes":1,"deadline":9,"release":4},{"id":"now","name":"now","minutes":1,"deadline":99}]' | /tmp/essential-errands --json -); JSON_RESULT="$json" python3 - <<'PY'
import json, os
r=json.loads(os.environ['JSON_RESULT'])
assert [e['kind'] for e in r['events']]==['errand','idle','errand']
assert r['events'][1]['start']==1 and r['events'][1]['finish']==4
assert r['events'][2]['release']==4
assert r['finish']-r['start']==r['total_service']+r['total_break_time']+r['total_idle_time']
PY
json=$(printf '[{"id":"early","name":"early","minutes":1,"deadline":1},{"id":"future","name":"future","minutes":1,"deadline":99,"release":7}]' | /tmp/essential-errands --from future --json -); JSON_RESULT="$json" python3 - <<'PY'
import json, os
r=json.loads(os.environ['JSON_RESULT'])
assert [e['kind'] for e in r['events']]==['idle','errand','errand']
assert r['events'][0]['start']==0 and r['events'][0]['finish']==7
assert r['finish']-r['start']==r['total_service']+r['total_break_time']+r['total_idle_time']
PY
json=$(printf '[]' | /tmp/essential-errands --json -); JSON_RESULT="$json" python3 -c 'import json,os; r=json.loads(os.environ["JSON_RESULT"]); assert r["events"]==[] and r["finish"]==0'
if printf '[]' | /tmp/essential-errands --json --break-after 1 - >/dev/null 2>&1; then exit 1; fi
echo 'Objective-C CLI tests: EDF, stable ties, malformed input passed'
