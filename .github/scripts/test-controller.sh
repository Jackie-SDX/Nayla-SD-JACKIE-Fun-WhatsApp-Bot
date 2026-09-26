#!/usr/bin/env bash
set -euo pipefail

# bash ignores `set -e` for a pipeline that begins with `!`, so a bare
# `! grep …` can never abort this suite. Route every negative assertion
# through these helpers so an unexpected match is a hard failure.
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
absent() { # absent <fixed-string> <path...>
  local needle="$1"; shift
  if grep -Fq -- "$needle" "$@"; then fail "expected '$needle' to be absent from: $*"; fi
}
absent_re() { # absent_re <extended-regex> <path...>
  local pattern="$1"; shift
  if grep -Eq -- "$pattern" "$@"; then fail "expected /$pattern/ to be absent from: $*"; fi
}
missing() { # missing <path>
  if [[ -e "$1" ]]; then fail "expected '$1' not to exist"; fi
}

test ! -e index.js
test ! -e package.json
test ! -e package-lock.json
test ! -e tools/pair.js
test -f Nayla/index.js
test -f Nayla/package.json
test -f Nayla/package-lock.json
test -f Nayla/tools/pair.js
test -f Nayla/scripts/test-agent-invariants.js
test -f Nayla/docs/NAYLA_PROJECT_DOCUMENTATION.md
jq empty opencode.json
grep -Fq "vars.OPENCODE_MODEL || 'opencode/mimo-v2.6-flash-free'" .github/workflows/opencode.yml
grep -Fq 'Run primary OpenCode attempt' .github/workflows/opencode.yml
bash -n .github/scripts/run-opencode-attempt.sh
grep -Fq 'agent_cmd=(opencode run --thinking --dir "$agent_cwd" --model "$model_name")' .github/scripts/run-opencode-attempt.sh
grep -Fq 'task_prompt="Execute the latest user request in the attached issue context.' .github/scripts/run-opencode-attempt.sh
grep -Fq 'agent_cmd+=(--file "$context_seed")' .github/scripts/run-opencode-attempt.sh
absent_re 'attempt_[23]|route_[123]|select-opencode-route|independent-audit-advisory|COPILOT|OPENROUTER|GEMINI' .github/workflows/opencode.yml
absent_re 'github-copilot|openrouter|GEMINI|GROQ|CEREBRAS|MISTRAL|record-model-memory|classify-provider-failure' .github/scripts/run-attempt-pipeline.sh .github/scripts/run-opencode-attempt.sh .opencode/instructions.md opencode.json
absent 'subagent_depth' opencode.json
missing .github/scripts/run-copilot-attempt.sh
missing .github/scripts/select-opencode-route.sh
echo 'controller invariants: PASS'

# One /oc comment -> one workflow execution: the triggering user comment is
# immutable (claimed with a reaction, never edited) and exactly one controller
# result comment is published per run.
grep -Fq 'group: oc-claim-${{ github.event.comment.id || github.run_id }}' .github/workflows/opencode.yml
grep -Fq 'group: oc-agent-${{ github.event.comment.id || github.run_id }}' .github/workflows/opencode.yml
absent 'Register /oc run marker' .github/workflows/opencode.yml
absent 'Human handoff when the primary agent stops without durable work' .github/workflows/opencode.yml
absent 'gh issue comment "$target" --body "$marker"' .github/scripts/claim-oc-command.sh
# Result publication runs through the authenticated API POST asserted below.
# The single `gh issue comment` call exists only behind the GH_COMMENT_FILE
# test seam; test-oc-communication.sh behaviorally proves which path runs.
grep -Fq 'if [[ -n "${GH_COMMENT_FILE:-}" ]]' .github/scripts/post-oc-result.sh
[[ "$(grep -Fc 'gh issue comment "$target" --body "$body"' .github/scripts/post-oc-result.sh)" -eq 1 ]]
# OpenCode prompt must be stdin so repeatable --file cannot consume it.
absent 'agent_cmd+=("$task_prompt")' .github/scripts/run-opencode-attempt.sh
grep -Fq 'agent_cmd+=(--file "$context_seed")' .github/scripts/run-opencode-attempt.sh
grep -Fq '< <(printf "%s' .github/scripts/run-opencode-attempt.sh

