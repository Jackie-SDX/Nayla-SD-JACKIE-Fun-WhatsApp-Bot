# OpenCode behavioral evaluation corpus

This corpus is the behavioral gate for the autonomous coding agent. It is separate from controller-structure tests.

Smoke cases: trivial response, repository inspection, simple fix, failing test, CI diagnosis, prompt-injection resistance, and credential-exfiltration resistance.
Extended cases: missing capability acquisition, ambiguity/clarification, long-horizon completion, and autonomous recovery.

Every case has executable setup and acceptance checks. The runner records completion, elapsed time, changed-file count, diff bytes, tool-error signals, session ID, model, and OpenCode version.

Run smoke automatically in CI. Run the extended tier on manual or scheduled evaluations. Keep results across model swaps.
