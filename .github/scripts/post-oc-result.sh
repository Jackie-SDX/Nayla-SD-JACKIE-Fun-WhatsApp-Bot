#!/usr/bin/env bash
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
comment_id=0
if [[ -n "$GITHUB_EVENT_PATH" && -f "$GITHUB_EVENT_PATH" ]]; then
  comment_id="$(jq -r '.comment.id // 0' "$GITHUB_EVENT_PATH" 2>/dev/null || printf '0')"
fi
[[ "$comment_id" =~ ^[0-9]+$ && "$comment_id" != "0" ]] || exit 0

result_marker="<!-- oc-result-for:$comment_id -->"
marker="$result_marker"
if [[ "$GITHUB_EVENT_NAME" == "pull_request_review_comment" ]]; then
  comment_api="/repos/$repo/pulls/comments/$comment_id"
else
  comment_api="/repos/$repo/issues/comments/$comment_id"
fi
current_body="$(gh api "$comment_api" --jq '.body // ""' 2>/dev/null || true)"
grep -Fq "$result_marker" <<<"$current_body" && exit 0

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
  elif [[ "$A1" != "success" ]]; then
    safe_log="$SAFE_LOG"
    if [[ -z "$safe_log" ]]; then safe_log="$RUNNER_TEMP/opencode-1-safe.log"; fi
    if [[ -z "$safe_log" ]]; then safe_log="/tmp/opencode-1-safe.log"; fi
    findings=""
    if [[ -s "$safe_log" ]]; then findings="$(sanitize_response "$safe_log")"; fi
    if [[ -n "$findings" ]]; then
      body="$(printf "%s\nAgent did not complete successfully. No success is claimed.\n\nSanitized findings:\n\n%s" "$marker" "$findings")"
    else
      body="$(printf "%s\nAgent did not complete successfully. No success is claimed." "$marker")"
    fi
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

updated_body="$(printf '%s' "$current_body" | sed -E 's/[[:space:]]+$//')"
updated_body="$updated_body"$'\n\n---\n## /oc response\n'"$body"$'\n'"$result_marker"
gh api -X PATCH -f body="$updated_body" "$comment_api" >/dev/null
