# lean review verdict — #378

verdict=approve
run_id: review-378-2
session_id: cd2a59c2-acda-4ba6-8d90-d01848e5efc9
rounds: 2
pr: #382
reviewed_head: 9d28e4eca1589062aaad0e75bdf5c27130546c8d
reviewed_patch_id: 772cea827297997a791e874bae981dcc64c6d9dc
inherited_patch_id: 939314f173255b2419e84f426b8e924504c1307e
inherited_from_verdict: 0eabc17bb832c14356c6f86b893565f6a75b71a9
model: unknown

Round 2 — delta range `0eabc17..HEAD` (one commit, `9d28e4e`, 4 files), inheriting the coverage
of patch `939314f17325` from round 1. Round 1's findings were read first; every prior blocker and
warning was re-checked against the branch, not assumed fixed.

Reviewed through `review-lead`: 7 specialists dispatched via `code-review.mjs` over the **full**
branch range `origin/main...HEAD` rather than the delta — the wider read is always allowed and
makes the record strictly stronger, and the scope gate needs the whole diff. Scope Completeness
returned PASS. `maintainability-reviewer` went **dark** (died after its automatic retry:
`turn-budget: agent emitted no text on either attempt`) — a coverage gap recorded below, not a
pass. Every before/after claim here was reproduced by executing the code.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Untouched by the delta and re-read: both conditional enumerations name the dimension (`SKILL.md:134` never-suppressed sentence, `:169` Routing row). Config-sourced trigger with the shipped default (`:176`), model-judgment matching (`:178`), three-way provider map including the no-provider default (`:182-188`), never depth-suppressed. |
| AC-2 | satisfied | Re-ran all three sub-registry extractions against the branch `SKILL.md` (the delta edits it): pre-flight = routing = verdict = the identical **12** names, so DRIFT is clean. `check-reviewer-references.sh` exits 0 against the real plugin root — the `git commit` PreToolUse hook does not deny. |
| AC-3 | satisfied | Both clauses this round added are discharged by execution. `real-panel-design-absent` (`selftest.sh:185`) and `design-cache-layout` (`:223`) exist and each kills its mutant **as the only red** — 5 mutants applied and restored, table below. See W2 for a caveat on the second that does not reach the AC's letter. |
| AC-9 | satisfied | Executed in **both** configurations, not just the tested one. A consumer `.claude/agents/design-faithful-reviewer.md` fixture: design-toolkit **present** → exit 1 + `SHADOW`; design-toolkit **absent** → exit 1 + `SHADOW` (plus the exemption notice for the other name). The same fixture on `main` gives `ORPHAN` — so the branch now reports the correct failure class where round 1 measured exit 0 and silence. `design-shadow` (`:202`) kills the file-presence mutant as the only red. |
| AC-4 | satisfied | Executed, not inferred (the fan-out's scope reviewer could only infer it here). Branch: `review-context/{design,figma}-faithful-reviewer.md` → `check-review-context: clean`, exit 0; the same two files against `main` → both `UNKNOWN-REVIEWER-FILE`, so the panel edit is what enables them. Typo'd `figma-faithful-reviewr.md` control → `UNKNOWN-REVIEWER-FILE`, exit 1: still fails closed. `reviewers.remove` of **both** names → exit 0, no `REMOVE-UNKNOWN`. |
| AC-5 | satisfied | **B1 fixed.** Both statements are re-keyed on the dimension having been selected: `SKILL.md:192` ("the condition is that **the dimension was selected** — by *any* row of the map above, the no-provider default included") and `:311` (the Not-selected bullet, same wording). `:194` records why the keying is load-bearing. The lint's exemption (`check-reviewer-references.sh:269`) carries no provider condition at all, so the two halves of the degrade now agree — which is what the AC's last sentence requires. |
| AC-6 | satisfied | `plugins/dev-pipeline/skills/run-lean/SKILL.md` absent from `git diff origin/main...HEAD --name-only`. |
| AC-7 | satisfied | No path under `stages/`, no `code-review.mjs`, no `check-model-tiers.sh` anywhere in the branch-wide name-only diff. |
| AC-8 | satisfied | CI green at `9d28e4e` on both `lint-and-selftests` (7m00s) and `selftests (macos, bash 3.2)` (9m35s). The PR-scoped mutation sweep runs inside the former and passed: `applied=14 killed=8 survived=6`, every survivor baselined. Locally: `shellcheck -e SC1091,SC2015,SC2181` exits 0 on both changed scripts; the paired suite is **14/14** under bash 5 and under stock `/bin/bash` 3.2, with `CLAUDE_CODE_SESSION_ID` unset. `pr-gates` is red on one thing only — the stale round-1 `verdict=needs-work` record — which this round replaces. |

**The spec amendment is legitimate.** The delta grows `docs/plans/second-shift-378-lean.md` by 36
lines: AC-3 and AC-5 gain clauses, AC-9 is new, and two design notes are added. Checked
mechanically rather than by judgment — `git diff 0eabc17..HEAD -- <spec>` deletes **zero content
lines** (the two `-` lines are line continuations whose text is preserved verbatim in their
replacements). Every addition encodes a round-1 finding as a checkable requirement, and the diff
was then changed to meet them; nothing was narrowed to match code that already existed. That is
the append-only shape the "amended to match the diff is itself a blocker" rule permits.

## Mutation verification

Every kill claim in the PR body for the three new cases was reproduced by applying the mutant to
the real script and running the paired suite, then restoring by `cp` from a backup (`git status`
confirmed clean after each). All five are single-case reds — no mutant reddens a second case, so
each new case is load-bearing on its own:

| Mutant applied | Result | Only red |
| --- | --- | --- |
| `DESIGN_TOOLKIT_PANEL` loses `figma-faithful-reviewer` | 13/14 | `real-panel-design-absent` |
| SHADOW reverts to file-presence only (drop the `grep -qx` disjunct) | 13/14 | `design-shadow` |
| cache glob `tail -1` → `head -1` (oldest sibling) | 13/14 | `design-cache-layout` |
| cache glob drops the `[ -d "$cand/agents" ]` filter | 13/14 | `design-cache-layout` |
| cache glob deleted entirely | 13/14 | `design-cache-layout` |

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | `review-lead/SKILL.md:66` | The config-read fix anchors on `$WORKTREE`, which this file never binds — literal execution reproduces round 1's W3 silent-misroute. |
| W2 | warning | `check-reviewer-references-selftest.sh:223` | `design-cache-layout` is neutralized by an ambient `SECOND_SHIFT_DESIGN_TOOLKIT_ROOT`; the suite never unsets it. Proved: under the override, the "glob deleted" mutant survives 14/14. |
| N1 | note | `check-reviewer-references.sh:269` | The exemption's `[ -z "$DESIGN_AGENTS" ]` guard is an unkilled mutant; a *partially* installed design-toolkit DANGLING-denies. Not realized by any released version. |

### W1 — the relocated config read anchors on an unbound variable

Round 1's W3 said the relocated read hardcoded a cwd-relative literal, and prescribed "mirror
Stage 8: resolve the path once, then read from it." The fix does that at `SKILL.md:66`:

```bash
CONFIG="${SECOND_SHIFT_CONFIG:-$WORKTREE/.claude/second-shift.config.json}"
```

`SECOND_SHIFT_CONFIG` now works, which it did not before — that half is a real repair. But
`$WORKTREE` is never assigned anywhere in this file: `grep -n 'WORKTREE\|worktree'` returns
`:25`, `:32`, `:63`, `:66`, `:200`, and only `:66` is a read of the shell variable. `:25` and
`:200` name the **Workflow argument** `worktree`; `:32` explains how to derive that argument's
value; `:63` points at "the absolute repo-under-review path from Pre-flight". None of them binds
a shell variable, and the `reviewers` read at `:50-56` that `:63` cites as precedent is prose
with no bash derivation either — so the justification is a circular reference rather than a shown
derivation. The sibling this relocation mirrors does bind it
(`stages/8-code-review.md:84` assigns `WORKTREE=...` before any use).

Consequence if a session runs the snippet as written, in one Bash call (shell state does not
persist between calls, so the substitution has to happen *in* the snippet): `CONFIG` resolves to
`/.claude/second-shift.config.json`, `jq` fails, `DESIGN_PROVIDER` is empty and takes the *key
absent* row — routing `design-faithful-reviewer` at a repo that declared `figma` — and
`WEB_COMPONENT_GLOBS` falls through its `|| echo` to the shipped `apps/web` default. That is
verbatim the outcome `:63` itself declares unacceptable ("the wrong reviewer, with no
not-selected note, because absence is a legitimate state").

Reached independently by `unit-test-mutation-reviewer` (major, 84) and `security-reviewer`
(75, routed out of its own lane as a routing-correctness issue), and by this review's own read.

**Severity, stated rather than assumed.** This stays a warning, on two grounds. First, the
originating reviewer classified it `major`, which maps to Warning in the baseline vocabulary —
calling it a warning is that classification, not a softening of it. Second, the precedent from
PR #369 round 2: do not escalate a round-1 warning to a round-2 blocker when the code change was
the remedy round 1 prescribed. The build did what W3 asked; the residual is an imperfection *in
that remedy*, and the consequence is a routing default, not data loss or a broken gate. No AC
covers the config read, so no AC's letter fails. Fix is one line — bind `WORKTREE` from
`git rev-parse --show-toplevel` (standalone) or from the Pre-flight value, in the snippet itself.
Route it to its own issue rather than another round.

### W2 — the cache-layout case self-disables under an ambient override

`design-cache-layout` exists because every other design-* case short-circuits past the
versioned-sibling glob by supplying `SECOND_SHIFT_DESIGN_TOOLKIT_ROOT`; its comment says so. But
the suite never unsets that variable, and the case asserts only exit 0 + no exemption notice —
both of which an ambient override to any valid design-toolkit root also satisfies.

Reproduced, not argued. With `SECOND_SHIFT_DESIGN_TOOLKIT_ROOT` exported to the repo's own
`plugins/design-toolkit` **and** the entire versioned-sibling loop deleted from the script:

```
[check-reviewer-references-selftest] 14 passed, 0 failed
```

The mutant the case exists to kill survives, silently. In CI the variable is unset, so the guard
works today and AC-3's letter holds — this is fragility, not unkillability, which is why it is
not scored against the AC. It is the same discipline `design-present` already applies one level
up (exit 0 alone cannot distinguish resolution from the exemption; here it cannot distinguish
resolution-by-glob from resolution-by-ambient-override). One line fixes it: `unset
SECOND_SHIFT_DESIGN_TOOLKIT_ROOT` near the suite's top, or scope the case with `env -u`.

### N1 — the third install state is unguarded

`check-reviewer-references.sh:269` exempts a panel name only when `DESIGN_AGENTS` is empty.
Dropping that condition survives the whole suite (14/14). The behavior it protects is real:
design-toolkit **installed but missing** one declared panel agent is a third state neither the
three-root contract header nor any AC addresses, and it currently produces a `DANGLING` commit
denial rather than the exemption. Every design-toolkit version in the local cache (2.0.2 through
2.2.1) ships both agents, so no released pairing reaches it, and the failure is loud and names
the exact missing file — the opposite of the silent-green shape that made round 1's B2 a blocker.
Recorded so the state is on the record, not proposed as a change.

## Coverage gap

`maintainability-reviewer` went dark — no text emitted on either attempt, `maxTurns` reached
mid-exploration. Its domain (readability and future modifiability of the new prose and the three
new selftest cases) was not reviewed by a specialist this round. Merge readiness below is
assessed without it. This is the recurring emit-deadline failure, not a signal about this diff.

## Dismissed

`security-reviewer`'s `grep -qx "$name"` observation (70) — the membership test treats a
filename-derived value as a BRE, so a consumer file whose stem contains a regex metacharacter
could spuriously match a panel entry. Held as pre-existing rather than new: the identical
construction appears at three other sites in the same script (`:247`, `:258`, `:307`), all
predating this change, and the new line reproduces the established pattern verbatim. Fail-closed
in the matching direction — an extra SHADOW error, never a bypass. Flagging one instance of a
four-instance pattern would be inconsistent; if it is worth fixing it is worth fixing as a set.

## Strengths

- The B1 fix is stated in **both** places that carry the disposition (`:192`, `:311`) with the
  same words, and `:194` writes down *why* the keying is load-bearing. A future edit that
  re-narrows it to a declared provider now has to argue with a recorded reason.
- `real-panel-design-absent` asserts the notice names **both** declared entries, not merely exit
  0 — which is the half that makes a dropped entry red, and it doubles as the only lockstep
  between `DESIGN_TOOLKIT_PANEL` and the shipped panel.
- `design-cache-layout`'s three-sibling fixture is specific by construction: an empty `agents/`
  at the oldest version and a broken sibling at the newest kill `head -1` and the dropped
  directory filter *separately*. Confirmed — each of the three mutants reds it alone.
- The spec grew to encode each round-1 finding as a scoreable AC (AC-9 is entirely new) instead
  of leaving them as review prose. The next round scores them by letter rather than by memory.

## Verdict

**approve** — no blockers. Two warnings, both with one-line fixes and neither failing an AC's
letter; W1 is the one to route to a follow-up issue. All nine ACs satisfied, Scope Completeness
PASS, CI green on both selftest lanes and the PR-scoped mutation sweep at the reviewed head.
