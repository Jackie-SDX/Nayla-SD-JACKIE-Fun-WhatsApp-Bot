#!/usr/bin/env bash
set -euo pipefail
# Regression: oc-command-control.sh must decide from the classification written
# to $GITHUB_OUTPUT in the SAME step (select-oc-task-mode.sh only publishes to
# files, not the current shell), so prepare-oc-session.sh actually runs and the
# durable session branch is published for later steps.
#
# It also proves the controller only performs mechanical lifecycle work: it
# enters/materializes the durable session when — and only when — the request
# requires session handling, and it never probes capabilities or write
# permissions to decide whether the agent may start.
tmp="$(mktemp -d)"
head_sha="$(git rev-parse HEAD)"
# Hermetic git state: pre-create the durable branch locally so
# prepare-oc-session.sh uses it instead of branching from origin/main.
git branch oc/session-42 "$head_sha" 2>/dev/null || true
git branch -D oc/session-99 >/dev/null 2>&1 || true
trap '
  git branch -D oc/session-42 >/dev/null 2>&1 || true
  git branch -D oc/session-99 >/dev/null 2>&1 || true
  rm -rf "$tmp"
' EXIT

# The running agent session inherits the controller's exported OC_* contract
# (OC_SESSION_BRANCH, OC_COMMAND_TEXT, …). Those must not leak into the scripts
# under test, otherwise a request would inherit a stale durable session.
while IFS='=' read -r leaked _; do
  case "$leaked" in OC_*|SESSION_*) unset "$leaked" 2>/dev/null || true ;; esac
done < <(env)

cat > "$tmp/event.json" <<'JSON'
{"comment":{"body":"/oc implement a durable-session regression fix"}}
JSON

GITHUB_EVENT_PATH="$tmp/event.json" \
GITHUB_REPOSITORY=example/repo \
GITHUB_OUTPUT="$tmp/out" \
GITHUB_ENV="$tmp/env" \
RUNNER_TEMP="$tmp" \
TARGET_NUMBER=42 \
OC_SESSION_STATE_FILE="$tmp/state.json" \
bash .github/scripts/oc-command-control.sh >/dev/null

grep -Fq 'OC_TASK_MODE=code' "$tmp/env"
grep -Fq 'OC_SESSION_REQUIRED=true' "$tmp/env"
if ! grep -Eq '^OC_SESSION_BRANCH=[^[:space:]]+$' "$tmp/env"; then
  echo "oc-command-control.sh did not publish OC_SESSION_BRANCH (prepare-oc-session.sh skipped)." >&2
  exit 1
fi
session_branch="$(sed -nE 's/^OC_SESSION_BRANCH=//p' "$tmp/env" | tail -n 1)"
[[ "$session_branch" == "oc/session-42" ]]
grep -Fq 'oc/session-42' "$tmp/state.json"
grep -Fq '"phase"' "$tmp/state.json"
echo "oc-command-control.sh same-step durable-session bootstrap: OK ($session_branch)"

# No controller-side capability/write-permission probe remains.
if grep -Eq 'permissions\.push|Capability probe failed|Write capability unavailable|Target repository is archived|OC_CAPABILITY_(PUSH|TARGET)|gh api "/repos/' \
  .github/scripts/oc-command-control.sh; then
  echo "oc-command-control.sh still probes capabilities or write permissions." >&2
  exit 1
fi

# A durable session loaded from earlier state must be reachable through a stub
# gh so the lifecycle rules below can be exercised hermetically.
stub_bin="$tmp/stub-bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'FAKEGH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"--arg marker"*) printf '%s\n' '99' ;;
  *"issues/comments/99"*) cat "${FAKE_STATE_BODY:?}" ;;
  *) exit 0 ;;
esac
FAKEGH
chmod +x "$stub_bin/gh"

