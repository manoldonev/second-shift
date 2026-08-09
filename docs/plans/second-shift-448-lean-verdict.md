# lean review verdict — #448

verdict=approve
run_id: review-448-2
session_id: e3eade22-fa7c-4e0e-bf1b-9109fc6be9e9
rounds: 2
pr: #461
reviewed_head: c78ce39ef6fe8d52b8684a75534c9a2897981d92
reviewed_patch_id: 025f4e1c23637009fb9a144d1d7885c9a4246a18
inherited_patch_id: a5ae3b4074fb75df08318855b44aedc2581a6545
inherited_from_verdict: 51d7e178307cc9dfd8f8007cd34c928e3ab9f298
fidelity: not-applicable
model: unknown

Round 2, delta `51d7e17..c78ce39` (5 files), inheriting the coverage of patch `a5ae3b4074fb`
from the round-1 record. Round 1's blocker and both warnings are addressed; each fix was
confirmed by execution rather than by reading, and no new blocker was introduced.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | resolved (was round-1 blocker) | `tools/selftest-cache-inputs.tsv:36-79` | The depth-2 closure is now declared and, independently traced, complete. Three rows added: `eval-criteria.md` and `tools/ledger-corroborate.sh` for `statectl-selftest.sh`, `tools/gh-bot.sh` for `cost-block-selftest.sh` — exactly the three files round 1 proved could move a cached suite's verdict while appearing in no row. I re-derived the closure from the tree rather than accepting the commit message: every `$here/`-style resolution out of **every** declared script terminates inside the declared set. `gen-statectl-validators.sh` resolves `state-schema.md`, `eval-criteria.md`, `statectl.sh` (all declared); `statectl.sh` resolves `tools/ledger-corroborate.sh` (declared) and otherwise only the gitignored config and state dirs; `pipeline-cost-block.sh` resolves `tools/gh-bot.sh` (declared), which resolves an out-of-repo wrapper under `$HOME`. `scenario-lib.sh`, `stage-times.sh`, `ledger-corroborate.sh` and `mutation-gate.mjs` invoke no further repo script. The suites' own direct references (`${SKILL_DIR}/…`, `$FIX/…`, `$HERE/../pipeline-cost-block.sh`) are each declared. The row comments' termination claims are accurate. |
| 2 | resolved (was round-1 warning) | `tools/run-selftests.sh:81, 296-302` | The runner's own bytes are on the key axis (`runner=<blob>` in the manifest header), resolved from `BASH_SOURCE` rather than `$ROOT` — correct, since `--root` may name a tree not containing the script. Unhashable runner returns 1, so the key is empty and every suite runs: fail-closed, same as any unhashable input. The hash is computed after the `[[ -f "$list" ]]` guard, so only rowed suites pay for it. **The new assertion is live, not decorative** — I probed it in an isolated worktree at this head: stripping `\|runner=%s` and its argument out of `cache_manifest` (syntax-checked, `cmp`-verified non-no-op) reds exactly `runner-axis: one byte changed in the runner` and nothing else, suite `FAIL (1)`. The two sibling cases (seed, control) stay green, so the block cannot pass vacuously. |
| 3 | resolved (was round-1 warning) | `docs/testing.md:121`, `docs/plans/second-shift-448-lean.md:71` | Both now name `CACHE_EPOCH`, matching `tools/run-selftests.sh:96`. |
| 4 | suggestion | `docs/plans/second-shift-448-lean.md:56-58` | The key-composition sentence folds `run-selftests.sh`'s own blob id into the `(D-13)` attribution, but ledger `D-13` lists only `RUNNER_OS`, the bash major version, the suite path, the declared-input hashes and the epoch. `SKIP_STRESS` is correctly flagged as "beyond D-13's list" two paragraphs down; the runner blob id is not, so a later auditor comparing spec to ledger finds an attribution the ledger does not carry. One clause. Not a blocker: the axis itself is justified in the very next paragraph, and it strengthens containment rather than weakening an AC. |
| 5 | note | issue #448 body | The issue still carries AC-8, AC-9 and its original six-suite input table verbatim, with no closing note and no linked follow-up; the retirement and the narrowing live only in the committed spec and in `.claude/pipeline-state/448-ledger.md` (D-4, D-7, D-9, D-15, OR-2). Under this lane that is sanctioned — the pre-flight ledger is a binding input that overrides the issue body, and D-15's preserved numbering gaps exist precisely so the retirement stays visible — so it is not a blocker and not an unsatisfied AC of this spec. It is worth a line on the issue at close, because the issue is the artifact an outside reader finds first. See the panel note below. |

## Reviewer panel

Six selected. `security`, `performance`, `maintainability`, `complexity` each returned
**approve with zero findings**; their suppressed items (a writable cache dir being trusted at
conf. 40, `gh-bot.sh` as a declared input at 35, the selftest executing a copy of the runner at
30, the long doc line at 55) I read and agree are below threshold.

**`test-coverage-reviewer` went dark** (`turn-budget: agent emitted no text on either attempt`,
after its automatic retry) — a coverage gap, not a pass. One reviewer of six is a partial panel,
so the round stands. I covered that domain by execution instead, which is the stronger evidence
here: `tools/run-selftests-selftest.sh` runs green at this head standalone (8s, all cases
including the three new `runner-axis` ones), and the round's only new assertion block was probed
to destruction as recorded in finding 2.

