#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FILTER="$ROOT_DIR/.github/scripts/filter-opencode-live-output.awk"
TMP="$(mktemp -d "${RUNNER_TEMP:-/tmp}/oc-live-filter-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/input" <<'EOF'
Useful finding: verify the Composio MCP URL against actual documentation.
|  Read {"filePath":"/home/runner/work/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/.github/workflows/opencode.yml"}
[19:01:22.137] INFO (#8936): touching file {
  file: "/home/runner/work/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/.github/workflows/opencode.yml"
}
[OC][PHASE 1/4] PLAN
[GEMINI][phase=plan] evidence summary: verify the live repository.
[OC][DECISION SUMMARY] accept: repository evidence confirms the finding.
[COPILOT] hypothesis: inspect validation contract.
Running deterministic checks.
|  Shell {"command":"git log --oneline -25"}
[19:01:54.183] INFO (#8293): process {
  "session.id": "ses_example",
  messageID: "msg_example",
}
[19:02:10.000] INFO (#8293): tracking {
  hash: "bc4f449ba226a7ba340b0104f7eb2505d1f09083",
  cwd: "/home/runner/work/example/example",
  git: "/home/runner/.local/share/opencode/snapshot/example/git",
}
[19:02:11.000] INFO (#8293): loop {
  "session.id": "ses_example",
  step: 4,
}
[19:01:54.184] INFO (#8293): stream {
  providerID: "opencode",
  modelID: "big-pickle",
}
[19:01:54.187] INFO (#9519): evaluated {
  permission: "read",
  pattern: "docs/CONCURRENCY_AND_ISOLATION_AUDIT.md",
  action: {
    permission: "read",
    pattern: "*",
    action: "allow",
  },
}
[19:02:03.000] INFO (#7000): llm runtime selected {
  "llm.runtime": "ai-sdk",
  "llm.provider": "opencode",
  "llm.model": "big-pickle",
}
EOF

awk -f "$FILTER" "$TMP/input" > "$TMP/output"

grep -Fq "Useful finding: verify the Composio MCP URL against actual documentation." "$TMP/output"
grep -Fq "Reading file..." "$TMP/output"
grep -Fq '|  Read {"filePath":"/home/runner/work/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/.github/workflows/opencode.yml"}' "$TMP/output"
grep -Fq "Making changes / editing file..." "$TMP/output"
grep -Fq 'touching file "/home/runner/work/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/.github/workflows/opencode.yml"' "$TMP/output"
grep -Fq "[OC][PHASE 1/4] PLAN" "$TMP/output"
grep -Fq "  -> [GEMINI][phase=plan] evidence summary: verify the live repository." "$TMP/output"
grep -Fq "  >> [OC][DECISION SUMMARY] accept: repository evidence confirms the finding." "$TMP/output"
grep -Fq "  -> [COPILOT] hypothesis: inspect validation contract." "$TMP/output"
grep -Fq "Running deterministic checks." "$TMP/output"
grep -Fq "Running shell command" "$TMP/output"
grep -Fq '|  Shell {"command":"git log --oneline -25"}' "$TMP/output"
! grep -Fq 'session.id' "$TMP/output"
! grep -Fq 'providerID: "opencode"' "$TMP/output"
! grep -Fq 'permission: "read"' "$TMP/output"
! grep -Fq 'llm.runtime' "$TMP/output"
! grep -Fq 'evaluated {' "$TMP/output"
! grep -Fq 'loop {' "$TMP/output"
! grep -Fq 'snapshot/example/git' "$TMP/output"
! grep -Fq 'hash: "bc4f449ba226a7ba340b0104f7eb2505d1f09083"' "$TMP/output"
! grep -Fq 'tracking {' "$TMP/output"

echo "human-oriented live OpenCode output filter: OK"
