# lean review verdict — #694

verdict=approve
run_id: review-694-2
session_id: 6b5078b1-14c6-424f-a5f0-6261c7dc3bbf
rounds: 2
pr: #701
reviewed_head: 6cd599b96152bb43750cc606834f43b80e37e1f5
reviewed_patch_id: b6da4c043a279407640d7ae292f50f1445094e76
inherited_patch_id: 4472a86437f3f0148e0db71cb62abc44d0f250d3
inherited_from_verdict: e5ef16bdf1fd5f128e523a9f1b250912745f4e09
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 2 — PR #701 (issue #694), head `6cd599b9`

Range read: `e5ef16bd..HEAD` — the round-1 fix commit `6cd599b9` alone, inheriting the coverage
of patch `4472a86437f3` recorded by round 1. Read wider than the range wherever the delta was
misleading: the whole `origin/main...HEAD` contribution for the per-`AC-n` scoring, and the
prior record's findings first.

Panel: 6 of 6 returned, none dark (security, performance, complexity, test-coverage,
maintainability, scope-completeness). **Zero findings from the panel, as in round 1**; every
statement below is hand-derived and measured. Design fidelity: **not-applicable** — the committed
spec declares no `## Design` section, and this repo's config declares no `design.provider`.

**A note on the branch's own diff.** `git diff main...HEAD` in a checkout whose local `main` is
stale sweeps in `609a22cf` (#699, merged) as branch content. The real merge-base is
`609a22cf` and `origin/main` is exactly that commit, so the contribution is
`origin/main...HEAD` — 20 files. The cost-block files are not this branch's.

**Verdict: `approve`.** All seven `AC-n` satisfied. All three round-1 blockers are fixed and each
fix was verified independently, not taken on the commit message's word. Both round-1 warnings are
closed. Two findings below are warnings that do not block: one is a pre-existing line outside
AC-4's declared family, the other is a successor-ticket consequence for the operator to act on at
promotion time, not a defect in this diff.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| W1 | Warning | `docs/live-render.md:178` | The one surviving live deferral to a pixel-diff gate — "the pixel-diff gate is still deferred" — in a file this branch edits, while five sibling documents it also edits now say no such gate exists and must not be deferred to. |
| W2 | Warning | `#695` (declared successor) | AC-4 as the spec broadened it lands #695's option 3 verbatim across the four documents #695 enumerates. Promoting #695 `ready-for-dev` on merge, as the issue instructs, queues a ticket whose problem statement no longer reproduces. |

### W1 — one deferral to the non-existent gate survives, outside AC-4's family

`git grep -i 'pixel-diff\|screenshot-diff'` over `plugins/ docs/` at `6cd599b9` returns eight live
sites. Seven are correct: the three `figma-faithful-*` agents and the `figma-faithful` /
`figma-faithful-spec` skills all now deny the gate exists and name the design-sighted `review-lean`
session; `design-faithful/SKILL.md:59` already said "no pixel-diff tool in-repo — do not invent";
`lean-gate.sh:3147` is a comment citing that. The eighth is `docs/live-render.md:178`:

> It verifies nothing against the design — the pixel-diff gate is still deferred, and a reviewer
> can still cite a real but irrelevant criterion.

**Not a blocker, and I want to be exact about why.** AC-4's subject is "every deferral in the
`figma-faithful` reviewer family". `docs/live-render.md` is repo documentation, not a member of
that family, and the line is pre-existing (#693's, unchanged by this branch's hunks). The two
statements are also not strictly contradictory: no gate *exists* (fact), and a decision about
whether to build one is *pending* in #695 (also fact). What makes it worth a line is that this
branch adds 22 lines to that same file and its own new prose elsewhere reads "do not defer to
one" — so the repo now says both things about the same absent gate, in two files one PR touched.
One sentence closes it, and it is the same sentence the five siblings already carry.

### W2 — the successor's problem statement is answered by this diff

The issue body ends: *"On merge, label #695 `ready-for-dev`. Successor: #695."* #695 is open and
titled *"Three reviewers defer fidelity to a pixel-diff gate that was never built"*. Its problem
statement enumerates exactly four documents — `figma-faithful-spec-reviewer.md:31`,
`figma-faithful-plan-reviewer.md:44`, `figma-faithful-reviewer.md:39`,
`figma-faithful-spec/SKILL.md:218` — and its "Fix shape" section says the direction is
**"Undecided by design — this ticket exists to make the standing debt visible and to force the
decision, not to presume it"**, listing three: build it, scope it down, or *"Retire the deferral.
Decide fidelity will remain attested, and rewrite all four documents to say so plainly instead of
pointing at a gate that is not coming."*

This PR rewrites all four of those documents to exactly that. After merge, #695's stated problem
does not reproduce at any of its four line references.

**Why this is a warning and not a blocker.** Three things had to be true for it to be one, and
none is:

1. *An AC would have to be unmet.* AC-4 as the **committed spec** states it — "every deferral in
   the `figma-faithful` reviewer family … none may name a gate that does not exist" — is met.
2. *The spec would have to have been amended to match the diff.* It was not.
   `docs/plans/second-shift-694-lean.md` has exactly **one** commit on this branch, `53fdeccb`,
   the spec commit that precedes all implementation, and AC-4's broad wording is in it verbatim
   at lines 54–56. `git diff 53fdeccb..HEAD -- docs/plans/second-shift-694-lean.md` is empty.
   The broadening (the issue's AC-4 named only `figma-faithful-spec-reviewer`'s deferral targets)
   was declared before code, not discovered after it.
3. *It would have to foreclose #695.* It does not. #695's own text says option 3 "closes
   nothing"; the real question — build a comparison, or scope it to measured properties — is
   untouched.

**What it does oblige.** Re-derive #695 before promoting it: its problem statement, its four line
references and its option 3 are all spent. Left as-is, a build session picks it up and finds the
work already done at every reference the ticket gives it.

## Round-1 blockers — each fix verified independently

### B1 (namespace red) — fixed, measured

`git grep 'dev-pipeline:' 6cd599b9 -- plugins/design-toolkit plugins/review-toolkit
plugins/intake-toolkit plugins/audit-toolkit` returns **nothing**. `lint-and-selftests` at head
`6cd599b9` is **success** (run 33089872958, job 98579499166) — the job that was `failure` on
step 15 at `4343498b`. The lane is named bare at every site, matching the precedent round 1
cited.

### B2 (the missed family member) — fixed, and wider than the blocker asked

`figma-faithful-reviewer.md:39` now reads "…it is not a pixel-diff gate, and no such gate exists
in this repo. Say so rather than implying you checked the design." The fix went past the one file:
grepping the *construct* found two further sites the round-1 review had not enumerated either —
`figma-faithful/SKILL.md:228` and `figma-faithful-spec/SKILL.md:219` — and both were rewritten.
That is the right method and it is worth naming: an AC phrased "every X in the family" is
satisfied by a grep that returns nothing, not by visiting the files someone remembered.

Each rewritten site names a reader that is real and reachable: `review-lean/SKILL.md:70-84` on
this branch publishes the `## Design fidelity evidence` grammar (`| RS-n | frame node | property |
design | rendered | verdict |`), and `lean-gate.sh:3155` enforces it at the verdict writer. The
deferral target is not another disclaimer.

### B3 (two fail-open shapes) — fixed, and I re-derived the kill rather than reading the claim

`plan_violations()` emits five malformed shapes; all five now have a `(dp*)` case — `(dp2)` no
column, `(dp3)` empty cell, `(dp4)` short row, **`(dp10)` no data row**, **`(dp11)` no delimiter
row**. Probed at `6cd599b9` in throwaway detached worktrees, never this checkout, serially, with
`CLAUDE_CODE_SESSION_ID` / `LEAN_ATTEND_MODE` / `LEAN_RUN_MODEL` / `LEAN_SPAWN_PERMISSION_MODE` /
`RUN_ID` / `SECOND_SHIFT_CONFIG` scrubbed. Each mutant is the catalog row's own `sed -E`
expression, verified to rewrite exactly one line and to leave the file parsing under `bash -n`:

| tree | mutant | passes | failures | terminal |
| --- | --- | ---: | ---: | --- |
| baseline | — | **551** | 0 | `all green` |
| `lean-plan-no-data-row-waived` | the `carries no data row` arm → `if (0) {` | 550 | **1 — exactly `(dp10)`** | `1 FAILURE(S)` |
| `lean-plan-delimiter-arm-waived` | `if (rowno == 2)` → `if (rowno == -1)` | 550 | **1 — exactly `(dp11)`** | `1 FAILURE(S)` |

Both rows are live, each new case is the sole killer of its row, and the baseline reproduces the
551 the PR body claims.

**The detail that makes these cases correct, and it is not incidental.** Under the no-data-row
mutant the gate still exits **rc=1** — the plan reads complete, so `design_plan_gate` walks on to
the stale-stamp block and refuses there instead. I captured the refusal it actually printed:

> ✗ milestone-3: the translation plan `docs/plans/acme-55-lean-plan.md` was written against
> different code — its 'planned_from' has been re-stamped to `aced9388f4dc`.

A `(dp*)` case asserting only `[ "$rc" -eq 1 ]` would have scored that as a kill while the shape
stayed fail-open. Both new cases assert the **refusal text**, which is what catches it. `(dp11)`
carrying two data rows is right for the mirror-image reason: with one row, `rowno` never reaches 3,
so the mutant falls through to `endtable()`'s no-data-row arm and the plan is still refused —
fail-closed with the wrong message rather than fail-open. Two rows is the shape a real plan has and
the only one where the arm is genuinely open.

## Round-1 warnings — both closed

- **W1 (the one-directional coupling note).** `docs/testing.md:788-799` now states the direction it
  was silent on, and the code agrees: `render_patch_id()` excludes only `$VERDICT_REL` and
  `$RENDER_MANIFEST_REL`, so the plan sits inside it and a plan-only commit does restale the
  receipt; `plan_patch_id()` additionally excludes `$PLAN_MANIFEST_REL`. The receipt is excluded
  from both, which is what makes it converge in one pass instead of looping — the note says
  exactly that.
- **W2 (the case count stated three ways).** Now stated once and correct. Measured at
  `6cd599b9`: **12** unique `(dp*)` ids (`dp0`–`dp11`) carrying **14** `pass` assertions. The
  fix commit's `Guard-mass:` trailer says "12 `(dp*)` case ids carrying 14 assertions".

## Per-`AC-n` scoring

Every `AC-n` is scored against the whole spec, not the delta.

| AC | Score | Evidence |
| --- | --- | --- |
| **AC-1** — the plan is a committed artifact at `<plansDir>/<key>-lean-plan.md` with a gate-stamped `planned_from:`; milestone 3 refuses **before the render pass** on absence / missing-or-empty table / stale binding; same arming predicate and `design_was_armed` lock as the render lane | **satisfied** | `design_plan_gate; rc=$?` is called at `lean-gate.sh:3960`, ahead of the `LR_COMMAND` check and every render call — the ordering is in the code, not only in the docs. `(dp0)` is the AND executioner (armed spec read through a no-design config must not mention a plan); `(dp8)` pins the disarm lock; `(dp5)`–`(dp7)` the stamp cycle and staleness convergence. All green in my scrubbed 551/551 baseline. |
| **AC-2** — the sizing check fires on the SILENT case (no dimension rows at all), not only on a repeating/wrapping group | **satisfied** | `figma-faithful-plan-reviewer.md`: new `[Blocker]` for "a plan for a **control-bearing screen** … that records **no dimension row at all**", explicitly labelled the silent case, with the pre-existing repeating/wrapping-group `[Warning]` retained beside it rather than replaced. |
| **AC-3** — a component whose rendered affordances exceed what the frame draws, with no intended-note, is reported | **satisfied** | New `### Component-resolution suitability` section, `[Blocker]` on excess affordances (steppers, chevrons, clear buttons) with no note and no suppressing prop, plus a `[Blocker]` on a resolution stated only as a name match. The section substitutes "what the plan describes the node as being" for "what the frame draws" — a real narrowing, but a **stated** one: its own preamble says "You have no Figma access, so you cannot confirm a component matches the frame", and the spec's *Explicitly out of scope* already says neither reviewer verifies a recorded value against the design. Declared, not silent. |
| **AC-4** — every deferral in the reviewer family names a lane-reachable owner or says none exists; none names an `N/A`-on-every-lean-input target; none names a gate that does not exist | **satisfied** | Grep of the construct across `plugins/`: no family member defers to a pixel-diff gate. Component *identity* is marked interactive-lane-only with its reason (`figma-faithful-spec-reviewer` `N/A`s every lean-lane spec) and its *suitability* half taken locally; copy *capture* is stated to have **no** lean-lane owner rather than handed to an agent that would `N/A` it. The named owner's contract exists (`review-lean/SKILL.md:70-84`, enforced at `lean-gate.sh:3155`). The plan reviewer's own input recognizer was widened to accept the lean-lane artifact — a recognizer narrower than the artifact would have been the same dropped check one level down. `docs/live-render.md:178` is W1 and is outside this AC's declared family. |
| **AC-5** — step 7 describes the artifact (path, tables, `planned_from`) and the asserting milestone, replacing #693's placeholder | **satisfied** | `figma-faithful/SKILL.md` §7 now carries the path derivation, the `planned_from: pending` header and what the gate does with it, both required columns, the every-cell/no-short-row rule with its rationale, and the "refuses **before** the render pass" ordering. |
| **AC-6** — `lean-gate-selftest.sh` covers arming, absence, **each** malformed shape, the stamp cycle, staleness and the disarm lock; `scenario-liveness-selftest.sh` carries the composed leg | **satisfied** | 12 ids / 14 assertions; all five `plan_violations()` shapes now have a case (this was round 1's B3, re-derived by probe above). `scenario-liveness-selftest.sh` gains `(lean-design-plan)`: three refusals with `rcs=111`, `attempts=0`, `armed=1` and no `lean-renders/88` directory — proving the order, the absent-budget economics and the arming lock in composition — then the same chain walking into the render pass once the plan is committed. |
| **AC-7** — `docs/live-render.md` and `build-lean/SKILL.md` describe the plan gate where they describe the render receipt | **satisfied** | `docs/live-render.md` §"What the gate does when armed — first, the translation plan" (+22 lines) covers the artifact, the budget split and the deliberate absence of a merge-boundary arm, with "**Then the render.**" following. `build-lean/SKILL.md:27` step 6 now names the plan clause ahead of the receipt clause in one sentence. Neither reads as the complete armed contract while omitting half of it. |

## Recorded, not blocking

- **`pr-gates` is red on step 7 alone** — *lean chain reconciliation*, which requires
  `verdict=approve`. Expected state for an unreviewed lean PR. Steps 3–6 — frozen files,
  `Changelog:` trailer, **guard budget**, pipeline chain reconciliation — are all **success**, so
  the `Guard-mass: +551` trailer is accepted. `lint-and-selftests` and
  `selftests (macos, bash 3.2)` are both green at this head.
- **`mutation-sweep-pr` is green in 12s and graded nothing.** `lean-gate-selftest.sh` is
  slow-listed in `tools/selftest-suite-timings.tsv`, so the PR-lane sweep defers it — the two new
  catalog rows have no CI oracle on this lane. That is why they were probed by hand above rather
  than credited to a green check.
- **All four `lean-plan-*` catalog seds apply cleanly under `sed -E`**, each rewriting exactly one
  line: `lean-plan-arm-uncalled` (`lean-gate.sh:3960`), `lean-plan-empty-cell-waived` (`:3851`),
  `lean-plan-no-data-row-waived` (`:3814`), `lean-plan-delimiter-arm-waived` (`:3836`). No
  syntax-broken mutant, so no vacuous kill.
- **`scripts/gate-buckets.tsv` +7 rows, `docs/prose-blocker-triage.tsv` +3 rows**, all present and
  anchored; the guards that validate them are inside the green `lint-and-selftests` job.
- **The `[REDACTED]` strings are the session's output filter, not file content.** They appear in
  tool output for `scenario-liveness-selftest.sh:1391` and `lean-gate.sh:3953`; `grep -c REDACTED`
  returns **0** for both files. Round 1 hit the same artifact and dismissed a confidence-92 panel
  finding on it.
- **The toolkit → dev-pipeline prose coupling deepens, legitimately.** `docs/namespaces.md` rule 3
  reads "the four toolkits never reference dev-pipeline", but its CI enforcement is two greps —
  the `dev-pipeline:` token and `dev-pipeline/` paths — and design-toolkit content now carries a
  good deal of lean-lane vocabulary (`review-lean`, the render receipt, milestone 3, `RS-n`,
  `<plansDir>/<key>-lean-plan.md`, `bash G 1 <issue>`). It greps clean and it is unavoidable:
  AC-4 requires naming an owner that runs on the lean lane, and AC-5 requires publishing the
  artifact's path. Main already carries the same shape (`review-lead/SKILL.md:190`,
  `plan-interview/SKILL.md:61`). Recorded because the volume changed, not because this diff broke
  a rule.
- **Tree pristine at the time of writing.** All probing ran in throwaway detached worktrees;
  this checkout is clean against `origin/claude/second-shift-694`, so `reviewed_patch_id` hashes
  the pushed patch and nothing else.
