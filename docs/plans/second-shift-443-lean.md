# Gate output classes: silent when satisfied, loud when it could not evaluate — #443

`scripts/check-lean-chain.sh` and `plugins/dev-pipeline/skills/run-lean/lean-evidence.sh` recite
every arm they checked on a passing run. A green gate that narrates itself teaches nothing and
buries the lines that matter.

Three classes replace today's two markers:

- **(a) satisfied, including vacuously satisfied** — no output. Which internal branch verified the
  contract is a source-reading question, not a log-reading one.
- **(b) could not evaluate** — exactly one line, on the green path. Mandatory, not permitted.
- **failure** — unchanged: as loud and as specific as today.

Satisfied arms are silent _unconditionally_, including on runs that end non-green. The output is
streamed, not buffered: the failure line already names the arm that failed, which is the context
that matters.

## Class (b): the pinned shape

Both files pin the same shape, because the two follow-on tickets in this decomposition emit into
this class and must not each invent one.

| Property     | Value                                                                                         |
| ------------ | --------------------------------------------------------------------------------------------- |
| stream       | **stdout**                                                                                    |
| prefix       | the gate's own tag, then three spaces and `· ` — `[lean-chain]   · ` / `[lean-evidence]   · ` |
| body         | `<arm>: <disposition> — <reason>`                                                             |
| dispositions | the closed set `not-applicable`, `reduced-strength`, `postdated`, `inert`                     |

`postdated` and `inert` are unused here and reserved for the successors. The set is declared once
per file as `LEAN_OUTPUT_DISPOSITIONS`, and the emitter refuses (rc=2) a disposition outside it, so
a successor cannot widen the vocabulary by typing a new word at a call site.

## Acceptance Criteria

- **AC-1** — WHEN `scripts/check-lean-chain.sh` runs on a lean PR whose every arm is class (a)
  THEN it writes nothing to stdout or stderr and exits 0.
- **AC-2** — WHEN `plugins/dev-pipeline/skills/run-lean/lean-evidence.sh` runs its `check` / `all`
  dispatch under the same condition THEN it writes nothing to stdout or stderr and exits 0. Its
  `classify` dispatch is exempt: `check-lean-chain.sh` parses that output as a delegation contract.
- **AC-3** — WHEN an arm cannot evaluate THEN it emits exactly one line on the green path, carrying
  its arm name and one disposition from the closed vocabulary, and the run still exits 0.
- **AC-4** — The freshness precedence-skip and the no-inherited-coverage line are class (a). An
  ordinary green PR with no armed design lane and no inheritance chain produces no output at all.
- **AC-5** — Failure-path output is unchanged for every failure case an existing selftest already
  covers.
- **AC-6** — No verbose or opt-in-output flag is introduced. "Silent" means both streams.
- **AC-7** — Every arm retains a kill criterion: for each arm whose green-path assertion was
  removed, some case still fails when that arm is disabled. Demotion to a bare exit-status
  assertion does not satisfy this, and the mutation sweep is the witness.
- **AC-8** — A contributor-doc paragraph states the obligation: a new arm ships with its producer's
  capability stamp, its not-applicable path, and its silence-on-green. **Explicitly non-scored** —
  repo convention forbids prose-presence guards, and the enforcement lives in the mechanism above.
  (The issue numbers this AC-6; it is renumbered here so every criterion in this spec has a unique
  ordinal.)
- **AC-9** (doc, added during BUILD) — Every in-repo text this change makes inaccurate is
  corrected in the same diff. Concretely: `plugins/second-shift/templates/consumer/second-shift-ci-check.sh`
  tells a consumer's operator to read the payload's output to learn which rc=0 reading applies,
  and after this change a complete lean PR prints none — so the shipped `ok` message and the
  comment above it must name the class-(b) decline line as the discriminator instead. Repo
  convention requires a change that makes docs stale to carry an explicit doc criterion; this is
  it.
- **AC-10** (harness, added during BUILD) — `lean-gate-selftest.sh` passes with `RUN_ID` exported
  in the ambient environment, not only with it absent. Found by this run's own milestone 3: case
  `(d5)` invokes `$GATE entry 7` without `env -u RUN_ID`, and `entry` PERSISTS the run-id cache,
  so an operator's exported id seeds the fixture cache and `(k6)`'s `cmd_mark` no-op test later
  resolves an id no fixture marker carries — falling through to the LIVE `$GH_BOT` write path. The
  suite is therefore green in CI, which exports no `RUN_ID`, and red for any operator who followed
  SKILL.md step 2 and kept theirs exported. Every sibling `entry` case already guards this; the
  fix is to make `(d5)` match them. Unrelated to this ticket's subject and fixed here anyway: it
  blocked this run's own green gate, and a harness bug worked around rather than closed is the
  thing that costs the next run the same cycle.

## The line inventory

Every green-path line in the two guards, and its class.

### `scripts/check-lean-chain.sh`

