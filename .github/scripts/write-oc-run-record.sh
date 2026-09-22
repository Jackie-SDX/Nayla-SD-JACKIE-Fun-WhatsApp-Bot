#!/usr/bin/env bash
set -euo pipefail
# Durable, machine-readable observability record for one /oc run (item 1).
#
# Writes docs/oc-runs/<run_id>.json into the runner worktree; an
# upload-artifact step ships it out with a long retention window after the run
# finishes. Records are NEVER committed: committing would rewrite the verified
# head and make the run's own evidence self-referential. No aggregation
# workflow exists yet; a follow-up task can summarize these artifacts.

run_id="${OC_OBS_RUN_ID:-}"
[[ "$run_id" =~ ^[0-9]+$ ]] || exit 0
out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/docs/oc-runs"
mkdir -p "$out_dir"

elapsed_seconds=""
start_epoch="${OC_JOB_START_EPOCH:-}"
if [[ "$start_epoch" =~ ^[0-9]+$ ]]; then
  elapsed_seconds=$(( $(date +%s) - 10#$start_epoch ))
fi

json="$(
  jq -n \
    --arg run_id "$run_id" \
    --arg repo "${GITHUB_REPOSITORY:-}" \
    --arg issue "${OC_OBS_ISSUE:-}" \
    --arg mode "${OC_OBS_MODE:-local}" \
    --arg opencode_version "${OC_OBS_VERSION:-}" \
    --arg initial_sha "${OC_OBS_INITIAL_SHA:-}" \
    --arg target_repo "${OC_OBS_TARGET_REPO:-}" \
    --arg target_base "${OC_OBS_TARGET_BASE:-}" \
    --arg target_branch "${OC_OBS_TARGET_BRANCH:-}" \
    --arg started_at "${OC_RUN_START_ISO:-}" \
    --arg finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg job_budget_seconds "${OC_JOB_BUDGET_SECONDS:-}" \
    --arg elapsed_seconds "$elapsed_seconds" \
    --arg r1 "${OC_OBS_R1:-}" --arg r1_provider "${OC_OBS_R1_PROVIDER:-}" \
    --arg a1 "${OC_OBS_A1:-}" --arg pu1 "${OC_OBS_PU1:-}" --arg c1 "${OC_OBS_C1:-}" --arg v1 "${OC_OBS_V1:-}" \
    --arg r2 "${OC_OBS_R2:-}" --arg r2_provider "${OC_OBS_R2_PROVIDER:-}" \
    --arg a2 "${OC_OBS_A2:-}" --arg pu2 "${OC_OBS_PU2:-}" --arg c2 "${OC_OBS_C2:-}" --arg v2 "${OC_OBS_V2:-}" \
    --arg r3 "${OC_OBS_R3:-}" --arg r3_provider "${OC_OBS_R3_PROVIDER:-}" \
    --arg a3 "${OC_OBS_A3:-}" --arg pu3 "${OC_OBS_PU3:-}" --arg c3 "${OC_OBS_C3:-}" --arg v3 "${OC_OBS_V3:-}" \
    --arg verified_sha "${OC_OBS_VERIFIED_SHA:-}" \
    --arg pr_url "${OC_OBS_PR_URL:-}" \
    --arg ci_run_id "${OC_OBS_CI_RUN_ID:-}" \
    --arg ci_surfaces "${OC_OBS_CI_SURFACES:-}" \
    --arg event "oc/issue-comment" \
    --arg task_mode "${OC_OBS_TASK_MODE:-code}" \
    --arg peer_result "${OC_OBS_PEER1:-}" \
    --arg peer_elapsed "${OC_OBS_PEER1_ELAPSED:-}" \
    --arg peer_rounds "${OC_OBS_PEER1_ROUNDS:-}" \
    --arg independent_audit "${OC_OBS_INDEPENDENT_AUDIT:-}" \
    '{
      schema_version: 2,
      event: $event,
      run_id: ($run_id | tonumber),
      repository: $repo,
      issue: ($issue | tonumber? // 0),
      mode: $mode,
      target: {
        repository: ($target_repo // ""),
        base: ($target_base // ""),
        branch: ($target_branch // "")
      },
      started_at: $started_at,
      finished_at: $finished_at,
      job_budget_seconds: ($job_budget_seconds | tonumber? // null),
      elapsed_seconds: ($elapsed_seconds | tonumber? // null),
      opencode_version: $opencode_version,
      task_mode: $task_mode,
      initial_sha: $initial_sha,
      attempts: [
        {attempt: 1, route: $r1, provider: $r1_provider, agent_outcome: $a1, publish_outcome: $pu1, classify_outcome: $c1, verified: $v1},
        {attempt: 2, route: $r2, provider: $r2_provider, agent_outcome: $a2, publish_outcome: $pu2, classify_outcome: $c2, verified: $v2},
        {attempt: 3, route: $r3, provider: $r3_provider, agent_outcome: $a3, publish_outcome: $pu3, classify_outcome: $c3, verified: $v3}
      ],
      collaboration: {peer_result: $peer_result, peer_elapsed_seconds: ($peer_elapsed | tonumber? // null), peer_rounds_used: ($peer_rounds | tonumber? // null)},
      independent_audit: $independent_audit,
      result: {
        verified: ($v1 == "true" or $v2 == "true" or $v3 == "true"),
        verified_sha: $verified_sha,
        pr_url: $pr_url,
        ci_run_id: $ci_run_id,
        ci_surfaces: $ci_surfaces
      }
    }'
)"
printf '%s\n' "$json" > "$out_dir/$run_id.json"
echo "Wrote /oc run record: $out_dir/$run_id.json"