# lean review verdict — #439

verdict=approve
run_id: review-439-3
session_id: aaf17509-d8cc-4d45-88e6-c152bcbda319
rounds: 3
pr: #452
reviewed_head: f727fcbdd4cf696730ef4212c69e954de1b9745d
reviewed_patch_id: 442786a48095542a7ee56820ee1af11683cb9784
inherited_patch_id: a68062b8f1efa5a920632db4b1b4ca07802f2755
inherited_from_verdict: f727fcbdd4cf696730ef4212c69e954de1b9745d
fidelity: not-applicable
model: unknown

Round 3, `review-439-3`. **Nothing was inherited in substance.** The round-2 record named patch
`a68062b8f1ef`; the rebase onto `cccd575` resolved a conflict by altering a line, so the branch
now hashes to `442786a48095` and that tree is gone. `delta` printed the whole branch range
`cccd575..HEAD` and said there was nothing verifiable to inherit — the header's
`inherited_patch_id` names the voided round-2 patch as the gate's own bookkeeping, not a coverage
claim this round rests on. This round read everything. Every `AC-n` is scored below against the
whole spec.

Panel of six (security, performance, maintainability, complexity, test-coverage,
scope-completeness) — none dark. `a11y` and the design-fidelity dimension were not routed: no
changed path matches `stageParams.webComponentGlobs` (unset; default `apps/web/**/*.{tsx,jsx}`),
and the diff is shell, markdown and a TSV.

## The round-3 question: is the conflict resolution faithful?

Round 2 approved this content. The only new variable is the merge, so I measured it rather than
reading the resolution narrative.

**`lean-gate.sh` — byte-identical contribution.** Extracting the branch's own added/removed lines
before and after the rebase (`diff b55e701..38a3989` vs `diff cccd575..f727fcb`, `+`/`-` lines
only) gives **170 lines on both sides, identical**. The auto-merge changed nothing this branch
wrote.

**`lean-gate-selftest.sh` — the contribution shrank by exactly 9 lines, and the 9 are not a
loss.** They are `(d5)`'s `env -u RUN_ID` and its 8-line comment. `main` at `cccd575` already
carries **both, verbatim** — #456 landed the same fix independently — so those lines stopped being
this branch's delta rather than leaving the tree. Confirmed by reading `cccd575:…selftest.sh`
lines 275–282 against the reviewed head's 288–295: same comment, same line. Both halves of AC-10
are present in the merged tree.

