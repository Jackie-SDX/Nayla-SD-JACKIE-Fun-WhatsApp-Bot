#!/usr/bin/env bash
set -u
repo="$GITHUB_REPOSITORY"
target="$TARGET_NUMBER"
base="$BASE_REF"
since="$OC_RUN_START_ISO"
runner_temp="$(printenv RUNNER_TEMP 2>/dev/null || printf /tmp)"
out="$(printenv OC_INDEPENDENT_AUDIT_FILE 2>/dev/null || true)"
[ -n "$out" ] || out="$runner_temp/oc-independent-audit.txt"
: > "$out"
echo "Independent agent audit (advisory only)" | tee -a "$out"
echo "This audit reports blind spots; it never invalidates successful autonomous work." | tee -a "$out"

prs="$(gh pr list --repo "$repo" --base "$base" --state open --limit 100 --json number,url,headRefName,headRefOid,createdAt 2>/dev/null || printf '[]')"
prefix="opencode/issue$target-"
pr="$(jq -c --arg p "$prefix" --arg s "$since" '[.[] | select((.headRefName|startswith($p)) and .createdAt >= $s)] | sort_by(.createdAt) | last // {}' <<<"$prs")"

if [ "$pr" = "{}" ]; then
  echo "No matching PR independently observable." | tee -a "$out"
else
  number="$(jq -r '.number' <<<"$pr")"
  sha="$(jq -r '.headRefOid' <<<"$pr")"
  url="$(jq -r '.url' <<<"$pr")"
  checks="$(gh api "/repos/$repo/commits/$sha/check-runs?per_page=100" 2>/dev/null || printf '%s' '{"check_runs":[]}')"
  statuses="$(gh api "/repos/$repo/commits/$sha/status" 2>/dev/null || printf '%s' '{"total_count":0,"statuses":[]}')"
  echo "PR #$number: $url" | tee -a "$out"
  echo "Head: $sha" | tee -a "$out"
  echo "Checks: $(jq -r '.check_runs|length' <<<"$checks"), green=$(jq -r '[.check_runs[]|select(.conclusion=="success" or .conclusion=="neutral")]|length' <<<"$checks"), failed=$(jq -r '[.check_runs[]|select(.conclusion=="failure" or .conclusion=="timed_out" or .conclusion=="cancelled" or .conclusion=="action_required" or .conclusion=="startup_failure" or .conclusion=="stale")]|length' <<<"$checks")" | tee -a "$out"
  echo "Commit statuses: $(jq -r '.total_count // 0' <<<"$statuses")" | tee -a "$out"
fi

summary="$(printenv GITHUB_STEP_SUMMARY 2>/dev/null || true)"
if [ -n "$summary" ]; then
  {
    echo "### Independent agent audit (advisory)"
    echo
    cat "$out"
  } >> "$summary"
fi
exit 0
