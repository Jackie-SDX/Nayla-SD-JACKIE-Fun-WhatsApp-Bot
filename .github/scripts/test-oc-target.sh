#!/usr/bin/env bash
# Deterministic offline contract tests for the /oc remote-target control plane.
#
# Covers: target parsing (explicit url/owner-repo selectors), local-mode
# preservation, /oc continue durable-marker recovery, target-policy isolation,
# stable resumable branch behavior, and the nested-Git/temporary-tree
# publication guard that blocked the earlier failing run.
#
# All fixtures live under mktemp directories and are removed on exit; nothing
# is ever created inside the controller worktree.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$ROOT_DIR/.github/scripts"
TESTS="$(mktemp -d "${RUNNER_TEMP:-/tmp}/oc-target-tests-XXXXXX")"
cleanup() { rm -rf "$TESTS"; }
trap cleanup EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; }
check() { # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

new_output_files() {
  GITHUB_OUTPUT="$TESTS/out-$1"; GITHUB_ENV="$TESTS/env-$1"
  : > "$GITHUB_OUTPUT"; : > "$GITHUB_ENV"
}

# ---------------------------------------------------------------------------
# 1. resolve-oc-target.sh
# ---------------------------------------------------------------------------
make_event() { # make_event <name> <body>
  jq -n --arg body "$2" '{comment:{body:$body}}' > "$TESTS/event-$1.json"
}

new_output_files resolver-local
make_event local "/oc explain this issue"
GITHUB_EVENT_PATH="$TESTS/event-local.json" \
GITHUB_REPOSITORY="Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot" \
TARGET_NUMBER=0 bash "$SCRIPTS/resolve-oc-target.sh"
if [[ "$(grep -E '^mode=' "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2)" == "local" ]] \
   && grep -Eq '^target_repo=$' "$GITHUB_OUTPUT" \
   && ! grep -q 'OC_TARGET_REPO=' "$GITHUB_ENV"; then
  ok "local mode preserved with full task for a plain /oc comment"
else
  bad "local mode preserved with full task for a plain /oc comment"
fi

new_output_files resolver-url
make_event url "/oc fix the bug https://github.com/Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot"
GITHUB_EVENT_PATH="$TESTS/event-url.json" \
GITHUB_REPOSITORY="Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot" \
TARGET_NUMBER=0 bash "$SCRIPTS/resolve-oc-target.sh"
grep -q '^mode=remote$' "$GITHUB_OUTPUT" && \
grep -q '^target_repo=Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot$' "$GITHUB_OUTPUT" && \
grep -q 'OC_TARGET_TASK=fix the bug' "$GITHUB_ENV" \
  && ok "explicit https://github.com/OWNER/REPO url is parsed into remote mode" \
  || bad "explicit https://github.com/OWNER/REPO url is parsed into remote mode"

new_output_files resolver-task-text
make_event task-text "/oc target=Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot Task: fix repository: parser behavior and inspect https://example.com/docs"
GITHUB_EVENT_PATH="$TESTS/event-task-text.json" \
GITHUB_REPOSITORY="o/x" TARGET_NUMBER=0 bash "$SCRIPTS/resolve-oc-target.sh"
grep -q '^mode=remote$' "$GITHUB_OUTPUT" && \
grep -q '^target_repo=Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot$' "$GITHUB_OUTPUT" && \
grep -q 'OC_TARGET_TASK=Task: fix repository: parser behavior and inspect https://example.com/docs' "$GITHUB_ENV" \
  && ok "explicit target preserves colon-containing task text and ordinary URLs" \
  || bad "explicit target preserves colon-containing task text and ordinary URLs"

for form in "repo=Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot" "repository=Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot" "target=Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot"; do
  key="${form%%=*}"
  new_output_files "resolver-$key"
  make_event "form-$key" "/oc $form do the thing"
  GITHUB_EVENT_PATH="$TESTS/event-form-$key.json" \
  GITHUB_REPOSITORY="o/x" TARGET_NUMBER=0 bash "$SCRIPTS/resolve-oc-target.sh"
  grep -q '^mode=remote$' "$GITHUB_OUTPUT" && \
  grep -q '^target_repo=Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot$' "$GITHUB_OUTPUT" && \
  grep -q 'OC_TARGET_TASK=do the thing' "$GITHUB_ENV" \
    && ok "selector '$form' parses into remote mode" \
    || bad "selector '$form' parses into remote mode"
done

new_output_files resolver-flag
make_event flag "/oc --repo Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot --base feature/x implement it"
GITHUB_EVENT_PATH="$TESTS/event-flag.json" \
GITHUB_REPOSITORY="o/x" TARGET_NUMBER=0 bash "$SCRIPTS/resolve-oc-target.sh"
grep -q '^mode=remote$' "$GITHUB_OUTPUT" && \
grep -q '^target_repo=Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot$' "$GITHUB_OUTPUT" && \
grep -q '^target_base=feature/x$' "$GITHUB_OUTPUT" && \
grep -q 'OC_TARGET_TASK=implement it' "$GITHUB_ENV" \
  && ok "--repo/--base flag form parses into remote mode" \
  || bad "--repo/--base flag form parses into remote mode"

new_output_files resolver-bad
make_event bad "/oc repo=Alice/One repo=Bob/Two do the thing"
if GITHUB_EVENT_PATH="$TESTS/event-bad.json" GITHUB_REPOSITORY="o/x" TARGET_NUMBER=0 \
   bash "$SCRIPTS/resolve-oc-target.sh" >"$TESTS/bad.log" 2>&1; then
  bad "conflicting remote targets are refused"
else
  ok "conflicting remote targets are refused"
fi

new_output_files resolver-continue
cat > "$TESTS/comments-continue.json" <<'JSON'
[
  {"created_at":"2026-09-20T10:00:00Z","body":"/oc do a remote task"},
  {"created_at":"2026-09-20T11:00:00Z","body":"<!-- oc-target-repo:Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot base:main branch:oc/remote-Jackie-SDX-something -->\n<!-- oc-checkpoint-run-id:1 issue:3 -->\ncheckpoint"}
]
JSON
make_event cont "/oc continue"
GITHUB_EVENT_PATH="$TESTS/event-cont.json" \
GITHUB_REPOSITORY="o/x" TARGET_NUMBER=3 OC_TARGET_COMMENTS_FILE="$TESTS/comments-continue.json" \
bash "$SCRIPTS/resolve-oc-target.sh"
grep -q '^mode=remote$' "$GITHUB_OUTPUT" && \
grep -q '^resume=1$' "$GITHUB_OUTPUT" && \
grep -q '^from_marker=1$' "$GITHUB_OUTPUT" && \
grep -q '^target_branch=oc/remote-Jackie-SDX-something$' "$GITHUB_OUTPUT" \
  && ok "/oc continue restores the durable remote-target marker (target-aware resume)" \
  || bad "/oc continue restores the durable remote-target marker (target-aware resume)"

# ---------------------------------------------------------------------------
# 2. prepare-oc-target.sh isolation + stable, resumable branch
# ---------------------------------------------------------------------------
TARGET_SRC="$TESTS/target-src"
CONTROLLER="$TESTS/controller"
mkdir -p "$TARGET_SRC/.opencode/agents" "$TARGET_SRC/plugins" "$CONTROLLER/.opencode/agents"
git -C "$TARGET_SRC" init -q -b main
git -C "$TARGET_SRC" config user.name "fixture"
git -C "$TARGET_SRC" config user.email "fixture@example.com"
printf 'target instructions\n' > "$TARGET_SRC/.opencode/instructions.md"
printf '{target:true}\n' > "$TARGET_SRC/opencode.json"
printf 'trust me\n'      > "$TARGET_SRC/AGENTS.md"
printf 'plugin\n'        > "$TARGET_SRC/plugins/thing.js"
printf 'code\n'          > "$TARGET_SRC/code.txt"
git -C "$TARGET_SRC" add -A && git -C "$TARGET_SRC" commit -qm init
printf '{controller:true}\n' > "$CONTROLLER/opencode.json"
printf 'controller enterprise policy\n' > "$CONTROLLER/.opencode/instructions.md"
printf 'critic rules\n' > "$CONTROLLER/.opencode/agents/critic.md"
FAKE_TOKEN="ghp_test000000000000000000000000"

run_prepare() { # run_prepare <name> <task> [extra_env...]
  local name="$1" task="$2"; shift 2
  GITHUB_OUTPUT="$TESTS/prep-out-$name"; GITHUB_ENV="$TESTS/prep-env-$name"
  : > "$GITHUB_OUTPUT"; : > "$GITHUB_ENV"
  OC_TARGET_REPO="Jackie-SDX/SomeRepo" OC_TARGET_BASE="main" OC_TARGET_TASK="$task" \
  OC_CONTROLLER_ROOT="$CONTROLLER" RUNNER_TEMP="$TESTS" \
  OC_TARGET_CLONE_URL="file://$TARGET_SRC" GH_TOKEN="$FAKE_TOKEN" \
  GITHUB_ENV="$GITHUB_ENV" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
  bash "$SCRIPTS/prepare-oc-target.sh" "$@" >"$TESTS/prep-run-$name.log" 2>&1
}

run_prepare first "add a feature" || bad "prepare-oc-target.sh first run"
ws1="$(grep -E '^OC_TARGET_WORKSPACE=' "$TESTS/prep-env-first" | cut -d= -f2 | tail -1)"
branch1="$(grep -E '^OC_TARGET_BRANCH=' "$TESTS/prep-env-first" | cut -d= -f2 | tail -1)"
if [[ -n "$ws1" ]] && [[ "$(cat "$ws1/opencode.json")" == "$(cat "$CONTROLLER/opencode.json")" && "$(cat "$ws1/.opencode/instructions.md")" == "controller enterprise policy" ]]; then
  ok "controller OpenCode config and instructions are authoritative in the target workspace"
else
  bad "controller OpenCode config and instructions are authoritative in the target workspace"
fi
if [[ -f "$ws1/.opencode/agents/critic.md" ]]; then
  ok "controller critic agent is installed in the target workspace"
else
  bad "controller critic agent is installed in the target workspace"
fi
if [[ ! -e "$ws1/AGENTS.md" && ! -e "$ws1/plugins" && "$(cat "$ws1/.opencode/instructions.md")" == "controller enterprise policy" ]]; then
  ok "target-owned AGENTS.md/plugins/.opencode policy is quarantined away from the run"
else
  bad "target-owned AGENTS.md/plugins/.opencode policy is quarantined away from the run"
fi

# second identical task must derive the same stable branch
run_prepare second "add a feature"
branch2="$(grep -E '^OC_TARGET_BRANCH=' "$TESTS/prep-env-second" | cut -d= -f2 | tail -1)"
if [[ -n "$branch1" && "$branch1" == "$branch2" ]]; then
  ok "target branch is stable and deterministic for the same task"
else
  bad "target branch is stable and deterministic for the same task"
fi

# simulate a previously pushed branch -> resume must reuse it
git -C "$TARGET_SRC" checkout -q -b "$branch1" >/dev/null 2>&1 || git -C "$TARGET_SRC" branch -q "$branch1"
run_prepare third "add a feature"
resume3="$(grep -E '^OC_TARGET_RESUME=' "$TESTS/prep-env-third" | cut -d= -f2 | tail -1)"
branch3="$(grep -E '^OC_TARGET_BRANCH=' "$TESTS/prep-env-third" | cut -d= -f2 | tail -1)"
if [[ "$resume3" == "1" && "$branch3" == "$branch1" ]]; then
  ok "existing remote target branch is resumed (resume=1, same branch); no duplicate work"
else
  bad "existing remote target branch is resumed (resume=1, same branch); no duplicate work"
fi

# ---------------------------------------------------------------------------
# 3. publication guard: nested Git repos and .octmp can never be staged
# ---------------------------------------------------------------------------
GUARD_REPO="$TESTS/guard-repo"
mkdir -p "$GUARD_REPO"
git -C "$GUARD_REPO" init -q -b main
git -C "$GUARD_REPO" config user.name "fixture"
git -C "$GUARD_REPO" config user.email "fixture@example.com"
git -C "$GUARD_REPO" commit -q --allow-empty -m init
# (a) embedded git repository fixture (the exact failure mode of the prior run)
mkdir -p "$GUARD_REPO/.octmp/octest/target"
git -C "$GUARD_REPO/.octmp/octest/target" init -q -b main
git -C "$GUARD_REPO/.octmp/octest/target" config user.name "fixture"
git -C "$GUARD_REPO/.octmp/octest/target" config user.email "fixture@example.com"
printf 'fixture\n' > "$GUARD_REPO/.octmp/octest/target/x.txt"
git -C "$GUARD_REPO/.octmp/octest/target" add -A
git -C "$GUARD_REPO/.octmp/octest/target" commit -qm fixture
if ! bash -c 'source "$0/oc-publish-lib.sh" && oc_guard_repo_publication "$1"' "$SCRIPTS" "$GUARD_REPO" >/dev/null 2>&1; then
  ok "publication guard refuses a nested Git repository (mode 160000 gitlink) under .octmp/"
else
  bad "publication guard refuses a nested Git repository (mode 160000 gitlink) under .octmp/"
fi
if git -C "$GUARD_REPO" ls-files | grep -q '^\.octmp/'; then
  bad "nested .octmp fixture is never left staged after the guard refuses"
else
  ok "nested .octmp fixture is never left staged after the guard refuses"
fi
# (b) plain untracked scratch under .octmp (no nested repo) must also be refused
rm -rf "$GUARD_REPO/.octmp"
mkdir -p "$GUARD_REPO/.octmp"
printf 'scratch\n' > "$GUARD_REPO/.octmp/scrap.txt"
if ! bash -c 'source "$0/oc-publish-lib.sh" && oc_guard_repo_publication "$1"' "$SCRIPTS" "$GUARD_REPO" >/dev/null 2>&1; then
  ok "publication guard refuses untracked .octmp/ scratch"
else
  bad "publication guard refuses untracked .octmp/ scratch"
fi
# (c) a legitimate change still passes the guard
rm -rf "$GUARD_REPO/.octmp"
printf 'real change\n' > "$GUARD_REPO/code.txt"
if bash -c 'source "$0/oc-publish-lib.sh" && oc_guard_repo_publication "$1" && git -C "$1" diff --cached --name-only' "$SCRIPTS" "$GUARD_REPO" >/dev/null 2>&1; then
  ok "publication guard allows a legitimate, secret-free change"
else
  bad "publication guard allows a legitimate, secret-free change"
fi

# no fixtures can ever appear in the controller worktree
if [[ -e "$ROOT_DIR/.octmp" ]]; then
  bad "controller worktree contains an .octmp fixture (should be impossible; tests are isolated)"
else
  ok "controller worktree is free of .octmp fixtures after the contract tests"
fi

# ---------------------------------------------------------------------------
# 4. remote verifier exact-head regression tests
# ---------------------------------------------------------------------------
VERIFY_WS="$TESTS/verify-target"
FAKE_BIN="$TESTS/fake-bin"
mkdir -p "$VERIFY_WS" "$FAKE_BIN"
git -C "$VERIFY_WS" init -q -b main
git -C "$VERIFY_WS" config user.name "fixture"
git -C "$VERIFY_WS" config user.email "fixture@example.com"
printf 'workspace base\n' > "$VERIFY_WS/base.txt"
git -C "$VERIFY_WS" add base.txt
git -C "$VERIFY_WS" commit -qm base
LOCAL_VERIFY_SHA="$(git -C "$VERIFY_WS" rev-parse HEAD)"
EXPECTED_VERIFY_SHA="2222222222222222222222222222222222222222"

cat > "$FAKE_BIN/gh" <<'FAKEGH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"pr list"*)
    printf '%s\n' '[{"number":1,"url":"https://github.com/fixture/target/pull/1","state":"OPEN","mergedAt":null,"headRefOid":"2222222222222222222222222222222222222222"}]'
    ;;
  *"/git/ref/heads/"*)
    printf '%s\n' '{"object":{"sha":"2222222222222222222222222222222222222222"}}'
    ;;
  *"/commits/"*"/check-runs"*)
    if [[ "${FAKE_GH_FAIL:-0}" == "1" ]]; then
      printf '%s\n' '{"check_runs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"failure"}]}'
    else
      printf '%s\n' '{"check_runs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"skipped"}]}'
    fi
    ;;
  *"/commits/"*"/status"*)
    case "${FAKE_GH_STATUS_MODE:-ok}" in
      fail)
        printf '%s\n' '{"state":"failure","total_count":1,"statuses":[{"context":"ci/circleci","state":"failure"}]}'
        ;;
      pending)
        printf '%s\n' '{"state":"pending","total_count":1,"statuses":[{"context":"ci/circleci","state":"pending"}]}'
        ;;
      *)
        printf '%s\n' '{"state":"success","total_count":1,"statuses":[{"context":"ci/circleci","state":"success"}]}'
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
FAKEGH
chmod +x "$FAKE_BIN/gh"

