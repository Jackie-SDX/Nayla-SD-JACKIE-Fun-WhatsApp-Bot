#!/usr/bin/env bash
set -euo pipefail
repo="$GITHUB_REPOSITORY"
provider="$PROVIDER"
attempt="$ATTEMPT"
target="$TARGET_NUMBER"
base_ref="$BASE_REF"
initial_sha="$INITIAL_SHA"
run_id="$GITHUB_RUN_ID"
wait_minutes="${OC_CI_VERIFY_WAIT_MINUTES:-}"
poll_seconds="${OC_CI_VERIFY_POLL_SECONDS:-}"
settle_seconds="${OC_CI_VERIFY_SETTLE_SECONDS:-}"
[[ -n "$wait_minutes" ]] || wait_minutes=20
[[ -n "$poll_seconds" ]] || poll_seconds=20
[[ -n "$settle_seconds" ]] || settle_seconds=30
[[ "$target" =~ ^[0-9]+$ ]] || target=0
[[ "$wait_minutes" =~ ^[0-9]+$ ]] || wait_minutes=20
[[ "$poll_seconds" =~ ^[0-9]+$ ]] || poll_seconds=20
[[ "$settle_seconds" =~ ^[0-9]+$ ]] || settle_seconds=30
(( poll_seconds >= 5 )) || poll_seconds=5
(( settle_seconds >= 0 )) || settle_seconds=0