write_durable_state() { # write_durable_state <path>
  cat > "$1" <<STATE
<!-- oc-session-state:v1 issue:42 -->

STATE-BEGIN
{"schema_version":1,"session_id":"oc-42","repository":"example/repo","issue":42,"base_ref":"main","active_branch":"oc/session-99","active_pr_number":0,"active_pr_url":"","active_head_sha":"$head_sha","goal":"earlier session","milestone":"complete","phase":"complete","status":"complete","state_revision":4,"capabilities":{"push":false,"target":""},"last_verified_sha":"","last_verified_evidence":"","created_at":"2026-09-26T00:00:00Z","updated_at":"2026-09-26T00:00:00Z","last_processed_comment_id":0,"current_request":"","completed_steps":[],"remaining_steps":[],"tests_run":[],"ci_runs":[],"research_sources":[],"copilot":{"status":"not_started","rounds":0},"warnings":[],"artifacts":[],"next_action":"await user direction","durable_work":true,"last_checkpoint_at":"2026-09-26T00:00:00Z"}
STATE-END
<!-- /oc-session-state -->
STATE
}

# Ordinary request: the durable session of an earlier task must NOT be entered.
# The branch stays out of the checkout and is cleared for later steps, so the
# attempt runs against the current revision instead of a stale session branch.
cat > "$tmp/event-trivial.json" <<'JSON'
{"comment":{"body":"/oc hello"}}
JSON
write_durable_state "$tmp/durable-state.json"

PATH="$stub_bin:$PATH" \
FAKE_STATE_BODY="$tmp/durable-state.json" \
GITHUB_EVENT_PATH="$tmp/event-trivial.json" \
GITHUB_REPOSITORY=example/repo \
GITHUB_OUTPUT="$tmp/out2" \
GITHUB_ENV="$tmp/env2" \
RUNNER_TEMP="$tmp" \
TARGET_NUMBER=42 \
OC_SESSION_STATE_FILE="$tmp/state2.json" \
bash .github/scripts/oc-command-control.sh >/dev/null

grep -Fq 'OC_TASK_MODE=code' "$tmp/env2"
grep -Fq 'OC_SESSION_REQUIRED=false' "$tmp/env2"
[[ "$(grep -E '^OC_SESSION_BRANCH=' "$tmp/env2" | tail -n 1)" == 'OC_SESSION_BRANCH=' ]]
if git show-ref --verify --quiet refs/heads/oc/session-99; then
  echo "oc-command-control.sh entered a durable session for an ordinary request." >&2
  exit 1
fi
echo "oc-command-control.sh ordinary request runs on the current checkout: OK"

# Session request: a known durable branch that is missing locally must still be
# materialized, so the attempt can always resolve it.
cat > "$tmp/event-session.json" <<'JSON'
{"comment":{"body":"/oc fix the parser"}}
JSON
write_durable_state "$tmp/durable-state-session.json"

PATH="$stub_bin:$PATH" \
FAKE_STATE_BODY="$tmp/durable-state-session.json" \
GITHUB_EVENT_PATH="$tmp/event-session.json" \
GITHUB_REPOSITORY=example/repo \
GITHUB_OUTPUT="$tmp/out3" \
GITHUB_ENV="$tmp/env3" \
RUNNER_TEMP="$tmp" \
TARGET_NUMBER=42 \
OC_SESSION_STATE_FILE="$tmp/state3.json" \
bash .github/scripts/oc-command-control.sh >/dev/null

grep -Fq 'OC_SESSION_REQUIRED=true' "$tmp/env3"
grep -Fq 'OC_SESSION_BRANCH=oc/session-99' "$tmp/env3"
if ! git show-ref --verify --quiet refs/heads/oc/session-99; then
  echo "oc-command-control.sh did not materialize the known durable branch oc/session-99." >&2
  exit 1
fi
echo "oc-command-control.sh durable session resume: OK (oc/session-99)"
echo "oc-command-control.sh capability-gate-free lifecycle: OK"
