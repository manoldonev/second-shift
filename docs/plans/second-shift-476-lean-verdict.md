# lean review verdict — #476

verdict=approve
run_id: review-476-2
session_id: 4384cce9-82d8-4167-ac45-1b31856498e7
rounds: 2
pr: #480
reviewed_head: ca9c26802b4289b7c5adc9dd12bb4067d8aa2e30
reviewed_patch_id: 3cd5035cf7c0e128dc5dd9711bbab44821e8a4e0
inherited_patch_id: 204b708a28370e25f684e02f29224f9565c66d33
inherited_from_verdict: 7b83100a25b7b96bcb0c058b313cc8bee63bf4cc
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2 — `review-476-2`. Verdict: **approve**. No blockers. Round 1's blocker is fixed and
verified by execution under both interpreters; two warnings and one suggestion, all
non-blocking.

Inherited coverage: patch `204b708a2837` (round 1, `docs/plans/second-shift-476-lean-verdict.md`).
Read this round: `7b83100..ca9c268` — the single fix commit — plus round 1's findings, plus the
whole register and both scripts at head, because the register is small enough that reading it
whole is strictly stronger than reading its diff.

## Round 1's blocker is closed, and the proof is execution not prediction

**B-1 (round 1) — `tools/capability-parity-check.sh` was inert under bash 3.2 and failed OPEN.**
Both `declare -A` arrays are now newline-delimited accumulators: duplicate detection reads back
with `awk -F'\t' '$2 == ENVIRON["c"]'`, coverage with `grep -qxF`. I ran the paired suite under
stock `/bin/bash` 3.2 driven through CI's own PATH shim (`ln -sf /bin/bash /tmp/bash32/bash`,
`PATH=/tmp/bash32:$PATH`, confirmed `GNU bash, version 3.2.57(1)-release`):

| Check | bash 5 | stock bash 3.2 |
| --- | --- | --- |
| `tools/capability-parity-check-selftest.sh` | 18/18 | **18/18** |
| `tools/capability-parity-check.sh` against the real register | OK — 37 rows | **OK — 37 rows** |

CI agrees at this exact head: run `31403195255` at `ca9c268` has `selftests (macos, bash 3.2)`
**success**, alongside `lint-and-selftests` and `mutation-sweep-pr`. The one red job is
`pr-gates`, and its only failing step is `lean chain reconciliation`, failing for exactly one
reason — the verdict record on the branch still reads `verdict=needs-work`, which is the record
this round replaces. `frozen files guard`, `changelog trailer guard` and
`pipeline chain reconciliation` all pass. That is the designed pre-handoff state, not a finding.

## Every assertion in the guard now has a verified killer

I mutated the guard line-exactly (`python3` line replacement, `bash -n` after each, and the
applied diff printed and checked — a mutant that does not apply scores as a vacuous green, and
two of my first-pass `perl` substitutions silently did exactly that before I re-ran them):

| Mutation | Cases that flip | Verified |
| --- | --- | --- |
| path-whitespace trim (131-132) → `:` | **(b) (e2) (m)** | bash 5 **and** 3.2 |
| coverage accumulator write (133) → `:` | (a) (b) (e2) (m) | bash 5 |
| coverage `err()` (153) → `:` | (e) | bash 5 |
| enum case arm (70) → always true | (c) (d) (l) | bash 5 |
| field-count `-ne 3` (90) → never fires | (f) (g) | bash 5 |
| empty-cell check (106) → never fires | (h) (h2) (h3) | bash 5 |
| zero-rows floor (137) → never fires | (j) | bash 5 |
| empty-stages-dir note (157) → `:` | (k2) | bash 5 |
| duplicate lookup → `awk '{ exit }'` | (i) | bash 5 |

Round 1's **W-1 is genuinely closed**: the beta fixture's path order is what does it, and the
suite comment says so in the imperative ("do not tidy it"). Note what the same probe also shows —
the real register still passes with the trim removed (`real-tree rc=0`), because every stage doc
happens to be cited first somewhere too. That is fine and it is the design: the fixture, not the
production register, is what carries this assertion, which is exactly what round 1 asked for.

W-3 (`.mjs` rooting), W-4 (coverage-clause causality), W-5 (delegated protocol docs), S-7 (the
mis-resolving second positional) and S-8 (the zero-`.md` branch) are all closed and spot-checked:
all 34 distinct cited paths exist on disk, all 11 `.mjs` citations are repo-root relative, and the
new `Changelog:` trailer states the precondition direction correctly.