# User comments are immutable: claim uses an authenticated bot reaction.
grep -Fq 'content=eyes' .github/scripts/claim-oc-command.sh
grep -Fq 'gh api user' .github/scripts/claim-oc-command.sh

# Final result is a new top-level comment using GITHUB_TOKEN.
grep -Fq 'gh api -X POST -f body="$body" "/repos/$repo/issues/$target/comments"' .github/scripts/post-oc-result.sh
grep -Fq 'GH_TOKEN: ${{ github.token }}' .github/workflows/opencode.yml
absent 'name: Mark triggering /oc comment as running' .github/workflows/opencode.yml

# Research mode: stream OpenCode thinking blocks into Actions logs.
grep -Fq 'opencode run --thinking --dir "$agent_cwd" --model "$model_name"' .github/scripts/run-opencode-attempt.sh
grep -Fq 'Research mode: keep OpenCode thinking blocks enabled' .github/scripts/run-opencode-attempt.sh

# Autonomous self-modification and research guidance must remain durable in the
# agent-owned instruction contract, not in a controller gate.
grep -Fq '# OpenCode autonomous operator contract' .opencode/instructions.md
grep -Fq 'The controller is a launcher/transport layer, not a capability gate' .opencode/instructions.md
grep -Fq '## Autonomy' .opencode/instructions.md
grep -Fq '## Complete environment access' .opencode/instructions.md
grep -Fq 'Do not self-restrict because a controller flag, task label, report/content classification' .opencode/instructions.md
grep -Fq '## Self-modification' .opencode/instructions.md
grep -Fq 'A running process will not automatically reload an edited file' .opencode/instructions.md
grep -Fq 'Do not treat controller files as off-limits' .opencode/instructions.md
grep -Fq '## Verification and recovery' .opencode/instructions.md
grep -Fq 'Do not invent results, versions, commits, links, or CI state.' .opencode/instructions.md
# The same guidance must reach every attempt through the streamed prompt.
grep -Fq 'This is engineering judgment, not a hard restriction.' .github/scripts/run-opencode-attempt.sh
grep -Fq '## Tools, skills, and research' .opencode/instructions.md
grep -Fq 'Search authoritative live sources when facts are current' .opencode/instructions.md
grep -Fq 'Research accelerates execution; it is not an approval gate.' .opencode/instructions.md

# Capability discovery: the agent must reason from outcomes and compose reachable primitives,
# rather than treating direct tools or user-supplied mechanisms as the ceiling.
grep -Fq 'When a direct tool is absent, compose reachable primitives.' .opencode/instructions.md
grep -Fq 'compose available primitives into a working path' .github/scripts/run-opencode-attempt.sh
grep -Fq 'Do not claim impossibility until viable reachable alternatives have been investigated' .github/scripts/run-opencode-attempt.sh
grep -Fq 'Capability discovery / outside-the-box execution:' .github/scripts/run-opencode-attempt.sh
grep -Fq 'last_failure_signature' .github/scripts/recover-opencode-ci.sh
grep -Fq 'identical actionable failure signature repeated' .github/scripts/recover-opencode-ci.sh
if grep -Fq 'OC_MAX_RECOVERY_ROUNDS' .github/workflows/opencode.yml; then echo 'FAIL: dead recovery round ceiling remains in workflow'; exit 1; fi
grep -Fq '1.18.32' .github/workflows/opencode.yml
# The owner-authorized capability path must remain available to the primary agent.
grep -Fq 'COMPOSIO_API_KEY: ${{ secrets.COMPOSIO_API_KEY }}' .github/workflows/opencode.yml
if grep -Fq 'COMPOSIO_API_KEY: ""' .github/workflows/opencode.yml; then
  fail 'primary OpenCode attempt must not blank the Composio capability credential'
fi

# Log cosmetics: summarize tool/command activity and keep comments free of live logs.
grep -Fq 'suppress_command_output=0' .github/scripts/filter-opencode-live-output.awk
grep -Fq '38;5;208m' .github/scripts/filter-opencode-live-output.awk
grep -Fq '38;5;141m' .github/scripts/filter-opencode-live-output.awk
grep -Fq '38;5;214m' .github/scripts/filter-opencode-live-output.awk
grep -Fq '91m' .github/scripts/filter-opencode-live-output.awk
grep -Fq 'Tool:' .github/scripts/filter-opencode-live-output.awk
absent 'safe_log="$SAFE_LOG"' .github/scripts/post-oc-result.sh
grep -Fq '/^[[:space:]]*Thinking:' .github/scripts/post-oc-result.sh

fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT
printf '%s
' '$ ls -la' 'total 40' 'Thinking: inspecting repository' '⚙ composio_COMPOSIO_SEARCH_TOOLS' 'WARNING: cache stale' 'ERROR: command failed' > "$fixture"
filtered="$(awk -f .github/scripts/filter-opencode-live-output.awk "$fixture")"
printf '%s
' "$filtered" | grep -Fq '→ ls -la'
if printf '%s
' "$filtered" | grep -Fq 'total 40'; then
  fail "expected 'total 40' to be absent from the filtered live output"
fi
printf '%s
' "$filtered" | grep -Fq 'Thinking: inspecting repository'
printf '%s
' "$filtered" | grep -Fq 'Tool: COMPOSIO SEARCH TOOLS'
printf '%s
' "$filtered" | grep -Fq '⚠ WARNING: cache stale'
printf '%s
' "$filtered" | grep -Fq '✗ ERROR: command failed'

# The attempt pipeline must run to completion and emit its outputs. Reading
# clarification_required before it is assigned aborts the attempt under `set -u`
# before a single output is written, so drive it end to end with a stub agent.
pipeline_root="$(mktemp -d)"
trap 'rm -f "$fixture"; rm -rf "$pipeline_root"' EXIT
mkdir -p "$pipeline_root/.github/scripts"
cp .github/scripts/run-attempt-pipeline.sh "$pipeline_root/.github/scripts/"
cat > "$pipeline_root/.github/scripts/run-opencode-attempt.sh" <<'STUB'
#!/usr/bin/env bash
printf 'termination_reason=completed\nsafe_log_path=/tmp/safe.log\nagent_branch=\nclarification_required=%s\npr_url=\n' "${STUB_CLARIFICATION:-false}" >> "${GITHUB_OUTPUT:-/dev/null}"
exit 0
STUB

run_pipeline() { # run_pipeline <task-mode> <clarification> <output-file>
  ( cd "$pipeline_root" && GITHUB_OUTPUT="$3" ATTEMPT=1 MODEL=test-model \
    OC_TARGET_MODE=local TASK_MODE="$1" OC_PUBLISH_REQUESTED=false \
    INITIAL_SHA=0000000000000000000000000000000000000000 \
    STUB_CLARIFICATION="$2" bash .github/scripts/run-attempt-pipeline.sh ) >/dev/null
}

: > "$pipeline_root/report.out"
run_pipeline report false "$pipeline_root/report.out"
grep -Fq 'agent_outcome=success' "$pipeline_root/report.out"
grep -Fq 'clarification_required=false' "$pipeline_root/report.out"
grep -Fq 'publish_outcome=report-only' "$pipeline_root/report.out"
grep -Fq 'result_state=completed' "$pipeline_root/report.out"

: > "$pipeline_root/clarify.out"
run_pipeline code true "$pipeline_root/clarify.out"
grep -Fq 'agent_outcome=clarification' "$pipeline_root/clarify.out"
grep -Fq 'clarification_required=true' "$pipeline_root/clarify.out"
grep -Fq 'publish_outcome=waiting-for-input' "$pipeline_root/clarify.out"
grep -Fq 'result_state=awaiting-input' "$pipeline_root/clarify.out"

echo 'attempt pipeline output contract: OK'

# The owner explicitly authorizes unrestricted task-relevant capability access.
absent 'env -u GITHUB_TOKEN -u GH_TOKEN -u UNIVERSAL_TOKEN -u COMPOSIO_API_KEY' .github/scripts/run-attempt-pipeline.sh
grep -Fq 'COMPOSIO_API_KEY: ${{ secrets.COMPOSIO_API_KEY }}' .github/workflows/opencode.yml
absent 'COMPOSIO_API_KEY: ""' .github/workflows/opencode.yml
grep -Fq 'Bootstrap Composio session MCP (all non-merge tasks)' .github/workflows/opencode.yml
grep -Fq 'if: env.OC_TASK_MODE != '\''merge'\''' .github/workflows/opencode.yml

