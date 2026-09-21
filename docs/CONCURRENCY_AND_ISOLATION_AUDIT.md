# Concurrency and Isolation Audit

Status: AUDITED at commit `72a04739cf24d8a7b65202faf1b28b0782ea8873` (2026-09-21).

This document records the concurrency, isolation, and serialization properties of the
OpenCode control plane and the host application, the reasoning behind each decision,
and the invariants that must not be reintroduced.

## 1. Control-plane workflow concurrency groups

| Workflow | Trigger keys | Group | cancel-in-progress | Purpose |
| --- | --- | --- | --- | --- |
| `opencode.yml` | issue_comment / PR review comment | `opencode-${{ issue.number \|\| pr.number \|\| run_id }}` | `false` | Main `/oc` and `/opencode` agent runs |
| `oc-control.yml` | issue_comment / PR review comment | `${{ issue.number \|\| pr.number \|\| run_id }}` | `false` | `/oc retry failed jobs` control lane |
| `enterprise-agent-validation.yml` | push, PR, dispatch | `enterprise-agent-validation-${{ github.ref }}` | `true` | Repo validation (fast, read-only, ref-scoped) |
| `oc-enterprise-e2e-self-test.yml` | PR, dispatch | `oc-enterprise-e2e-self-test-${{ github.head_ref \|\| github.ref }}` | `true` | Application e2e self-test on the PR head |
| `opencode-cache.yml` | push to main, dispatch, cron | `opencode-cache` | `false` | Cache creation (single lane by design) |

Rules that make this safe:

1. **Same issue, never concurrent.** Every `/oc` request for the same issue number
   serializes on the shared `opencode-<issue>` group with `cancel-in-progress: false`,
   so an older in-flight run is never killed mid-mutation by a newer one. This prevents
   two agents mutating the same working/PR state for the same issue at the same time.
   Newer runs queue instead of cancel.
2. **Cross-issue parallelism is preserved.** Parallel missions happen across issues,
   not within one. Verification targets exactly the PR/head for the current run
   (`verify-agent-result.sh` resolves the merged/head SHA for `opencode/issue<issue>-<ts>`
   or `oc/copilot-<target>-<run_id>` branches), so distinct runs verify distinct state.
3. **Ref-scoped validation only.** Validation and e2e self-test groups are scoped to the
   ref and may cancel a stale run of the *same ref* (an old result becomes meaningless
   once the ref moved), but never touch other refs.
4. **Control lane is separate.** `/oc retry failed jobs` runs under its own group and
   `if` filter; it cannot overlap with an agent run for the same issue. It retries only
   after inspecting the failing run, per the recovery architecture.

## 2. Why same-issue serialization (and not per-task parallelism)

The alternative is parallel same-issue runs on distinct branches merged by a controller.
Analysis of the existing architecture rejected this:

- The controller does not own a merge/migration ceremony; publication pushes the single
  derived branch (`opencode/issue<N>-<ts>`) and opens one PR per run. Two concurrent
  same-issue runs would race to create/update the same PR family and to post mutually
  conflicting result comments for the same issue.
- Evidence comments and `/oc continue` markers are issue-scoped; concurrent writes to
  the same issue thread would interleave.
- GitHub Actions `issue_comment` events can be delivered out of order; serializing on
  the shared group makes the ordering legal by construction ("oldest started wins the
  issue"). Scoping the group per issue keeps unrelated issues operating in parallel.

Decision: **keep `cancel-in-progress: false` same-issue serialization** and document it,
rather than introducing same-issue parallelism. Latency cost is bounded by issue, and
correctness/merge-race safety is preserved.

## 3. Branch isolation

- Main branch is shared but treated as a protected production line; all mutation is
  funneled through derived branches per run. The verified workflow creates unique
  branches such as `opencode/issue71-20260921101112` (per run) and copilot
  `oc/copilot-<target>-<run_id>` (pinned run id), then pushes and opens a PR. See
  `post-oc-continuation.sh:18` and `verify-agent-result.sh:272-273`.
- Remote-target runs publish through the controller-owned publication guard, refusing
  nested gitlinks and `.octmp`/`.oc-tmp` scratch, and are verified against the target
  repo's own PR/head state, never controller worktree state.

## 4. Recursion guard (self-trigger isolation)

- `opencode.yml` requires `comment.user.type == 'User'` and the comment author to equal
  `github.repository_owner`, so the bot's own comments can never trigger a new run
  (bot comments are typed bots, and non-owner users are ignored). See PR #58.
- `/oc continue` resumes the same captured branch; it never descends into a *new* task
  on its own output.
- Timeouts checkpoint durable state and require an explicit user resume comment;
  nothing re-fires automatically.

## 5. Host application isolation invariants

The repo's own product (WhatsApp bot, `index.js`) must keep these properties, which are
already implemented and verified:

- **Per-chat memory isolation**: active conversation memory is a per-chat Map keyed by
  `jid` (`groupMessageBuffers.set(jid, ...)` — `index.js`); memory for one group can
  never surface in another; on removal the bot deletes every per-chat structure
  (`groupMessageBuffers.delete(event.id)` etc., `index.js`). No cross-chat personal
  memory leakage.
- **Bounded concurrency**: a single load-shedding guard prevents unbounded queue growth
  (`index.js`, "[LOAD SHEDDING]"); `ACTIVE_CONTEXT_CAP` bounds the rolling window
  (`index.js`).
- **Bounded external waits**: external calls are wrapped with hard timeouts; no
  unbounded external waits.
- **Non-punitive, non-destructive defaults**: no automated punitive moderation and no
  automated message deletion; deletion remains manual-only.
- **Session persistence**: Baileys multi-device state persists to MongoDB (Render
  file storage is ephemeral and never treated as durable), preserving LID identity
  handling.
- **Manual-only deletion**: as above.

## 6. Invariants to preserve

- `cancel-in-progress: false` for agent and control lanes.
- Bot never self-triggers (user-type + owner filter).
- Unique per-run branches; deterministic resume branches for /oc continue.
- Per-chat memory isolation, bounded queues, bounded external waits.
- Manual-only deletion; no punitive moderation.
- Render ephemeral storage never treated as durable; MongoDB is the persistence layer.
- Quoted-message/reply handling remains non-regressive (media placeholder regex
  `MEDIA_PLACEHOLDER_TEXT_REGEX`).

## 7. Evidence sources

- `opencode.yml`, `oc-control.yml`, `enterprise-agent-validation.yml`,
  `oc-enterprise-e2e-self-test.yml`, `opencode-cache.yml` concurrency + trigger sections.
- `verify-agent-result.sh`, `post-oc-continuation.sh` branch derivation.
- PR #58 (bot-recursion guard); PR #70 (issue69 doc PR).
- `index.js` per-chat memory, load-shedding, removal cleanup, media placeholder fix.