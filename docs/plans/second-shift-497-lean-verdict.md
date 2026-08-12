# lean review verdict — #497

verdict=approve
run_id: review-497-1
session_id: 9d78c82b-19ce-44ee-a0fd-a405065d0261
rounds: 1
pr: #512
reviewed_head: 72f46eb14ba3e35cf98482405dbf88a55a780bda
reviewed_patch_id: 6809025be18537b1c45870be497cb50b928a4b3d
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 over the full branch diff (`288d7e1..HEAD`, six files) — `bash G delta 497` printed FULL range, nothing to inherit.

Panel: 7 reviewers selected, 7 returned, none dark. security / performance / complexity / test-coverage / scope-completeness `approve` with no findings; maintainability and unit-test-mutation `approve-with-nits`. `a11y-reviewer` and the design-fidelity dimension were not routed — no changed path matches `stageParams.webComponentGlobs` (unset, so the shipped default `apps/web/**/*.{tsx,jsx}`); this is a shell/markdown diff.

No blockers. Two warnings, both about test strength and operator diagnostics rather than shipped behavior.

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` (if12) | The case cannot fail on the contract it names. Its comment says "`*)` in the dispatch case routes every unknown subcommand through run_milestone, so a wrapper that recorded before validating would stamp `\| milestone-9 \| started \|` on its way to exit 2" — but `bash G 9 7` never reaches `run_milestone`: the pre-existing whitelist at `lean-gate.sh:242-245` (`entry\|claim\|mark\|1\|2\|3\|4\|5\|all\|teardown\|delta\|verdict\|progress`) envfails first, and every non-numeric arm is handled explicitly by the bottom dispatch, so `run_milestone` only ever receives 1..5. Its `*) envfail "run_milestone: unknown milestone"` arm is unreachable from the CLI. **Probed:** moving the validation block to *after* `append_started "$n"` in an isolated worktree leaves the whole suite green (rc=0) with (if12) still PASS — the mutation the case exists to catch survives it. The case is not worthless (it still guards the dispatch-level usage refusal and, importantly, that a usage error does not bring the progress file into existence), but it does not guard the validate-before-record ordering. Remedy: drive the ordering through a reachable path — the file already has the `LEAN_GATE_LIB` library-mode seam, so a case can source the gate and call `run_milestone 9` directly — or drop the case's ordering claim and the dead arm and say why. |
| 2 | Warning | `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`, `run_milestone` | Contradictory operator diagnostics on the exhaustion path. The announce is unconditional on `unclosed > 0`, so at `unclosed >= INTERRUPTED_BUDGET` it prints `… (interrupted 5/5) — re-running it now.` and is immediately contradicted by `… has been begun and cut off 5 times without ever concluding — hard stop.`. Under `LEAN_GATE_OBSERVE=1` it is worse: the announce still claims a re-run, the observe arm returns 4 without running anything, and the hard-stop line never prints — so the only message the operator sees is the false one. Separately, unlike this gate's other refusals (`require_entry_attested` spends three lines naming the remedy) the hard stop names none, and the state is self-locking: only `concluded` rows clear it and a refused call never writes one, so the only exit is hand-editing a gitignored file. Remedy: move the announce below the budget check, or gate it on `unclosed -lt INTERRUPTED_BUDGET`, and name the recovery in the refusal. |
| 3 | Suggestion | `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh:1421` | `# ---- leg 3d` collides with the existing `leg 3d` at line 1206 (the #496 milestone-4 taxonomy), so grepping the file by leg name now returns two unrelated blocks. Consistent with pre-existing looseness in the file (`leg 3c` at 1381/1475, `leg 4` at 1257/1504) rather than a pattern this PR invented, but the new leg had a free choice of a unique suffix. |
| 4 | Suggestion (no action) | `lean-gate.sh`, the `interrupted-exhausted` payload | Raised by the mutation reviewer: `$unclosed` on the exhaustion line is only ever exercised at exactly `INTERRUPTED_BUDGET`, so substituting the constant would be byte-identical in every fixture. Checked and **not** a coverage hole: a call is only made when `unclosed <= 4`, and a refusal never appends a `started` row, so `unclosed` cannot exceed 5 on any serial path. The only way past the budget is two concurrent calls on one milestone — OR-1, explicitly out of scope. The mutant is genuinely equivalent; recording it so the next reader does not re-derive it. |

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — the pair is written around every milestone body | satisfied | `run_milestone` appends `started` before the `cmd_N` dispatch and `concluded \| rc=<rc>` after, generically for 1..5. `(if1)` asserts order + rc; `(if5c)` asserts an uninvoked milestone carries neither row. Live evidence on this run's own record: `milestone-3 \| started` at 11:38:04 → `concluded \| rc=0` at 11:58:48, a 20-minute span. The "unknown subcommand still exits 2 having written nothing" clause holds — but via the pre-existing whitelist, not `run_milestone`; see finding 1. |
| AC-2 — `concluded` is non-idempotent | satisfied | `(if3)` asserts 3 started / 3 concluded / 1 satisfied. **Probed:** forcing `append_concluded` idempotent (the issue's own original sketch) reds `(if3)` and `(if4)` *and* the pre-existing `(c4)`/`(c5)`/`(c7)` budget cases — `(c5)`'s rc sequence degrades `11111111114` → `11111144444`, an honest run hard-stopping partway through. The spec's central argument is empirically confirmed, not just asserted. Live record: milestone-2 re-evaluated at 11:23 wrote a second pair with no second `satisfied` row. |
| AC-3 — a killed evaluation is distinguishable from one that never ran | satisfied | `(if5)` drives a real blocking lane and `kill -9` on the gate's **process group**, then asserts 1 started / 0 concluded; `(if5b)` asserts no lane child survived; `(if5c)` is the discriminator against a gate that stamps every milestone. Ran green here. |
| AC-4 — the next evaluation announces and still runs | satisfied | `(if6)` asserts rc=0 + the marker + the exact `1 earlier evaluation(s) … (interrupted 1/5)` text. `(if4)` is a sound negative control — `gate()` ends `2>&1`, so the stderr announce would reach the capture if it fired. |
| AC-5 — interruption is bounded on its own budget | satisfied | `(if7)` asserts rc=4, no body, no new `started`, one exhaustion row; `(if7b)` asserts the reported number counts unconcluded rows, not the exhaustion lines the gate wrote itself. **Probed:** flipping the refusal's `-ge` to `-gt` reds exactly `(if7)` and `(if7b)` — the boundary is guarded, not asserted past. `rc=4` reuse routes through `orchestrate-lean.sh:465`'s existing hard stop unchanged. |
| AC-6 — no existing counter moves | satisfied | `(if8)` and `(if9)`. Verified independently against every reader rather than only the suite: `progress_token`'s ERE `(satisfied$\|attempt [\|])` matches none of the three new verbs; `attempt_count` / `absent_count` / `design_was_armed` / `append_satisfied` all anchor `\| milestone-N \| <verb> \|` with the trailing separator; `interrupted-exhausted` contains neither `budget-exhausted` nor `absent-exhausted`. External readers are also clear — `lean-reconcile.sh` reads only header keys and `\| entry \| ledger=`, `retro-corpus.sh` reads no milestone rows, and `check-lean-chain.sh` never sees the file (gitignored, never reaches CI). **Probed:** replacing the difference with a raw `started` count reds six cases including `(if4)`/`(if7)`/`(if7b)`. |
| AC-7 — an observed evaluation records nothing | satisfied | `(if10)` (top-level observe writes neither half) and `(if11)` (spent budget predicted as 4, counter unmoved), plus the composed `(lean-interrupted)` leg driving the seam `orchestrate-lean.sh:342` actually uses. The declared deviation from receipt row D-10 is correct on the facts: `verdict_rc` runs `LEAN_GATE_OBSERVE=1 bash "$GATE" 4 "$ISSUE"` at top level, which the dispatch routes through `run_milestone`, so the bypass D-10 relied on is real but not exhaustive. Adding the guard rather than bending the contract is the right call. |
| AC-8 — the record's own documentation is current | satisfied | Pinned line-shape block carries all three new verbs; `INTERRUPTED_BUDGET` sits beside `FIX_BUDGET`/`ABSENT_BUDGET` with its sizing rationale; `pipeline-retro/SKILL.md:65` updated. Swept the rest of `docs/` and every `SKILL.md` for other enumerations of the row kinds — `pipeline-retro` is the only one, so the "one out-of-file description" claim holds. |
| AC-9 — the mutation baseline is re-keyed in this diff | satisfied | Re-derived rather than taken on trust. The three baselined generic ordinals resolve to `lean-gate.sh` lines 137-139 — `cmp-eq::1` to the `-ne` inside "zero-network", `default::1`/`default::2` to the `${GH:-gh}` / `${CURL:-curl}` prose entries — and those three lines are **byte-identical in `origin/main` and on the branch**, while the branch's first hunk starts at line 183. No ordinal moved, so "no baseline edit" is the honest result, not an omission. All three pre-existing `mutation-catalog.tsv` anchors for this guard still match unchanged sites; both new anchors match exactly one site each, the observe row's `run_milestone` range correctly isolating 1 of the file's 4 `LEAN_GATE_OBSERVE` conditions. |
| AC-10 — the liveness scenario covers the new verdict path | satisfied | `(lean-interrupted)` added; suite runs **91 passed, 0 failed**. The leg seeds by duplicating the real writer's own line rather than hand-spelling the shape, and carries its stated discriminator — concluding the rows restores the milestone, so it cannot pass for a gate that merely stops working after six calls. |

## Verification run for this round

From the reviewed head, `env -u CLAUDE_CODE_SESSION_ID -u LEAN_RUN_MODEL -u RUN_ID -u TMPDIR`:

- `lean-gate-selftest.sh` — all green; all 15 new `(if*)` cases present and passing.
- `scenario-liveness-selftest.sh` — 91 passed, 0 failed.
- `lean-reconcile-selftest.sh` — green.
- `shellcheck -e SC1091,SC2015,SC2181` on all three changed shell files — clean (0.11.0).
- `/bin/bash` 3.2.57 parses all three files, and the new code adds no `[[ ]]`, `declare -A`, or GNU-only idiom to the `[ ]`-portable gate.

Four mutation probes were run in isolated worktrees, never the reviewed one, and scored by case id: three killed as predicted (budget off-by-one → `(if7)`/`(if7b)`; forced `concluded` idempotence → `(if3)`/`(if4)`/`(c4)`/`(c5)`/`(c7)`; `unclosed_count` as a raw count → six cases), one survived and became finding 1.

Design: `not-applicable`. The spec arms no `## Design` render-state table (`## Design, in one paragraph` is prose about the change, not the render contract), the progress record carries no `\| milestone-3 \| armed \|` row, and this repo configures no `design.provider` — so there is no receipt to hash-verify and no RS row to score.