| Today                                                           | Class               | After                                  |
| --------------------------------------------------------------- | ------------------- | -------------------------------------- |
| whole-gate `non-lean change — … not applicable` block (4 lines) | (b)                 | one line, `lean-chain: not-applicable` |
| `applicable via <trigger>`                                      | (a)                 | removed                                |
| `source issue: #<key>`                                          | (a)                 | removed                                |
| `✓ spec: …`                                                     | (a)                 | removed                                |
| `✓ claim: …`                                                    | (a)                 | removed                                |
| `✓ authorship: …`                                               | (a)                 | removed                                |
| `note: the claim comment carries no session_id …`               | (b)                 | `authorship: reduced-strength`         |
| `· freshness (inferred): skipped — … precedence`                | (a) — AC-4 names it | removed                                |
| `✓ freshness (inferred): …`                                     | (a)                 | removed                                |
| `✓ freshness (declared): …`                                     | (a)                 | removed                                |
| `· verdict record declares no inherited coverage`               | (a) — AC-4 names it | removed                                |
| `✓ inheritance chain: N inherited link(s)`                      | (a)                 | removed                                |
| `· spec declares no armed design render lane`                   | (a) — AC-4 names it | removed                                |
| `· render receipt present, but there is no verdict record …`    | (b)                 | `design-evidence: not-applicable`      |
| `✓ design evidence: …`                                          | (a)                 | removed                                |
| final `lean evidence complete for #<key> …`                     | (a)                 | removed                                |

### `plugins/dev-pipeline/skills/run-lean/lean-evidence.sh`

| Today                                                           | Class | After                                     |
| --------------------------------------------------------------- | ----- | ----------------------------------------- |
| whole-gate `non-lean change — … not applicable` block (3 lines) | (b)   | one line, `lean-evidence: not-applicable` |
| `applicable via <trigger>`                                      | (a)   | removed                                   |
| `source issue: #<key>`                                          | (a)   | removed                                   |
| `✓ verdict record: …`                                           | (a)   | removed                                   |
| `· identity: UNAVAILABLE AT REDUCED STRENGTH — … jira …`        | (b)   | `identity: reduced-strength`              |
| `✓ authorship: …`                                               | (a)   | removed                                   |
| `✓ freshness (declared, patch-id …)`                            | (a)   | removed                                   |
| `· no intent-gap record for #<key> …`                           | (a)   | removed                                   |
| `✓ intent gap: … ratified`                                      | (a)   | removed                                   |
| final `lean evidence complete for #<key>.`                      | (a)   | removed                                   |

## Decisions

- **D-1 — the whole-gate decline keeps its diagnostics, inside the one line.** The decline's
  reason text carries the head branch, the resolved key and the "a lean spec IS present but it is
  not this PR's key" note. Collapsing to a bare `not-applicable` would drop the only facts an
  operator argues a misclassification with, and AC-3 constrains the line count, not its width.
- **D-2 — `plugins/dev-pipeline/skills/run-lean/lean-reconcile.sh` is untouched.** It is named
  neither in the ticket's scope nor in its out-of-scope list, but it falls squarely under the
  rationale that excludes `pipeline-doctor.sh`: an operator-run diagnostic whose output _is_ its
  product, read deliberately rather than skimmed in a job log. Its own copy of the
  no-inherited-coverage line therefore stays.
- **D-3 — the `LEAN_BRANCH_PREFIX` retirement notice is outside the taxonomy and stays.** It
  reports an _input_ the caller supplied, not the outcome of a check, so it is neither a satisfied
  arm nor an arm that could not evaluate. It fires only for a workflow still setting a constant
  retired in #413, which is not the ordinary green PR AC-1/AC-2 quantify over.
- **D-4 — the suites replace each removed green-path grep with an explicit total-silence
  assertion.** `rc=0 && output is empty` is a real assertion about both streams, not the bare
  exit-status demotion AC-7 forbids: it fails the moment any arm starts narrating again. The
  arms' kill criteria remain their existing negative cases, which are unchanged (AC-5).
- **D-5 — two chain cases lose an observable and are re-armed differently.** `(V3b)`
  (self-inheritance) and `(V6b)` (the walk's header-anchored read one level down) pinned the
  printed _link count_, which class (a) removes. For `(V6b)` an rc-observable replacement exists
  and is added: a prior record whose body quotes a **non-resolving** value dangles under a
  first-match walk and passes under a header-anchored one. For `(V3b)` none exists — an unbounded
  walk is provably the bounded walk plus one self-link with an identical terminal state, so no
  exit code and no message can separate them. Its site (`CHAIN_PAST -eq 1`) is `cmp-eq` ordinal 6
  and sits outside the sweep's `K=2` window, so the sweep loses nothing; the case keeps rc=0 plus
  the silence assertion.

## Obligations

Mutation-baseline rows for both edited guards are re-keyed in the same diff, and any
mutation-catalog row addressing them is re-anchored.

## Design

Design: none — both artifacts are shell guards and their CI job log; there is no rendered surface.
