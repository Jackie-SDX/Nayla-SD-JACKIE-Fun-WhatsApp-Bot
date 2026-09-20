#!/usr/bin/env bash
set -euo pipefail
repo="$GITHUB_REPOSITORY"
provider="$PROVIDER"
attempt="$ATTEMPT"
target="$TARGET_NUMBER"
base_ref="$BASE_REF"
initial_sha="$INITIAL_SHA"
run_id="$GITHUB_RUN_ID"
wait_minutes="$OC_CI_VERIFY_WAIT_MINUTES"
poll_seconds="$OC_CI_VERIFY_POLL_SECONDS"
[[ -n "$wait_minutes" ]] || wait_minutes=20
[[ -n "$poll_seconds" ]] || poll_seconds=20
[[ "$target" =~ ^[0-9]+$ ]] || target=0
[[ "$wait_minutes" =~ ^[0-9]+$ ]] || wait_minutes=20
[[ "$poll_seconds" =~ ^[0-9]+$ ]] || poll_seconds=20
(( poll_seconds >= 5 )) || poll_seconds=5

retryable=false
verified=false
timed_out=false
reason=""
pr_url=""
ci_run_id=""
emit() { printf '%s=%s
' "$1" "$2" >> "$GITHUB_OUTPUT"; }
emit verified false
emit retryable false
emit timed_out false
emit pr_url ""
emit ci_run_id ""

# ---- Remote-target verification -------------------------------------------
# Remote targets are verified against the target repository's PR/head state
# and its own observable checks/workflows. No success is claimed when no CI
# evidence is visible. The controller's own 'validate' check name is never
# assumed to exist in another repository.
if [[ "${OC_TARGET_MODE:-local}" == "remote" ]]; then
  rrepo="${OC_TARGET_REPO:-}"
  rbase="${OC_TARGET_BASE:-main}"
  rbranch="${OC_TARGET_BRANCH:-}"
  rlocal_head="$(git -C "${OC_TARGET_WORKSPACE:-.}" rev-parse HEAD 2>/dev/null || true)"
  reason=""
  pr_url=""

  if [[ -z "$rrepo" || -z "$rbranch" ]]; then
    reason="remote target was not fully resolved"
  elif ! gh api "/repos/$rrepo" >/dev/null 2>&1; then
    reason="the available workflow credential cannot read the target repository $rrepo"
  fi

  find_target_pr() {
    gh pr list --repo "$rrepo" --head "$rbranch" --base "$rbase" --state all --limit 20 \
      --json number,url,state,mergedAt,headRefOid 2>/dev/null | jq -r '.[0] // empty' 2>/dev/null || true
  }

  pr="$(find_target_pr)"
  if [[ -n "$reason" ]]; then
    :
  elif [[ -z "$pr" ]]; then
    reason="no observable target pull request for $rrepo@$rbranch"
  else
    pr_url="$(jq -r '.url // ""' <<<"$pr")"
    pr_state="$(jq -r '.state // ""' <<<"$pr")"
    merged_at="$(jq -r '.mergedAt // ""' <<<"$pr")"
    head_sha="$(jq -r '.headRefOid // ""' <<<"$pr")"
    pr_number="$(jq -r '.number // ""' <<<"$pr")"
    if [[ "$pr_state" == "MERGED" || -n "$merged_at" ]]; then
      verified=true
      emit verified true
      emit retryable false
      emit pr_url "$pr_url"
      [[ -n "$rlocal_head" ]] && emit ci_run_id "$rlocal_head"
      echo "Remote target PR verified (merged): $pr_url"
      exit 0
    fi
    if [[ -n "$rlocal_head" && -n "$head_sha" && "$rlocal_head" != "$head_sha" ]]; then
      reason="target PR head ($head_sha) does not match the policed workspace head ($rlocal_head)"
    fi
  fi

  deadline=$((SECONDS + wait_minutes * 60))
  pending=false
  while [[ "$verified" != "true" && -z "$reason" ]]; do
    checks="$(gh api "/repos/$rrepo/commits/$head_sha/check-runs?per_page=100" 2>/dev/null || true)"
    if [[ -z "$checks" ]]; then
      checks="$(gh api "/repos/$rrepo/pulls/$pr_number/checks?per_page=100" 2>/dev/null || true)"
    fi
    # shellcheck disable=SC2181
    if [[ -z "$checks" ]]; then
      reason="target CI evidence is not observable with the available workflow credential"
      break
    fi
    success_count="$(jq '[.check_runs[]? | select(.conclusion == "success")] | length' <<<"$checks" 2>/dev/null || echo 0)"
    if [[ "$success_count" -gt 0 ]]; then
      verified=true
      break
    fi
    st="$(gh api "/repos/$rrepo/commits/$head_sha/status" 2>/dev/null || printf '%s' '{"state":"pending"}')"
    if [[ "$(jq -r '.state // ""' <<<"$st")" == "success" ]]; then
      verified=true
      break
    fi
    states="$(jq -r '[.check_runs[]?.status] | if index("in_progress") or index("queued") then "pending" else "done" end' <<<"$checks" 2>/dev/null || echo done)"
    if [[ "$states" == "pending" && "$SECONDS" -lt "$deadline" ]]; then
      pending=true
      sleep "$poll_seconds"
      continue
    fi
    break
  done

  if [[ "$verified" == "true" ]]; then
    emit verified true
    emit retryable false
    [[ -n "$pr_url" ]] && emit pr_url "$pr_url"
    emit ci_run_id "$head_sha"
    echo "Remote target PR verified: $pr_url"
    exit 0
  fi
  if [[ "$pending" == "true" && "$SECONDS" -ge "$deadline" ]]; then
    reason="target PR checks remained pending beyond the verification wait window"
    timed_out=true
  fi
  [[ -n "$reason" ]] || reason="remote target could not be verified"
  retryable=true
  emit verified false
  emit retryable true
  emit timed_out "$timed_out"
  [[ -n "$pr_url" ]] && emit pr_url "$pr_url"
  echo "::warning title=Remote target not independently verified::$reason"
  [[ -n "$target" && "$target" != "0" ]] && gh issue comment "$target" --body "<!-- oc-remote-verify-failed attempt:$attempt repo:$rrepo branch:$rbranch -->
## /oc remote-target verification did not pass

- Target: $rrepo
- Branch: $rbranch
- PR: ${pr_url:-not identified}
- Reason: $reason

No success is claimed. Inspect the target repository state and continue." 2>/dev/null || true
  exit 1
fi

if ! git diff --check >/dev/null 2>&1; then
  retryable=true
  reason="git diff --check failed"
fi

if [[ -z "$reason" && -f package.json ]]; then
  runner_temp="$RUNNER_TEMP"
  [[ -n "$runner_temp" ]] || runner_temp=/tmp
  npm_log="$(mktemp "$runner_temp/oc-verify-npm.XXXXXX")"
  if ! npm test >"$npm_log" 2>&1; then
    retryable=true
    reason="npm test failed"
  fi
fi

current_sha="$(git rev-parse HEAD 2>/dev/null || printf '%s' "$initial_sha")"
dirty="$(git status --porcelain 2>/dev/null || true)"
local_mutation=false
[[ -n "$dirty" || ( -n "$initial_sha" && "$current_sha" != "$initial_sha" ) ]] && local_mutation=true

prs="$(gh pr list --state all --limit 100 --json number,url,state,mergedAt,headRefName,headRefOid,baseRefName,createdAt,updatedAt 2>/dev/null || printf '%s' '[]')"
branches="$(gh api --paginate --slurp "/repos/$repo/branches?per_page=100" 2>/dev/null | jq 'add // []' 2>/dev/null || printf '%s' '[]')"
target_prefix="opencode/issue"$target"-"
copilot_prefix="oc/copilot-"$target"-"$run_id"-"
agent_branch="$(jq -r --arg a "$target_prefix" --arg c "$copilot_prefix" '[.[] | select((.name | startswith($a)) or (.name | startswith($c)))] | sort_by(.name) | last | (.name // "")' <<<"$branches")"

candidate_prs="$(
  {
    jq -r --arg a "$target_prefix" --arg c "$copilot_prefix" --arg branch "$agent_branch" --arg base "$base_ref" '
      .[] | select(.baseRefName == $base) |
      select((.headRefName | startswith($a)) or (.headRefName | startswith($c)) or (.headRefName == $branch)) |
      .number
    ' <<<"$prs"
    if (( target > 0 )); then
      gh api --paginate --slurp "/repos/$repo/issues/$target/comments?per_page=100" 2>/dev/null |
        jq -r --arg since "${OC_RUN_START_ISO:-1970-01-01T00:00:00Z}" '
          add // [] |
          .[] |
          select((.created_at // "") >= $since) |
          .body // "" |
          scan("https://github[.]com/[^/]+/[^/]+/pull/([0-9]+)") |
          .[]?
        ' 2>/dev/null || true
    fi
  } | awk 'NF' | sort -nu
)"

check_pr() {
  local number="$1" pr head_sha checks validate status runs safe_tail
  pr="$(gh pr view "$number" --json number,url,state,mergedAt,headRefName,headRefOid,baseRefName 2>/dev/null || true)"
  [[ -n "$pr" ]] || return 1
  [[ "$(jq -r '.baseRefName' <<<"$pr")" == "$base_ref" ]] || return 1
  head_ref="$(jq -r '.headRefName // ""' <<<"$pr")"
  [[ "$head_ref" == "$target_prefix"* || "$head_ref" == "$copilot_prefix"* ]] || return 1
  created_at="$(jq -r '.createdAt // ""' <<<"$pr")"
  start_iso="${OC_RUN_START_ISO:-1970-01-01T00:00:00Z}"
  [[ "$created_at" == "$start_iso" || "$created_at" > "$start_iso" ]] || return 1
  state="$(jq -r '.state // ""' <<<"$pr")"
  merged_at="$(jq -r '.mergedAt // ""' <<<"$pr")"
  [[ "$state" == "OPEN" || -n "$merged_at" ]] || return 1
  head_sha="$(jq -r '.headRefOid // ""' <<<"$pr")"
  [[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  pr_url="$(jq -r '.url // ""' <<<"$pr")"

  checks="$(gh api "/repos/$repo/commits/$head_sha/check-runs?per_page=100" 2>/dev/null || printf '%s' '{"check_runs":[]}')"
  validate="$(jq -c '[.check_runs[] | select(.name == "validate")] | sort_by(.completed_at // "") | last // {}' <<<"$checks")"
  if [[ "$(jq -r '.conclusion // ""' <<<"$validate")" == "success" ]]; then
    verified=true
    return 0
  fi

  status="$(jq -r '.status // ""' <<<"$validate")"
  if [[ "$status" == "queued" || "$status" == "in_progress" || "$status" == "" ]]; then
    return 2
  fi

  retryable=true
  reason="required validate check is $(jq -r '.conclusion // "unknown"' <<<"$validate")"
  runs="$(gh api "/repos/$repo/actions/runs?head_sha=$head_sha&per_page=20" 2>/dev/null || printf '%s' '{"workflow_runs":[]}')"
  ci_run_id="$(jq -r '[.workflow_runs[] | select(.name == "enterprise-agent-validation")] | sort_by(.created_at) | last | (.id // "")' <<<"$runs")"
  emit ci_run_id "$ci_run_id"

  if [[ "$target" != "0" ]]; then
    safe_tail=""
    if [[ "$ci_run_id" =~ ^[0-9]+$ ]]; then
      safe_tail="$(gh run view "$ci_run_id" --log-failed 2>/dev/null | tail -n 120 || true)"
      safe_tail="$(printf '%s' "$safe_tail" | sed -E         -e 's/(gh[ps]_[[:alnum:]_]{20,}|github_pat_[[:alnum:]_]{20,})/[REDACTED_GITHUB_TOKEN]/g'         -e 's/(sk-or-v1-[[:alnum:]_-]{20,})/[REDACTED_EXTERNAL_API_KEY]/g'         -e 's/Bearer[[:space:]]+[^[:space:]]+/Bearer [REDACTED]/g')"
    fi
    pr_display="$pr_url"; [[ -n "$pr_display" ]] || pr_display="not identified"
    ci_display="$ci_run_id"; [[ -n "$ci_display" ]] || ci_display="unknown"
    evidence="$safe_tail"; [[ -n "$evidence" ]] || evidence="No sanitized CI log was available."
    gh issue comment "$target" --body "$(cat <<EOF
<!-- oc-ci-failure-run-id:$ci_display attempt:$attempt -->
## /oc CI verification found a failure

Provider: $provider
Attempt: $attempt
PR: $pr_display
Required check: validate
Reason: $reason

Inspect this exact CI evidence and continue from the current repository/PR state rather than creating duplicate work.

Sanitized failure evidence:
$evidence
EOF
)"
  fi
  return 1
}

deadline=$((SECONDS + wait_minutes * 60))
pending=false
while :; do
  pending=false
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    if check_pr "$n"; then
      break 2
    else
      rc=$?
      [[ "$rc" -eq 2 ]] && pending=true
    fi
  done <<<"$candidate_prs"
  [[ "$verified" == "true" ]] && break
  if [[ -z "$candidate_prs" && "$local_mutation" == "false" && -z "$agent_branch" && -z "$reason" ]]; then
    verified=true
    break
  fi
  if [[ "$pending" == "true" && "$SECONDS" -lt "$deadline" ]]; then
    sleep "$poll_seconds"
    continue
  fi
  break
done

if [[ "$verified" == "true" ]]; then
  emit verified true
  emit retryable false
  [[ -n "$pr_url" ]] && emit pr_url "$pr_url"
  echo "Agent attempt $attempt verified."
  exit 0
fi
if [[ "$local_mutation" == "true" && -z "$candidate_prs" && -z "$reason" ]]; then
  retryable=true
  reason="agent mutated local state without an observable PR"
fi
if [[ -n "$agent_branch" && -z "$candidate_prs" && -z "$reason" ]]; then
  retryable=true
  reason="agent branch exists without an observable PR"
fi
if [[ "$pending" == "true" && "$SECONDS" -ge "$deadline" ]]; then
  retryable=true
  reason="required validate check remained pending beyond the verification wait window"
  timed_out=true
fi
if [[ "$retryable" == "true" && "$provider" == "opencode" ]]; then
  echo "OPENCODE_RETRY_CURRENT_ROUTE=1" >> "$GITHUB_ENV"
fi
emit verified false
emit retryable "$retryable"
emit timed_out "$timed_out"
[[ -n "$pr_url" ]] && emit pr_url "$pr_url"
[[ -n "$reason" ]] && echo "::warning title=Agent completion not independently verified::$reason"
exit 1
