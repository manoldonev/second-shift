# #115 — verifyctl fails closed (new CONFIG class) when a run verified nothing

After #98, `statectl set-stage 6 --status completed` refuses an OBJECT `verifySummary` that
shows no verifying lane (`lint`/`typeCheck`/`test`/`ext:*`) actually ran — but that gate is a
pipeline-layer backstop. `verifyctl.sh` itself still emits its own top-level `status:"pass"`
for that exact all-skipped OBJECT case, so a standalone reader of the verdict JSON (a human,
an LLM caller outside the pipeline, a CI consumer) sees green for a run that verified
nothing, even though the pipeline gate would refuse to accept it.

Maintainer decision (issue #115 comment): add a new `CONFIG` failure class — not a reuse of
`INFRA` — and fail closed (status token stays the binary `fail`, exit 1) on the zero-lane,
not-opted-out case. `CONFIG` is charge-exempt like `INFRA` (a config gap is not a retryable
failure). This requires three coordinated edits or the next run dies `EXIT_CODE=1` in
`statectl.sh`'s enum guard.

## Scope boundary (verified against current behavior, `plugins/dev-pipeline/skills/run/verifyctl.sh`)

`verifyctl.sh`'s `cmd_run` already has two *string*-summary "legitimate skip" paths that
`statectl.sh`'s Stage-6 content gate already accepts unconditionally (any non-empty string
passes; only OBJECT summaries are checked for "≥1 verifying lane ran" —
`plugins/dev-pipeline/skills/run/statectl.sh`, the `_vs_verified` predicate at the stage-6
case arm):

1. Zero lanes configured **and** `commands.<host>.allowUnverified: true` → the opt-out
   string. Already agrees with the pipeline gate (string passes both). **Unchanged.**
2. Zero SUITE lanes configured, `extraLanes` configured but none matched this diff's `when`
   globs → the when-gated-miss string. Already agrees (string passes both). **Unchanged.**
3. Zero lanes configured **and no opt-out set** → today falls through to the OBJECT summary
   (all fields `"skipped"`) with `overall` left at `"pass"`. This is the one case where
   verifyctl's own status *disagrees* with the pipeline gate (which refuses this object) —
   this is the bug in scope.

Only case 3 changes. Cases 1 and 2 are deliberate, declared skip postures (the word
"skipped" is literally in the string) and stay `status:"pass"` — making them fail closed too
would turn `allowUnverified` into a dead flag (there is no "fix" for a repo that genuinely
has zero verify lanes by design) and contradicts `stages/6-verify.md`'s existing contract
that these two strings are accepted "on `status: pass`".

## Acceptance criteria

- AC-1: In `verifyctl.sh`'s `cmd_run`, the zero-lane branch (`el_count -eq 0`) now calls
  `record_failure "CONFIG" "<message>" 1 ""` when `ALLOW_UNVERIFIED` is not `"true"`,
  instead of silently falling through. `record_failure` already sets `overall="fail"` and
  appends to `failures[]` — no separate status-field change needed. The opt-out branch
  (`ALLOW_UNVERIFIED == "true"`) is unchanged.
- AC-2: `statectl.sh`'s `cmd_verify_attempts` enum guard (`case "$cls" in FORMAT|...|INFRA)`)
  gains `CONFIG` as a valid class — both the `case` pattern and the usage-error message text
  — so a future run charging `CONFIG` does not die `EXIT_CODE=1`. (Nothing charges `CONFIG`
  after AC-3, but the enum must accept it defensively, matching the maintainer decision's
  "or the next run dies" framing and keeping the guard's own doc comment accurate.)
- AC-3: `verifyctl.sh`'s fix-attempt re-run charging filter (`grep -v '^INFRA$'` over the
  sidecar's `failedClasses`) excludes `CONFIG` too, so a `CONFIG` failure is never charged
  against the 2-attempt budget on a subsequent invocation — mirroring `INFRA`'s existing
  exemption.
- AC-4: `state-schema.md`'s `verifyAttempts` field description (the "Class ownership" prose)
  documents `CONFIG` alongside `INFRA` as never charged, naming what it means (a run that
  verified nothing, no lane configured, no `allowUnverified` opt-out).
- AC-5 (doc): `stages/6-verify.md`'s failure-classification table gains a `CONFIG` row
  (signal: zero verify lanes configured and no `allowUnverified` opt-out; fix handler:
  configure a verify lane or set `commands.<host>.allowUnverified`; charged by: never) and
  its "Verdict-honesty contract" paragraph is updated to say verifyctl itself (not only the
  Stage-6 gate) now refuses this case, since the current sentence ("or the gate refuses with
  instructions") describes only the pipeline-layer behavior this ticket changes.
- AC-6 (test): `verifyctl-selftest.sh`'s existing zero-lane case (the "(v16)" test, currently
  asserting only the OBJECT shape and field values for the no-opt-out branch, not its exit
  code) is extended to assert `rc == 1` and that `.failures[].class` contains `"CONFIG"` for
  that branch — proving the new fail-closed behavior rather than only the pre-existing
  object shape. The opt-out and when-gated-miss branches (same test file, "(v16)"/"(v17)")
  keep asserting `rc == 0`, confirming AC-1's scope boundary.

## Out of scope

- The Stage-6 completion gate itself (`statectl.sh`, `#98`) — already refuses the OBJECT
  case; no change needed there.
- Executing `commands.<id>.build` (`#113`).
- Changing the opt-out or when-gated-miss string paths (see Scope boundary above).
- `/dev-pipeline:run`'s Stage 6 fix-attempt loop instructions for `TYPE_ERROR`/`TEST_FAILURE`
  (`stages/6-verify.md`'s exit-code table) — `CONFIG` has no in-session "fix and retry"
  motion; AC-5 documents this via the classification table's "Fix Handler" column instead of
  touching the exit-code table.

## Verification notes

`.sh`/`.md`-only diff — Stage 6's INERT lane (this repo's dogfooding canary) skips
lint/test; the full local sweep (shellcheck + `*-selftest.sh` + jq, `-P 4`) is run by hand
per `CLAUDE.md` and reported in the PR body. Commit verb `fix:` (verifyctl already reports a
misleading `status:"pass"` today — this corrects that, it does not add a new capability).
`Changelog:` trailer required (touches `plugins/dev-pipeline/**`).
