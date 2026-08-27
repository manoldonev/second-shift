# lean review verdict — #695

verdict=approve
run_id: review-695-2
session_id: 494caaa4-6019-400a-bd00-f8d31511fe8f
rounds: 2
pr: #702
reviewed_head: 03c8522cacef70216ea1c379696e5a0602e05b04
reviewed_patch_id: d9140ec842b4e66d8fbfa4013de50442ba54ffa4
inherited_patch_id: 5c7d72737f9c8371ae83b7ed5e61809a21fc8f4b
inherited_from_verdict: e2d815a06a88b47f0612ed29c03a5fa4a9fc4a4a
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 2 — PR #702 (#695)

**Verdict: approve.** No blockers. Two warnings, one suggestion.

Range read: `e2d815a..03c8522` (delta round — 2 files, +36/-6), inheriting the coverage of patch
`5c7d72737f9c` recorded by round 1. The panel was dispatched over the **full branch**
(`6dd9f70...03c8522`) rather than the delta, because the diff is small and a round that read
everything is the stronger record. Reviewed from the lane worktree with
`claude/second-shift-695` checked out; head re-verified against `origin` immediately before
writing this record.

Gate of record: the **branch copy** of `lean-gate.sh`
(`plugins/dev-pipeline/skills/build-lean/lean-gate.sh`), not the installed `dev-pipeline/11.0.0`
cache — `main` is at 12.1.0 and the cached gate lacks `plan_patch_id` / `PLAN_MANIFEST_REL` /
`seed_lane_worktree_settings`. Same choice rounds 1 and the build session made.

## Prior round disposition

| Prior | Status | Evidence |
| --- | --- | --- |
| **B1** (blocker) — `docs/live-render.md:34` credited the gate with "route derivation and comparison" | **Fixed** | `:34-36` now reads "route derivation, the state matrix, the PNG hashes and the manifest — **never comparison**, which is the review session's", with an anchor into `## Why there is no pixel-diff gate`. Re-verified against `cmd_3`, not just against the prose: the gate parses `RS-n<TAB>route<TAB>state` from the spec table (`lean-gate.sh:3119-3131`), substitutes `{route}` (`:4053`), `lean_sha256`es the PNG (`:4077`) and writes the manifest (`:4088`). Every one of the four named responsibilities is real; the removed one is not. The anchor `#why-there-is-no-pixel-diff-gate-and-none-is-coming` resolves against the heading at `:192`. |
| **W1** — the shipped doc asserted a follow-up ticket exists for direction 2 | **Fixed** | `:206-211` now reads "It **would need** a ticket of its own, with those costs priced; none is filed, and this document does not wait on one." No longer asserts a ticket a reader can go looking for. |
| **W2** — `Changelog: none` on a consumer-visible correction | **Fixed without rewriting history** | `03c8522` carries a real `Changelog:` block. Trailers are extracted grep-anywhere across the branch and `Changelog: none` "counts as trailer-present but renders nothing" (`scripts/derive-release.sh:29-36`), so the three `none` trailers on the earlier commits do not pollute the squashed entry. No force-push, no lost committer identity. |

No prior finding was suppressed rather than addressed, and none was re-introduced.

## Finding table

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| W1 | Warning | `docs/plans/second-shift-695-lean.md` (AC-6 arm 2 triage) | The AC asserts "**12 hits**, none a live claim". The committed grep, run verbatim at `03c8522`, returns **13 lines**. The enumeration itself is complete — the miscount comes from listing `orchestrate-lean.sh:48-49` as one entry when it is two matching lines. A criterion that states a count the criterion's own command does not produce makes the next reader reconcile a discrepancy that is not a defect. |
| W2 | Warning | `docs/plans/second-shift-695-lean.md` (AC-6 arm 2 triage) | The triage is a **point-in-time snapshot pinned inside a durable criterion**. Thirteen line numbers across seven files are named in an AC that must be re-scored every round; all thirteen resolve today, and every one drifts the next time any of those files is edited. The criterion proper ("no hit credits the gate, the lane, or milestone 3 with comparing a render against the design") is durable; the hit table is a round artifact. Recording the triage was right — round 1's lesson was that an unrecorded broad grep gets re-triaged cold — but it belongs in the verdict record or a "measured at" note, not inside the AC's own text. |
| S1 | Suggestion | `docs/live-render.md:34-36` | "**never comparison**" is unqualified in the section a consumer reads to build their harness, while the gate *does* perform one comparison the same file tells them to design for: the byte-identical-states detector (`:162-165`, "Two declared states that produce byte-identical screenshots red"). The restrictive clause ("which is the review session's") and the anchor both scope it to the design comparison, and `:169` states the bounded form correctly — so this is an imprecision, not the ticket's defect class (it under-claims rather than over-claims). One word — "never *design* comparison" — closes it. |