new_output_files verifier-head-mismatch
if PATH="$FAKE_BIN:$PATH" \
   GITHUB_REPOSITORY="fixture/controller" PROVIDER="opencode" ATTEMPT="1" TARGET_NUMBER=0 BASE_REF="main" \
   INITIAL_SHA="$LOCAL_VERIFY_SHA" GITHUB_RUN_ID=1 GITHUB_OUTPUT="$GITHUB_OUTPUT" \
   OC_TARGET_MODE="remote" OC_TARGET_REPO="fixture/target" OC_TARGET_BASE="main" \
   OC_TARGET_BRANCH="oc/test" OC_TARGET_WORKSPACE="$VERIFY_WS" EXPECTED_TARGET_HEAD="$EXPECTED_VERIFY_SHA" \
   OC_CI_VERIFY_WAIT_MINUTES=0 OC_CI_VERIFY_POLL_SECONDS=5 OC_CI_VERIFY_SETTLE_SECONDS=0 \
   bash "$SCRIPTS/verify-agent-result.sh" >/dev/null 2>&1; then
  ok "remote verifier accepts exact target PR/check head when local workspace SHA differs"
else
  bad "remote verifier accepts exact target PR/check head when local workspace SHA differs"
fi
grep -q "^ci_surfaces=check-runs,commit-status$" "$GITHUB_OUTPUT" \
  && ok "remote verifier records the observed CI surfaces (check-runs + commit statuses)" \
  || bad "remote verifier records the observed CI surfaces (check-runs + commit statuses)"
