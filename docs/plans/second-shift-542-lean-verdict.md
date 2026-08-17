# lean review verdict — #542

verdict=approve
run_id: review-542-1
session_id: 121c91a4-6447-40b6-b2e1-9c079f109638
rounds: 1
pr: #576
reviewed_head: 6af660b39299aadc7dee9ef4e5a026f986b962a6
reviewed_patch_id: 5a4ac35c1c40604eb1bd8d0fadfaa9abe95ea251
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #576 (issue #542)

**Verdict: approve.** No blockers. Three warnings and one suggestion, all non-blocking.

Range read: full branch diff `a8cd2b5..6af660b` (root round, nothing to inherit), 10 files /
758 insertions. Panel: security, performance, maintainability, complexity, test-coverage,
scope-completeness — all six returned, none dark, none blocking.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| **AC-1** — the guard, and why a job not `[skip ci]` | **satisfied** | `second-shift-delta-guard.sh:120-152` classifies `parent..head`; skip requires exactly one path (`FILE_COUNT -eq 1`) whose name ends in `LEAN_VERDICT_SUFFIX`. `skip` is exposed as a `workflow_call` output (`.yml:52-58`) and consumed via job-level `if:` (`.yml:19-22`). The `[skip ci]` / required-check rationale is stated in both the script header (`.sh:19-23`) and the workflow header (`.yml:27-32`). |
| **AC-2** — the trust condition | **satisfied** | `.sh:154-196`. Skip fires only on `completed/success` for the **parent** SHA, matched on `workflow_id` **resolved from the calling run** (`.sh:169`, not taken as an input — closes the point-it-at-a-cheap-workflow hole) and on `GUARD_EVENT_NAME`. Every unknown resolves to `skip=false`: git absent, unresolvable parent, `git diff` failure, gh/jq absent, `GH_REPO`/`GUARD_RUN_ID`/`GUARD_EVENT_NAME` unset, unresolvable workflow id, API read failure, unparseable response. Verified live: 46/46 selftest assertions green in this checkout. |
| **AC-3** — option 2 rejected on the record | **satisfied** | `.sh:38-52`, in the guard's own header as the AC specifies. Names both costs (loss of the diffable in-PR artifact; `reviewed_patch_id` load-bearing in milestone 4 / `lean-evidence.sh` / `lean-reconcile.sh`) and the trade explicitly ("minutes of runner time … not worth trading a committed artifact for"). |
| **AC-4** — concurrency note in consumer guidance | **satisfied** | `docs/onboarding.md` (the standalone "Concurrency, whether or not you adopt the guard" bullet) and `templates/consumer/SECOND-SHIFT.md` (the "Related, and worth doing whether or not you wire the guard" bullet). Also restated in `onboard/SKILL.md` Step 7 item 4 and in the workflow header `.yml:41-44`. Both AC-named surfaces carry it. |
| **AC-5** — selftest coverage for the three verdicts | **satisfied** | `second-shift-delta-guard-selftest.sh`, 46 assertions, all green when run directly. The three named verdicts are cases 1/2/3. Fail-closed set covers no-PR-context, unresolvable parent, API failure, wrong workflow, wrong event, still-running, failed, no run at all, each of the four unset env vars, gh absent, and no `$GITHUB_OUTPUT`. Plus the emitted workflow's wiring, asserted against the extracted `env:`/`permissions:` blocks rather than by substring — so a commented-out wiring cannot satisfy it. |
| **AC-6** — docs for the third emitted pair | **satisfied** (with W2) | Step 3 acceptance offer (`onboard/SKILL.md:198-205`), Step 7 emit (item 4, `:387-419`), Step 8 commit list (`:467-470`); plus `docs/onboarding.md`, `SECOND-SHIFT.md`, `docs/team-rollout.md`. All three AC-named onboard surfaces are updated. See W2 for a stale count left behind in two of them. |