**Nothing was dropped or duplicated.** All **11** `(ms)` cases (main's) and all **12** `(fp)` cases
(this branch's) are present, `(ms)` block then `(fp)` block. Line arithmetic closes exactly:
main 3273 + 261 added = head 3534, with **zero** deletions — a pure append.

**The merged tree runs green, and it had never been executed before the rebase.** Two full suite
runs at the reviewed head, in both environment directions:

| Run | Env | `(fp5)` | `(d5)` / `(k6)` | Suite |
| --- | --- | --- | --- | --- |
| A | no `RUN_ID`, no prettier | `SKIPPED` | PASS | 238 PASS / 1 SKIP, all green |
| B | `RUN_ID` exported, prettier **3.7.4** on `PATH` | **PASS** | PASS | 239 PASS / 0 SKIP, all green |

Run B is the one that matters twice over. It is AC-8's oracle in its asserting direction — the
goldens are what a live prettier actually writes, re-derived on the merged tree — and it is AC-10
under the exact condition the AC describes, with `(d5)` and `(k6)`, the pair that fails when the
guard is absent, both passing with an ambient `RUN_ID`.

## Probe run

| Probe | Mutant | Expected | Result |
| --- | --- | --- | --- |
| P6 | `lean_format_verdict_record`'s `record_verdict` comparison → `if false` | some `(fp)` case fails | **SURVIVED** — all green |

Applied to a detached worktree at the reviewed head, byte-verified (`1 file changed, 1 insertion,
1 deletion`) and `bash -n`-checked before running. It is the basis of finding 1.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Suggestion | `lean-gate.sh` `lean_format_verdict_record` | The `verdict=`-line revert branch is unguarded — P6 disables it and the suite stays green. |
| 2 | Note | — | Round 2's two items carry forward untouched. |

### 1 — Suggestion: the `verdict=` revert branch has no case

`lean_format_verdict_record` guards two things after the formatter runs: every key in
`LEAN_VERDICT_HEADER_KEYS`, and separately the `verdict=` line via
`record_verdict "$tmp" != record_verdict "$f"`. `verdict` is **not** a member of that key list, so
the second is a genuinely distinct code path — and no case reaches it. `(fp8)` uses a benign
formatter, `(fp10)` an absent one, and `(fp9)`'s `join` formatter trips the header-key loop first
and returns from inside it, asserting `changed header key`. Nothing drives a formatter that
mutates the `verdict=` line while leaving every header key intact. P6 confirms it: the branch can
be disabled outright with no case noticing.

**Not a blocker, and the reason is the spec rather than the size.** AC-5 asks for exactly the
header-key re-read, and this branch is defense-in-depth beyond its letter — so the AC is satisfied
by the guard that *is* tested. It is also close to unreachable in practice: `record_verdict` greps
`verdict=[A-Za-z-]+` anywhere in the file, so a markdown formatter would have to delete or rewrite
the token itself to trip it. A `fp_formatter` variant that rewrites only that line, asserting the
`changed the 'verdict=' line` warning, would close it in a few lines whenever this file is next
opened.

### 2 — Note: round 2's items are unchanged

`(fp12)`'s undeclared position-dependence on the shared fixture tree, and the orphaned short line
in the spec's AC-8 paragraph. Both survive the rebase untouched, and neither was worth a round
then or now.

The scope-completeness reviewer raised the issue body's "skip silently" against the gate's one
warn line on an absent formatter. Dispositioned, not carried: the spec's binding input is the
ledger (`Where a row there conflicts with the issue body, the row wins`), D-6 specifies the warn
line, and AC-6's deliverable — never fails the call — holds either way.

## Acceptance criteria

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — manifest emitted in Prettier's exact form | satisfied | `(fp1)`–`(fp4)` green on the merged tree; `(fp5)` PASSes against live prettier 3.7.4 in run B, re-deriving every golden. |
| AC-2 — padding computed at the write site | satisfied | `md_table_prettier` is pure `awk`, no formatter on the manifest path; `(fp6)` green — the milestone-3 re-derive converges on the padded form. |
| AC-3 — no reader changes, legacy manifests parse | satisfied | `render_manifest_rows()` untouched across the whole branch diff; `(fp7)` green. |
| AC-4 — verdict record formatted by a local formatter | satisfied | Read directly: `lean_resolve_prettier` carries the worktree rung then the main-checkout rung and returns 1 — no `npx`, no `PATH`. Anchored as a `verbatim` lockstep row against `verifyctl.sh`'s `resolve_prettier`; `lint-and-selftests` green covers the pair check. `(fp8)` green. |
| AC-5 — formatting never damages the header | satisfied | Read the verify-and-revert body; `(fp9)` green — the flattening fake formatter is reverted, warned about once, not fatal. (Finding 1 concerns the branch *beyond* this AC.) |
| AC-6 — absent formatter is a consumer fact | satisfied | `(fp10)` green, and observed live in run A: no formatter resolved, one warning, suite green, call not failed. |
| AC-7 — both commit instructions name the obligation | satisfied | `(fp11)` pins the milestone-3 message including the re-derive/void cost; `(fp12)` pins **each** milestone-4 refusal branch with branch-discriminating greps. |
| AC-8 — Prettier-exact claim bound by fixtures, CI takes no node dependency | satisfied | Both directions measured on the merged tree: `SKIPPED` in run A, **PASS** in run B against prettier 3.7.4. CI installs no node — `lint-and-selftests` and `selftests (macos, bash 3.2)` are green with the case skipping. |
| AC-9 — two docs brought current | satisfied | `docs/live-render.md` records the pre-padded receipt, the no-network posture and the OR-1/OR-2 flanks; `docs/testing.md` documents the library-mode seam, its `set -u` positional caveat, and the opportunistic-oracle rules. |
| AC-10 — suite hermetic against an exported `RUN_ID` | satisfied | Verified on the merged tree rather than inherited: run B exports `RUN_ID` and `(d5)` and `(k6)` both pass, suite green. The top-level `unset RUN_ID` guard is on the branch; `(d5)`'s `env -u RUN_ID` is now carried by `main` as well. |

## CI

On the reviewed head `f727fcb`: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
`mutation-sweep-pr` pass, `release-pr-gates` skipped. `pr-gates` red, and its only `✗` is the
stale `reviewed_patch_id` — `reviewed patch a68062b8f1ef, but this branch's diff … now hashes to
442786a48095`, the void this round exists to clear. It resolves with this record. No CI blocker
outside the AC set.

`mutation-sweep-pr` passing on the rebased head also answers the re-key question: the rebase moved
`lean-gate.sh` line numbers by `main`'s 136 added lines, and no baseline-absent survivor came back.

## Verdict

`approve` — the rebase is a faithful replay. The production contribution is byte-identical, the
suite contribution lost only the 9 lines `main` now owns, both case blocks are intact, and the
merged tree — which had never been executed before the rebase — is green in both environment
directions, with `(fp5)` and the `(d5)`/`(k6)` pair each asserting rather than skipping. All ten
ACs are satisfied. Finding 1 is a real, probe-confirmed coverage hole in a guard the spec never
asked for; it is not worth a fourth round.