grep -q "^verified_sha=$EXPECTED_VERIFY_SHA$" "$GITHUB_OUTPUT" \
  && ok "remote verifier records the exact verified SHA in its output" \
  || bad "remote verifier records the exact verified SHA in its output"

new_output_files verifier-status-fail
if PATH="$FAKE_BIN:$PATH" FAKE_GH_STATUS_MODE=fail \
   GITHUB_REPOSITORY="fixture/controller" PROVIDER="opencode" ATTEMPT="1" TARGET_NUMBER=0 BASE_REF="main" \
   INITIAL_SHA="$LOCAL_VERIFY_SHA" GITHUB_RUN_ID=1 GITHUB_OUTPUT="$GITHUB_OUTPUT" \
   OC_TARGET_MODE="remote" OC_TARGET_REPO="fixture/target" OC_TARGET_BASE="main" \
   OC_TARGET_BRANCH="oc/test" OC_TARGET_WORKSPACE="$VERIFY_WS" EXPECTED_TARGET_HEAD="$EXPECTED_VERIFY_SHA" \
   OC_CI_VERIFY_WAIT_MINUTES=0 OC_CI_VERIFY_POLL_SECONDS=5 OC_CI_VERIFY_SETTLE_SECONDS=0 \
   bash "$SCRIPTS/verify-agent-result.sh" >/dev/null 2>&1; then
  bad "remote verifier fails closed when an external status provider reports failure on the same SHA"
