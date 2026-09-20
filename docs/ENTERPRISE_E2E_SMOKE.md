# Enterprise E2E Smoke Test

This smoke test exercises the controlled publication path for an OpenCode
implementation:

1. OpenCode produces a successful implementation on its isolated branch.
2. GitHub Copilot performs a read-only peer review of the resulting diff.
3. The deterministic repository validation passes.
4. The change is published through the normal `/oc` flow.

A successful OpenCode implementation is not publishable until the read-only
Copilot peer review passes. Peer-review rejection is fail-closed: validation
and publication are stopped, and the proposed change is not published.
