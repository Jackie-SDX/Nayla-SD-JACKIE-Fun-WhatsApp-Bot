# OpenCode engineering contract

An owner-issued `/oc` command authorizes one primary OpenCode engineering session to own the requested lifecycle from inspection through validated completion.

## Execution

- Inspect the live repository and the request before editing.
- Use the smallest evidence-backed change that satisfies the task.
- Test the changed behavior, inspect CI, repair failures, and publish only when requested.
- Do not ask for routine approval for normal engineering actions.
- Do not delegate to Copilot, Gemini, OpenRouter fallback agents, critics, or nested AI subagents.
- One primary OpenCode session is the only decision-making agent.


## Operator-facing progress

Keep human-facing progress concise and useful. After meaningful milestones, emit one short line beginning with OC-STATUS: describing what you learned or what you are doing next. Before a substantial multi-step change, emit one short OC-PLAN: line. After verified completion, emit one short OC-DONE: line.

These are operator progress summaries, not hidden chain-of-thought. Never expose private/internal reasoning, raw tool payloads, credentials, or repetitive implementation detail. Prefer statements such as:
- OC-STATUS: I now have the full picture; the remaining work is isolated to the controller logging layer.
- OC-PLAN: I’ll update the presentation filter, then run the controller validation suite.
- OC-DONE: The logging change is implemented and the validation checks are green.

Tool activity itself should remain compact: let the console summarize reads, edits, searches, and commands rather than narrating every low-level payload.

## Repository boundary

- OpenCode/controller infrastructure lives at repository root: `.github/`, `.opencode/`, `opencode.json`, and controller docs.
- The WhatsApp application is isolated under `Nayla/`. Keep product implementation, dependencies, tests, pairing, and product documentation there.
- Preserve the target repository's own instructions when operating in remote-target mode.

## Durable state and evidence

Persist useful progress, the exact branch/PR/head, completed checks, known failures, and the next action. A checkpoint is not completion.
Never invent tool results, model IDs, versions, CI state, or publication state. Prefer repository/worktree and CI evidence.

## Safety

Never print or publish credentials. Never force-push, rewrite protected history, bypass branch protection, or mutate unrelated files. Merge only on explicit user instruction.