else
  ok "remote verifier fails closed when an external status provider reports failure on the same SHA"
fi

new_output_files verifier-status-pending
if PATH="$FAKE_BIN:$PATH" FAKE_GH_STATUS_MODE=pending \
   GITHUB_REPOSITORY="fixture/controller" PROVIDER="opencode" ATTEMPT="1" TARGET_NUMBER=0 BASE_REF="main" \
   INITIAL_SHA="$LOCAL_VERIFY_SHA" GITHUB_RUN_ID=1 GITHUB_OUTPUT="$GITHUB_OUTPUT" \
   OC_TARGET_MODE="remote" OC_TARGET_REPO="fixture/target" OC_TARGET_BASE="main" \
   OC_TARGET_BRANCH="oc/test" OC_TARGET_WORKSPACE="$VERIFY_WS" EXPECTED_TARGET_HEAD="$EXPECTED_VERIFY_SHA" \
   OC_CI_VERIFY_WAIT_MINUTES=0 OC_CI_VERIFY_POLL_SECONDS=5 OC_CI_VERIFY_SETTLE_SECONDS=0 \
   bash "$SCRIPTS/verify-agent-result.sh" >/dev/null 2>&1; then
  bad "remote verifier waits for a pending external status instead of declaring success"
else
  ok "remote verifier waits for a pending external status instead of declaring success"
