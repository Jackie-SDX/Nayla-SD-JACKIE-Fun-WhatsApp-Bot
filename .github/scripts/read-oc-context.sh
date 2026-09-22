#!/usr/bin/env bash
set -euo pipefail
file="${1:-${OC_ISSUE_CONTEXT_FILE:-}}"
start="${2:-1}"
count="${3:-200}"
[[ -f "$file" ]] || { echo "::error title=Context file missing::Cannot read $file" >&2; exit 2; }
[[ "$start" =~ ^[1-9][0-9]*$ ]] || start=1
[[ "$count" =~ ^[1-9][0-9]*$ ]] || count=200
end=$((start + count - 1))
sed -n "${start},${end}p" "$file"
