# lean review verdict — #613

verdict=needs-work
run_id: review-613-1
session_id: b6a5f573-7a81-4633-94af-0ff789f68199
rounds: 1
pr: #626
reviewed_head: 2fcaf12d6d76a9b4d266107804d7ba01e3527ce5
reviewed_patch_id: 843e20baeb12833f224b0a402047c746575b6ffc
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review Summary

Round 1, full-branch range `4e3cc3c3..HEAD`, 19 files / +1713. The mechanism is well built and
the design reasoning is carried in the code rather than in a plan nobody re-reads. The closed
gate enum, the write-side-only attendance check, the `\037` separator fix, and the LOCKSTEP copy
of the reader in the payload are all correct calls, and each is argued at its site. Both flagship
consumers are wired end to end and guarded at the surface a real run takes.

One blocker: the merge-boundary half of AC-5 is implemented but **unguarded**. Deleting
`delegate override` from `scripts/check-lean-chain.sh` leaves every suite green — verified by
probe. That is the boundary silently validating nothing, which is the exact class the repo's
"Scenario-first" rule exists for, and the arm this PR mirrors (`intent-gap`) is guarded at both
levels.

Panel: 5 of 6 reviewers usable. `test-coverage-reviewer` went dark (died after retry,
maxTurns-cap). That dimension was covered directly by this session — reading every new suite and
running the mutation-style probes below — so the round is not short a domain, but the reduced
panel is recorded.

## Verification performed in this session

| Check | Result |
| --- | --- |
| CI on head `2fcaf12d` | `lint-and-selftests` pass · `selftests (macos, bash 3.2)` pass · `mutation-sweep-pr` pass · `pr-gates` fails ONLY on the absent verdict record (expected pre-handoff) |
| shellcheck (CI recipe, 7 changed scripts) | clean |
| `check-lockstep-pairs.sh` | 26 anchors, 0 failed — includes the new `override-record-reader` pair |
| `check-fail-open-shapes.sh` | 13 sites, all dispositioned — unchanged, so AC-6's reconciliation clause holds |
| **Probe A** — the fetched-ALONE property | `lean-evidence.sh` copied into an empty dir with **zero siblings** still refuses a bad `scope:` and an empty `run_id:` and passes a well-formed record. The rationale for the LOCKSTEP copy is real and the copy works. |
| **Probe B** — the `\037` fix at the boundary | an empty `run_id:` is reported as `run_id is empty`, not as a bogus `expiry` — the IFS-whitespace collapse is genuinely gone on the boundary's copy, not just the mechanism's |
| **Probe C** — `record` with an unvalidated `--issue` | writes the file, then refuses; a traversal-shaped value lands the artifact outside `plansDir` |
| **Probe D** — mutant: delete `delegate override` | `check-lean-chain-selftest.sh` **green**, `lean-evidence-selftest.sh` **green**, `scenario-liveness-selftest.sh` **green**. Nothing catches it. |

## Blockers

**B-1 — the merge boundary's override arm has no guard at the surface AC-5 names.**
`scripts/check-lean-chain.sh:820`

AC-5 binds "the merge-boundary chain check validates every present override record". It does, and
`lean-evidence-selftest.sh` (ov1–ov5) proves the *payload* arm. What nothing proves is that the
chain **calls** it. Probe D: with `delegate override` deleted, `bash -n` clean, all three
candidate suites go green. A lost or typo'd arm name is worse than a removed check — `run_arms`
matches `*,override,*`, so `delegate overide` runs zero arms, emits zero violations and exits 0.
The boundary reports clean while reading nothing.

This is the shape CLAUDE.md's Scenario-first paragraph was written from: "the stacked-PR path died
with all 42 selftests green because every one of them checked a component against itself."
`lean-evidence-selftest` checks the payload against itself.

The precedent this PR explicitly claims to follow is guarded on both rungs — the intent-gap arm
has chain-level cases `(S1)`/`(S3)` in `check-lean-chain-selftest.sh`, not only payload-level
ones. Mirroring `(S1)` for a malformed override record is the fix, ~15 lines.

Not asking for more than that: the behavior is correct today and Probe A/B confirm it. What is
missing is the thing that keeps it correct.

## Warnings

**W-1 — `record` builds its path from an unvalidated `--issue` and writes before validating.**
`plugins/dev-pipeline/tools/operator-override.sh:296-323` (security-reviewer, confidence 88;
reproduced here)

`record_path` interpolates `--issue` straight into `$root/$PLANS_DIR/$REPO_SLUG-$issue-...`, and
`mkdir -p` + the header + the block are all written before `override_block_violation` ever sees
the value. Probed: `--issue '../../escaped'` creates and populates
`docs/plans/escaped-lean-override.md` and then refuses; `--issue` omitted entirely writes
`acme--lean-override.md`.