## Findings

### Warnings

**W-1 — three assertions introduced by this round's rewrite have no killing case.** Found twice
independently — `unit-test-mutation-reviewer` predicted all three (confidence 80), and I then
scored them by execution. All three leave the suite at **18/18** and the real register green:

| Mutation | Result | What it costs |
| --- | --- | --- |
| `grep -qxF` → `grep -qF` (drop `-x`) | **survives 18/18** | whole-line → substring: a citation that is a strict superstring of a real stage-doc path masks that doc as covered |
| `grep -qxF` → `grep -qx` (drop `-F`) | **survives 18/18** | literal → regex: `.` and `-` in a path become metacharacters |
| `ENVIRON["c"]` → `awk -v c=` | **survives 18/18** | restores backslash-escape processing on the duplicate needle |

Each of the three is defended by a comment naming the failure it prevents (lines 111-113 and
150-151) — and none of them is exercised, which is the same shape as round 1's W-1 in a guard
whose entire value is that it cannot pass what it did not judge. The `-x` case is the one that
matters: its failure direction is a **false green on an uncovered stage doc**, the exact class
this guard exists to prevent.

Three one-line fixtures cover all three, and each is a real kill I checked the mechanics of:
- create `$SB_STAGES/4-delta.md` and cite `…/stages/4-delta.md.bak` — without `-x` the real
  file substring-matches the backup citation and the guard passes; with `-x` it reds;
- create `$SB_STAGES/1-alpha.md` and cite `…/stages/1XalphaXmd` — without `-F` the `.`
  metacharacters match and the guard passes;
- duplicate a capability literally named `alpha\tbeta` — `-v` expands `\t` to a TAB, which no
  field can equal, so the duplicate slips through; `ENVIRON` compares it literally and reds.

Not a blocker, and this is the same call round 1 made on the same shape: an execution-verified
surviving mutant in this guard was W-1 there too, non-blocking, and the round approved. The
difference from B-1 is the one that decides it — B-1 was a guard that *was* inert, in the diff;
this is a guard that works and whose two grep flags a future edit could remove unnoticed. No AC
names these flags, the suite proves all three of AC-6's named red paths under both interpreters,
and reaching the `-x` hole needs a hand-written superstring citation nobody has written. It is
the round's one piece of unpaid test-the-tests debt, and the natural first item if a round 3
happens for other reasons.

**W-2 — two rows under-cite the artifacts that actually carry their contract, and the staged
lane's own entry point is cited by no row at all.** This round closed W-3 and W-5 for the `.mjs`
files and the delegated protocol docs; the same class survives in two places, one of them in the
row this round added:

- Row 72 `review-exhaustion handoff artifacts` cites `stages/8-code-review.md`,
  `stages/9-open-pr.md`, `statectl.sh` — but the contract is also stated in
  `skills/run/SKILL.md:649` (the resume/idempotency table) and `:687` (the draft-PR policy
  paragraph that names both `needs-deep-review` and `codeReviewExhausted`), and defined in
  `skills/run/state-schema.md:103`.
- Row 74 `dark-reviewer and voided-round handling` cites `stages/8-code-review.md` and
  `workflows/code-review.mjs`; `codeReviewVoided` is implemented in `statectl.sh` and defined in
  `state-schema.md:104`.
- `plugins/dev-pipeline/skills/run/SKILL.md` is cited by **zero** rows. It is the staged lane's
  entry point, `#348` deletes it, and `#348`'s parity story is keyed on deleted paths — so that
  deletion matches nothing, which is precisely the failure W-3 was raised about.

Not an AC-5 miss — both capabilities have a row with an in-enum disposition, and the guard's file
universe is `stages/*.md` by design (D-14/D-17), so no citation gap can red. It is an accuracy
gap in the handoff `#348` will read.

**W-3 (carried, deliberately unfixed) — row permanence is asserted and enforced nowhere.** Round
1's W-6. The PR body declines it explicitly and gives the reason: the guard for it compares
against history rather than the working tree, and its only exercise is `#348`'s own deletion PR.
Flagged rather than smuggled in, which is the right call. Re-recorded here so it does not
evaporate between this round and `#348`.

### Suggestions

