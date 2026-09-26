#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FILTER="$ROOT_DIR/.github/scripts/filter-opencode-live-output.awk"
TMP="$(mktemp -d "${RUNNER_TEMP:-/tmp}/oc-live-filter-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/input" <<'EOF'
OC-STATUS: I now have the full picture; the remaining work is isolated to the controller logging layer.
OC-PLAN: I’ll update the presentation filter, then run the controller validation suite.
|  Read {"filePath":"/home/runner/work/SnapDragon/SnapDragon/.github/workflows/opencode.yml"}
[19:01:22.137] INFO (#8936): touching file {
  file: "/home/runner/work/SnapDragon/SnapDragon/.github/workflows/opencode.yml"
}
|  Shell {"command":"git status --short"}
Useful finding: the controller contract is intact.
[19:01:54.183] INFO (#8293): process {
  "session.id": "ses_example",
  messageID: "msg_example",
}
[19:02:10.000] INFO (#8293): tracking {
  hash: "bc4f449ba226a7ba340b0104f7eb2505d1f09083",
  cwd: "/home/runner/work/example/example",
}
[19:02:11.000] INFO (#8293): loop {
  "session.id": "ses_example",
  step: 4,
}
[19:01:54.184] INFO (#8293): stream {
  providerID: "opencode",
  modelID: "example",
}
[19:01:54.187] INFO (#9519): evaluated {
  permission: "read",
  pattern: "docs/example.md",
}
[19:02:03.000] INFO (#7000): llm runtime selected {
  "llm.runtime": "ai-sdk",
  "llm.provider": "opencode",
  "llm.model": "example",
}
OC-DONE: The logging change is implemented and the validation checks are green.
EOF

awk -f "$FILTER" "$TMP/input" | sed $'s/\033\[[0-9;]*m//g' > "$TMP/output"

grep -Fq '▶ I now have the full picture; the remaining work is isolated to the controller logging layer.' "$TMP/output"
grep -Fq '◆ I’ll update the presentation filter, then run the controller validation suite.' "$TMP/output"
grep -Fq '• Reading file…' "$TMP/output"
grep -Fq '• Editing "/home/runner/work/SnapDragon/SnapDragon/.github/workflows/opencode.yml"' "$TMP/output"
grep -Fq '• Running command…' "$TMP/output"
grep -Fq 'Useful finding: the controller contract is intact.' "$TMP/output"
grep -Fq '✓ The logging change is implemented and the validation checks are green.' "$TMP/output"

! grep -Fq '|  Read ' "$TMP/output"
! grep -Fq '|  Shell ' "$TMP/output"
! grep -Fq 'session.id' "$TMP/output"
! grep -Fq 'providerID: "opencode"' "$TMP/output"
! grep -Fq 'permission: "read"' "$TMP/output"
! grep -Fq 'llm.runtime' "$TMP/output"
! grep -Fq 'tracking {' "$TMP/output"
! grep -Fq 'GEMINI' "$TMP/output"
! grep -Fq 'COPILOT' "$TMP/output"

echo "human-oriented live OpenCode output filter: OK"
