# Plan — perf-retro: cross-run execution-latency retrospective skill

## Context / problem framing

The improvement loop has one retro axis. `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` scores a
single run for **correctness** — eval re-score, contract-deviation audit, environment friction — and
routes findings through a ladder that reaches for cheaper enforcement first. Nothing in that loop pushes
back on **latency**, so every improvement lands as another gate, another round, another serialized
dispatch, and run wall-time drifts upward unopposed.

The timing data to argue against that already exists and has no systematic consumer:

- `stages.N.startedAt` / `completedAt` in every run-state file.
- `plugins/dev-pipeline/skills/run/tools/stage-times.sh` — pause-aware per-stage effective time plus
  inter-stage gaps, whose own header reads "optimize from this data, not from impressions".
- `.claude/audit/<session>.jsonl` — timestamps on every tool call and `SubagentStop`, from which
  per-dispatch latency is derivable by differencing.

`pipeline-retro` spends one paragraph on this data and real retros repeatedly conclude "no timing
finding". This change adds the second axis as a sibling skill, cross-run by default, with quality held
as an explicit invariant rather than a hope.

## Assumptions

- The skill is **prose only**. It shells out to the existing `stage-times.sh`; it introduces no script,
  no selftest, and no new state field. This follows the repo tier map, under which prose gets no test.
- The corpus is the operator's own recorded runs. `.claude/pipeline-state/` is gitignored, so the
  window is machine-local by construction — a fresh clone has an empty corpus, and that is the expected
  steady state, not a defect.
- The report is a gitignored artifact under `.claude/pipeline-state/`, matching the sibling's
  `{issue}-retro.md` convention.
- No release artifact is touched: no `plugin.json` version, no `CHANGELOG.md`, no marketplace metadata.
  Skill registration is the file's existence.

## Decision Ledger

Rows hydrated verbatim from the pre-flight ledger at `.claude/pipeline-state/{issue}-ledger.md`.

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Separate skill vs extending pipeline-retro Step 4 | Separate sibling skill; quality retro stays per-run, perf retro is cross-run with different inputs and different outputs | user-answered |
| D-2 | Skill name and invocation | perf-retro, invoked /dev-pipeline:perf-retro; the plugin namespace already carries the pipeline context | user-delegated |
| D-3 | v1 ships scripts or prose only | Prose only; reuses tools/stage-times.sh per run; zero new test surface per the CLAUDE.md tier map | user-delegated |
| D-4 | Safety posture for optimization candidates | Every candidate names an existing regression guard or routes as needs-guard-first; gate-weakening changes are never applied directly | user-answered |
| D-5 | Handling of untrustworthy timing windows | Fidelity triage excludes degraded windows from aggregates and routes each defect as an instrumentation finding | codebase-derived |
| D-6 | Per-agent dispatch latency source | Audit-ledger SubagentStop differencing when present; Workflow runtime bans Date.now so workflow-side timing is out of scope | codebase-derived |
| D-7 | Routing and approval mechanics | Reuse the pipeline-retro Route improvements ladder, meaningful-issue bar, and approval gate by reference, not by copy | codebase-derived |
| D-8 | Landing path | Filed as issue 225 for a dev-pipeline run (operator overrode the drafted direct-PR path) | user-answered |
| D-9 | Cross-run scope and corpus bound | Cross-run by default over the 15 most recent trusted runs; argument widens the window or focuses one issue; enumeration is gated on a stages key and excludes stale snapshots | user-delegated |

Four further decisions were resolved at intake from the codebase, and are recorded here as
`codebase-derived` because they close gaps the ticket left underdetermined:

| ID   | Decision | Resolution | Provenance |
| ---- | -------- | ---------- | ---------- |
| D-10 | Which co-resident artifacts the enumeration must exclude | Gate on the top-level `stages` key and exclude both quarantine families — `*-stale-*` and `*-released-*`. The recorded corpus contains bare `{key}-stale-{ts}.json` files that are complete state files carrying `stages` with a distinct `runId` from the live run of the same key, so the clause is load-bearing; `reclaim --release` quarantines a live state file to `{key}-released-{ts}.json` with `stages` intact, which the ticket's stated gate would admit | codebase-derived |
| D-11 | Disambiguating the single overloaded integer argument | A bare integer means issue focus, mirroring the sibling's `<issue-number>`; `--last N` widens the window. Stated once in the usage line so neither reading is guessed | codebase-derived |
| D-12 | Where the corpus is enumerated from | The state directory resolves against the main checkout, following `statectl`'s `state_dir` precedence anchored via `--git-common-dir`. A bare glob relative to the session cwd is empty inside a worktree, while `stage-times.sh` reads the corpus correctly from one | codebase-derived |
| D-13 | Same-day report filename collision | A second run on the same date overwrites, matching the sibling report's posture. The read-only hard rule is scoped to existing run state and tracker items so it does not read as forbidding the Step 6 write | codebase-derived |

## Affected files/modules

| Path | Change |
| ---- | ------ |
| `plugins/dev-pipeline/skills/perf-retro/SKILL.md` | `[NEW]` — the skill |
| `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` | one boundary line in Step 4 |
| `plugins/dev-pipeline/skills/run/SKILL.md` | name the second sibling in the Post-Run Eval paragraph |
| `docs/namespaces.md` | add the qualified invocation to the rule-1 example list |
| `.claude/SECOND-SHIFT.md` | add `perf-retro` to the dev-pipeline skills line |
| `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` | same edit, identical text |

All six exist except the first. Unverified references: none.

## Reuse inventory

- `plugins/dev-pipeline/skills/run/tools/stage-times.sh` — the per-run timing source. Invoked read-only,
  once per selected run. Already resolves the state directory from the main checkout, so it works
  unchanged from a worktree.
- `plugins/dev-pipeline/skills/pipeline-retro/SKILL.md` "Route improvements" — referenced **by section
  title** for the dedup-first rule, the enforcement-mechanism ladder, the meaningful-issue bar, the
  approval gate, and the route table. Not copied; the repo's no-mirror rule makes a duplicated copy
  worse than none, because a copy cannot fail when the original changes.
- `.claude/audit/<session>.jsonl` — the existing audit ledger, read for `SubagentStop` differencing.
- `plugins/dev-pipeline/skills/run/statectl.sh` `state_dir` precedence — the resolution rule the skill's
  enumeration prose mirrors rather than reinvents.

No new helpers introduced.

## Implementation steps

1. Author `plugins/dev-pipeline/skills/perf-retro/SKILL.md` `[NEW]` with frontmatter (`name`,
   `description`), a qualified usage line carrying the D-11 argument contract, the hard rules, six
   numbered steps, and the report template. Mirror the sibling's shape and stay at sibling-parity
   length.
2. Step 1 (Gather): enumeration gated on a top-level `stages` key, both quarantine families excluded
   per D-10, anchored at the main checkout per D-12, bounded to the 15 most recent by `startedAt`,
   completed and aborted runs both in scope; per-run inputs named (`stage-times.sh`, `cost-log.jsonl`,
   existing retro timing paragraphs, audit ledgers for sessions on disk).
3. Step 2 (Fidelity triage): the five degraded signals, exclusion from aggregates, and the mandate that
   each fidelity defect route as an instrumentation finding — deduped by mechanism, never by ticket
   number.
4. Step 3 (Profile): the per-stage effective-time table that is the measured baseline every candidate
   must cite; shares computed over the sum of listed stage times with lifecycle-dropped stages as
   explicit known-unknown rows.
5. Step 4 (Candidates): the four-field record — evidence, mechanism, risk class, regression guard — with
   the `needs-guard-first` route for anything guard-less or gate-weakening, and a short seed list marked
   explicitly as examples rather than a checklist.
6. Step 5 (Route): defer to the sibling's "Route improvements" section by title, adding only the
   perf-specific obligation that a filed candidate quotes its measured baseline.
7. Step 6 (Report): the report path, its four sections, and the inline summary.
8. Land the five cross-references. The two consent docs are edited identically — their dev-pipeline
   skills line is byte-identical today and no lockstep-manifest row covers the pair, so the mirroring is
   by hand.