fi
grep -q "^timed_out=true$" "$GITHUB_OUTPUT" \
  && ok "remote verifier marks an unresolved pending status as timed out, never green" \
  || bad "remote verifier marks an unresolved pending status as timed out, never green"

new_output_files verifier-mixed-fail
if PATH="$FAKE_BIN:$PATH" FAKE_GH_FAIL=1 \
   GITHUB_REPOSITORY="fixture/controller" PROVIDER="opencode" ATTEMPT="1" TARGET_NUMBER=0 BASE_REF="main" \
   INITIAL_SHA="$LOCAL_VERIFY_SHA" GITHUB_RUN_ID=1 GITHUB_OUTPUT="$GITHUB_OUTPUT" \
   OC_TARGET_MODE="remote" OC_TARGET_REPO="fixture/target" OC_TARGET_BASE="main" \
   OC_TARGET_BRANCH="oc/test" OC_TARGET_WORKSPACE="$VERIFY_WS" EXPECTED_TARGET_HEAD="$EXPECTED_VERIFY_SHA" \
   OC_CI_VERIFY_WAIT_MINUTES=0 OC_CI_VERIFY_POLL_SECONDS=5 OC_CI_VERIFY_SETTLE_SECONDS=0 \
   bash "$SCRIPTS/verify-agent-result.sh" >/dev/null 2>&1; then
  bad "remote verifier rejects any failed check-run even when another check is green"