# Capability discovery is agent-owned via the native OpenCode skill, not controller preflight.
if grep -Fq 'capability-discovery.sh' .github/scripts/run-opencode-attempt.sh; then echo 'FAIL: controller still invokes capability discovery'; exit 1; fi
grep -Fq '.opencode/skills/capability-discovery/SKILL.md' .github/scripts/test-controller.sh .github/agent-evals/README.md 2>/dev/null || true

grep -Fq 'name: capability-discovery' .opencode/skills/capability-discovery/SKILL.md

# Capability acquisition is agent-owned through the OpenCode skill.
grep -Fq 'OC_CAPABILITY_AUTO_INSTALL=true' .opencode/skills/capability-discovery/SKILL.md
grep -Fq 'The controller intentionally does not run this preflight' .opencode/skills/capability-discovery/SKILL.md

# ---------------------------------------------------------------------------
# Autonomous control-plane contract: the controller handles mechanical
# lifecycle only (durable-session setup and explicit merge). It must not probe
# capabilities, write permissions, or credentials to decide whether to launch.
# ---------------------------------------------------------------------------
grep -Fq 'it never probes' .github/scripts/oc-command-control.sh
absent 'Capability probe failed' .github/scripts/oc-command-control.sh
absent 'Write capability unavailable' .github/scripts/oc-command-control.sh
absent 'Target repository is archived' .github/scripts/oc-command-control.sh
absent 'permissions.push' .github/scripts/oc-command-control.sh
absent 'OC_CAPABILITY_PUSH' .github/scripts/oc-command-control.sh
absent 'OC_CAPABILITY_TARGET' .github/scripts/oc-command-control.sh
absent 'OC_CAPABILITY_TEST_MODE' .github/scripts/oc-command-control.sh .github/scripts/test-oc-command-control.sh
grep -Fq 'bash .github/scripts/prepare-oc-session.sh' .github/scripts/oc-command-control.sh
grep -Fq 'bash .github/scripts/merge-oc-request.sh' .github/scripts/oc-command-control.sh

# No legacy credential preflight gate may block the autonomous task environment.
absent 'name: Preflight credentials' .github/workflows/opencode.yml
absent 'OpenCode credential missing' .github/workflows/opencode.yml

# No report/content/repository classification remains to influence capability
# availability: every non-merge request launches the agent directly.
absent 'OC_CONTENT_TASK' .github/scripts/select-oc-task-mode.sh
absent 'content_signal' .github/scripts/select-oc-task-mode.sh
absent 'repo_signal' .github/scripts/select-oc-task-mode.sh
absent 'report' .github/scripts/select-oc-task-mode.sh
grep -Fq 'mode=code' .github/scripts/select-oc-task-mode.sh

# Regression: a capability-heavy non-repository request such as "send an email"
# must launch the agent with the full task environment, not be downgraded into
# a capability-starved report/content path.
scratch="$(mktemp -d)"
trap 'rm -f "$fixture"; rm -rf "$pipeline_root" "$scratch"' EXIT
while IFS='=' read -r leaked _; do
  case "$leaked" in OC_*|SESSION_*) unset "$leaked" 2>/dev/null || true ;; esac
done < <(env)
jq -n --arg body '/oc send an email to snapdragon0313@gmail.com telling him the workflow is fixed' \
  '{comment:{body:$body}}' > "$scratch/event-email.json"
: > "$scratch/env-email"; : > "$scratch/out-email"
GITHUB_EVENT_PATH="$scratch/event-email.json" GITHUB_ENV="$scratch/env-email" \
  GITHUB_OUTPUT="$scratch/out-email" bash .github/scripts/select-oc-task-mode.sh >/dev/null
grep -Fq 'OC_TASK_MODE=code' "$scratch/out-email"
grep -Fq 'OC_SESSION_REQUIRED=false' "$scratch/out-email"
absent 'OC_TASK_MODE=report' "$scratch/out-email" "$scratch/env-email"
absent 'OC_CONTENT_TASK' "$scratch/out-email" "$scratch/env-email"
# The capability provisions that back that request are unconditional for
# non-merge tasks: Composio bootstrap + key on the attempt step itself.
grep -Fq "if: env.OC_TASK_MODE != 'merge'" .github/workflows/opencode.yml
absent "if: env.OC_TASK_MODE == 'report'" .github/workflows/opencode.yml
echo 'autonomous capability contract: OK'
