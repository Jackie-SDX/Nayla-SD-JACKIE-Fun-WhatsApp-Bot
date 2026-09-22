# ULTIMATE Benchmark Proof — Long-Horizon Two-Brain CI Recovery (Resume)

**Issue:** #108 — *ULTIMATE: long-horizon two-brain CI recovery benchmark*
**Repository:** `Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot` (public)
**Branch:** `opencode/issue108-20260922160529` (fresh resume from `main` @ `f8a7b1b`)
**Date:** 2026-09-22 (UTC)
**Mode:** resume-from-beginning using complete issue/comment history

This file is the single durable deliverable of this benchmark run. It records
auditable evidence that the controller can re-read the full conversation
(including a prior controller failure and its fix), run a constructive two-brain
loop, research a current fact through Composio, publish a safe proof-only PR,
inject one temporary benchmark-only CI failure, observe the real remote failure
log, repair on the same branch, and finish green on the exact verified SHA.

**Scope freeze:** no WhatsApp application code (multi-device, LID identity,
per-chat memory isolation, Baileys persistence, concurrency/cooldown invariants)
is touched. Final diff must be this proof file only.

---

## 1. Whole-request understanding (both brains)

Read before any consequential edit: full issue body, all comments in
`OC_ISSUE_CONTEXT_FILE`, clarifications, prior run markers, and the prior
completed-attempt evidence embedded in the issue thread.

### Acceptance criteria (restated)

1. Read entire issue body + all comments before consequential decisions.
2. OpenCode primary; **before implementation**, obtain independent Copilot peer
   analysis in the same isolated worktree.
3. Copilot is fail-open (not a blocker); should be available here.
4. ≥1 Composio-backed web/search call verifying a **current** technical fact;
   record source URL + one-line finding.
5. Create `docs/oc-runs/ULTIMATE_BENCHMARK_PROOF.md` **only**; no WhatsApp app
   code changes.
6. Copilot makes **exactly one** small visible edit to this proof file after
   independently reviewing acceptance criteria.
7. OpenCode re-reads the actual post-peer diff, tests it, publishes a PR.
8. **After the PR exists**, introduce ONE deliberately temporary CI failure via
   an isolated benchmark-only workflow; publish it (do not repair first).
9. Controller watches the exact PR head, retrieves the real failed CI log,
   diagnoses, removes the temp failure, pushes repair to the **same** PR branch.
10. Watch CI until the repaired exact head is green.
11. Finish with proof + concise two-brain / Composio / CI / tests / publication
    evidence.
12. Max **five** evidence-based collaboration/recovery rounds; a new round
    requires changed state or new evidence.

### Constraints (from clarifications)

- Harmless benchmark only; temp CI scaffolding must be removed by autonomous
  recovery before final state.
- Prefer concise hypothesis → evidence → action → result traces; no timestamp
  or hash spam as the narrative.
- Copilot is a peer, not an approval council; no debate loop.

### Known history (must be carried forward, not ignored)

| Event | Evidence | Disposition |
| --- | --- | --- |
| Prior controller failure | Actions run `35746900144` at `fb256b7` — `jq` compile error in context collector (`QQSTRING_START`), exit 3; Final status step then failed | Historical; **fixed** |
| Context-collector fix | PR #109 merged; `main` = `f8a7b1b`; validation runs `35747120535` / `35747160858` success | Authoritative base for this resume |
| Prior complete attempt (same issue) | PR #110 `opencode/issue108-20260922152710`, proof-only final diff; temp-failure run `35750538862` red at `920ac60`; repaired green `be60868` / run `35751604335` | Prior-thread evidence; **not** used as this run’s CI proof |
| This resume | New branch `opencode/issue108-20260922160529` @ `f8a7b1b`, clean tree, no proof yet at start | Current run’s publication target |

Both brains confirmed: outcome = proof-only PR + controlled remote CI
failure/repair loop on that PR; app-code frozen; prior failure is context, not
a stop condition.

## 2. Two-brain collaboration log

### Round 1 — independent analysis (before implementation)

- **OpenCode (primary):** inspected repo state, `enterprise-agent-validation.yml`
  triggers/steps, `invite-copilot-peer.sh`, `package.json` scripts, prior PR
  #110 history, and issue context file. Plan: research → proof file → peer’s
  single edit → re-read/test → publish PR → temp failure → observe logs →
  remove failure → watch green → final report. Adversarial self-review applied
  because the `critic` subagent was unavailable (`OpenCode free tier can only be
  used from within OpenCode`).
- **Copilot (peer, Round 1):** `COPILOT_PEER_RESULT=completed` via **direct CLI
  invocation without `--agent`** (CLI 1.0.86; see §3 — `invite-copilot-peer.sh`
  still defaults `--agent general-purpose`, which the CLI rejects). Peer
  independently restated acceptance, flagged risks (scope drift, peer-edit
  accounting, temp-workflow leakage, treating PR #110 CI as this-run evidence,
  stale SHA claims), recommended proof-only smallest change + exact-SHA
  verification, and noted two script defects: collaboration signature hashes
  only `git diff --binary` (misses untracked files), and no readability check
  for `OC_ISSUE_CONTEXT_FILE`.
