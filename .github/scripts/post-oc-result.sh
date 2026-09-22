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
  cat "$file" |
    tr -d '\r' |
    sed -E '/^\[OPENCODE\]/d; /^\[COPILOT\]/d; /\[object Object\]/d; s/(gh[ps]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})/[REDACTED_GITHUB_TOKEN]/g; s/(sk-or-v1-[A-Za-z0-9_-]{20,})/[REDACTED_EXTERNAL_API_KEY]/g; s/(AIza[A-Za-z0-9_-]{20,})/[REDACTED_GOOGLE_KEY]/g; s/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g' |
    sed -e 's/[[:space:]]*$//' |
    cut -c1-12000
}

select_response_file() {
  local n outcome file
  for n in 3 2 1; do
    case "$n" in
      3) outcome="${A3:-}" ;;
      2) outcome="${A2:-}" ;;
      1) outcome="${A1:-}" ;;
    esac
    file="${RUNNER_TEMP:-/tmp}/opencode-final-response-$n.md"
    if [[ "$outcome" == "success" && -s "$file" ]]; then
      printf '%s' "$file"
      return 0
    fi
  done
  return 1
}

if [[ "${MERGE_REQUESTED:-false}" == "true" ]]; then
  if [[ "${MERGE_EXIT:-1}" == "0" ]]; then
    body="$(printf "%s\n## /oc\nMerge command completed successfully." "$marker")"
  else
    body="$(printf "%s\n## /oc\nMerge command did not complete successfully. No merge success is claimed." "$marker")"
  fi
else
  # Every successful /oc agent run has a user-facing response lane. This is
  # independent of OC_PUBLISH_REQUESTED, which means repository/PR publication.
  response_file="$(select_response_file || true)"
  answer=""
  if [[ -n "$response_file" ]]; then
    answer="$(sanitize_response "$response_file")"
  fi

  if [[ -n "$answer" ]]; then
    body="$(printf "%s\n## /oc\n\n%s" "$marker" "$answer")"
  elif [[ "$task_mode" == "report" ]]; then
    body="$(printf "%s\n## /oc\n\nOpenCode completed, but no clean final response was captured." "$marker")"
  else
    selected="0"
    for n in 3 2 1; do
      case "$n" in
        3) outcome="${A3:-}" ;;
        2) outcome="${A2:-}" ;;
        1) outcome="${A1:-}" ;;
      esac
      if [[ "$outcome" == "success" ]]; then selected="$n"; break; fi
    done
    if [[ "$selected" == "0" ]]; then
      body="$(printf "%s\n## /oc\nAgent did not complete successfully. No success is claimed." "$marker")"
    else
      case "$selected" in
        3) pub="${P3:-}"; ver="${V3:-}"; pr="${PR3:-}"; sha="${SHA3:-}" ;;
        2) pub="${P2:-}"; ver="${V2:-}"; pr="${PR2:-}"; sha="${SHA2:-}" ;;
        1) pub="${P1:-}"; ver="${V1:-}"; pr="${PR1:-}"; sha="${SHA1:-}" ;;
      esac
      if [[ "${OC_TARGET_MODE:-local}" == "remote" && -n "${OC_TARGET_REPO:-}" && -n "${OC_TARGET_BRANCH:-}" ]]; then
        remote_sha="$(gh api "/repos/$OC_TARGET_REPO/git/ref/heads/$OC_TARGET_BRANCH" --jq '.object.sha' 2>/dev/null || true)"
        if [[ "$remote_sha" =~ ^[0-9a-f]{40}$ ]]; then
          summary="Completed target work on `$OC_TARGET_REPO@$OC_TARGET_BRANCH` at `$remote_sha`."
        else
          summary="OpenCode completed, but the target branch could not be observed."
        fi
        if [[ "$pub" == "published" && -n "$pr" ]]; then summary="$summary PR: $pr"; fi
      else
        if [[ -n "$pr" ]]; then
          summary="Completed and published: $pr"
        elif [[ "$pub" == "checkpointed" ]]; then
          summary="Completed durable work and checkpointed the session; resume with `/oc continue`."
        else
          summary="OpenCode completed successfully."
        fi
      fi
      if [[ "$ver" == "true" && -n "$sha" ]]; then
        summary="$summary Verified exact SHA `$sha` with observable CI checks."
      elif [[ "$pub" == "published" ]]; then
        summary="$summary Independent CI verification is not currently recorded as green."
      fi
      body="$(printf "%s\n## /oc\n%s" "$marker" "$summary")"
    fi
  fi
fi

gh issue comment "$target" --body "$body" >/dev/null