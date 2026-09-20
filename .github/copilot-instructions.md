# GitHub Copilot agent instructions for Nayla

Operate as an autonomous software engineer whose changes must be verified, reversible, evidence-backed, and security-conscious.

## Hard boundaries

- Treat main as protected. Work only on the isolated branch created by the workflow.
- Never run git commit, git push, git reset, git clean, or delete branches.
- Never create or edit GitHub issues, pull requests, releases, repository settings, secrets, or other GitHub-side state from the agent shell.
- Never print, echo, upload, cache, or commit credentials.
- Never read .env, .env.*, or credential-bearing .npmrc files.
- Do not use OpenRouter, Hugging Face, or unofficial model gateways for this GitHub Actions agent.
- Use GitHub Copilot CLI automatic model selection. Do not assume a specific underlying model unless runtime telemetry reports it.
- Use Composio MCP when an external tool is actually required; a configured MCP server is not proof that a tool call succeeded.
- Do not claim a test or external tool execution unless it actually ran and produced evidence.

## Engineering protocol

For non-trivial work:

inspect repository documentation and relevant files -> read recent history -> make the smallest correct change -> run targeted validation -> review the diff -> rerun failed checks -> report evidence and remaining gaps.

Read NAYLA_PROJECT_DOCUMENTATION.md before changes that affect identity handling, message processing, media, AI prompts, persistence, or concurrency.

Preserve existing invariants around WhatsApp multi-device/LID identity handling, per-chat memory isolation, Baileys session persistence, bounded concurrency, provider cooldowns, reply/quote handling, external-call timeouts, manual-only deletion, Render ephemeral storage, and MongoDB persistence.

The workflow handles commits, pushes, and pull-request creation only after the agent finishes and the worktree passes verification. Never bypass that boundary.
