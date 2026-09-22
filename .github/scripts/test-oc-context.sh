#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
file="$tmp/context"
for i in $(seq 1 1000); do printf 'line-%04d\n' "$i" >> "$file"; done
out="$(bash .github/scripts/read-oc-context.sh "$file" 501 50)"
[[ "$out" == *line-0501* ]]
[[ "$out" == *line-0550* ]]
[[ "$out" != *line-0500* ]]
echo 'bounded context reader contract: OK'