retryable=false
verified=false
timed_out=false
reason=""
pr_url=""
ci_run_id=""
verified_sha=""
failure_commented=false
emit() { printf '%s=%s
' "$1" "$2" >> "$GITHUB_OUTPUT"; }
emit verified false
emit retryable false
emit timed_out false
emit pr_url ""
emit ci_run_id ""
emit verified_sha ""
emit ci_surfaces ""
emit ci_observation_start ""
emit ci_observation_end ""

observe_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
emit ci_observation_start "$observe_start"

# ---------------------------------------------------------------------------
# Generalized CI-surface evaluation.
#
# A commit is only ever considered verified when BOTH observable CI surfaces
# agree:
#   1. GitHub Actions check-runs for the exact SHA (all completed runs); and
#   2. combined commit statuses for the exact SHA (external providers such as
#      CircleCI report through the legacy statuses API and appear here).
#
# The evaluator fails closed: if either surface shows a failing/non-green
# conclusion or a failing/error status context, verification fails. Pending
# surfaces keep the poll alive because external providers can post late.
# An empty statuses set (total_count == 0) is treated as *unobserved*: it is
# never pending and never failing by itself, so repos without statuses-based
# CI are not blocked, but a remote target with no observable CI at all still
# cannot be declared verified.
#
# load_ci_state <repo> <sha>  -> populates CI_* globals
# evaluate_ci_state <repo> <sha> -> sets CI_EVAL in {verified,pending,failed}
#                                    and CI_EVAL_REASON on failure
# ---------------------------------------------------------------------------
load_ci_state() {
  local crepo="$1"
  local head_sha="$2"
  CI_CHECK_JSON="$(gh api "/repos/$crepo/commits/$head_sha/check-runs?per_page=100" 2>/dev/null || printf '%s' '{"check_runs":[]}')"
  CI_STATUS_JSON="$(gh api "/repos/$crepo/commits/$head_sha/status" 2>/dev/null || printf '%s' '{"state":"pending","statuses":[],"total_count":0}')"
  CI_TOTAL="$(jq '.check_runs | length' <<<"$CI_CHECK_JSON" 2>/dev/null || echo 0)"
  CI_FAIL="$(jq '[.check_runs[]? | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "cancelled" or .conclusion == "action_required" or .conclusion == "startup_failure" or .conclusion == "stale")] | length' <<<"$CI_CHECK_JSON" 2>/dev/null || echo 0)"
  CI_PENDING="$(jq '[.check_runs[]? | select((.status == "queued" or .status == "in_progress" or .status == "pending"))] | length' <<<"$CI_CHECK_JSON" 2>/dev/null || echo 0)"
  CI_SUCCESS="$(jq '[.check_runs[]? | select(.status == "completed" and .conclusion == "success")] | length' <<<"$CI_CHECK_JSON" 2>/dev/null || echo 0)"
  CI_SKIPPED="$(jq '[.check_runs[]? | select(.status == "completed" and .conclusion == "skipped")] | length' <<<"$CI_CHECK_JSON" 2>/dev/null || echo 0)"
  CI_NEUTRAL="$(jq '[.check_runs[]? | select(.status == "completed" and .conclusion == "neutral")] | length' <<<"$CI_CHECK_JSON" 2>/dev/null || echo 0)"
  CI_STATUS_STATE="$(jq -r '.state // "pending"' <<<"$CI_STATUS_JSON" 2>/dev/null || echo pending)"
  CI_STATUS_TOTAL="$(jq '.total_count // 0' <<<"$CI_STATUS_JSON" 2>/dev/null || echo 0)"
  CI_STATUS_PENDING="$(jq '[.statuses[]? | select(.state == "pending")] | length' <<<"$CI_STATUS_JSON" 2>/dev/null || echo 0)"
  CI_STATUS_FAILURES="$(jq -r '[.statuses[]? | select(.state == "failure" or .state == "error") | (.context // "unknown")] | join(", ")' <<<"$CI_STATUS_JSON" 2>/dev/null || true)"
}

evaluate_ci_state() {
  local crepo="$1" csha="$2"
  load_ci_state "$crepo" "$csha"
  local failing=""
  local surfaces=""
  [[ "$CI_TOTAL" -gt 0 ]] && surfaces="check-runs"
  [[ "$CI_STATUS_TOTAL" -gt 0 ]] && surfaces="${surfaces:+${surfaces},}commit-status"
  [[ -z "$surfaces" ]] && surfaces="none-observed"
  CI_OBSERVED_SURFACES="$surfaces"

  if [[ "$CI_FAIL" -gt 0 ]]; then
    local failure_count="$CI_FAIL"
    failing="GitHub Actions has $failure_count failed/non-green check run(s) on the exact SHA."
  fi
  if [[ -n "$CI_STATUS_FAILURES" ]]; then
    failing="${failing:+${failing} }External status provider(s) report failure/error on the exact SHA: $CI_STATUS_FAILURES."
  fi
  if [[ -n "$failing" ]]; then
    CI_EVAL="failed"
    CI_EVAL_REASON="$failing"
    return
  fi

  # An empty statuses set is unobserved, never pending or failing by itself.
  if [[ "$CI_PENDING" -gt 0 ]] || { [[ "$CI_STATUS_TOTAL" -gt 0 ]] && { [[ "$CI_STATUS_STATE" == "pending" ]] || [[ "$CI_STATUS_PENDING" -gt 0 ]]; }; }; then
    CI_EVAL="pending"
    return
  fi

  # Skipped is never success. A snapshot is only green when at least one
  # observable check-run demonstrably completed with success/neutral. A SHA
  # whose only observable checks were all skipped stays pending (it can never
  # be declared verified), while partial skips next to real green checks remain
  # acceptable -- exactly like GitHub treats a path-filtered job as n/a.
  if [[ "$CI_TOTAL" -gt 0 && "$((CI_SUCCESS + CI_NEUTRAL))" -lt 1 ]]; then
    CI_EVAL="pending"
    return
  fi

  CI_EVAL="verified"
}

# issue_comments_marker <marker> returns 0 when an existing issue comment
# already carries the given exact marker fragment; used to make failure
# reporting idempotent across attempts/processes, not only within a single
# verifier invocation.
issue_comments_marker() {
  local want="$1"
  [[ "$target" =~ ^[0-9]+$ && "$target" != "0" ]] || return 1
  if gh api "/repos/$repo/issues/$target/comments?per_page=100" 2>/dev/null |
    jq -e --arg w "$want" '[.[] | select((.body // "") | contains($w))] | length > 0' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# ---- Remote-target verification -------------------------------------------
# Remote targets are verified against the target repository's PR/head state
# and its own observable checks/statuses/workflows. No success is claimed when
# no CI evidence is visible. The controller's own 'validate' check name is
# never assumed to exist in another repository.
if [[ "${OC_TARGET_MODE:-local}" == "remote" ]]; then
  rrepo="${OC_TARGET_REPO:-}"
  rbase="${OC_TARGET_BASE:-main}"
  rbranch="${OC_TARGET_BRANCH:-}"
  expected_head="${EXPECTED_TARGET_HEAD:-}"
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
      verified_sha="$head_sha"
      emit verified true
      emit retryable false
      emit pr_url "$pr_url"
      emit ci_run_id "$head_sha"
      emit verified_sha "$head_sha"
      emit ci_surfaces "merged-pr"
      emit ci_observation_end "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "Remote target PR verified (merged): $pr_url ($head_sha)"
      exit 0
    fi
    if [[ -n "$expected_head" && "$expected_head" != "$head_sha" ]]; then
      reason="target PR head ($head_sha) does not match the controller published target head ($expected_head)"
    fi
    if [[ -z "$reason" ]]; then
      branch_sha="$(gh api "/repos/$rrepo/git/ref/heads/$rbranch" 2>/dev/null | jq -r ".object.sha // \"\"" 2>/dev/null || true)"
      if [[ -z "$branch_sha" ]]; then
        reason="target branch ref $rbranch is not observable"
      elif [[ "$branch_sha" != "$head_sha" ]]; then
        reason="target branch head ($branch_sha) does not match target PR head ($head_sha)"
      fi
    fi
  fi

  deadline=$((SECONDS + wait_minutes * 60))
  pending=false
  settle_done=false
  while [[ "$verified" != "true" && -z "$reason" ]]; do
    evaluate_ci_state "$rrepo" "$head_sha"
    if [[ "$CI_EVAL" == "failed" ]]; then
      reason="target CI failed on exact head $head_sha: $CI_EVAL_REASON"
      break
    fi
    if [[ "$CI_EVAL" == "pending" ]]; then
      if [[ "$SECONDS" -lt "$deadline" ]]; then
        pending=true
        sleep "$poll_seconds"
        continue
      fi
      pending=true
      timed_out=true
      break
    fi
    # Nominal green on both surfaces. Wait one bounded settle window so late
    # external statuses cannot flip a prematurely green snapshot.
    if [[ "$CI_OBSERVED_SURFACES" == "none-observed" ]]; then
      reason="target CI evidence is not observable with the available workflow credential"
      break
    fi
    if [[ "$settle_done" == "false" && "$settle_seconds" -gt 0 && "$SECONDS" -lt "$deadline" ]]; then
      settle_done=true
      pending=true
      sleep "$settle_seconds"
      continue
    fi
    verified=true
    verified_sha="$head_sha"
    break
  done

  if [[ "$verified" == "true" ]]; then
    emit verified true
    emit retryable false
    [[ -n "$pr_url" ]] && emit pr_url "$pr_url"
    emit ci_run_id "$head_sha"
    emit verified_sha "$head_sha"
    emit ci_surfaces "$CI_OBSERVED_SURFACES"
    emit ci_observation_end "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Remote target PR verified: $pr_url"
    exit 0
  fi
  if [[ "$pending" == "true" && "$SECONDS" -ge "$deadline" ]]; then
    reason="target PR checks/statuses remained pending beyond the verification wait window"
    timed_out=true
  fi
  [[ -n "$reason" ]] || reason="remote target could not be verified"
  retryable=true
  emit verified false
  emit retryable true
  emit timed_out "$timed_out"
  [[ -n "$pr_url" ]] && emit pr_url "$pr_url"
  emit verified_sha "$head_sha"
  echo "::warning title=Remote target not independently verified::$reason"
  if [[ -n "$target" && "$target" != "0" ]] && ! issue_comments_marker "repo:$rrepo branch:$rbranch"; then
    gh issue comment "$target" --body "<!-- oc-remote-verify-failed attempt:$attempt repo:$rrepo branch:$rbranch -->
## /oc remote-target verification did not pass

- Target: $rrepo
- Branch: $rbranch
- PR: ${pr_url:-not identified}
- Reason: $reason

No success is claimed. Inspect the target repository state and continue." 2>/dev/null || true
  fi
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

# Candidate PRs come from two independent windows:
#   1. The controller naming window (opencode/issueN-* / oc/copilot-N-run-*) --
#      the branch/PR the /oc run itself publishes through. Requires the prefix.
#   2. The issue-comment window -- pull requests explicitly referenced in this
#      issue's thread after the run started (e.g. an agent that publishes onto a
#      task-specific branch such as the demo-loop PR). These carry their own
#      authorship evidence (created within this run's window + base match) and
#      every observable CI surface on the exact head must still be green, so
#      the strict prefix is not required for them.
branch_candidate_prs="$(
  jq -r --arg a "$target_prefix" --arg c "$copilot_prefix" --arg branch "$agent_branch" --arg base "$base_ref" '
    .[] | select(.baseRefName == $base) |
    select((.headRefName | startswith($a)) or (.headRefName | startswith($c)) or (.headRefName == $branch)) |
    .number
  ' <<<"$prs"
)"
scan_candidate_prs="$(
  {
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
candidate_prs="$( { printf '%s\n' "$branch_candidate_prs"; printf '%s\n' "$scan_candidate_prs"; } | awk 'NF' | sort -nu )"

# check_pr evaluates one candidate pull request. Exit codes:
#   0 verified, 1 failed with reason/retryable set, 2 still pending.
# The second argument allows candidates sourced from the issue-comment window
# to skip the strict controller branch-prefix requirement; they are still bound
# by the run-window creation timestamp, the base-branch match, and the exact-SHA
# all-surface CI verdict.
check_pr() {
  local number="$1" allow_unprefixed="${2:-0}" pr head_sha checks validate pr_state status surfaces_ok prefix_ok
  pr="$(gh pr view "$number" --json number,url,state,mergedAt,headRefName,headRefOid,baseRefName,createdAt 2>/dev/null || true)"
  [[ -n "$pr" ]] || return 1
  [[ "$(jq -r '.baseRefName' <<<"$pr")" == "$base_ref" ]] || return 1
  head_ref="$(jq -r '.headRefName // ""' <<<"$pr")"
  prefix_ok=0
  [[ "$head_ref" == "$target_prefix"* || "$head_ref" == "$copilot_prefix"* ]] && prefix_ok=1
  if [[ "$prefix_ok" == "0" && "$allow_unprefixed" != "1" ]]; then
    return 1
  fi
  created_at="$(jq -r '.createdAt // ""' <<<"$pr")"
  start_iso="${OC_RUN_START_ISO:-1970-01-01T00:00:00Z}"
  [[ "$created_at" == "$start_iso" || "$created_at" > "$start_iso" ]] || return 1
  pr_state="$(jq -r '.state // ""' <<<"$pr")"
  merged_at="$(jq -r '.mergedAt // ""' <<<"$pr")"
  [[ "$pr_state" == "OPEN" || -n "$merged_at" ]] || return 1
  head_sha="$(jq -r '.headRefOid // ""' <<<"$pr")"
  [[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  pr_url="$(jq -r '.url // ""' <<<"$pr")"

  # Every observable CI surface on the exact head must be green, not only the
  # named validate check. A green GitHub Actions run is never treated as full
  # success while another surface (e.g. an external provider's commit status)
  # reports failure.
  evaluate_ci_state "$repo" "$head_sha"
  if [[ "$CI_EVAL" == "failed" ]]; then
    retryable=true
    reason="$CI_EVAL_REASON"
    validate="$(jq -c '[.check_runs[] | select(.name == "validate")] | sort_by(.completed_at // "") | last // {}' <<<"$CI_CHECK_JSON")"
    validate_conclusion="$(jq -r '.conclusion // "not-present"' <<<"$validate")"
    runs="$(gh api "/repos/$repo/actions/runs?head_sha=$head_sha&per_page=20" 2>/dev/null || printf '%s' '{"workflow_runs":[]}')"
    ci_run_id="$(jq -r '[.workflow_runs[] | select(.name == "enterprise-agent-validation")] | sort_by(.created_at) | last | (.id // "")' <<<"$runs")"
    emit ci_run_id "$ci_run_id"
    emit_ci_failure_comment "$pr_url" "$reason"
    return 1
  fi

  checks="$CI_CHECK_JSON"
  validate="$(jq -c '[.check_runs[] | select(.name == "validate")] | sort_by(.completed_at // "") | last // {}' <<<"$checks")"
  if [[ "$(jq -r '.conclusion // ""' <<<"$validate")" == "success" && "$CI_EVAL" == "verified" ]]; then
    verified=true
    verified_sha="$head_sha"
    return 0
  fi

  # Neither failed nor fully verified yet: still pending somewhere.
  status="$(jq -r '.status // ""' <<<"$validate")"
  if [[ "$CI_EVAL" == "pending" || "$status" == "queued" || "$status" == "in_progress" || "$status" == "" ]]; then
    return 2
  fi

  retryable=true
  reason="required validate check is $(jq -r '.conclusion // "unknown"' <<<"$validate")"
  runs="$(gh api "/repos/$repo/actions/runs?head_sha=$head_sha&per_page=20" 2>/dev/null || printf '%s' '{"workflow_runs":[]}')"
  ci_run_id="$(jq -r '[.workflow_runs[] | select(.name == "enterprise-agent-validation")] | sort_by(.created_at) | last | (.id // "")' <<<"$runs")"
  emit ci_run_id "$ci_run_id"
  emit_ci_failure_comment "$pr_url" "$reason"
  return 1
}

emit_ci_failure_comment() {
  local pr_display="$1" failure_reason="$2"
  if [[ "$failure_commented" == "true" ]]; then
    return 0
  fi
  failure_commented=true
  if [[ "$target" == "0" ]]; then
    return 0
  fi
  local ci_display="$ci_run_id"; [[ -n "$ci_display" ]] || ci_display="unknown"
  # Durable idempotency: if a prior attempt already posted a CI-failure
  # comment for this exact run id, do not duplicate it on a later attempt.
  if [[ "$ci_display" != "unknown" ]] && issue_comments_marker "<!-- oc-ci-failure-run-id:$ci_display "; then
    echo "CI-failure comment for run $ci_display already exists; skipping duplicate."
    return 0
  fi
  local safe_tail=""
  if [[ "$ci_run_id" =~ ^[0-9]+$ ]]; then
    safe_tail="$(gh run view "$ci_run_id" --log-failed 2>/dev/null | tail -n 120 || true)"
    safe_tail="$(printf '%s' "$safe_tail" | sed -E         -e 's/(gh[ps]_[[:alnum:]_]{20,}|github_pat_[[:alnum:]_]{20,})/[REDACTED_GITHUB_TOKEN]/g'         -e 's/(sk-or-v1-[[:alnum:]_-]{20,})/[REDACTED_EXTERNAL_API_KEY]/g'         -e 's/Bearer[[:space:]]+[^[:space:]]+/Bearer [REDACTED]/g')"
  fi
  [[ -n "$pr_display" ]] || pr_display="not identified"
  local evidence="$safe_tail"; [[ -n "$evidence" ]] || evidence="No sanitized CI log was available."
  gh issue comment "$target" --body "$(cat <<EOF
<!-- oc-ci-failure-run-id:$ci_display attempt:$attempt -->
## /oc CI verification found a failure

Provider: $provider
Attempt: $attempt
PR: $pr_display
Required check: validate (all observable CI surfaces must be green)
Reason: $failure_reason

Inspect this exact CI evidence and continue from the current repository/PR state rather than creating duplicate work.

Sanitized failure evidence:
$evidence
EOF
)"
}

deadline=$((SECONDS + wait_minutes * 60))
pending=false
settle_done=false
while :; do
  pending=false
  local_verified_candidate=""
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    if check_pr "$n" 0; then
      local_verified_candidate="$n"
      break
    else
      rc=$?
      [[ "$rc" -eq 2 ]] && pending=true
    fi
  done <<<"$branch_candidate_prs"
  if [[ -z "$local_verified_candidate" ]]; then
    while IFS= read -r n; do
      [[ -n "$n" ]] || continue
      if check_pr "$n" 1; then
        local_verified_candidate="$n"
        break
      else
        rc=$?
        [[ "$rc" -eq 2 ]] && pending=true
      fi
    done <<<"$scan_candidate_prs"
  fi
  if [[ -n "$local_verified_candidate" ]]; then
    # Late-status settle: a green snapshot only becomes verified after the
    # same all-surface state is re-confirmed after a bounded settle window,
    # so a late external status cannot silently flip the result.
    if [[ "$settle_done" == "false" && "$settle_seconds" -gt 0 && "$SECONDS" -lt "$deadline" ]]; then
      settle_done=true
      sleep "$settle_seconds"
      continue
    fi
    verified=true
    break
  fi
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
  [[ -n "$verified_sha" ]] && emit verified_sha "$verified_sha"
  emit ci_observation_end "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
  reason="required validate check or CI status remained pending beyond the verification wait window"
  timed_out=true
fi
if [[ -z "$reason" ]]; then
  # The agent published (or attempted to publish) work but none of the
  # candidate pull requests ended up verifiably green in this run's window.
  # Surface a concrete reason so the run failure is never a silent red step.
  reason="no candidate pull request was verifiably green on its exact head within this run window"
  [[ "$retryable" == "true" ]] || retryable=true
fi
if [[ "$retryable" == "true" && "$provider" == "opencode" ]]; then
  echo "OPENCODE_RETRY_CURRENT_ROUTE=1" >> "$GITHUB_ENV"
fi
emit verified false
emit retryable "$retryable"
emit timed_out "$timed_out"
[[ -n "$pr_url" ]] && emit pr_url "$pr_url"
[[ -n "$verified_sha" ]] && emit verified_sha "$verified_sha"
emit ci_observation_end "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "::warning title=Agent completion not independently verified::$reason" >&2
if [[ "$failure_commented" != "true" && "$target" != "0" ]] && ! issue_comments_marker "<!-- oc-unverified-run-id:$run_id "; then
  gh issue comment "$target" --body "<!-- oc-unverified-run-id:$run_id attempt:$attempt -->
## /oc agent completed but publication could not be independently verified

Provider: $provider
Attempt: $attempt
Reason: $reason

The agent reported completion, but no published pull request on this repository
was verifiably green on its exact head inside this run's verification window.
No success is claimed. Inspect the open pull requests and their exact-SHA CI
state before continuing." 2>/dev/null || true
fi
exit 1