No privilege boundary is crossed — the caller is an attended operator session that already holds
filesystem write, which is the stated posture. The concrete cost is two-sided:

- an orphaned artifact at a path nobody will look at, and
- for a typo'd `--gate`/`--scope` (which lands in the *correct* file), a malformed block that now
  makes `check` return 2 for that issue on every subsequent run — the lane hard-refuses with an
  environment error until a human hand-edits the record. The tool creates the artifact that
  blocks the lane.

The post-write parse-against-the-artifact validation is the right authoritative check and the
comment defending it is correct — this is not a request to replace it. Add the numeric guard on
`$issue` (the `case "$issue" in ''|*[!0-9]*)` shape already at line 254) before `record_path` is
called, and/or assemble the block in a temp file, parse it, and append only on a clean read.

## Suggestions

- `override_affordance` (lean-gate.sh) says "One command per region" but interpolates only
  `${1%%,*}`. On a two-region refusal the operator gets one command and has to infer the second.
- `cmd_check` assigns `ex` without a `local` declaration (line 443) while its siblings `g`/`rg`
  are declared at 391 — no behavioral effect, just an asymmetry a reader will trip on.

## Not findings (checked, and they hold)

- **`arm_override` does not evaluate the persistent register's expiry.** Deliberate, argued at
  the site, and D-14 records the reasoning with the phase-2 pointer. The register is empty today,
  so the common path pays no `gh` round-trip.
- **The headless refusal never mentions the override route.** AC-4 binds the headless sentence
  byte-for-byte; this is the AC being satisfied, not an omission.
- **Exit 3 fires for headless unintaken rejects too, not only attended ones.** Consistent with
  D-13 ("applied only when the unintaken probe is the sole failure" — not "only when attended"),
  the `run-lean` SKILL exit table is updated, and `(g2b)` pins that a second failing probe keeps
  it at 2.
- **`LEAN_ATTEND_MODE` added to both `SEAM_SCRUB` copies.** Necessary, not a weakening: a lane
  command is where the override suite's own attended cases run, and the session-id binding remains
  the belt that holds.
- **AC-6's fail-open reconciliation.** `check-fail-open-shapes.sh` enumerates the same 13
  dispositioned sites; no `scripts/fail-open-sites.tsv` row is owed.

## AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `operator-override-selftest.sh` (a)(b)(c)(d)(e)(f)(p) cover absent / corrupt / session-mismatch / run-mismatch / marked-headless / self-asserted-env; **(g)** is the one AC-1 names — a FORGED token resolves attended and still yields nothing |
| AC-2 | satisfied | (h)(i)(i2–i5) bind gate, region, issue and scope identity; (n) refuses persistence in a per-issue record; (m1–m5) cover the register's live / expired / unevaluable / unjustified / date-shaped rows |
| AC-3 | satisfied | `orchestrate-lean-selftest.sh` (g1) rc=3 + `preflight-rejected-resumable` + unchanged wording + `attendance: headless`; (g1b) no affordance leaks headless; (g2b) not resumable alongside another failure; (ov1) attended-no-record still rejects; (ov2) a record accepts with **zero tracker writes**; (ov3) malformed fails closed |
| AC-4 | satisfied | `lean-gate-selftest.sh` (yo1) override clears the region, (yo2) another region's does not, (yo3) headless refusal unchanged with no affordance spliced in, (yo4) attended-no-record still refuses and prints the command, (yo5) malformed is rc=2 and spends no fix attempt |
| AC-5 | satisfied (functionally) — **guard gap, see B-1** | the record names gate/run/decision/scope; the yield path refuses before the record exists (yo4, ov1); the boundary refuses malformed and mis-expired records — verified independently by Probe A/B. What is absent is any guard that the chain keeps delegating the arm |
| AC-6 | satisfied | closed `OVERRIDE_GATES` enum with (k) proving a third gate is an error; `check-fail-open-shapes.sh` unchanged at 13 sites; no gate outside the two consumers changes behavior |
| AC-7 | satisfied | `scenario-liveness-selftest.sh` `(lean-override)` composes an attended-session record through a HEADLESS milestone-1 run, with `(lean-override-nv)` proving non-vacuity; `docs/pipeline-manifesto.md` carries the trust posture and the local-gate residual |

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass (1 minor) | 1 | 88 |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | **Dark (no output)** | — | — |
| Orchestrator (this session) | Fail | 1 blocker | 95 |

Coverage gap: `test-coverage-reviewer` died after retry (maxTurns cap). Its domain was covered
directly by this session — every new suite read, and four probes run, one of which is B-1.

**Ready to merge?** No — B-1.

**Reasoning:** the mechanism is correct and independently verified at the boundary, but the
boundary's own delegation is the one surface in this PR that no suite holds; a probe deleting it
leaves all three candidate suites green. One chain-level case mirroring `(S1)` closes it.