### Why none of these is a blocker

W1 and W2 are accuracy and durability notes on a criterion that is otherwise **stronger than the
one it replaced**, and neither changes what the tree contains. S1 points at an under-claim, which
is the mirror image of the defect class #695 exists to retire and is disambiguated twice in the
same file. Nothing here credits a component with fidelity work it does not do.

## The round-2 question this run turns on: is the widened AC-6 real?

Round 1's blocker was not the line — it was that the spec's own completeness criterion was
**phrase-shaped while the defect was shape-shaped**, so a sentence crediting the gate with
comparison passed a check that read as complete. The fix widened AC-6 to a second arm over the
defect shape. That amendment is the thing worth auditing hardest, because a spec amended after
the fact to match the diff is itself a blocker.

It is not that. Three checks:

1. **The amendment is stricter, not looser**, and its source is named — D-6 cites the round-1
   verdict record, `codebase-derived`, with the resolution quoting the finding. AC-6 arm 1
   survives verbatim; arm 2 is added on top.
2. **The criterion is live, not vacuous.** Probed the committed regex against both defect
   sentences this ticket exists to remove:
   - `"The gate owns route derivation and comparison."` → **matched** (the round-1 blocker).
   - `"milestone 3 … semantically compares it against the cached design frame."` → **matched**
     (the AC-5 defect).
   A criterion that catches both shapes the run found is a real gate, not a restatement.
