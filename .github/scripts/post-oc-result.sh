#!/usr/bin/env bash
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
target=0
if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
  target="$(jq -r '.issue.number // .pull_request.number // 0' "$GITHUB_EVENT_PATH" 2>/dev/null || printf '0')"
fi
[[ "$target" =~ ^[0-9]+$ && "$target" != "0" ]] || exit 0

run_id="${GITHUB_RUN_ID:-0}"
marker="<!-- oc-result-run-id:$run_id -->"
if gh api --paginate --slurp "/repos/$repo/issues/$target/comments?per_page=100" 2>/dev/null | jq -e --arg marker "$marker" 'add // [] | any(.[]; (.body // "") | contains($marker))' >/dev/null 2>&1; then
  exit 0
fi

task_mode="${TASK_MODE:-report}"
body=""

sanitize_response() {
  local file="$1"
  sed -E \
    -e '/^\[OPENCODE\]/d' \
    -e '/\[object Object\]/d' \
    -e 's/OC-STATUS:[[:space:]]*//g' \
    -e 's/OC-PLAN:[[:space:]]*//g' \
    -e 's/OC-DONE:[[:space:]]*//g' \
    -e 's/(gh[ps]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})/[REDACTED_GITHUB_TOKEN]/g' \
    -e 's/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g' \
    "$file" | tr -d '\r' | sed 's/[[:space:]]*$//' | cut -c1-12000
}

if [[ "${MERGE_REQUESTED:-false}" == "true" ]]; then
  if [[ "${MERGE_EXIT:-1}" == "0" ]]; then
    body="$(printf "%s\n## /oc\nMerge command completed successfully." "$marker")"
  else
    body="$(printf "%s\n## /oc\nMerge command did not complete successfully. No merge success is claimed." "$marker")"
  fi
else
  response_file="${RUNNER_TEMP:-/tmp}/opencode-final-response-1.md"
  answer=""
  if [[ "${A1:-}" == "success" && -s "$response_file" ]]; then
    answer="$(sanitize_response "$response_file")"
  fi
  if [[ -n "$answer" ]]; then
    body="$(printf "%s\n## /oc\n\n%s" "$marker" "$answer")"
  elif [[ "$task_mode" == "report" && "${A1:-}" == "success" ]]; then
    body="$(printf "%s\n## /oc\nOpenCode completed, but no clean final response was captured." "$marker")"
  elif [[ "${A1:-}" != "success" ]]; then
    body="$(printf "%s\n## /oc\nAgent did not complete successfully. No success is claimed." "$marker")"
  else
    if [[ "${OC_TARGET_MODE:-local}" == "remote" && -n "${OC_TARGET_REPO:-}" && -n "${OC_TARGET_BRANCH:-}" ]]; then
      remote_sha="$(gh api "/repos/$OC_TARGET_REPO/git/ref/heads/$OC_TARGET_BRANCH" --jq '.object.sha' 2>/dev/null || true)"
      if [[ "$remote_sha" =~ ^[0-9a-f]{40}$ ]]; then
        summary="Completed target work on $OC_TARGET_REPO@$OC_TARGET_BRANCH at $remote_sha."
      else
        summary="OpenCode completed, but the target branch could not be observed."
      fi
      [[ "${P1:-}" == "published" && -n "${PR1:-}" ]] && summary="$summary PR: $PR1"
    else
      if [[ -n "${PR1:-}" ]]; then
        summary="Completed and published: $PR1"
      elif [[ "${P1:-}" == "checkpointed" ]]; then
        summary="Durable work checkpointed; resume with /oc continue."
      else
        summary="OpenCode completed successfully."
      fi
    fi
    if [[ "${V1:-}" == "true" && -n "${SHA1:-}" ]]; then
      summary="$summary Verified exact SHA $SHA1 with observable CI checks."
    fi
    body="$(printf "%s\n## /oc\n%s" "$marker" "$summary")"
  fi
fi

gh issue comment "$target" --body "$body" >/dev/null
