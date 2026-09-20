#!/usr/bin/env bash
set -euo pipefail

repo_cfg="opencode.json"
test -f "$repo_cfg"

jq empty "$repo_cfg"

jq -e '.subagent_depth >= 1' "$repo_cfg" >/dev/null
for agent in architect-reviewer adversarial-reviewer adjudicator verifier; do
  jq -e --arg agent "$agent" '.permission.task[$agent] == "allow"' "$repo_cfg" >/dev/null
  test -f ".opencode/agents/$agent.md"
  grep -q '^mode: subagent$' ".opencode/agents/$agent.md"
  grep -q '^permission:$' ".opencode/agents/$agent.md"
  grep -q '^  edit: deny$' ".opencode/agents/$agent.md"
  grep -q '^  task: deny$' ".opencode/agents/$agent.md"
  grep -q '^  doom_loop: deny$' ".opencode/agents/$agent.md"
done

grep -q '^model: opencode/big-pickle$' .opencode/agents/architect-reviewer.md
grep -q '^model: opencode/mimo-v2.5-free$' .opencode/agents/adversarial-reviewer.md
grep -q '^model: opencode/mimo-v2.5-free$' .opencode/agents/adjudicator.md
grep -q '^model: opencode/big-pickle$' .opencode/agents/verifier.md

grep -q 'MANDATORY AGENT COUNCIL' .opencode/instructions.md
grep -q 'architect-reviewer' .opencode/instructions.md
grep -q 'adversarial-reviewer' .opencode/instructions.md
grep -q 'adjudicator' .opencode/instructions.md
grep -q 'verifier' .opencode/instructions.md

echo "Agent council static validation: PASS"
