# lean review verdict — #813

verdict=approve
run_id: review-813-1
session_id: 2aa82b79-0696-40c2-a618-2843e2bf331b
rounds: 1
pr: #817
reviewed_head: 2b0e66771c758551029dbba33705947f6c2bee44
reviewed_patch_id: 1c81e471b4049f54cd2228921d9b609048bb1fdd
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:security-reviewer,review-toolkit:unit-test-mutation-reviewer,review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

Round 1 of 3. Full branch diff (`e67f82c9..HEAD`), 10 files, +1241/−21. Root round — nothing inherited.

Two shell tools and their selftests: `tools/lane-bench-arm.sh` (the `LEAN_SPAWN_BIN` handle that
loads one arm's plugin directories into the lane's payload sessions) and `tools/lane-bench.sh run`
(one bench cell end to end). The tools are correct on the paths the suites bind, the refusal
ordering the ticket cares about is real and asserted, and the four new catalog rows are honest —
I re-probed all four in an isolated worktree because the suite's new timings row means the PR-lane
sweep no longer scores them. Three warnings, no blockers.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-2 | satisfied | `tools/lane-bench-arm.sh` validates the manifest on every invocation, then appends `--setting-sources ''` plus one `--plugin-dir` per entry **only** when argv carries `--bg`/`-p`/`--print`, and `exec`s. `tools/lane-bench-arm-selftest.sh` asserts the full argv against a `claude` fake for a six-directory (a1) and a two-directory (b1) manifest with the scheduler's own dispatch argv reproduced whole, asserts `--setting-sources` carries the empty string rather than a name (a2), asserts `agents --json --all` (d1) and `stop <id>` (d2) reach the fake byte-identical, asserts the `backgrounded · <id> · <name>` line reaches the caller unprefixed and that the scheduler's field-3 parse still reads the id off it (c1/c2), asserts the child's exit status is the wrapper's (c4), and asserts exit-2-with-nothing-exec'd for an unset (e1), unreadable (e2/e3), empty (e4) manifest and an entry naming a missing directory (e5). Re-run by me at `2b0e6677`: 18 passed, 0 failed. CI at the same head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass (run 34152249398). |
| AC-7 | satisfied | `cmd_run` performs every step the AC names in the order it names them; the four pre-cell refusals all land before `gh issue create`. `tools/lane-bench-selftest.sh` covers all ten enumerated cases over a `LEAN_BENCH_LANE_BIN` lane stub and an argv-discriminated `gh` fake: `approved` (k1, with harness_sha, CLI version, both **resolved** model ids, slug, class, rounds and wall minutes each asserted), `paused` (l1), `no-pr` (l2, m1), `pr-unapproved` (n1), `lane-error` with its single re-run on a fresh issue (o1) and the two-error terminal (o2), `unscorable` (p1), the duplicate-cell (q1), in-arm drift (r1), dirty-worktree (s1) and wrong-tracker-host (t1, plus t2 for an errored host read) refusals — each of the four asserting `issue create` was never called, not merely that the exit code was 2. Re-run by me at `2b0e6677`: 43 passed, 0 failed. |
| AC-10 | satisfied | The mechanical rung is present and covered: `cmd_run` compares `gh repo view --json nameWithOwner` run from the substrate root against the operator-supplied `--substrate <owner>/<repo>` and refuses before any tracker write, treating an errored read as a refusal (`tools/lane-bench.sh` — the `HOST_RC`/`HOST` block). Guarded by (t1)/(t2) and by catalog row `lane-bench-tracker-host-assertion`, which I applied in an isolated worktree and confirmed KILLED (41/43). The results-file audit half is operator-run on the bench repo. |
| AC-11 | satisfied | Read the full diff and the PR body; scanned both for consumer repo names, org names, company tracker keys and GitHub App identifiers and found none. The substrate is an argument (`--substrate`), never a literal — D-50's stated reason. Fixtures use `bench-owner/substrate` and `example.invalid`. The declared oracle is a denylist the operator keeps outside the repo; that pre-merge run remains theirs. |
| AC-12 | satisfied | `git diff --name-only e67f82c9..HEAD` names no `plugins/*/.claude-plugin/plugin.json`, no `CHANGELOG.md` and no `.claude-plugin/marketplace.json`. |
| AC-13 | satisfied | `docs/lane-bench.md`'s closing "successor slice" sentence is replaced by a `## Running a cell` section that states the runner's contract in full — the arm worktree, the per-cell manifest, the detached `nohup` launch, the terminal-row poll, the resolved-model-id read, the single-re-run rule and all four pre-cell refusals. `tools/lane-bench-classes.tsv`'s "WHO READS THIS" note now names `run` as a reader and states the class-pair rule. `tools/lane-bench.sh`'s header carries a "WHAT `run` DOES" paragraph naming what it reads. |

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `tools/lane-bench.sh:278` (and the seam table at `:77`) | `run` resolves the substrate's state dir as `${STATECTL_STATE_DIR:-$ROOT/<paths.pipelineStateDir>}`, but neither collaborator honors that first rung: `orchestrate-lean.sh:524` sets `STATE_DIR="$(cfg '.paths.pipelineStateDir' …)"` and writes the launch ledger to `$MAIN_ROOT/$STATE_DIR`, and `lean-gate.sh`'s `pause_and_ask_ledger_path()` computes `$MAIN_ROOT/$STATE_DIR/$ISSUE-ledger.md` the same way. D-28's cited precedent is real (`plugins/dev-pipeline/tools/retro-corpus.sh:142`) but it is a different consumer. With `STATECTL_STATE_DIR` exported the runner writes the receipt where milestone 1 will not look and polls a ledger the scheduler will never write, so every cell burns the full `LEAN_BENCH_CELL_CEILING_SECS` twice before recording `no-terminal-row`/`lane-error`. Advertising the seam in the header is what makes this worth fixing rather than ignoring — the default path is correct and is what all 43 cases bind. Confidence 88. |
| 2 | Warning | `tools/lane-bench.sh:503` | D-54 states that more than one transcript matching a session-id prefix is "a refusal, not a first-wins pick", and the code implements it (`[ "$n" -eq 1 ] \|\| die`). No case constructs an ambiguous match: every `FAKEHOME` fixture has exactly one transcript per id. **Probed**: `s/\[ "$n" -eq 1 \]/[ "$n" -ge 1 ]/` in an isolated worktree at `2b0e6677` SURVIVES the suite 43/43 — the first-wins behavior the ledger row exists to forbid is unguarded. A second fixture transcript sharing the `bsid0001` prefix would kill it. Confidence 90. |
| 3 | Warning | `tools/lane-bench.sh:270` | `[ "$ROOT" != "$SS_ROOT" ] \|\| die "…would file issues and post comments on this repository's own tracker"` is the only refusal standing between a cell and second-shift's own tracker when `--substrate` itself names this repo — the host assertion would agree in that case. It is untested: `LEAN_BENCH_SS_ROOT` is bound to `$SS` and the config root is `$SUB` in every case, so `ROOT == SS_ROOT` is never constructed. **Probed**: `s/\[ "$ROOT" != "$SS_ROOT" \]/[ 1 -eq 1 ]/` SURVIVES 43/43. AC-7's enumerated case list does not name this refusal, so it is a gap beyond the spec rather than an unmet criterion — but it guards the same property AC-10 exists for. Confidence 88. |
| 4 | Suggestion | `tools/mutation-baseline.tsv:148-149` | Two inherited rows cite line numbers into files this PR moves: the `mktemp … lane-bench-score.XXXXXX` fallback is cited `(:161)` and now sits at `:602`; the `${GH:-gh}` fallback is cited `(:189)` and now sits at `:630`; and the second row's `export GH="$BIN/gh" (:123)` is now `tools/lane-bench-selftest.sh:143`. The rows themselves key on `file::class::hash`, so the sweep is unaffected — but this register is authoritative under CLAUDE.md and a reader chasing `:161` lands in the middle of `cmd_run`. The three rows the PR adds deliberately carry no line citations, which is the right form. Confidence 92. |
| 5 | Suggestion | `tools/lane-bench.sh:325-331` | `lane_bench_run_cleanup` runs on the EXIT trap, so interrupting the runner mid-poll removes `$WORK` (the manifest) and the arm worktree while the detached lane is still live. The wrapper validates the manifest on *every* invocation by design, so from that moment `orchestrate-lean.sh`'s own `"$SPAWN_BIN" agents --json --all` and `"$SPAWN_BIN" stop <id>` both exit 2 — the scheduler terminals `spawn-unreadable` and cannot stop the session it started. The comment explains why cleanup cannot simply be dropped; a guard that skips teardown while a launched lane has no terminal row would close it. Confidence 80. |
| 6 | Suggestion | `tools/lane-bench.sh:176-184` | The four `die` branches enforcing that `--skeleton`/`--control-ref` and `--arm-ref` are proper alternatives are never driven with an invalid combination. CLI ergonomics, not a data or write boundary. Confidence 80. |

