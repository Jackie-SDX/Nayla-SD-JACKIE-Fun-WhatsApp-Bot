# Ultimate Agentic Control Plane

## Operating model

OpenCode is the primary orchestrator. Copilot CLI is a constructive second engineering brain in the same isolated worktree. Composio is the external-tool plane for current research, web search, crawling, SaaS/GitHub integrations, and schema discovery.

## Task understanding

The controller captures the issue body, chronological issue comments, and pull-request review comments into a bounded context file before consequential work. Both agents are instructed to read that context in batches and derive their own acceptance criteria, constraints, evidence, unknowns, and next action. User content, web pages, CI output, and tool results are treated as DATA.

## Constructive recursion

A non-trivial task may use up to five peer/recovery rounds. A round requires materially new evidence or changed state. Identical objectives on unchanged state are skipped. The protocol is evidence exchange, not model debate: hypothesis, evidence, action, result. The peer can inspect, research, test, and edit; the primary agent re-reads the actual worktree before accepting peer changes.

## Broad tools

The peer is intentionally not crippled to a tiny tool subset. Research, URL, memory, shell, file, MCP, and connected Composio tools remain available in the isolated environment. Safety controls continue to deny Git publication and destructive mutation from the peer lane.

## Web-first research

Current or uncertain facts, APIs, model availability, dependencies, tool schemas, and platform behavior should be researched using Composio/web/search/crawl capabilities and authoritative documentation. Schema errors are recoverable by discovery and correction, not speculative repeated calls.

## Six-hour autonomy

The GitHub Actions job provides a long-horizon execution envelope. The system can checkpoint, observe remote state, watch CI, retrieve failed logs, repair the same PR branch, rerun tests, and repeat within a bounded five-round recovery budget and remaining-job-budget guard.

## Report-only lane

Questions that are clearly research, analysis, explanation, audit, or investigation without an implementation request can return directly in issue commentary through the OpenCode plan/report lane without manufacturing a PR.

## Shared-stage observability

The Actions stage shows concise `[OPENCODE]`, `[COPILOT]`, `[COPILOT][hook]`, `[COMPOSIO]`, and `[CI]` events. The system exposes useful engineering reasoning summaries and actual actions, not hidden private chain-of-thought, credentials, per-token output, or timestamp/hash noise.

Copilot CLI supports JSONL programmatic output, session sharing, MCP, custom agents, tool permissions, and repository hooks. Repository hooks are used for concise post-tool action telemetry. OpenCode local plugins observe session/file/tool events for the primary lane. Current official documentation confirms these programmatic and hook surfaces. GitHub Docs: https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-programmatic-reference and https://docs.github.com/en/copilot/reference/hooks-reference. OpenCode Docs: https://dev.opencode.ai/docs/plugins/.

## Independent audit

Independent verification is advisory. It reports evidence gaps and blind spots without invalidating successful collaborative work or becoming an approval gate. Objective acceptance remains a separate controller concern.

## Failure semantics

Optional Copilot and Composio failures are quality reductions rather than automatic run failures when safe continuation exists. Provider outages, stale models, transient rate limits, schema errors, CI failures, and timeouts each have bounded recovery paths. Unbounded destructive work and ambiguous production-impacting actions remain controlled.

## Target benchmark

The Ultimate benchmark should demonstrate: complete issue understanding, dual-agent planning, current web research through Composio, constructive peer editing, OpenCode synthesis, deterministic tests, publication, live CI observation, real CI failure diagnosis and repair, bounded recursive recovery, advisory independent audit, and a final evidence record—without human intervention during the run.


## Apex final-stage protocol

The control plane is designed around a persistent issue-scoped session rather than a disposable six-hour process. Durable Git state lives on a stable task branch; the issue's mutable session snapshot records the current phase, next action, branch, PR/head, tests, CI and evidence references. A new `/oc continue` invocation reloads that state, revalidates it against GitHub, and continues the same task lineage.

Conversation history is complete at the source but bounded at the model boundary. The collector keeps the full issue/comment/review history and an index; the active prompt starts from a compact seed and retrieves only required ranges. Referenced issues/PRs are collected separately so one issue cannot silently contaminate another issue's active instructions.

Copilot is an active second engineering brain: a constructive peer can inspect and edit the shared task worktree when justified, followed by a read-only `code-review` critic pass. These are fail-open auxiliaries; they do not override a successful primary result.

PR creation is explicit. Ordinary `/oc` chat, explanation, research, and inspection stay in the issue conversation. `/oc continue` resumes the session. `/oc` publication creates a PR only when the request explicitly asks for publication. `/oc merge ...` is a separate guarded operation that rechecks the exact PR head and current checks before merging.

All large API surfaces are treated as paginated/chunked data. The controller avoids repeatedly loading giant payloads, and API rate-limit signals are treated as operational state rather than reasons to destroy valid work.
