#!/usr/bin/env bash
set -u
repo="$REPO"
pr="$PR_NUMBER"
sha="$HEAD_SHA"
wait_minutes="$(printenv OC_CI_WATCH_MINUTES 2>/dev/null || printf 60)"
poll="$(printenv OC_CI_WATCH_POLL_SECONDS 2>/dev/null || printf 20)"
runner_temp="$(printenv RUNNER_TEMP 2>/dev/null || printf /tmp)"
report="$(printenv OC_CI_WATCH_REPORT 2>/dev/null || true)"
[ -n "$report" ] || report="$runner_temp/oc-ci-watch-report.txt"
: > "$report"

if ! [[ "$pr" =~ ^[0-9]+$ ]] || ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "[CI] missing PR number or exact SHA" | tee -a "$report"
  exit 2
fi

deadline=$(( $(date +%s) + wait_minutes * 60 ))
short_sha="$(printf '%.12s' "$sha")"

snapshot() {
  checks="$(gh api "/repos/$repo/commits/$sha/check-runs?per_page=100" 2>/dev/null || printf '%s' '{"check_runs":[]}' )"
  statuses="$(gh api "/repos/$repo/commits/$sha/status" 2>/dev/null || printf '%s' '{"statuses":[],"total_count":0,"state":"pending"}')"
  jq -n --argjson c "$checks" --argjson s "$statuses" '{
    check_total:($c.check_runs|length),
    check_fail:([ $c.check_runs[]? | select(.conclusion=="failure" or .conclusion=="timed_out" or .conclusion=="cancelled" or .conclusion=="action_required" or .conclusion=="startup_failure" or .conclusion=="stale") ]|length),
    check_pending:([ $c.check_runs[]? | select(.status!="completed") ]|length),
    check_green:([ $c.check_runs[]? | select(.status=="completed" and (.conclusion=="success" or .conclusion=="neutral")) ]|length),
    status_total:($s.total_count // 0),
    status_pending:([ $s.statuses[]? | select(.state=="pending") ]|length),
    status_fail:([ $s.statuses[]? | select(.state=="failure" or .state=="error") ]|length),
    status_contexts:([ $s.statuses[]? | select(.state=="failure" or .state=="error") | .context ]|join(", "))
  }'
}

while :; do
  state="$(snapshot)"
  failures="$(jq -r '.check_fail + .status_fail' <<<"$state")"
  pending="$(jq -r '.check_pending + .status_pending' <<<"$state")"
  greens="$(jq -r '.check_green' <<<"$state")"
  total="$(jq -r '.check_total + .status_total' <<<"$state")"
  echo "[CI] PR #$pr $short_sha: observed=$total green=$greens pending=$pending failures=$failures" | tee -a "$report"

  if [ "$failures" -gt 0 ]; then
    echo "--- failed CI evidence ---" | tee -a "$report"
    jq -r '.status_contexts' <<<"$state" | tee -a "$report"
    runs="$(gh api "/repos/$repo/actions/runs?head_sha=$sha&per_page=50" 2>/dev/null || printf '%s' '{"workflow_runs":[]}')"
    jq -r '.workflow_runs[]? | select(.conclusion=="failure") | .id' <<<"$runs" |
      while read -r run_id; do
        gh run view "$run_id" --log-failed 2>/dev/null | tail -n 180 | tee -a "$report" || true
      done
    exit 3
  fi

  if [ "$pending" -eq 0 ] && [ "$greens" -gt 0 ]; then
    echo "[CI] exact SHA is green" | tee -a "$report"
    exit 0
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "[CI] watch timed out or remained unobserved" | tee -a "$report"
    exit 2
  fi
  sleep "$poll"
done
