#!/usr/bin/env bash
set -euo pipefail
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
grep -Fq 'model: opencode/mimo-v2.6-flash-free' .github/workflows/opencode.yml
grep -Fq 'Run primary OpenCode attempt' .github/workflows/opencode.yml
bash -n .github/scripts/run-opencode-attempt.sh
grep -Fq 'agent_cmd=(opencode run --thinking --dir "$agent_cwd" --model "$model_name")' .github/scripts/run-opencode-attempt.sh
grep -Fq 'task_prompt="Execute the latest user request in the attached issue context.' .github/scripts/run-opencode-attempt.sh
grep -Fq 'agent_cmd+=(--file "$context_seed")' .github/scripts/run-opencode-attempt.sh
! grep -Eq 'attempt_[23]|route_[123]|select-opencode-route|independent-audit-advisory|COPILOT|OPENROUTER|GEMINI' .github/workflows/opencode.yml
! grep -Eq 'github-copilot|openrouter|GEMINI|GROQ|CEREBRAS|MISTRAL|record-model-memory|classify-provider-failure' .github/scripts/run-attempt-pipeline.sh .github/scripts/run-opencode-attempt.sh .opencode/instructions.md opencode.json
! grep -Fq 'subagent_depth' opencode.json
! test -e .github/scripts/run-copilot-attempt.sh
! test -e .github/scripts/select-opencode-route.sh
echo 'controller invariants: PASS'

# One /oc comment -> one workflow execution: controller responses edit, never create, comments.
grep -Fq 'group: oc-claim-${{ github.event.comment.id || github.run_id }}' .github/workflows/opencode.yml
grep -Fq 'group: oc-agent-${{ github.event.comment.id || github.run_id }}' .github/workflows/opencode.yml
! grep -Fq 'Register /oc run marker' .github/workflows/opencode.yml
! grep -Fq 'Human handoff when the primary agent stops without durable work' .github/workflows/opencode.yml
! grep -Fq 'gh issue comment "$target" --body "$marker"' .github/scripts/claim-oc-command.sh
! grep -Fq 'gh issue comment "$target" --body "$body"' .github/scripts/post-oc-result.sh
# OpenCode prompt must be stdin so repeatable --file cannot consume it.
! grep -Fq 'agent_cmd+=("$task_prompt")' .github/scripts/run-opencode-attempt.sh
grep -Fq 'agent_cmd+=(--file "$context_seed")' .github/scripts/run-opencode-attempt.sh
grep -Fq '< <(printf "%s' .github/scripts/run-opencode-attempt.sh

# User comments are immutable: claim uses an authenticated bot reaction.
grep -Fq 'content=eyes' .github/scripts/claim-oc-command.sh
grep -Fq 'gh api user' .github/scripts/claim-oc-command.sh

# Final result is a new top-level comment using GITHUB_TOKEN.
grep -Fq 'gh api -X POST -f body="$body" "/repos/$repo/issues/$target/comments"' .github/scripts/post-oc-result.sh
grep -Fq 'GH_TOKEN: ${{ github.token }}' .github/workflows/opencode.yml
! grep -Fq 'name: Mark triggering /oc comment as running' .github/workflows/opencode.yml

# Research mode: stream OpenCode thinking blocks into Actions logs.
grep -Fq 'opencode run --thinking --dir "$agent_cwd" --model "$model_name"' .github/scripts/run-opencode-attempt.sh
grep -Fq 'Research mode: keep OpenCode thinking blocks enabled' .github/scripts/run-opencode-attempt.sh


# Log cosmetics: summarize tool/command activity and keep comments free of live logs.
grep -Fq 'suppress_command_output=0' .github/scripts/filter-opencode-live-output.awk
grep -Fq '38;5;208m' .github/scripts/filter-opencode-live-output.awk
grep -Fq '38;5;141m' .github/scripts/filter-opencode-live-output.awk
grep -Fq '38;5;214m' .github/scripts/filter-opencode-live-output.awk
grep -Fq '91m' .github/scripts/filter-opencode-live-output.awk
grep -Fq 'Tool:' .github/scripts/filter-opencode-live-output.awk
! grep -Fq 'safe_log="$SAFE_LOG"' .github/scripts/post-oc-result.sh
grep -Fq '/^[[:space:]]*Thinking:' .github/scripts/post-oc-result.sh

fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT
printf '%s\n' '$ ls -la' 'total 40' 'Thinking: inspecting repository' '⚙ composio_COMPOSIO_SEARCH_TOOLS' 'WARNING: cache stale' 'ERROR: command failed' > "$fixture"
filtered="$(awk -f .github/scripts/filter-opencode-live-output.awk "$fixture")"
printf '%s\n' "$filtered" | grep -Fq '→ ls -la'
! printf '%s\n' "$filtered" | grep -Fq 'total 40'
printf '%s\n' "$filtered" | grep -Fq 'Thinking: inspecting repository'
printf '%s\n' "$filtered" | grep -Fq 'Tool: COMPOSIO SEARCH TOOLS'
printf '%s\n' "$filtered" | grep -Fq '⚠ WARNING: cache stale'
printf '%s\n' "$filtered" | grep -Fq '✗ ERROR: command failed'
