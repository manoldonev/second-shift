# lean review verdict — #297

verdict=approve
run_id: review-486-1
session_id: 761976e6-f12d-454b-8522-e4125441076b
rounds: 1
pr: #486
reviewed_head: 6fbf444bfe7f71ae985416b74cecbe1dd07c7dfa
reviewed_patch_id: dd070f29c572b7150aa475c6333d6b466d6d49e7
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 (full branch range `c4742ad..HEAD`, nothing to inherit). Six reviewers dispatched, six returned — no dark reviewer, no voided coverage. Verdict rests on the panel plus orchestrator-run mechanical verification of the catalog sed, the enumeration loop, the bash-3.2 lane risk, and every `emit_row` call site.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — fourth site armed by a catalog row, not a `k` raise | **satisfied** | Applied the committed sed verbatim out of the TSV (`awk -F'\t'` → `sed -E`): exactly one changed line, `69c69`, `[ -n "$line" ]` → `[ -z "$line" ]`. Output is `bash -n`-valid and not byte-identical, so neither LOUD arm fires. The six sibling `-n `/`-z ` sites the spec names (37, 39, 50, 58, 78, 94) are untouched — the `while IFS= read` anchor excludes them structurally. `K_BUDGET` still defaults to 2; `mutation-baseline.tsv`, `mutation-operators.tsv`, `mutation-exclusions.tsv` and `mutation-pair-map.tsv` are all absent from the diff. |
| AC-2 — `note` contract admits a timeout-kill row | **satisfied** | The new `TIMEOUT-KILL ROWS.` header block states all three required clauses: the row's value is arming plus anchor-drift loudness, not a survivor prediction; its verdict rests on the killer TIME BOUND rather than the paired suite's assertions; and it instructs the author to write the note as what the mutant *does*. The landed row's own `note` opens `TIMEOUT-KILL row (see the header block)`, so the row and the file it lives in no longer contradict. |
| AC-3 — report distinguishes "no applicable site" from "site beyond budget" | **satisfied** | `sites_beyond_budget` is appended last in both the header `printf` and `emit_row`. All four `emit_row` call sites pass 8 arguments (836, 854, 1673, 1713) — no `set -u` hole. The "solely for budget" clause is honored structurally: `used` increments only *after* the `bash -n`-invalid and no-op-flip `continue`s, so neither harness artifact consumes budget or lands in `beyond`. Report-only confirmed by reading — no code path reds on the value — and pinned by `(ak3)`. `--mode merge` compares the header byte-wise against its own locally built 8-column `MERGE_HDR`, so a stale-harness shard reds loudly rather than silently mis-parsing. Verified the only positional readers of the report are the selftest's `report_row`/`report_beyond`; `.github/workflows/mutation-sweep.yml` passes the path and parses no columns. |
| AC-4 — column and row guarded, each new assertion probed | **satisfied** | Case `(ak)` on a two-guard fixture differing only in site count (5 vs 2 against k=2). The four assertions are mutually non-vacuous: `ak1` asserts a *non-empty* `fail-open:3` through the same `report_beyond` accessor that `ak2` asserts empty on, so `ak1` is the control that rules out a silently-broken accessor faking `ak2`'s green. `ak3` pins rc=0 *and* `2/0/`, so it covers both the report-only posture and the survival of `$5/$6/$7`; `ak4` pins the header suffix directly rather than inferring position from cells. Each probe's applied diff was printed before scoring per the PR body. |
| AC-5 — falsified prose corrected in the same PR | **satisfied** | Both statements the AC names are gone: `mutation-sweep.sh`'s "The third is not safe, only out of budget: raising MUTATION_SWEEP_K to 5 arms it" now reads "armed by the `scaffold-spin-at-eof` catalog row", and the matching `docs/testing.md` paragraph ("Raising `MUTATION_SWEEP_K` arms it") is rewritten to the landed mechanism. `docs/testing.md` also names the new column and its report-only posture as the AC requires. See W1 for residual drift the AC's letter does not reach. |

Design: **not-applicable** — the spec carries no `## Design` section, the repo declares no `design.provider`, and no changed path is a web-component surface.

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| W1 | Warning | `tools/mutation-sweep.sh:888`, `docs/testing.md:457` | **The corrected block still undercounts the carriers.** Both rewritten passages assert "THREE live guards carry that idiom". Four in-universe guards carry it today: the three named, plus `tools/capability-parity-check.sh:82`, which is not in `mutation-exclusions.tsv`. (`mutation-sweep.sh` carries it three times but is the sweep's own excluded recursion guard.) The staleness arrived in `c4742ad` — PR #480, this branch's own base commit — so the PR did not introduce it; but AC-5 had this session rewriting exactly these two passages, and the count was re-asserted rather than re-checked. **Not a safety gap:** that fourth carrier sits at `cmp-z` **ordinal 1**, inside `k=2`, with a paired suite (`tools/capability-parity-check-selftest.sh`), so it is already armed and a spinning mutant is timeout-killed by the bound case `(z)` pins. Nothing is dark. Also, `docs/testing.md:458` calls the newly-armed site "That fourth site" in a paragraph that opens "Three tracked guards", while `mutation-sweep.sh` calls the same site "the third" — a reader reconciling the two cannot. |
| W2 | Warning | `tools/mutation-sweep.sh:1480`, `tools/mutation-sweep-selftest.sh:344` | **The plus-join is documented but unpinned.** AC-3, the `emit_row` comment block and `docs/testing.md` all give `cmp-z:3+cmp-eq:1` as the multi-operator shape, and `${BEYOND:+$BEYOND+}` is the code that produces it. `make_budget_fixture` declares a single operator (`fail-open`), so no assertion in `(ak)` — or anywhere — exercises the separator. Dropping the `+` from the join, or swapping `${BEYOND:+$BEYOND+}` for a bare `$BEYOND`, leaves the whole suite green. AC-4's letter asks only for the two cases that were written, so this is not an unmet AC; but the format the docs promise is the one thing the guard does not check, and guards on multi-operator guards are the common case in the real tree at `k=2`. |

Neither warning is a blocker: every AC is met on the diff, and W1's subject is a pre-existing inaccuracy inherited from the base commit whose operational consequence is nil.

## Panel

Security, performance, maintainability, complexity: approve, no findings. Scope-completeness: approve. Test-coverage: approve-with-nits, one nit (confidence 82) on the `docs/testing.md` "fourth"/"three" mismatch — verified independently and folded into W1, which the orchestrator widened after finding the fourth carrier the nit did not reach.

`db-reviewer`, `pipeline-reviewer`, `unit-test-mutation-reviewer` not selected — no DB, queue, or co-located unit-spec surface. `a11y-reviewer` and the design-fidelity dimension not routed: no changed path is a web-component surface and the repo declares no `stageParams.webComponentGlobs`.

## CI

`lint-and-selftests` pass (3m52s), `selftests (macos, bash 3.2)` pass (5m33s), `mutation-sweep-pr` pass. `pr-gates` fails on exactly one thing — `no committed verdict record (a file named *-297-lean-verdict.md)` — which is this record, and is by design red until it lands.

Independently checked the bash-3.2 lane rather than inferring from the ubuntu job: `A[${#A[@]}]=""` counts the empty element, `A[gi]=` accepts the bare arithmetic subscript, and `${BEYOND:+$BEYOND+}` joins correctly under 3.2.57 with `set -uo pipefail`. No bash-4 construct is introduced. `tools/mutation-sweep-selftest.sh` has no row in `tools/selftest-cache-inputs.tsv`, so case `(ak)` cannot be cache-skipped in CI.