**Design fidelity: not-applicable.** The spec disarms with `Design: none — no UI surface; this is
CI plumbing (shell + workflow YAML)`. Verified against the diff: no changed path is a web
component, and this repo declares no `design.provider`. The disarm is justified.

## Warnings (should fix; none blocking)

**W1 — a reusable workflow cannot elevate the caller's token, so `actions: read` is not
guaranteed.** `second-shift-delta-guard.yml:71-73` requests `contents: read` + `actions: read`,
and the header correctly explains that a `permissions:` block replaces the defaults wholesale.
What it does not say is the `workflow_call`-specific half: a called workflow's permissions can
only be **downgraded** from the caller's, never elevated. A consumer whose heavy workflow
declares the common hardening `permissions: { contents: read }` therefore gets `actions: none`,
the `gh api` read at `.sh:174` 403s, and the guard is **permanently inert** — `skip=false` on
every run, forever.

The behavior is fail-safe and it does annotate (`decide_unknown` → `::warning`, `.sh:110-112`),
so this is not a correctness defect. It is a wiring instruction the consumer will need and does
not have: the annotation names the scope but not the fix, which lives in the *caller's*
`permissions:` block, not this file's. Worth one clause in the Step 7 item-4 wiring snippet and
in the `.yml` header — and note the tree already documents the analogous cap for the unclaim
pair ("a `permissions:` block only narrows the repo maximum", `onboard/SKILL.md:382-384`), so
this is the established convention rather than a new obligation.

**W2 — two stale pair-counts left in the paragraphs this PR edits.** `onboard/SKILL.md` now
emits three pairs, but:
- `:192` — "**One question, one acceptance** — on yes both file pairs are emitted in Step 7",
  six lines above the new sentence that adds "(c) the delta guard" to that same acceptance. The
  paragraph contradicts itself.
- `:359-360` — "One acceptance covers both pairs; there is no second question:", immediately
  above a numbered list that now runs to item 4.

Not scored against AC-6, because the acceptance offer and the emit list both name the third pair
unambiguously and an onboard run following the numbered list emits all three. But this is
operator-executable prose, and a count that disagrees with the list under it is exactly the kind
of drift that gets one pair dropped later. Two-word fix.

**W3 — the guidance AC-4 ships is not what this repo's own CI does.** `.github/workflows/ci.yml`
runs `on: pull_request` with `group: ${{ github.workflow }}-${{ github.ref }}` +
`cancel-in-progress: true` — verbatim the shape AC-4 tells consumers to avoid — and its inline
comment (`:8-11`) argues *for* it on the grounds that "a superseded run's verdict is about a
commit no reviewer will read", which is the reasoning #542 exists to refute for the verdict-push
case specifically.

Deliberately **not** scored as a scope gap: neither the issue nor the spec asks second-shift to
change its own CI, and the practical impact here is bounded — this repo runs no delta guard, so
the head (verdict) SHA still gets a full run and no code goes unverified. It is the cancelled
run on the code SHA that is cosmetic. Raising it because CLAUDE.md makes this repo the
dogfooding canary and the contradiction is now written down in two places. A follow-up ticket,
not a change to this PR.

## Suggestion

**S1 — two fall-through branches have no case.** `.sh:123` (`git` absent) and `.sh:133-134`
(`git diff` itself failing) are the only classification branches the selftest never drives. AC-5
names "unreadable diff" among the fail-closed unknowns, and the root-commit case (`:171-176`)
covers the reachable instance of it — an unresolvable parent — so the AC is met. Both uncovered
branches are defensive against states the `actions/checkout` step would already have failed on.
Noting for completeness, not asking for it.

## Reviewer panel

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 (3 suppressed) | 45–60 |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

`a11y-reviewer` and the design-fidelity dimension were **not routed** — no changed path matched
`stageParams.webComponentGlobs` (unset; resolves to the shipped default
`apps/web/**/*.{tsx,jsx}`). `db-reviewer` / `pipeline-reviewer` not triggered: no DB layer, no
queue-processor surface. Not-selected, not dark.