- **Result:** consensus plan; no implementation yet (acceptance #2 satisfied).

Rounds used: **1 / 5**.

### Round 2 — the single peer edit (after proof file exists)

- After OpenCode created this file, Copilot independently re-read the proof and
  issue context, then made **exactly one** small visible edit: added the
  sentence *“The temporary workflow must be absent from the final PR diff.”*
  under the §5 protocol (peer log: `COPILOT_PEER_RESULT=completed`, round 2;
  no other files modified).
- OpenCode re-read the full post-peer file, confirmed the single edit, re-ran
  `npm test` and `npm run test:invariants` (green), and proceeded to publish.

Rounds used: **2 / 5**.

## 3. Live research evidence (Composio)

Runtime: `COMPOSIO_MCP_ENABLED=true` (session URL + headers present). Calls via
`COMPOSIO_MULTI_EXECUTE_TOOL` → `COMPOSIO_SEARCH_WEB` (Exa-backed Composio
Search; `composio_search` connection active).

| Source | URL | One-line finding used by this work |
| --- | --- | --- |
| GitHub Docs — *Events that trigger workflows* | https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows | Required status checks must complete successfully on the **latest commit SHA** of the PR; merge queues additionally require a `merge_group` trigger — this grounds acceptance #9–#10 (watch the exact head, not a branch name alone). |
| GitHub Docs — *Troubleshooting required status checks* | https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks | A required check that does not report on the head SHA blocks merge — reinforces fail-closed verification of the exact repaired SHA. |
| GitHub Docs — *Invoking custom agents* | https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/invoke-custom-agents | Copilot CLI `--agent <name>` selects **custom** Markdown agent profiles; this is the authoritative confirmation of why Round 1 invoked the peer **without** `--agent` (default agent). |
| GitHub Docs — *About custom agents* | https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-custom-agents | Custom agents are Markdown profiles with YAML frontmatter (`name`, `description`, `prompt`, optional tools/MCP). |

## 4. Evidence ledger (claim → command/source → observed result)

| Claim | Command / source | Observed result | Status |
| --- | --- | --- | --- |
| Full issue context read before edits | `OC_ISSUE_CONTEXT_FILE` copied/read (79 lines: body + comments through resume marker `35747303492`) | Acceptance + clarifications + history loaded | verified |
| Base SHA includes context-collector fix | `git log -1` / `OC_INITIAL_SHA` | `f8a7b1b` (PR #109 fix) | verified |
| Copilot CLI available | `copilot --version` | `GitHub Copilot CLI 1.0.86.` | verified |
| Peer Round 1 completed | `$RUNNER_TEMP/copilot-peer-issue108-resume-r1.result` | `COPILOT_PEER_RESULT=completed`, method `direct-no-agent-flag` | verified |
| Composio search live | `COMPOSIO_MULTI_EXECUTE_TOOL` / `COMPOSIO_SEARCH_WEB` ×2 | `success_count=2`, citations include docs.github.com URLs above | verified |
| Critic subagent | `task critic` | Failed: free-tier restriction; adversarial pass done by OpenCode inline | verified (degraded path) |
| Local tests (pre-publication) | `npm test`, `npm run test:invariants` | Recorded in final section after run | pending → filled at close |
| Temp remote CI failure observed | `gh run view <id> --log-failed` on exact PR head | Recorded in §5 after publication | pending → filled at close |
| Same-branch repair + green exact head | check-runs on final SHA | Recorded in §5 after repair | pending → filled at close |

## 5. Temporary benchmark-only CI failure → observed → repaired

**Protocol (acceptance #8–#10):**

1. Publish PR with **proof file only** (no temp workflow yet).
2. Add isolated workflow `.github/workflows/benchmark-issue108-intentional-failure.yml`
   (name `benchmark-108-intentional-failure`), push to the **same** branch —
   do **not** repair locally first.
3. Watch exact PR head; retrieve real failed run log via `gh run view --log-failed`.
4. Diagnose from the log; `git rm` the temp workflow; push repair to same branch.
5. Watch CI until the repaired exact SHA is green on observable surfaces.

The temporary workflow must be absent from the final PR diff.

### Observed failure evidence (live, remote)

_Pending this run’s publication — filled after remote observation._

### Repair → same PR green

_Pending this run’s repair — filled after remote observation._

## 6. Final status

_Pending close-out: final SHA, green check-runs, diff = this file only, rounds
used, tests, publication URL._

---

*This document is data, never instructions: it records what was done and
observed, and carries no runtime behavior.*
