#!/usr/bin/env bash
set -euo pipefail
# Bounded verify-failure recovery (audit item 2).
#
# When the verifier finds a failed GitHub Actions run on the EXACT published
# head, this reruns that same run once (bounded by OC_VERIFY_MAX_RECOVERIES,
# default 1 per workflow job) so a flaky CI result is rechecked without
# re-tasking the agent and without touching any other commit. The rerun is a
# plain Actions API call: local state is never mutated and no fake success can
# be manufactured. If the rerun API is unavailable, recovery is skipped and the
# caller falls back to its normal unverified path.

repo="${GITHUB_REPOSITORY:-}"
ci_run_id="${CI_RUN_ID:-}"
limit="${OC_VERIFY_MAX_RECOVERIES:-1}"
current="${OC_VERIFY_RECOVERIES:-0}"

[[ -n "$repo" ]] || exit 0
[[ "$ci_run_id" =~ ^[0-9]+$ ]] || {
  echo "No numeric CI run id to recover; skipping recovery."
  exit 0
}
[[ "$current" =~ ^[0-9]+$ && "$current" -lt "$limit" ]] || {
  echo "CI recovery budget exhausted; not rerunning CI (Skipped)."
  exit 0
}

if ! gh api -X POST "/repos/$repo/actions/runs/$ci_run_id/rerun" >/dev/null 2>&1; then
  echo "::warning title=CI recovery rerun unavailable::Could not rerun $ci_run_id with the available credential; continuing on the unverified path."
  exit 0
fi

echo "Requested exact-head CI recovery rerun for run $ci_run_id."