else
  ok "remote verifier rejects any failed check-run even when another check is green"
fi

# ---------------------------------------------------------------------------
# 5. durable failure-comment idempotency (cross-attempt, cross-process)
# ---------------------------------------------------------------------------
# Verifies the local verifier only ever posts ONE CI-failure comment per run id
# and ONE remote-verify-failed comment per (repo, branch), even when the same
# failure is verified once per attempt (attempt 1, 2, 3) in separate processes.
# Uses a stateful fake gh that records posted issue comments and replays them on
# the next invocation, exactly like the real GitHub API would.
DEDUPE_BIN="$TESTS/dedupe-bin"
mkdir -p "$DEDUPE_BIN"
DEDUPE_STATE="$TESTS/dedupe-state"
mkdir -p "$DEDUPE_STATE"

cat > "$DEDUPE_BIN/gh" <<'FAKE_DEDUPE'
#!/usr/bin/env bash
# Stateful fake gh: records `issue comment` bodies into a state file and serves
# them back through the comments list API, mirroring real GitHub behavior so the
# verifier can dedupe across processes/attempts.
set -euo pipefail
STATE="${DEDUPE_STATE_DIR:?}"
CMDS="$STATE/commands.log"
printf 'cmd: %s\n' "$*" >> "$CMDS"
POSTED="$STATE/posted-comments.json"
[[ -f "$POSTED" ]] || printf '[]\n' > "$POSTED"

# gh issue comment <issue> --body <body>
if [[ "$1" == "issue" && "$2" == "comment" ]]; then
  issue="$3"
  body="$5"
  python3 - "$POSTED" "$issue" "$body" <<'PY'
import json, sys
posted, issue, body = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(posted))
data.append({"issue": issue, "body": body})
json.dump(data, open(posted, "w"))
PY
  exit 0
fi