9. Self-lint the plan, then run the repo verification triple.

## Test strategy

Verify-after; this is a prose/infra change with no behavior surface. The repo's tier map routes prose to
**nothing** — a grep asserting a markdown file contains words cannot fail for a reason a reader of the
diff would not already see, and the no-prose-presence-guards rule forbids writing one. `unitTestSurface`
is `skip`: the repo declares no `unitTestScope`, so there is no mutation surface.

The real behavioral check is an operator dry-run of the finished skill against the recorded corpus. It
is executable from this worktree — `stage-times.sh` anchors on the main checkout — and must show the
enumeration selecting run-state files only, the two known-bad windows classified degraded, and a stop at
the approval gate with proposed routes only.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| ----- | ----------------- | ------- | ------- |
| AC-1 | Skill file exists, prose-only, qualified usage, hard rules, six steps, report template, sibling-parity length | 1 | — no test (infra-only) |
| AC-2 | Step 1 gated on `stages` key, excludes quarantined snapshots, 15-run default with widening/focusing argument | 2 | — no test (infra-only) |
| AC-3 | Step 2 lists the five degraded signals, excludes from aggregates, routes each defect | 3 | — no test (infra-only) |
| AC-4 | Every candidate carries evidence / mechanism / risk class / regression guard; guard-less or gate-weakening routes `needs-guard-first` | 5 | — no test (infra-only) |
| AC-5 | Step 5 defers to the sibling's "Route improvements" section by title, no copied routing prose | 6 | — no test (infra-only) |
| AC-6 | All five cross-referenced files updated | 8 | — no test (infra-only) |
| AC-7 | Negative: no frozen release artifacts, no new scripts or selftests, no `eval-criteria.md` edit, no persisted perf-profile artifact, no ticket-number literals in the skill prose | 1–8 | — no test (infra-only) |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

Change-specific, beyond the triple:

```bash
# AC-7: no frozen release artifact in the diff.
bash scripts/check-frozen-files.sh origin/main
# AC-7: no ticket-number literals in the new skill prose (expect no output).
grep -nE '#[0-9]{2,4}' plugins/dev-pipeline/skills/perf-retro/SKILL.md
# AC-6: both consent-doc copies name the new skill identically.
grep -h 'Skills:' .claude/SECOND-SHIFT.md plugins/second-shift/templates/consumer/SECOND-SHIFT.md | sort -u
# AC-1: sibling-parity length.
wc -l plugins/dev-pipeline/skills/perf-retro/SKILL.md plugins/dev-pipeline/skills/pipeline-retro/SKILL.md
```

## Risks / rollback notes

- **Routing prose drifts from the sibling.** Mitigated by referencing the section by title instead of
  copying it — the failure mode the repo's no-mirror rule exists to prevent.
- **A perf candidate weakens a gate.** This is the change's central risk and the reason the risk-class
  and regression-guard fields are mandatory rather than advisory: a candidate with no named guard cannot
  be applied, only routed as `needs-guard-first`.
- **Degraded windows silently skew the profile.** Mitigated by triaging fidelity before aggregating, and
  by carrying lifecycle-dropped stages as explicit known-unknown rows rather than omitting them, which
  would understate a stage's share.
- **Rollback** is deleting the new file and reverting five one-line edits. No state, no schema, no
  release artifact is involved.

## Out-of-scope

- Instrumentation changes — additional pause-span recording sites, per-dispatch timers, cost-block
  hardening. The first real run of the skill routes these as evidence-backed findings; the stage-entry
  timing warning is already separately scoped.
- Any new eval criterion. `eval-criteria.md` is untouched.
- Fixing the sibling's own bare, non-resolving usage-line spelling. Visible and inconsistent with the
  qualified spelling required here, but not asked for by this ticket.
- Appending the prose-budget ratchet row for the new file. The ticket reserves this as an operator step
  after merge. A missing row is a warning and never a failure, so nothing breaks in the interim.
- Adding a lockstep-manifest row for the two consent docs.
