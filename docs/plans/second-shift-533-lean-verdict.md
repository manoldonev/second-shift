# lean review verdict — #533

verdict=approve
run_id: review-533-1
session_id: 3149f426-8e95-4dc1-b940-3368ec091845
rounds: 1
pr: #556
reviewed_head: 9efe8bf4e4ba4d43d2d441d9fa2e9c6a2e832752
reviewed_patch_id: b0f63c78fcceff60ad4eace1aa227fdc41b5af2f
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1, full branch range (`3e39430..HEAD`) — nothing verifiable to inherit, so this round read
the whole diff: `docs/plans/second-shift-533-lean.md`,
`plugins/dev-pipeline/skills/build-lean/lean-gate.sh`,
`plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh`.

Panel: 6 reviewers selected (security, performance, maintainability, complexity, test-coverage,
scope-completeness), 6 returned — no dark reviewer, no coverage gap. All six returned `approve`
with no finding at or above the confidence threshold. a11y and the design-fidelity dimension were
not routed: no changed path matches `stageParams.webComponentGlobs` (unset; resolved default
`apps/web/**/*.{tsx,jsx}`). db / pipeline / unit-test-mutation reviewers were not triggered — no
DB layer, no queue worker, no co-located unit spec surface in this repo.

## Verdict: approve — no blockers

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Suggestion | `lean-gate.sh:2732` | `ids` is now built with `sort -u`, so the ids in the refusal message come out in lexical rather than document order — `OR-1, OR-10, OR-2`. Message-only cosmetics; the dedup itself is the point and is guarded. |
| 2 | Suggestion | `lean-gate.sh:2693-2694` | `cat "$ledger_path" 2>&1` captures stderr into `ledger_content`, but the failure branch discards it and prints a fixed reason. The two `gh` arms it mirrors interpolate their captured stderr into the reason, so those refusals name *why* the read failed and this one does not. Either interpolate it or drop the `2>&1`. |
| 3 | Note | `docs/plans/second-shift-533-lean.md` AC-2 | The AC's rationale states `scenario-liveness-selftest.sh`'s composed lean legs "depend on this seam"; that file is not in the diff and passes no `--ledger-file`. Verified harmless: the legs run the gate from a fixture `$LEAN_TREE`, so the resolved default path is inside the fixture and absent, and they are unaffected either way. The AC's *requirement* (the flag exists, symmetric with `--issue-file`/`--comments-file`) is met — only the justification is forward-looking. |
| 4 | Note | `lean-gate-selftest.sh` `(n16a)`/`(n16d)` | Both are clear-direction (rc=0) cases and therefore survive a mutant that restores the pre-#533 blanket jira short-circuit. Confirmed by probe m3 below. Not a defect: the PR body claims the non-vacuity for `(n16b)`/`(n16c)`, and the probe confirms exactly those two carry it. |

Dismissed: complexity-reviewer's nit (confidence 55) that `pause_and_ask_ledger_path()` has a
single call site — it carries real branching plus the load-bearing default-path rationale, and
inlining it would bury that. Below threshold and not a defect.

Two security-reviewer observations were self-suppressed at confidence 40/45 (`$ISSUE`
interpolation into the default path; stderr folding) — both pre-existing idioms already present
for `PROGRESS_FILE`/`RUN_ID_CACHE` and the `gh issue view` arm. Item 2 above is the actionable
half of the second, restated as a suggestion rather than a security finding.

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — ids derived from BOTH the ledger and the issue body; union, deduplicated | **satisfied** | `check_pause_and_ask` reads the ledger unconditionally and the body under github, then `sort -u`s the two lists. `(y12)` ledger-only refuses; `(y13)` the same id in both sources is named once; `(y14)` a ledger-only `reversible-default-and-flag` does not refuse, so the disposition enum applies uniformly to the new source. Parser genuinely reused — `pause_and_ask_ids` is unchanged. |
| AC-2 — injectable seam, symmetric with `--issue-file`/`--comments-file` | **satisfied** | `--ledger-file` added to the arg loop, the `-h` doc block, and the `sed -n '2,295p'` help range (checked: line 295 is the last comment line, 296 is `set -uo pipefail`). Default `$MAIN_ROOT/$STATE_DIR/$ISSUE-ledger.md` matches the real convention — `interviewing-baseline/SKILL.md:33` and `plan-lint.sh:260` both spell `{issue}-ledger.md`, and this repo's own `.claude/pipeline-state/` carries live `<n>-ledger.md` files. `(y15)` an explicit missing path is an environment refusal; `(y17)` the *default* path is live, not just the seam. See item 3 for the one overstated clause in the AC's rationale. |
| AC-3 — reachable under `tracker.type: jira` | **satisfied** | The blanket `[ "$TRACKER_TYPE" = "jira" ] && return 0` is gone; only the issue-body read and the comment-trail fetch are jira-guarded, and `comments` defaults to `"[]"` so `region_resolved` still runs. `(n16b)` a ledger region refuses under jira; `(n16c)` a comment that *would* resolve it under github does not; `(n16d)` a ratified intent-gap record still clears it. |
| AC-4 — unreadable ≠ absent, and neither silently clear | **satisfied** | `[ -f ]` gates the read (a `chmod 000` file is still `-f`), the `cat` failure branch returns 2, and absence falls through to the issue body rather than to CLEAR. `(y16)` absent default path is clear; `(y18)` unreadable at that path is rc=2, named, and spends no fix-budget attempt. |

## Verification run in this review context

Full `lean-gate-selftest.sh` at the reviewed head, in an isolated detached worktree,
`env -u TMPDIR -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL`: **rc=0, all cases pass**,
including the 11 new/re-pointed ones.

Probe of the new assertions — four single mutants of `lean-gate.sh`, each `bash -n`-checked and
confirmed applied by `git diff --stat` before running, scored by case id rather than message text:

| Mutant | Killed by | Survivors of note |
| --- | --- | --- |
| m1 — drop the `sort -u` two-source dedup | `(y13)` | — |
| m2 — an unreadable ledger returns CLEAR instead of rc=2 | `(y18)` | — |
| m3 — restore the pre-#533 blanket jira short-circuit | `(n16b)`, `(n16c)` | `(n16a)`, `(n16d)` — expected, both are rc=0 cases (item 4) |
| m4 — break the DEFAULT path resolution, leaving `--ledger-file` intact | `(y17)`, `(y18)` | — |

m4 is the one that matters most: it distinguishes "the seam works" from "production is wired",
and `(y17)` is the case that would otherwise have let a live-looking default path be inert.

Repo gates checked directly against the base: `check-frozen-files.sh 3e39430` clean (no
release-owned file touched — no version bump, no `CHANGELOG.md` edit), `check-changelog-trailer.sh
3e39430` OK. CI's `pr-gates` is red solely on `no committed verdict record (a file named
*-533-lean-verdict.md)` — this record is that artifact.

Mutation: the PR's claim that `lean-gate-selftest.sh` is nightly-deferred by its existing
`tools/mutation-slow-suites.tsv` row, unchanged and with no new row added, matches the diff.
