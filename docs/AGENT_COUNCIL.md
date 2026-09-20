# OpenCode Agent Council

## Purpose

This repository uses a multi-model council around the OpenCode primary build agent to reduce single-model blind spots.

The council does not fuse model weights. It fuses independent evidence and reasoning at explicit gates.

## Roles

| Agent | Model | Role | Mutation |
|---|---|---|---|
| architect-reviewer | opencode/big-pickle | Architecture, correctness, state, performance, maintainability | Read-only |
| adversarial-reviewer | opencode/mimo-v2.5-free | Security, reliability, edge cases, resource/failure analysis | Read-only |
| adjudicator | opencode/mimo-v2.5-free | Evidence reconciliation and decision ledger | Read-only |
| verifier | opencode/big-pickle | Fresh post-change verification / second-pass audit | No tracked edits |

OpenCode supports project-local Markdown agents under .opencode/agents/, and the primary agent can invoke them as subagents.

## Coding-task lifecycle

task -> Brain A -> Brain B -> adjudication -> implementation -> deterministic validation -> fresh verifier -> correction loop if needed -> final CI -> PR

The two first reviewers are independent. Brain B does not receive Brain A's report before its own inspection.

The adjudicator does not use majority voting. It resolves claims by evidence quality and requests reproduction/research where required.

The verifier is a fresh context. A passing test suite alone is not sufficient for final acceptance.

## Audit lifecycle

audit -> Brain A -> Brain B -> adjudication -> fresh second-pass verifier -> final report

The verifier treats the first audit as a hypothesis set and actively searches for missed findings and unsupported conclusions.

## Confidence rules

Use explicit statuses:
- CONFIRMED — directly established from repository/runtime evidence.
- REPRODUCED — failure or behavior reproduced by execution.
- SUPPORTED — strong evidence but not fully reproduced.
- UNVERIFIED — plausible but missing decisive evidence.
- REJECTED — evidence contradicts the claim.

Never treat model agreement as proof.

## Recovery budget

A normal council run allows two independent reviews, one adjudication, one verifier, and up to two correction/re-adjudication loops.

If a high-impact disagreement remains unresolved after reasonable evidence gathering, stop at the evidence boundary and report the uncertainty.

## Provider policy

The council uses currently configured free OpenCode Zen models by default. The repository's existing Copilot path remains the fallback route, but Copilot fallback is explicitly not represented as independent two-model evidence.

The free Zen catalog is time-limited and may change, so CI validates the agent configuration and runtime discovery before an OpenCode task runs.

## Security boundary

Reviewers do not receive edit permission. The verifier may use shell inspection/testing but is instructed not to mutate tracked files or GitHub state. The primary Build agent remains the only worker authorized to implement changes through the repository's existing guarded workflow.

## Maintenance

When OpenCode changes agent configuration syntax, model availability, or Task/subagent semantics, update the council files and validation checks together. Revalidate with the OpenCode agent list command and a real controlled /oc task.