# gh api /repos/<repo>/issues/<n>/comments  (with --paginate --slurp, gh returns
# an array of pages; without it, a flat array. Mirror that so the verifier's
# `add // []` flattening and its direct array access both behave like GitHub.)
case "$*" in
  *"/issues/"*"/comments"*)
    if [[ "$*" == *"--paginate --slurp"* ]]; then
      printf '[%s]\n' "$(cat "$POSTED")"
    else
      cat "$POSTED"
    fi
    ;;
  *"/branches?per_page=100"*)
    printf '%s\n' '[[{"name":"main"},{"name":"opencode/issue7-fake-ts"}]]'
    ;;
  *"pr list"*)
    printf '%s\n' '[{"number":9,"url":"https://github.com/fixture/controller/pull/9","state":"OPEN","mergedAt":null,"headRefName":"opencode/issue7-fake-ts","headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","baseRefName":"main","createdAt":"2026-09-21T00:00:00Z","updatedAt":"2026-09-21T00:00:00Z"}]'
    ;;
  *"pr view"*)
    printf '%s\n' '{"number":9,"url":"https://github.com/fixture/controller/pull/9","state":"OPEN","mergedAt":null,"headRefName":"opencode/issue7-fake-ts","headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","baseRefName":"main","createdAt":"2026-09-21T00:00:00Z"}'
    ;;
  *"/commits/"*"/check-runs"*)
    printf '%s\n' '{"check_runs":[{"name":"validate","status":"completed","conclusion":"failure"}]}'
    ;;
  *"/commits/"*"/status"*)
    printf '%s\n' '{"state":"success","total_count":0,"statuses":[]}'
    ;;
  *"/actions/runs?head_sha="*)
    printf '%s\n' '{"workflow_runs":[{"name":"enterprise-agent-validation","id":424242}]}'
    ;;
  *"run view"*)
    printf '%s\n' 'fake failure log line'
    ;;
  *) exit 0 ;;
esac
FAKE_DEDUPE
chmod +x "$DEDUPE_BIN/gh"

run_dedupe_verify() { # run_dedupe_verify <attempt> ; verifier exits 1 when it reports a failure, which is expected here
  local attempt="$1" rc
  new_output_files "dedupe-$attempt"
  rc=0
  ( cd "$VERIFY_WS" && PATH="$DEDUPE_BIN:$PATH" \
    DEDUPE_STATE_DIR="$DEDUPE_STATE" \
    GITHUB_REPOSITORY="fixture/controller" PROVIDER="opencode" ATTEMPT="$attempt" TARGET_NUMBER=7 BASE_REF="main" \
    INITIAL_SHA="$LOCAL_VERIFY_SHA" GITHUB_RUN_ID=1 GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    OC_TARGET_MODE=local OC_RUN_START_ISO="1970-01-01T00:00:00Z" \
    OC_CI_VERIFY_WAIT_MINUTES=0 OC_CI_VERIFY_POLL_SECONDS=5 OC_CI_VERIFY_SETTLE_SECONDS=0 \
    bash "$SCRIPTS/verify-agent-result.sh" >/dev/null 2>&1 ) || rc=$?
  echo "dedupe local-mode attempt $attempt verifier rc: $rc (expect 1)"
}

run_dedupe_verify 1
run_dedupe_verify 2
run_dedupe_verify 3
posted_count="$(jq 'length' "$DEDUPE_STATE/posted-comments.json" 2>/dev/null || echo 0)"

if [[ "$posted_count" == "1" ]]; then
  ok "durable CI-failure comment dedupe: exactly one comment across 3 separate verifier attempts"
else
  bad "durable CI-failure comment dedupe: expected 1 posted comment across 3 attempts, got $posted_count"
fi
if jq -e '.[0].body | contains("<!-- oc-ci-failure-run-id:424242 attempt:1 -->")' "$DEDUPE_STATE/posted-comments.json" >/dev/null 2>&1; then
  ok "durable CI-failure comment carries the run-id marker for exact-SHA auditing"
else
  bad "durable CI-failure comment carries the run-id marker for exact-SHA auditing"
fi

