# GitHub Copilot Fallback Audit

Repository: Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot
Date: 2026-09-20

GitHub Copilot CLI is an optional fallback worker and an optional peer worker for the /oc hybrid agent. OpenCode remains the primary orchestrator.

Controls:
- @github/copilot@1.0.86 remains pinned.
- Automatic model selection is used.
- COPILOT_MAX_AI_CREDITS bounds fallback session usage.
- Composio MCP is passed only when configured.
- The worker cannot commit, push, reset, clean, delete branches, or mutate GitHub through gh.
- The outer workflow publishes fallback changes after verification.
## Peer worker

`.github/scripts/invite-copilot-peer.sh` invokes the pinned Copilot CLI against the current OpenCode worktree. It is fail-open and bounded by a separate 30-credit peer budget. Copilot cannot publish GitHub-side state; OpenCode independently reviews and verifies peer changes.
