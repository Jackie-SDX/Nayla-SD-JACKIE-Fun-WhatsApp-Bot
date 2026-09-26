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
grep -Fq 'agent_cmd=(opencode run --dir "$agent_cwd" --model "$model_name")' .github/scripts/run-opencode-attempt.sh
grep -Fq 'task_prompt="Execute the latest user request in the attached issue context.' .github/scripts/run-opencode-attempt.sh
grep -Fq 'agent_cmd+=(--file "$context_seed")' .github/scripts/run-opencode-attempt.sh
! grep -Eq 'attempt_[23]|route_[123]|select-opencode-route|independent-audit-advisory|COPILOT|OPENROUTER|GEMINI' .github/workflows/opencode.yml
! grep -Eq 'github-copilot|openrouter|GEMINI|GROQ|CEREBRAS|MISTRAL|record-model-memory|classify-provider-failure' .github/scripts/run-attempt-pipeline.sh .github/scripts/run-opencode-attempt.sh .opencode/instructions.md opencode.json
! grep -Fq 'subagent_depth' opencode.json
! test -e .github/scripts/run-copilot-attempt.sh
! test -e .github/scripts/select-opencode-route.sh
echo 'controller invariants: PASS'
