#!/usr/bin/env bash
set -euo pipefail
repo="$(printenv GITHUB_REPOSITORY || true)"
target="$(printenv TARGET_NUMBER || printf 0)"
cmd="${1:-load}"
runner_temp="${RUNNER_TEMP:-/tmp}"
state_file="${OC_SESSION_STATE_FILE:-$runner_temp/oc-session-state.json}"
marker="<!-- oc-session-state:v1 issue:$target -->"
end_marker="<!-- /oc-session-state -->"
mkdir -p "$runner_temp"
[[ "$target" =~ ^[0-9]+$ && "$target" != 0 && -n "$repo" ]] || exit 0
emit_env(){ printf '%s=%s\n' "$1" "$2" >> "${GITHUB_ENV:-/dev/null}"; }
emit_out(){ printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT:-/dev/null}"; }
find_comment_id(){ gh api --paginate --jq --arg marker "$marker" '.[] | select((.body // "") | contains($marker)) | .id' "/repos/$repo/issues/$target/comments?per_page=100" 2>/dev/null | tail -n 1; }
publish_state_comment(){
  local json body comment_id
  json="$(cat "$state_file")"
  if grep -Eq 'gh[pous]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-or-v1-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._-]+' <<<"$json"; then
    echo "::warning title=Session state blocked::Potential credential material detected; state comment not updated."
    return 0
  fi
  body="$(printf '%s\n\nSTATE-BEGIN\n%s\nSTATE-END\n%s' "$marker" "$json" "$end_marker")"
  comment_id="$(find_comment_id || true)"
  if [[ "$comment_id" =~ ^[0-9]+$ ]]; then
    gh api -X PATCH -f body="$body" "/repos/$repo/issues/comments/$comment_id" >/dev/null
  else
    gh issue comment "$target" --body "$body" >/dev/null
  fi
}
export_state_env(){
  local json="$1"
  printf '%s\n' "$json" > "$state_file"
  emit_env OC_SESSION_STATE_FILE "$state_file"
  emit_env OC_SESSION_ID "$(jq -r '.session_id // ""' "$state_file")"
  emit_env OC_SESSION_BRANCH "$(jq -r '.active_branch // ""' "$state_file")"
  emit_env OC_SESSION_BASE "$(jq -r '.base_ref // "main"' "$state_file")"
  emit_env OC_SESSION_HEAD_SHA "$(jq -r '.active_head_sha // ""' "$state_file")"
  emit_env OC_SESSION_PR_NUMBER "$(jq -r '.active_pr_number // 0' "$state_file")"
  emit_env OC_SESSION_PR_URL "$(jq -r '.active_pr_url // ""' "$state_file")"
  emit_env OC_SESSION_PHASE "$(jq -r '.phase // "unknown"' "$state_file")"
  emit_env OC_SESSION_STATUS "$(jq -r '.status // "new"' "$state_file")"
  emit_env OC_SESSION_EXISTS true
  emit_out state_file "$state_file"
  emit_out session_id "$(jq -r '.session_id // ""' "$state_file")"
  emit_out branch "$(jq -r '.active_branch // ""' "$state_file")"
  emit_out head_sha "$(jq -r '.active_head_sha // ""' "$state_file")"
  emit_out pr_number "$(jq -r '.active_pr_number // 0' "$state_file")"
  emit_out pr_url "$(jq -r '.active_pr_url // ""' "$state_file")"
  emit_out phase "$(jq -r '.phase // "unknown"' "$state_file")"
}
case "$cmd" in
  load)
    comment_id="$(find_comment_id || true)"
    if [[ "$comment_id" =~ ^[0-9]+$ ]]; then
      raw="$(gh api "/repos/$repo/issues/comments/$comment_id" --jq '.body // ""' 2>/dev/null || true)"
      json="$(awk -v a="$marker" -v b="$end_marker" 'index($0,a){inside=1;next} index($0,b){inside=0} inside{print}' <<<"$raw" | sed -n '/^STATE-BEGIN$/,/^STATE-END$/p' | sed '1d;$d')"
      if jq empty <<<"$json" >/dev/null 2>&1; then
        export_state_env "$json"
        echo "Loaded durable session $(jq -r '.session_id' "$state_file")"
        exit 0
      fi
    fi
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    base="$(printenv BASE_REF || printf main)"
    json="$(jq -n --arg repo "$repo" --arg issue "$target" --arg base "$base" --arg now "$now" --arg sid "oc-$target" '{schema_version:1,session_id:$sid,repository:$repo,issue:($issue|tonumber),base_ref:$base,active_branch:"",active_pr_number:0,active_pr_url:"",active_head_sha:"",goal:"",milestone:"received",phase:"received",status:"new",state_revision:0,capabilities:{push:false,target:""},last_verified_sha:"",last_verified_evidence:"",created_at:$now,updated_at:$now,last_processed_comment_id:0,current_request:"",completed_steps:[],remaining_steps:[],tests_run:[],ci_runs:[],research_sources:[],copilot:{status:"not_started",rounds:0},warnings:[],artifacts:[],next_action:"classify request"}')"
    export_state_env "$json"
    echo "Initialized durable session $(jq -r '.session_id' "$state_file") for issue #$target."
    ;;
  save|checkpoint)
    [[ -f "$state_file" ]] || { echo "::warning title=Session state unavailable::No durable state file is present; continuing."; exit 0; }
    publish_state_comment || echo "::warning title=Session state degraded::The issue state comment could not be updated; durable Git state remains available."
    export_state_env "$(cat "$state_file")"
    ;;
  set)
    json="$(printenv SESSION_JSON || true)"
    jq empty <<<"$json" >/dev/null 2>&1 || { echo "::error title=Invalid session state::SESSION_JSON is not valid JSON." >&2; exit 2; }
    printf '%s\n' "$json" > "$state_file"
    publish_state_comment || true
    export_state_env "$json"
    ;;
  *) echo "::error title=Unknown session command::Use load, save/checkpoint, or set." >&2; exit 2 ;;
esac
