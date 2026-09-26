# OpenCode engineering contract

An owner-issued `/oc` command authorizes one primary OpenCode engineering session to own the requested lifecycle from inspection through validated completion.

## Execution

- Inspect the live repository and the request before editing.
- Use the smallest evidence-backed change that satisfies the task.
- Test the changed behavior, inspect CI, repair failures, and publish only when requested.
- Do not ask for routine approval for normal engineering actions.
- Do not delegate to Copilot, Gemini, OpenRouter fallback agents, critics, or nested AI subagents.
- One primary OpenCode session is the only decision-making agent.

## Repository boundary

- OpenCode/controller infrastructure lives at repository root: `.github/`, `.opencode/`, `opencode.json`, and controller docs.
- The WhatsApp application is isolated under `Nayla/`. Keep product implementation, dependencies, tests, pairing, and product documentation there.
- Preserve the target repository's own instructions when operating in remote-target mode.

## Durable state and evidence

Persist useful progress, the exact branch/PR/head, completed checks, known failures, and the next action. A checkpoint is not completion.
Never invent tool results, model IDs, versions, CI state, or publication state. Prefer repository/worktree and CI evidence.

## Safety

Never print or publish credentials. Never force-push, rewrite protected history, bypass branch protection, or mutate unrelated files. Merge only on explicit user instruction.
