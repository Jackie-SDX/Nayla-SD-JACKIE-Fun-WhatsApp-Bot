#!/usr/bin/env bash
set -euo pipefail
target="$TARGET_NUMBER"
runner_temp="$(printenv RUNNER_TEMP 2>/dev/null || printf /tmp)"
out="$runner_temp/oc-issue-context.md"
max_bytes="$(printenv OC_CONTEXT_MAX_BYTES 2>/dev/null || printf 2000000)"
mkdir -p "$runner_temp"
tmp="$(mktemp)"
issue_json="$(mktemp)"
comments_json="$(mktemp)"
reviews_json="$(mktemp)"
trap 'rm -f "$tmp" "$issue_json" "$comments_json" "$reviews_json"' EXIT
: > "$out"

if ! [[ "$target" =~ ^[0-9]+$ ]] || [ "$target" = "0" ]; then
  echo "OC_ISSUE_CONTEXT_FILE=$out" >> "$GITHUB_OUTPUT"
  echo "OC_ISSUE_CONTEXT_FILE=$out" >> "$GITHUB_ENV"
  exit 0
fi

gh api "/repos/$GITHUB_REPOSITORY/issues/$target" > "$issue_json"
gh api --paginate --slurp "/repos/$GITHUB_REPOSITORY/issues/$target/comments?per_page=100" > "$comments_json" || printf '[]' > "$comments_json"
gh api --paginate --slurp "/repos/$GITHUB_REPOSITORY/pulls/$target/comments?per_page=100" > "$reviews_json" 2>/dev/null || printf '[]' > "$reviews_json"

{
  echo "# /oc task context"
  echo "Read the complete issue context in chronological order; retrieve source comments in batches when the local bound is reached."
  jq -r '"## Issue\n\n- Number: #\(.number)\n- Title: \(.title // "")\n- Author: @\(.user.login // "unknown")\n- State: \(.state // "unknown")\n- Created: \(.created_at // "")\n\n### Issue body\n\n\(.body // "")\n"' "$issue_json"
  echo "## Issue comments (chronological)"
  jq -r 'add // [] | sort_by(.created_at)[] | "### Comment #\(.id) — @\(.user.login // "unknown") — \(.created_at // "")\n\n\(.body // "")\n\n---\n"' "$comments_json"
  if jq -e 'add // [] | length > 0' "$reviews_json" >/dev/null 2>&1; then
    echo "## Pull-request review comments (chronological)"
    jq -r 'add // [] | sort_by(.created_at)[] | "### Review comment #\(.id) — @\(.user.login // "unknown") — \(.created_at // "")\n\n\(.body // "")\n\n---\n"' "$reviews_json"
  fi
} > "$out"

size="$(wc -c < "$out")"
if [ "$size" -gt "$max_bytes" ]; then
  half=$((max_bytes / 2))
  {
    head -c "$half" "$out"
    echo
    echo "[CONTEXT WINDOW BOUNDARY: middle omitted from local snapshot due to safety bound. Re-read source comments in batches before consequential decisions.]"
    echo
    tail -c "$half" "$out"
  } > "$tmp"
  mv "$tmp" "$out"
fi

echo "OC_ISSUE_CONTEXT_FILE=$out" >> "$GITHUB_OUTPUT"
echo "OC_ISSUE_CONTEXT_FILE=$out" >> "$GITHUB_ENV"
echo "Captured complete task context: $out ($(wc -c < "$out") bytes)"