## Suppressed (below the reporting bar)

- `tools/lane-bench.sh:433` — Confidence 55 — `lane_bench_class` greps the whole progress record for `pause-and-ask` rather than scoping to a milestone-1 line. Verified equivalent: `lean-gate.sh:3102` is the only site that writes that token into a progress record, and `cmd_4` explicitly excludes the check.
- `tools/lane-bench-arm.sh:68` — Confidence 60 — `--setting-sources ''` drops settings-declared hooks and grants for payload sessions. That is the ablation the arm design specifies (#811 D-26), applied identically in every arm, on an operator-run bench against a private substrate.
- `tools/lane-bench.sh:262` — Confidence 78 — `[ -s "$MANIFEST" ]` (an arm whose `plugins/` declares no plugin manifest) has no `run`-side fixture; the wrapper's own empty-manifest refusal is covered (e4).
- `tools/lane-bench.sh` — Confidence 65 — `run` is a function and `score` is straight-line code after an early `exit`, so the file's two halves have different shapes. This is the minimal-diff form the spec's Out section required (`score` unchanged except for header sentences), not a new divergence.
- `tools/lane-bench.sh:110` — Confidence 60 — `-h|--help` prints `sed -n '2,78p' "$0"`, a hardcoded range with nothing holding it to the header block's actual end. Pre-existing shape from #812; correct at this head.

## Verification performed by this round

- Both new suites re-run at the reviewed head: `lane-bench-arm-selftest` 18/18, `lane-bench-selftest` 43/43 (11s, which is the honest figure for D-58's timings row — `MUTATION_SWEEP_SLOW_THRESHOLD_S` defaults to 5).
- `shellcheck -e SC1091,SC2015,SC2181` clean on all four changed shell files (0.11.0 locally; CI's 0.9.0 lane is green at this head).
- All four new `tools/mutation-catalog.tsv` rows applied with `sed -E` in an isolated worktree at `2b0e6677` and confirmed KILLED — `lane-bench-arm-dispatch-discrimination` (16/18), `lane-bench-tracker-host-assertion` (41/43), `lane-bench-pause-discrimination` (41/43), `lane-bench-review-model-na` (40/43). Re-probed rather than credited because the new timings row takes `tools/lane-bench-selftest.sh` off the PR-lane sweep, so `mutation-sweep-pr`'s green at this head is not an oracle for them.
- CI at `2b0e6677` (run 34152249398): `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr` pass. `pr-gates` fails on exactly one arm — `lean-evidence`/`lean-chain` reporting no committed verdict record — which this record resolves.

## Panel

`review-toolkit:security-reviewer` (approve, 0 findings), `review-toolkit:unit-test-mutation-reviewer`
(request-changes, 3 findings — findings 2, 3 and 6 above, each independently re-derived and two of
them probe-confirmed here), `review-toolkit:scope-completeness-reviewer` (approve, 0 findings).
No reviewer went dark. `a11y-reviewer` and the design-fidelity dimension were not routed: no changed
path is in the web-component surface (`stageParams.webComponentGlobs` unset, default
`apps/web/**/*.{tsx,jsx}`). `db-reviewer` and `pipeline-reviewer` did not trigger. Performance,
maintainability, complexity and test coverage were reviewed by the lead pass.
