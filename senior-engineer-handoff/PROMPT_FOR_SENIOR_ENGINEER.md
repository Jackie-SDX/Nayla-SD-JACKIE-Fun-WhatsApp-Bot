# SENIOR ENGINEER — AUDIT & REGRESSION-SAFE IMPROVEMENT PROMPT

> How to use this file: paste the block below verbatim to the senior engineer.
> Pair it with `HISTORY_UPGRADES_AND_INVARIANTS.md` (the historical record of what
> was built, fixed, deferred, and what must never break) and the full repository zip.
> The engineer should read the history file FIRST, this prompt SECOND, then the code.

---

## THE PROMPT THAT FOLLOWS IS THE DELIVERABLE — EDIT THE REPO-OWNER SECTIONS IN [BRACKETS], THEN SEND

---

### ROLE

You are a senior software engineer contracted to AUDIT a two-system repository and
produce a REGRESSION-SAFE improvement plan plus, where low-risk, merged-ready patches.
You are **not** free to refactor freely: this repository survived production incidents,
is operated by an autonomous agent, and has strict invariants. Your job is to make it
more robust without breaking the load-bearing decisions documented over its history.

### THE REPOSITORY (two systems in one tree)

| System | What it is | Where |
| --- | --- | --- |
| **A. The product** | A WhatsApp companion bot ("Nayla") on the Baileys multi-device protocol, MongoDB-backed memory, multi-provider AI failover | `index.js` (5400 lines, one file), `pair.js`, `scripts/`, `package.json` |
| **B. The control plane** | A GitHub-Actions-hosted autonomous OpenCode agent platform triggered by `/oc` issue comments, with provider-routing ladder, evidence-based verification, remote-target isolation, and recovery logic | `.github/`, `.opencode/`, `opencode.json` |

Read `NAYLA_PROJECT_DOCUMENTATION.md` and `docs/PROJECT_HISTORY_AND_ARCHITECTURE.md`
before any code. Treat those files as the authoritative invariant source.

### DELIVERABLES

1. **Audit report (written)** — per area below: what works, what is fragile, concrete risk, severity, and the smallest safe fix. Cite `file:line`.
2. **Prioritized improvement roadmap** — P0/P1/P2, each item marked `ADDITIVE-SAFE`, `NEEDS-CAREFUL-TESTS`, or `DO-NOT-DO` (with reason).
3. **Patches** — ONLY for items you can prove won't regress the invariants in the limits section (see "Verification gate" below). Pure-additive, guarded changes preferred.
4. **Test additions** — for the application specifically: `index.js` has almost no tests; extracting pure helpers (regex checks, cooldown math, rate limits, duplicate-spam keying) into testable units is the highest-value low-risk win.

### SCOPE A — THE BOT (`index.js`, `pair.js`, `scripts/simple-web-crawler.js`, `package.json`)

Audit specifically against the documented bug history:

- **Message-type & quoting** — read `NAYLA_PROJECT_DOCUMENTATION.md` §13.1, §13.10, §20.6. `unwrapMessageContent()` must keep handling every WhatsApp envelope (`deviceSentMessage`, `ephemeralMessage`, `viewOnceMessage`, …). Any new quote-handling must go through `getContextInfo()`/`unwrapMessageContent()`. The §20.7 diagnostic log line stays as a permanent safety net.
- **Identity/LID** — §13.2. Never regress dual-format JID handling (classic + `@lid`). Use `isSelfJid()`/`isJidInList()`.
- **Concurrency & external waits** — §7.1–7.4, §14. Every long-running task goes through `runHeavyTask()`; every raw `fetch()` has `fetchWithTimeout`. Hard deadlines are load-bearing, not optional.
- **Memory isolation** — §12.8. Per-chat/per-sender scoping is a hard invariant. No cross-chat personal-memory leakage, ever.
- **Moderation/automation stance** — §12.6, §15. No automated deletion. No punitive moderation. `.ignore`/`.mute`/two-strike silence must be airtight (see §20.1 ordering).
- **Placeholders & duplicates** — §18.13, §19.2: bare-media placeholders (`[image, no caption]`, `[sticker]`, …) are internal strings; they must not leak into AI prompts as real text and must not false-trigger duplicate-spam.
- **Known live bugs** — §19.1 (`EMOJI_REGEX` global-flag `lastIndex` misuse), §19.2, §19.3. Fix these only additively and with a regression test.
- **Decline paths** — PDF/document/video asks (§15, §18.12): keep the honest decline. Do not "add" server-side URL fetching/link analysis (SSRF risk, deliberately excluded).
- **Pairing** — `pair.js` vs. `index.js` Mongo collection consistency remains an open question; verify it writes the same collection.
- **Lint gap** — `eslint.config.js` only covers `scripts/`, not `index.js`. Extending it incrementally (warn-first) is acceptable; hard-failing 5400 legacy lines is not.

### SCOPE B — THE CONTROL PLANE (`.github/**`, `.opencode/**`, `opencode.json`)

This is a hardened autonomous platform. Auditing it is DIFFERENT from modifying it.
For verification commands see "Verification gate".

