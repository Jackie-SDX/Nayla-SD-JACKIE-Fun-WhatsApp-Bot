# Hybrid OpenCode + Copilot Agent Audit

Repository: Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot
Date: 2026-09-20

## Current architecture

OpenCode is the primary /oc runtime. GitHub Copilot CLI is both an optional fallback worker and an optional peer worker. OpenCode remains the primary orchestrator.

Primary path:
/oc or /opencode -> GitHub Actions -> OpenCode CLI -> OpenCode Zen free model -> OpenCode GitHub App/OIDC -> OpenCode branch/commit/push/PR

Fallback path:
OpenCode failure -> evidence classification -> replay-safety gate -> Copilot CLI -> isolated fallback branch -> workflow-owned commit/push/PR

## Restored and preserved controls

- OpenCode Zen is configured with OPENCODE_API_KEY and opencode/<model-id>; no provider block is required in opencode.json.
- The Zen free-model list is configurable because the free lineup changes over time.
- OpenCode installation remains release-digest verified and cache-aware.
- The interactive workflow restores cache but never writes cache; the trusted cache workflow owns cache population.
- Route selection performs no inference health probes.
- The trigger has a maximum of three full agent invocations.
- The inner agent protocol retains the five-cycle forensic recovery budget and three-strike circuit breaker.
- Failed OpenCode runs are not blindly replayed after local or remote mutation is detected.
- Copilot remains pinned and session-credit bounded.
- Copilot agent-side Git and GitHub CLI mutation commands remain denied.
- Secrets remain environment-backed and diagnostics are sanitized.

## Current Zen evidence

OpenCode's current Zen documentation lists Big Pickle and MiMo-V2.5 Free as free models, with additional limited-time free offerings. The implementation defaults to those two and allows changing the repository variable as the official catalog changes.

## Operator prerequisites

1. Install the OpenCode GitHub App from github.com/apps/opencode-agent on this repository.
2. Add OPENCODE_API_KEY under the repository's Actions secrets. Never paste the key into chat or source.
3. Keep COPILOT_GITHUB_TOKEN configured only when the fallback lane is desired.
4. Run the real /oc acceptance test only after the App and secret are configured.

## Sources

- https://dev.opencode.ai/docs/github
- https://dev.opencode.ai/docs/cli/
- https://opencode.ai/docs/zen/
- https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli/use-copilot-cli-in-github-actions
## Two-brain peer path

OpenCode can invite Copilot during the same task: `invite-copilot-peer.sh` runs Copilot against the SAME isolated worktree, allowing inspection, testing, and corrective edits. OpenCode then re-reads the tree and remains responsible for the final decision. This is not failover: a missing or failed peer is non-fatal and the primary task continues.

## OpenRouter recovery path

A Zen free-tier context rejection can route the next attempt through OpenCode using the `openrouter/free` router. This preserves the OpenCode runtime and worktree; Copilot remains available as a peer or terminal fallback. The route is credential-gated and non-blocking.