# Same idempotency for the remote-target failure notice: repeated attempts in
# separate processes post exactly one remote-verify-failed comment.
rm -f "$DEDUPE_STATE/posted-comments.json"
printf '[]\n' > "$DEDUPE_STATE/posted-comments.json"
run_remote_dedupe() {
  local attempt="$1" rc
  new_output_files "dedupe-remote-$attempt"
  rc=0
  ( cd "$VERIFY_WS" && PATH="$DEDUPE_BIN:$PATH" \
    DEDUPE_STATE_DIR="$DEDUPE_STATE" \
    GITHUB_REPOSITORY="fixture/controller" PROVIDER="opencode" ATTEMPT="$attempt" TARGET_NUMBER=7 BASE_REF="main" \
    INITIAL_SHA="$LOCAL_VERIFY_SHA" GITHUB_RUN_ID=1 GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    OC_TARGET_MODE=remote OC_TARGET_REPO="fixture/target" OC_TARGET_BASE="main" \
    OC_TARGET_BRANCH="oc/test2" OC_TARGET_WORKSPACE="$VERIFY_WS" EXPECTED_TARGET_HEAD="$EXPECTED_VERIFY_SHA" \
    OC_CI_VERIFY_WAIT_MINUTES=0 OC_CI_VERIFY_POLL_SECONDS=5 OC_CI_VERIFY_SETTLE_SECONDS=0 \
    bash "$SCRIPTS/verify-agent-result.sh" >/dev/null 2>&1 ) || rc=$?
  echo "dedupe remote-mode attempt $attempt verifier rc: $rc (expect 1)"
}
run_remote_dedupe 1
run_remote_dedupe 2
remote_posted="$(jq -r '[.[].body] | join("\n")' "$DEDUPE_STATE/posted-comments.json" 2>/dev/null | grep -c 'oc-remote-verify-failed' || true)"
if [[ "$remote_posted" == "1" ]]; then
  ok "durable remote-verify-failed comment dedupe: one notice across repeated attempts"
else
  bad "durable remote-verify-failed comment dedupe: expected 1, got ${remote_posted:-0}"
fi

printf '\nremote-target contract tests: %s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

# ---------------------------------------------------------------------------
# 6. post-oc-continuation.sh candidate filtering and jq interpolation
# ---------------------------------------------------------------------------
# Regression: the open-PR summary line must interpolate the jq values (escaped
# parens), not render literal "(.number)" text, so checkpoints actually name the
# agent-created PRs on /oc continue.
CONT_BIN="$TESTS/cont-bin"
mkdir -p "$CONT_BIN"
cat > "$CONT_BIN/gh" <<'FAKE_CONT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "issue" && "$2" == "comment" ]]; then
  printf 'ISSUE_COMMENT: %s\n' "$5"
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  printf '%s\n' '[{"number":9,"url":"https://github.com/fixture/controller/pull/9","headRefName":"opencode/issue7-fake-ts","headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","baseRefName":"main"},{"number":99,"url":"https://github.com/fixture/controller/pull/99","headRefName":"oc/copilot-7-abc","headRefOid":"cccccccccccccccccccccccccccccccccccccccc","baseRefName":"main"},{"number":10,"url":"https://github.com/fixture/controller/pull/10","headRefName":"opencode/issue8-other","headRefOid":"dddddddddddddddddddddddddddddddddddddddd","baseRefName":"main"}]'
  exit 0
fi
exit 0
FAKE_CONT
chmod +x "$CONT_BIN/gh"

new_output_files continuation
continuation_out="$( ( cd "$VERIFY_WS" && PATH="$CONT_BIN:$PATH" \
  GITHUB_REPOSITORY=fixture/controller TARGET_NUMBER=7 BASE_REF=main GITHUB_RUN_ID=424242 \
  GITHUB_OUTPUT="$GITHUB_OUTPUT" GITHUB_ENV="$GITHUB_ENV" \
  bash "$SCRIPTS/post-oc-continuation.sh" 2>/dev/null ) )"
if grep -Fq 'ISSUE_COMMENT: ' <<<"$continuation_out" \
   && grep -Fq 'https://github.com/fixture/controller/pull/9' <<<"$continuation_out" \
   && grep -Fq 'https://github.com/fixture/controller/pull/99' <<<"$continuation_out" \
   && ! grep -Fq '#(.number) (.url) (.headRefName) (.headRefOid)' <<<"$continuation_out"; then
  ok "continuation checkpoint reliably interpolates open-PR candidates (no literal jq operators)"
else
  bad "continuation checkpoint interpolates open-PR candidates (no literal jq operators)"
fi
if grep -Fq 'https://github.com/fixture/controller/pull/10' <<<"$continuation_out"; then
  bad "continuation checkpoint excludes PRs outside the target prefix"
else
  ok "continuation checkpoint excludes PRs outside the target prefix"
fi

printf '\nremote-target contract tests: %s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
