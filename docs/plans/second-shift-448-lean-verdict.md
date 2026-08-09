# lean review verdict — #448

verdict=needs-work
run_id: review-448-1
session_id: 3af55f20-9115-4264-957f-ad19300d1ed8
rounds: 1
pr: #461
reviewed_head: 04c60cc9d4300fe1c2a50c4e0fdef1edc15a7eec
reviewed_patch_id: a5ae3b4074fb75df08318855b44aedc2581a6545
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1, full branch diff (`c19f19e..04c60cc`, 10 files). No prior record to inherit from.

The mechanism is well built and the containment argument is right. The blocker is not in the
mechanism — it is in the two rows the mechanism is pointed at. Both shipped input sets are
under-declared, and each omission was confirmed by execution, not by reading.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **blocker** | `tools/selftest-cache-inputs.tsv:42-59` | Both participating suites under-declare their inputs. Three files move a cached suite's verdict and appear in no row, so an edit to any one of them is served a stale pass on the PR lane — the silently-skipped gate this whole design exists to contain. All three verified by mutating the file and running the paired suite at this head: **(a)** `plugins/dev-pipeline/skills/run/eval-criteria.md` — `tools/gen-statectl-validators.sh` parses its locked `## Scoring` JSON to emit the `valid_eval_criteria_key` region, and `statectl-selftest.sh`'s regenerate-and-diff case byte-compares the regeneration against `statectl.sh`. Renaming one criteria key makes the regeneration DIFFER from the committed `statectl.sh` (baseline: IDENTICAL), so the drift case reds. **(b)** `plugins/dev-pipeline/skills/run/tools/ledger-corroborate.sh` — `statectl.sh:207-210` resolves and executes it, and the suite has 13 `(lcg*)` cases driving it. `exit 3` at the top of that file → `statectl-selftest.sh` **rc=11, 267 passed / 11 failed**. **(c)** `plugins/dev-pipeline/skills/run/tools/gh-bot.sh` — `pipeline-cost-block.sh:237-244` resolves and executes it whenever `tracker.bot.enabled` is true, which the suite's identity cases exercise. `exit 3` at the top → `cost-block-selftest.sh` **rc=1, 33 passed / 14 failed**. Neither omission is reachable by the runner's own checks: self-inclusion and subject-inclusion are both satisfied by these rows. This is the same transitive-closure property OR-2 used to drop `scenario-liveness-selftest.sh`; `statectl-selftest.sh` and `cost-block-selftest.sh` have it too, one level deeper, where the sets look closed. Remedy is three TSV lines (depth-2 was checked — `gh-bot.sh` and `ledger-corroborate.sh` invoke no further repo scripts, so the closure terminates there). |
| 2 | warning | `tools/run-selftests.sh:289-290` | The runner's own bytes are on no key axis. The manifest carries epoch, OS, bash major, `SKIP_STRESS`, suite path and the declared inputs — but not `run-selftests.sh` itself, which is the harness that produces the verdict. A change to how workers are dispatched or what environment they inherit is therefore served past on the next push, on exactly the suites the change is most likely to affect. This is the self-inclusion rule of property 2 applied one level up, and the fix is one `git hash-object` line in `cache_manifest`. Today's mitigation is the manual epoch bump, which OR-1 scopes to runner-*image* drift and does not mention for the runner *script*. |
| 3 | warning | `docs/testing.md:114`, `docs/plans/second-shift-448-lean.md:65` | Both name the invalidation constant `SELFTEST_CACHE_EPOCH`; the code calls it `CACHE_EPOCH` (`tools/run-selftests.sh:87`). A reader following the doc greps for a name that does not exist in the tree. |

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `run-selftests-selftest.sh:346-352` — the rowed suite is served, the un-rowed one still prints its run marker, on the same hot store. |
| AC-2 | satisfied | Six `reject_case` arms (`:530-555`), each asserting rc=2 **and** the named cause, plus a green control over the same fixture (`:559-564`). All run without `--cache-dir`, so the "validated on every sweep" half is asserted too. |
| AC-3 | satisfied | `:391-429` — seed, control hit, then editing only the declared subject reds with `cache: 0 served`; the self-inclusion half re-seeds and moves only the suite's own bytes. |
| AC-4 | satisfied | `:499-505` — the un-rowed suite reds while its rowed neighbour is served in the same run. |
| AC-5 | satisfied | `:436-466` — exact marker counts before/after a red run, a passing control on the identical fixture, and a verdict-less worker (`RUN_SELFTESTS_DROP_RC=1`) leaving an empty store. |
| AC-6 | satisfied | `:479-492` — `--cache-dir` alone records nothing, the `--cache-write` control does record, and `--cache-write` without a store is rc=2. Workflow side: `ci.yml` gates both the flag and `actions/cache/save` on `push`, and `on.push.branches` is `[main]`. |
| AC-7 | satisfied | Runner side `:355-358` (a live marker is ignored with no `--cache-dir`). Workflow side: `nightly-guards.yml`'s two `wholesale-selftests` jobs pass no `--cache-dir`, carry the same `--exclude` and the same `SKIP_STRESS` asymmetry as `ci.yml`. |
| AC-10 | satisfied | `:366-379` — the printed key must be the key the marker is filed under, and the skip block must name both declared inputs with 40-hex blob ids. |
| AC-11 | satisfied | `docs/testing.md:65-121` documents the key, all four containment properties, the pass-only/miss-on-malformed rules, the summary-line semantics, and the "adding a row is the risky edit" guidance. Finding 3 is one inaccurate identifier inside it, not a missing contract. |
| AC-12 | satisfied | No `install-topology.yml` reference survives outside historical verdict records and the deliberate "this file was" note in `nightly-guards.yml:16`. `CLAUDE.md:76`, `docs/testing.md:243` and the `ci.yml:196` comment all point at the rename. |

AC-8 and AC-9 are retired by `.claude/pipeline-state/448-ledger.md` (D-4, D-7); the numbering gaps are preserved as D-15 requires. Every AC that landed is satisfied — finding 1 is not an AC violation, because no AC covers the completeness of the shipped table. That gap is itself worth noting: the runner mechanizes self- and subject-inclusion, and nothing mechanizes the transitive closure the two shipped rows actually needed.

## Obligations

Mutation obligations discharged as the spec requires: `tools/mutation-baseline.tsv` drops
`tools/run-selftests.sh::default::2` with the displacement reasoning recorded as a comment
(`tsv_rows()` skips `#` lines, so the parser is unaffected), and `tools/mutation-catalog.tsv`
gains three rows, one per mechanizable containment property.

## Design fidelity

`not-applicable`. The spec's `## Design` section is an architecture section — no handoff link
and no `| RS-n |` render-state rows — and the repo's `.claude/second-shift.config.json`
configures no design provider, so the disarm is justified rather than a missed arming.
