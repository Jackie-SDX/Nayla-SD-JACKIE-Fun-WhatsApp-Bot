# GitHub Copilot Fallback Audit

Repository: Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot
Date: 2026-09-20

GitHub Copilot CLI is retained as an optional fallback worker for the /oc hybrid agent. It is not the primary runtime.

Controls:
- @github/copilot@1.0.86 remains pinned.
- Automatic model selection is used.
- COPILOT_MAX_AI_CREDITS bounds fallback session usage.
- Composio MCP is passed only when configured.
- The worker cannot commit, push, reset, clean, delete branches, or mutate GitHub through gh.
- The outer workflow publishes fallback changes after verification.