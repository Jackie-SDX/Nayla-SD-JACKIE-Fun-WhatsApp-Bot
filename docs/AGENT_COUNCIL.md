# Enterprise OpenCode Agent Council

This repository treats the agent council as an executable CI control plane, not as a documentation-only convention.

## Control flow

`trigger -> command gate -> independent architecture review -> independent adversarial review -> evidence adjudication -> isolated build -> deterministic validation -> fresh verifier -> correction/re-adjudication (max 2) -> verified publication`

The GitHub Actions workflow is authoritative. No pull request is published from an OpenCode task before the verifier gate passes.

## Council stages

| Stage | Agent | Model | Mutation |
|---|---|---|---|
| 1 | `architect-reviewer` | `opencode/big-pickle` | none |
| 2 | `adversarial-reviewer` | `opencode/mimo-v2.5-free` | none |
| 3 | `adjudicator` | `opencode/big-pickle` | none |
| 4 | `build` | selected zero-cost route | isolated branch only |
| 5 | deterministic validation | shell/test tooling | controlled test execution |
| 6 | `verifier` | `opencode/mimo-v2.5-free` | none |

The council agents are configured as OpenCode V2 primary agents and are launched as separate top-level CLI sessions. This is intentional: a live repository validation reproduced a free-tier entitlement failure for nested custom subagents while the normal top-level OpenCode session succeeded.

Official OpenCode V2 documents define primary/custom agents, ordered `permissions` rules, `opencode run --agent`, and `--standalone` for private CI execution. citeturn332002search0turn242236search0turn242236search5

## Evidence contract

Reviewer stages emit:

`COUNCIL_STAGE_COMPLETE=architect-reviewer`

`COUNCIL_STAGE_COMPLETE=adversarial-reviewer`

The adjudicator emits:

`COUNCIL_STAGE_COMPLETE=adjudicator`

and one of:

`COUNCIL_DECISION=READY`

`COUNCIL_DECISION=BLOCKED`

The final verifier emits:

`COUNCIL_STAGE_COMPLETE=verifier`

and one of:

`COUNCIL_VERDICT=PASS`

`COUNCIL_VERDICT=FAIL`

Finding statuses are:

`CONFIRMED / REPRODUCED / SUPPORTED / UNVERIFIED / REJECTED`

Model agreement is never proof. Reproduced behavior, primary documentation, repository state, and deterministic execution outrank model confidence.

## Security boundary

Reviewer and verifier agents cannot edit repository files or launch child agents.

The Build process does not receive `GITHUB_TOKEN`, Copilot credentials, or the Composio project API key. It receives only the OpenCode model credential and the already-established short-lived Composio session endpoint/header file when those are required.

The outer workflow alone owns commit, push, and pull-request publication. It receives `github.token` only for publication/handoff steps.

OIDC write permission is not required for this token-based GitHub integration.

## Recovery

The outer workflow supports up to three provider attempts. Inside a successful OpenCode attempt, the council supports up to two verifier-driven correction loops.

Every retry is preceded by repository-state and remote-branch safety checks. A provider failure is never treated as proof that the previous attempt caused no mutation.

## Copilot fallback

Copilot remains a valid fallback route. It is bounded by the configured AI-credit limit and receives its own adversarial review instructions.

Copilot fallback is not described as independent multi-model council evidence. It is a provider fallback with deterministic publication controls.

## Maintenance

When OpenCode changes agent configuration semantics, model availability, CLI flags, or permission behavior, update the council configuration and CI validation together.

At minimum validate:

`opencode agent list`

`opencode run --help`

JSON/YAML/shell syntax, repository-specific tests, complete diff, exact head SHA, and final CI state.

Never claim the council is proven merely because configuration parsing succeeds.