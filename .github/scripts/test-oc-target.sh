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
git -C "$GUARD_REPO" commit -q --allow-empty -m init
# (a) embedded git repository fixture (the exact failure mode of the prior run)
mkdir -p "$GUARD_REPO/.octmp/octest/target"
git -C "$GUARD_REPO/.octmp/octest/target" init -q -b main
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

printf '\nremote-target contract tests: %s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]