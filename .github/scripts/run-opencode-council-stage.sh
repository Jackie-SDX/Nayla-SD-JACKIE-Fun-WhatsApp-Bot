#!/usr/bin/env bash
set -u

stage="${1:?stage}"
model="${2:?model}"
prompt_file="${3:?prompt_file}"
out_file="${4:?out_file}"

raw_log="$(mktemp "${RUNNER_TEMP:-/tmp}/council-${stage}-raw.XXXXXX")"
cleanup() { rm -f "$raw_log"; }
trap cleanup EXIT

set +e
opencode run --standalone --auto --agent "$stage" --model "$model" "$(cat "$prompt_file")" >"$raw_log" 2>&1
exit_code=$?
set -e

python3 - "$raw_log" "$out_file" <<'PY'
import os, re, sys
from pathlib import Path
src, dst = map(Path, sys.argv[1:])
raw = src.read_text(errors='replace')
for key in ('OPENCODE_API_KEY','COMPOSIO_API_KEY','GITHUB_TOKEN','COPILOT_GITHUB_TOKEN','COMPOSIO_MCP_URL','COMPOSIO_MCP_HEADERS_FILE'):
    value = os.environ.get(key)
    if value:
        raw = raw.replace(value, '[REDACTED]')
raw = re.sub(r'(gh[ps]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})', '[REDACTED_GITHUB_TOKEN]', raw)
raw = re.sub(r'(AIza[A-Za-z0-9_-]{20,})', '[REDACTED_GOOGLE_KEY]', raw)
raw = re.sub(r'(Bearer\s+)[^\s]+', r'\1[REDACTED]', raw)
dst.write_text(raw)
PY

if [[ "$exit_code" -ne 0 ]]; then
  echo "::error title=Council stage execution failed::$stage exited with code $exit_code."
  exit "$exit_code"
fi

if [[ ! -s "$out_file" ]]; then
  echo "::error title=Council stage contract failed::$stage exited successfully but produced no output."
  exit 1
fi

if ! grep -q "COUNCIL_STAGE_COMPLETE=$stage" "$out_file"; then
  printf '\nCOUNCIL_STAGE_COMPLETE=%s\n' "$stage" >> "$out_file"
fi

if [[ "$stage" == "adjudicator" ]]; then
  grep -Eq 'COUNCIL_DECISION=(READY|BLOCKED)' "$out_file" || {
    echo "::error title=Council adjudication failed::No explicit READY/BLOCKED decision."
    exit 1
  }
fi

if [[ "$stage" == "verifier" ]]; then
  grep -Eq 'COUNCIL_VERDICT=(PASS|FAIL)' "$out_file" || {
    echo "::error title=Council verifier failed::No explicit PASS/FAIL verdict."
    exit 1
  }
fi

echo "Council stage $stage completed with process exit code: $exit_code"
exit 0