**S-1 — a stale comment contradicts the header two lines after the header makes its claim.**
`tools/capability-parity-check.sh:143-144` still reads "Resolved against `$ROOT` so an **override
dir** under a sandbox still yields the citation form the register uses" — written when the second
positional existed, which this same commit removed, and which line 42 now says is "deliberately"
absent. Reword to the actual mechanism: the sandbox relocates `$ROOT` by copying the checker, so
`STAGES_DIR` is derived, never overridden. (maintainability-reviewer, confidence 85; I confirmed
the contradiction independently.)

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-2 | **satisfied** | Was the round-1 blocker. The oracle now judges the register on every lane CI runs: 18/18 and a green real register under stock 3.2 locally, and `selftests (macos, bash 3.2)` green in CI at this head. The coverage clause is live — killing its `err()` flips (e), killing the accumulator write flips (a)(b)(e2)(m) — and it fires on an uncovered doc's presence, which is the precondition direction the AC now states. |
| AC-5 | **satisfied** | 37 rows = 4 seeded + 33 proposed (18 `already-covered` / 16 `dropped` / 2 `choreography` / 1 `ported`), matching the PR body name-for-name, and the four seeded rows carry their settled dispositions. The +1 over round 1 is the `review-exhaustion handoff artifacts` row, which closes round 1's W-2 exactly as W-2 proposed — and its claims check out: the three tokens live only in the staged lane, and `grep` over `run-lean/` and `review-lean/` finds none of them and no round cap. Round 1's full stage-doc walk is inherited; the stage docs are unchanged in this delta. All 34 distinct cited paths exist. |
| AC-6 | **satisfied** | The CI step is unchanged and in the right job, and the AC's three named red paths are each execution-verified rather than asserted: off-enum → (c)(d)(l), uncovered stage doc → (e), malformed row → (f)(g)(h)(h2)(h3), and the duplicate red alongside them → (i). All hold under bash 3.2 as well as bash 5, which is what round 1 found they did not. |

Design fidelity: **not-applicable**. The spec's `Design: none — <reason>` disarm is justified —
the repo's config declares no `design` key, and no changed path is a rendered surface.

## Strengths

- **The remedy was verified before it was believed.** The PR body says "Verified, not predicted:
  18/18 under stock `/bin/bash` 3.2 driven through CI's own PATH shim" — and it reproduces
  exactly, on the shim, at this head. A round-1 approve died precisely because a green local
  sweep was mistaken for lane coverage; this round does not repeat that.
- **The fixture reorder is a real kill, not a plausible one.** Round 1 asked for the beta row's
  paths to be reordered so the trim becomes load-bearing. It is: the trim mutant now flips
  (b)/(e2)/(m) under both interpreters, where round 1 measured it surviving 17/17.
- **The header now argues against its own simplification.** The BASH 3.2 block does not say
  "don't use `declare -A`"; it says what `declare -A` costs here — an arithmetic subscript, a
  `set -u` death mid-loop, and **exit 0** — so the next reader knows the failure mode is silent
  success rather than a diagnosable error. That is the difference between a note and a guard
  rail.
- **W-6 was declined in the open.** The PR body names it, explains why the fix is a different
  guard shape, and says whose PR would exercise it. A round that fixes five findings and quietly
  drops the sixth is the common failure; this is not that.

## Panel

7 reviewers selected, 7 returned, none dark. `test-coverage-reviewer` died once and returned on
its automatic retry.

The convergence worth naming: `unit-test-mutation-reviewer` predicted W-1's three survivors from
reading alone, and my 12 line-exact mutants then scored them — agreeing on all three, and on the
nine that die. Prediction and execution reached the same list, which is the strongest form this
dimension's evidence takes.

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matched
`stageParams.webComponentGlobs`, which resolves to the shipped default `apps/web/**/*.{tsx,jsx}`
(the repo's config declares no override).

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope Completeness | Pass | 0 |
| Security | Pass | 0 (2 suppressed, conf 20-25) |
| Performance | Pass | 0 (1 suppressed, conf 60) |
| Complexity | Pass | 0 |
| Maintainability | Pass (with nit) | 1 minor, conf 85 → S-1 |
| Test Coverage | Pass | 0 |
| Unit Test Mutation | Fail | 2 (1 major + 1 minor, both conf 80) → W-1 |

W-2 is the orchestrator's own, from walking the register's citations against the staged lane's
real file set; W-3 is round 1's W-6, carried forward.