3. **The criterion passes at its own head, and I ran it rather than reading it.** Extracted the
   fenced command verbatim from the committed spec and executed it: 13 hits, every one in the
   compliant classes the AC names (hypothetical, denial, attributed to the sighted reader, or a
   different subject entirely — the scheduler's progress-token comparison, P4's derived
   comparison, `stall-probe.mjs`'s "comparable across arms"). Every one of the thirteen cited
   line numbers resolves at head. Only the **count** is wrong (W1). Note also that the
   `':!docs/plans/'` exclusion is load-bearing and correctly present: without it the AC is
   unsatisfiable at its own head, because this very record quotes the offending sentence in order
   to report it.

## Per-AC scoring (against the committed spec `docs/plans/second-shift-695-lean.md`)

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Direction 3 recorded with reasoning against directions 1 and 2 in `## Decision (AC-1)`, and operatively in `docs/live-render.md:192-214` under a heading that states the posture is settled ("and none is coming"). D-1/D-2 carry it in the ledger with legal `provenance` values. Unchanged by this round's delta; re-verified at head. |
| AC-2 | **satisfied** | Re-measured at `03c8522`, not inherited from the spec's table: `figma-faithful-spec-reviewer.md:33`, `figma-faithful-plan-reviewer.md:59,64`, `figma-faithful-reviewer.md:39`, `figma-faithful-spec/SKILL.md:219`, `design-faithful/SKILL.md:59` — every one denies the gate exists. Zero edits to these files remains the correct answer, not a gap. |
| AC-3 | **satisfied** | No gate built, so nothing is owed on "asserted by the lane" and no selftest is owed. Re-ran the broadened "coming gate" grep (`once/when/until the gate`, `future gate`, `planned gate`, `not yet built`, `gate is coming`, `will be built`) over `plugins/ docs/` excluding `docs/plans/` at head: three hits, none about a fidelity gate (a scheduler token, an eval baseline, a db-reviewer tenancy note). |
| AC-4 | **satisfied** | "the pixel-diff gate is still deferred" is gone; `:192-214` states the settled posture and its reasoning. Arm-1 grep at head returns 12 lines, all denial, heading, anchor link, or the explicit hypothetical — no live deferral anywhere in `plugins/ docs/`. |
| AC-5 | **satisfied** | The opening (`:3-12`) describes what the gate does — runs the command, takes the PNG, hashes it into the patch-bound receipt — states "**The gate compares nothing against the design** — it caches no design frame", and names the `/dev-pipeline:review-lean` session as the comparer. Verified against `cmd_3`. |
| AC-6 | **satisfied**, and now a real criterion | Both arms run clean at head; both are recorded above with their triage. Round 1 scored this "satisfied as written, weak as a criterion"; that weakness is what this round's delta fixed, and the probe in the section above is the evidence it is no longer weak. W1/W2 are accuracy notes on the AC's prose, not an unmet criterion. |

**Design fidelity: `not-applicable`.** The repo config declares no `design.provider`, so no
`## Design` section is required or present in the spec, and no render receipt exists. Step 5b does
not apply.

## Panel

| Reviewer | Verdict | Findings | Model |
| --- | --- | --- | --- |
| Maintainability | Pass | 0 | sonnet |
| Scope completeness | Pass | 0 (2 suppressed, both visibility-only: AC-2's five files untouched but read at head; the spec's AC-4/AC-5 exceed the issue's three ACs — additional work, which cannot fail the gate) | opus |

Routing: **trivial-inert** — every changed file is Markdown outside `.claude/`, so security,
performance, complexity and test-coverage were not selected (no executable surface). a11y and the
design-fidelity dimension were not routed: no changed path matches
`stageParams.webComponentGlobs`, which the repo config does not set (default
`apps/web/**/*.{tsx,jsx}`). Not-selected, not dark — both selected reviewers returned usable
results, so the round is intact. Noted for calibration: maintainability returned in 7s on one tool
call, declining to open every file under proportionate grounding; that is a usable result, but it
is not what this round rested on. All three findings below are mine, verified against the gate
source before being raised.

## Strengths

- **The fix went to the criterion, not just the line.** The one-line correction was the cheap
  half; widening AC-6 to a second arm over the defect *shape* is what stops the next instance
  being caught by a reviewer instead of by the spec. D-6 records it with its source, so the
  amendment is auditable rather than silent.
- **The new sentence is a positive denial, not a deletion.** "route derivation, the state matrix,
  the PNG hashes and the manifest — never comparison" names what the gate owns before denying what
  it does not, so a later reader cannot re-add the false claim by inference from an absence. All
  four named responsibilities check out in `cmd_3`.
- **The `':!docs/plans/'` exclusion on the new arm was thought through.** Promoting a review's
  triage grep into an AC verbatim would have made the AC unsatisfiable at its own head — this
  run's records quote the offending sentence in order to report it. Arm 2 carries the same
  exclusion arm 1 already had, on the same stated ground.
- **W2 was discharged without rewriting history.** A real `Changelog:` on the fix commit
  discharges a `Changelog: none` on an earlier one, because trailers are extracted grep-anywhere
  and survive the squash. Cheaper and safer than an amend or a merge-dialog edit.
- **W1's fix declines to over-correct.** "It would need a ticket of its own … none is filed, and
  this document does not wait on one" removes the dangling pointer without pretending the
  direction was refuted — the recommendation survives, the false assertion does not.

## Recommendation

Approve and merge. W1 and W2 are worth folding into the spec at some point — the count is wrong
and the hit table will go stale inside a durable criterion — but neither changes the tree, neither
is consumer-visible, and neither is worth a round. S1 is a one-word polish on `docs/live-render.md:34`.

Still owed by the operator, outside this PR: **file the direction-2 follow-up ticket** drafted in
the spec's "Follow-up owed" section. The shipped doc no longer asserts it exists, so nothing is
broken by the delay — but the recommendation is live and the precondition (#701's committed
`dimensions` table) is now in place.