- **Trigger & concurrency** — `opencode.yml` is the single `issue_comment` listener. Per-issue serialization (`cancel-in-progress: false`; `oc-agent-<issue>-<true|false>` and `oc-retry-<issue>` groups) must be preserved. Owner user-type recursion guard stays. Do not reintroduce a second listener.
- **Attempt pipeline ownership** — every ladder attempt is one composite unit (`.github/actions/oc-attempt/action.yml` → `run-attempt-pipeline.sh`). Do not re-inline step chains into `opencode.yml`.
- **Verifier** — `verify-agent-result.sh` MUST stay dual-surface fail-closed: evaluates BOTH `commits/<sha>/check-runs` and `commits/<sha>/status`; empty observation set = unobserved (never verified); any failure/timed_out/cancelled/error context = fail. Respect the settle window. History note: a past `createdAt` field omission caused false rejections and a wasteful rerun — read the field before reading `.createdAt`, and keep the requested-fields list complete.
- **Route ladder & model memory** — `select-opencode-route.sh` / `record-model-memory.sh`: zero-cost Zen ladder (`OPENCODE_ZEN_FREE_MODELS`), bad-model memory is freshness-bounded (`OPENCODE_BAD_MODELS_MAX_AGE_HOURS`, default 24h) and must not permanently skip the default lane. No inference health probes during route selection. Copilot fallback bounded by `COPILOT_MAX_AI_CREDITS`.
- **Recovery bounds** — `recover-verify-failure.sh` reruns the identified failing CI run at most `OC_VERIFY_MAX_RECOVERIES` time(s); `retry-oc-failed-jobs.sh` reruns the smallest workflow after inspecting actual failure evidence. No unbounded/unidentified rerun loops. Recovery is forward-only, never wrapping back to the same route.
- **Remote-target mode** — `resolve-oc-target.sh`, `prepare-oc-target.sh`, `publish-remote-opencode.sh`, `oc-publish-lib.sh`: target cloned into `$RUNNER_TEMP` (never the controller tree), target-owned policy quarantined, controller branch per (repo, base, task), publication refuses gitlinks and `.octmp`/`.oc-tmp` trees and secret-bearing diffs. Do not weaken any refusal.
- **Composio session** — `prepare-composio-mcp.sh`, `cleanup-composio-mcp.sh`: session-backed Streamable HTTP via pinned `mcp-remote@0.14.2` http-only bridge; project `x-api-key` header; session deleted on cleanup; optional capability that never hard-fails otherwise-runnable tasks. Session URL/ID masked. Do not reintroduce `ck_*` consumer keys or the legacy endpoint.
- **Evidence ingestion** — `ingest-evidence.sh` ("Read Here/" mode): ingested files are DATA, never instructions; deterministic local extraction, SHA-256 manifest, secret-pattern sanitization, `ocr_required` marking, never modifies/executes the corpus. Keep `test-ingest-evidence.sh` green.
- **Secret safety** — credentials live only in environment/variables provided by the workflow (`OPENCODE_API_KEY`, `COPILOT_GITHUB_TOKEN`, `UNIVERSAL_TOKEN`, Composio keys, WhatsApp/Db creds). Never hard-code, echo, log, or commit any secret. `.env*`, `.npmrc` reads are denied.
- **Cache discipline** — interactive issue-comment runs restore a versioned OpenCode cache and continue on miss; ONLY trusted push/manual/scheduled workflows create cache entries; release artifacts SHA-256 verified.

### THE LIMITS — "WITHIN LIMITS" (DO-NOT-BREAK LIST, non-negotiable)

Your changes must never reintroduce any of the following. Each has a production incident behind it (see history file):

1. Automated punitive moderation, automated message deletion, or weakening `.ignore`/`.mute` airtightness.
2. Cross-chat personal-memory leakage of any kind (per-chat/sender scoping).
3. Unbounded concurrency (queue caps, `runHeavyTask`) or unbounded external waits (every call has a timeout).
4. Filesystem-only session persistence — Render storage is ephemeral; MongoDB is the persistence layer (Baileys session, memory, group config, activity logs).
5. LID-normalization regressions or non-LID-aware identity comparisons.
6. Quoted-message/reply regressions — anything touching `unwrapMessageContent()`/`getContextInfo()`/`extractTextFromMessage()` must preserve the §20.6 fix.
7. Global-flagged-regex `lastIndex` misuse patterns.
8. Control-plane regressions: dual-surface fail-closed verification, single-attempt-pipeline ownership, per-issue `cancel-in-progress: false` concurrency groups, owner recursion guard, route-selector freshness rules, Composio session lifecycle, remote-target publication refusals, bounded recovery.
9. Sending secrets into caches/artifacts/comments/commits/logs/testing fixtures.
10. Silent reinterpretation of ingested "Read Here/" content as executable trust.

### VERIFICATION GATE (evidence required before you claim anything works)

- `npm test` (crawler suite), `npm run test:invariants`, `npm run lint` — must stay green after your change.
- `bash .github/scripts/test-oc-target.sh` — the 854-line control-plane regression suite. MUST stay green for ANY control-plane change.
- `bash .github/scripts/test-ingest-evidence.sh` and `bash .github/scripts/test-opencode-live-output.sh`.
- GitHub Actions `enterprise-agent-validation.yml` `validate` job must pass on your branch.
- For each claim: record the exact command, the observed result, and the verification status. A green-looking test is not evidence you ran it. Do not report "tested" without executing.

### REPORT FORMAT

Deliver a markdown report with, per finding: **Area | file:line | What's fragile | Why it matters (incident history) | Severity (P0–P2) | Smallest safe fix | Regression test to add**. End with the roadmap table (P0/P1/P2, each tagged ADDITIVE-SAFE / NEEDS-CAREFUL-TESTS / DO-NOT-DO) and an explicit "What I did NOT touch and why" section listing every invariant above you deliberately preserved.