#!/usr/bin/env bash
set -euo pipefail

jq empty opencode.json
jq -e '.permissions | type == "array"' opencode.json >/dev/null
jq -e 'has("permission") | not' opencode.json >/dev/null
jq -e '.permissions[] | select(.action=="subagent" and .resource=="*" and .effect=="deny")' opencode.json >/dev/null
jq -e '.permissions[] | select(.action=="shell" and .resource=="git push *" and .effect=="deny")' opencode.json >/dev/null
jq -e '.permissions[] | select(.action=="shell" and .resource=="git commit *" and .effect=="deny")' opencode.json >/dev/null
jq -e '.permissions[] | select(.action=="shell" and .resource=="gh *" and .effect=="deny")' opencode.json >/dev/null
jq -e '.mcp.composio.command | index("mcp-remote@0.14.2") != null' opencode.json >/dev/null
jq -e '.mcp.composio.command | index("http-only") != null' opencode.json >/dev/null
jq -e '.mcp.composio.command | index("--header-file") != null' opencode.json >/dev/null

for agent in architect-reviewer adversarial-reviewer adjudicator verifier; do
  f=".opencode/agents/$agent.md"
  test -f "$f"
  grep -q '^mode: primary$' "$f"
  grep -q '^model: ' "$f"
  grep -q '^permissions:$' "$f"
  grep -q 'action: edit' "$f"
  grep -q 'action: subagent' "$f"
  grep -q 'effect: deny' "$f"
  ! grep -q '^temperature:' "$f"
  ! grep -q '^permission:' "$f"
done

grep -q '^model: opencode/big-pickle$' .opencode/agents/architect-reviewer.md
grep -q '^model: opencode/mimo-v2.5-free$' .opencode/agents/adversarial-reviewer.md
grep -q '^model: opencode/big-pickle$' .opencode/agents/adjudicator.md
grep -q '^model: opencode/mimo-v2.5-free$' .opencode/agents/verifier.md

test -f .github/scripts/run-opencode-council-stage.sh
test -f .github/scripts/run-opencode-attempt.sh
test -f .github/scripts/publish-opencode-change.sh
test -f .github/scripts/validate-application.sh

grep -q 'opencode run --standalone --auto --agent' .github/scripts/run-opencode-council-stage.sh
! grep -R -q 'opencode agent list' .github/scripts .github/workflows
grep -q 'COUNCIL_STAGE_COMPLETE=' .github/scripts/run-opencode-council-stage.sh
grep -q 'COUNCIL_DECISION=' .github/scripts/run-opencode-attempt.sh
grep -q 'COUNCIL_VERDICT=' .github/scripts/run-opencode-attempt.sh
grep -q 'Publish OpenCode attempt 1' .github/workflows/opencode.yml
grep -q 'Validate command gate' .github/workflows/opencode.yml
grep -q 'secrets.OPENCODE_API_KEY' .github/workflows/opencode.yml
grep -q 'COUNCIL_EVIDENCE_DIR' .github/workflows/opencode.yml
grep -q 'The GitHub Actions workflow is the authoritative council control plane' .opencode/instructions.md
grep -q 'separate top-level CLI sessions' docs/AGENT_COUNCIL.md

bash -n .github/scripts/run-opencode-council-stage.sh
bash -n .github/scripts/run-opencode-attempt.sh
bash -n .github/scripts/publish-opencode-change.sh
bash -n .github/scripts/validate-application.sh

! grep -q 'connect.composio.dev/mcp' .github/scripts/run-copilot-attempt.sh
! grep -q 'x-consumer-api-key' .github/scripts/run-copilot-attempt.sh
! grep -q '^      id-token: write$' .github/workflows/opencode.yml
! grep -q '^      GITHUB_TOKEN:' .github/workflows/opencode.yml
! grep -q '^\s*GITHUB_TOKEN:' .github/workflows/opencode.yml

# OpenCode 2.x exposes custom agents from repository markdown frontmatter; do not use the removed V1-style
# `opencode agent list` positional command here. The actual agent executors perform the authoritative
# runtime smoke/council stages and emit completion markers.
grep -R -q '^mode: primary
 .opencode/agents
grep -q '^model: opencode/big-pickle
 .opencode/agents/architect-reviewer.md
grep -q '^model: opencode/mimo-v2.5-free
 .opencode/agents/adversarial-reviewer.md

echo "Enterprise council validation: PASS"