### Suppressed security findings, checked independently

All three were suppressed correctly; I re-derived each rather than taking the confidence score.

- **`$GITHUB_OUTPUT` injection via a crafted path (45).** `REASON` interpolates `$CHANGED` and
  is appended as `reason=$REASON` with no delimiter, so a newline plus `skip=true` would append
  a later-winning key. Unreachable: git C-quotes any path containing a control character
  regardless of `core.quotePath`, so no real line break survives into `$FILES`. Every other
  interpolated value is a numeric count, a SHA, or a GitHub status enum.
- **A fork PR can rewrite the guard script (60).** True and not new — on `pull_request` GitHub
  already evaluates workflow files from the PR head, so the same contributor can set
  `if: false` directly. The read-only token bounds it.
- **`gh api` path interpolation (50).** `GH_REPO`/`GUARD_RUN_ID` are GitHub-supplied context.
  `WORKFLOW_ID` is additionally digit-validated at `.sh:170-172` before reaching `--argjson`.

## Verification run in this checkout

- `second-shift-delta-guard-selftest.sh` — **46/46 green**.
- `shellcheck -e SC1091,SC2015,SC2181` over the two new scripts and `lean-evidence.sh` — clean
  (0.11.0 locally; CI pins 0.9.0).
- `scripts/check-lockstep-pairs.sh` — **23 pairs, 0 failed**, including the new
  `lean-verdict-suffix` row.
- `second-shift-delta-guard.yml` parses as YAML.
- **Mutation-baseline obligation discharged, and correctly so.** CLAUDE.md requires re-baselining
  a guard's position-keyed survivor ordinals when the guard is edited. This PR inserts nine lines
  at `lean-evidence.sh:333`, and its two baselined rows are `cmp-eq::1` and `default::1` — both
  prose sites in the Seams header at lines 114 and 119, above the insertion. The ordinals do not
  move, so leaving `tools/mutation-baseline.tsv` untouched is right, not an omission.

## Strengths

- **The trust condition is built where it is hardest to weaken.** Resolving `workflow_id` from
  the calling run (`.sh:169`) rather than accepting a workflow name as input closes the
  point-it-at-a-cheap-always-green-workflow hole structurally — there is no input to
  misconfigure. Pairing it with the event match is the second half most implementations skip.
- **The fail-open shapes are named and pre-empted in code, not just in prose.** `git diff` read
  into a variable whose status is checked rather than piped into a matcher (`.sh:130-134`); the
  count check plus an independent single-line read as "the second lock, on the reasoning that
  the count check is the line a future edit relaxes" (`.sh:143-152`); `!= 'true'` rather than
  `== 'false'` because an absent output must run the lane. Each carries the failure it prevents.
- **The selftest asserts the emitted artifact, not just the script.** The `env:`/`permissions:`
  wiring is checked against `awk`-extracted blocks with anchored patterns, so a commented-out or
  relocated key cannot satisfy it — and it cites the `second-shift-ci-check-selftest.sh`
  precedent where the substring form passed that exact mutation. The `no $GITHUB_OUTPUT` case
  asserting that *no file was written into the working tree* is the right shape for what it
  guards.
- **The lockstep row's reasoning is the non-obvious part and it is written down.** Adding
  `lean-verdict-suffix` without reversing the standing DROP for the rest of the suffix table
  required explaining what changed — a third holder with a different transport, committed into a
  consumer repo rather than fetched at the pinned ref, whose divergence is silent and green.
  Both the manifest note and the two code comments say it, and the comments are placed outside
  the markers so `verbatim` stays honest.
- **The probe findings in the PR body were acted on rather than baselined.** The mixed-diff case
  that passed only on its message, the `default::1` survivor from an unset `$GITHUB_OUTPUT`, and
  two of the author's own comments displacing real mutation sites — each fixed in its own commit.
  The advisory slow-suite warning left standing with a stated reason ("adding the row would defer
  that guard to nightly") is the right call, not an omission.
