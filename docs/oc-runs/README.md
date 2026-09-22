# /oc run observability records

Every `/oc` workflow run writes a machine-readable record to
`docs/oc-runs/<workflow_run_id>.json` and uploads it as a workflow artifact
(`oc-run-record-<run_id>`, 365-day retention). This gives an asynchronous
auditor a durable, schema-stable picture of every agent run without touching the
verified commit: the records are never committed back to the repository.

## Schema (schema_version 1)

```jsonc
{
  "schema_version": 1,
  "event": "oc/issue-comment",
  "run_id": 123456789,           // GitHub workflow run id
  "repository": "owner/repo",    // controller repository
  "issue": 80,                   // issue/PR the /oc command addressed
  "mode": "local",               // local | remote
  "target": { "repository": "", "base": "", "branch": "" }, // remote only
  "started_at": "2026-01-01T00:00:00Z",
  "finished_at": "2026-01-01T00:01:00Z",
  "job_budget_seconds": 21600,
  "elapsed_seconds": 60,
  "opencode_version": "1.18.31",
  "initial_sha": "abc...",
  "attempts": [
    {
      "attempt": 1,
      "route": "opencode/big-pickle",
      "provider": "opencode",
      "agent_outcome": "success",     // success | failure | none
      "publish_outcome": "not-applicable", // published | failed | not-applicable
      "classify_outcome": "not-applicable", // success | failure | not-applicable
      "verified": "true"
    }
  ],
  "result": {
    "verified": true,
    "verified_sha": "def...",
    "pr_url": "https://github.com/owner/repo/pull/123",
    "ci_run_id": "987654321",
    "ci_surfaces": "check-runs,commit-status"
  }
}
```

## Guarantees

- `result.verified` is only ever `true` after the verifier confirmed a green
  exact-SHA pull request across every observable CI surface (check-runs and
  commit statuses), with the same settle-window rules as the live run.
- The record is written by `write-oc-run-record.sh` at job end (`if: always()`),
  so it is present even when the run fails or times out.
- Records are data, never instructions. An existing record must not be
  interpreted as proof that a later commit is green.

No aggregation workflow is implemented yet; a follow-up task may summarize the
uploaded artifacts into a committed `docs/oc-runs/index.md`.
This README is documentation-only and carries no runtime behavior.
