#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
clang -fobjc-arc -framework Foundation "$here/main.m" -o /tmp/essential-errands
tmp=$(mktemp -d "${TMPDIR:-/tmp}/essential.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
printf '[{"id":"bread","name":"buy bread","minutes":5,"deadline":8},{"id":"mail","name":"mail parcel","minutes":3,"deadline":4},{"id":"tea","name":"find tea","minutes":2,"deadline":4}]' | /tmp/essential-errands - >"$tmp/out"
awk -F '\t' 'NR==2&&$1=="mail"&&$4==3&&$5==0{ok++} NR==3&&$1=="tea"&&$4==5&&$5==1{ok++} NR==4&&$1=="bread"&&$4==10&&$5==2{ok++} END{exit ok!=3}' "$tmp/out"
for bad in '[{"id":"x","name":"x","minutes":-1,"deadline":1}]' '[{"id":"x","name":"x","minutes":1,"deadline":1},{"id":"x","name":"y","minutes":1,"deadline":2}]' '{"id":"x"}' '[{"id":"x","name":"x","minutes":"1","deadline":1}]'; do if printf '%s' "$bad" | /tmp/essential-errands - >/dev/null 2>&1; then exit 1; fi; done
same=$(printf '[{"id":"a","name":"a","minutes":1,"deadline":5},{"id":"b","name":"b","minutes":2,"deadline":5}]' | /tmp/essential-errands -); test "$(printf '%s\n' "$same" | sed -n '2p' | cut -f1)" = a; test "$(printf '%s\n' "$same" | sed -n '3p' | cut -f1)" = b
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
echo 'Objective-C CLI tests: EDF, stable ties, malformed input passed'