**`scope-completeness-reviewer` returned `block`** on three items — AC-8 unsatisfied, AC-9
unsatisfied, and the table covering 2 of the 6 suites the issue names. All three are factually
correct **about the issue body**, and all three are the same object as finding 5. That gate scores
against the GitHub issue; this lane's definition of done is the committed lean spec, whose
`## Binding input` section retires AC-8 and AC-9 on the pre-flight ledger's authority (D-4: #447
made the install-topology guard nightly-only, so per-plugin keying has no PR lane to save on, and
AC-7 mandates the nightly bypass the cache anyway; D-7: prose-only PRs fire on 1 of the last 100
commits here because every lean PR commits its `docs/plans/*-lean.md` beside the diff) and narrows
the row set on D-9's ≥30s measurement plus OR-2's stated default. Round 1 scored this the same
way. I am not re-litigating a ledger-sanctioned retirement in round 2 — the retired ACs are
absent from this spec's AC set, so they cannot be unsatisfied ACs of it, and the numbering gaps
are preserved so the drop is legible.

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `run-selftests-selftest.sh:346-352` — the rowed suite is served while the un-rowed one still prints its run marker on the same hot store; fail-closed without `--cache-dir` asserted at `:355-358`. Green in my standalone run at this head. |
| AC-2 | satisfied | Six `reject_case` arms (`:530-555`), each asserting `rc=2` **and** the named cause, plus a green control over the same fixture (`:559-564`). All run without `--cache-dir`, so "validated on every sweep" is asserted too. Green in my run. |
| AC-3 | satisfied | `:391-429` — seed, control hit, then editing only the declared subject reds with `cache: 0 served`. Strengthened this round: the three added rows put the depth-2 inputs on the key, and finding 1 confirms the closure now terminates inside the declared set, which is what makes this AC true of the *shipped* table and not only of the mechanism. |
| AC-4 | satisfied | `:499-505` — the un-rowed suite reds while its rowed neighbour is served in the same run. Green in my run. |
| AC-5 | satisfied | `:436-466` — exact marker counts before/after a red run, a passing control on the identical fixture, and a verdict-less worker (`RUN_SELFTESTS_DROP_RC=1`) leaving an empty store. Green in my run. |
| AC-6 | satisfied | `:479-492` — `--cache-dir` alone records nothing, the `--cache-write` control does record, `--cache-write` without a store is `rc=2`. Workflow side unchanged this round: `ci.yml` gates both the flag and `actions/cache/save` on `push`, and `on.push.branches` is `[main]`. |
| AC-7 | satisfied | Runner side `:355-358` — a live marker is ignored with no `--cache-dir`. Workflow side unchanged this round: `nightly-guards.yml`'s two `wholesale-selftests` jobs pass no `--cache-dir` and carry the same `--exclude` and `SKIP_STRESS` asymmetry as `ci.yml`. |
| AC-10 | satisfied | `:366-379` — the printed key must be the key the marker is filed under, and the skip block must name every declared input with a 40-hex blob id. The delta additionally surfaces `runner=<blob>` in the same `over:` header line, so the new axis is visible to a log reader rather than silent. |
| AC-11 | satisfied | `docs/testing.md:65-131`. The four containment properties are still enumerated (`:81-95`); the delta adds "Derive the closure, not the file list" (`:114-119`), which documents the one thing nothing mechanizes, and corrects the constant's name (`:121`). Round 1's finding 3 is discharged. |
| AC-12 | satisfied | Unchanged by this delta; inherited from the round-1 record. No `install-topology.yml` reference survives outside historical verdict records and the deliberate "this file was" note in `nightly-guards.yml:16`. |

AC-8 and AC-9 are retired by `.claude/pipeline-state/448-ledger.md` (D-4, D-7); the numbering
gaps are preserved as D-15 requires. Every AC in this spec's landing set is satisfied.

**The residual risk is unchanged and correctly stated in-tree.** Nothing mechanizes the
transitive closure — self-inclusion and subject-inclusion are both satisfiable by a set that
under-declares at depth 2, which is what round 1 caught. The delta's response is the honest one:
it records the obligation in the table's comments, in `docs/testing.md` and in the spec, rather
than claiming a check it does not have. AC-7's nightly cache-bypassing sweep is the backstop that
turns an under-declaration into a next-day red instead of a permanent silent skip.

## CI at this head

`lint-and-selftests` pass · `selftests (macos, bash 3.2)` pass · `mutation-sweep-pr` pass with
`tools/run-selftests.sh applied=14 killed=14 survived=0`, so the guard-edit mutation obligation is
discharged at `c78ce39` and no new baseline row is owed. `pr-gates` reds solely on the round-1
record reading `verdict=needs-work` — the expected pre-verdict state, superseded by this record.

## Design fidelity

`not-applicable`. The spec's `## Design` section is an architecture section — no handoff link and
no `| RS-n |` render-state rows — and the repo's `.claude/second-shift.config.json` carries no
`design` key at all, so the disarm is justified rather than a missed arming.
