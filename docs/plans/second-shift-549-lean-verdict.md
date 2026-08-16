# lean review verdict — #549

verdict=needs-work
run_id: review-549-1
session_id: da5c2b16-a227-4e3d-856e-76b26d82f3ca
rounds: 1
pr: #560
reviewed_head: 5bd3654c10b54cfb7c180d978a549424020d2dfe
reviewed_patch_id: 07655a0bf0dbd108d5b20fa2aceb477ae68ae538
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #560 (issue #549)

**Range read:** `54aec70..HEAD` — the whole branch diff (root round, nothing to inherit).
One file, `docs/plans/second-shift-549-lean.md`, +155/-0.

**Panel:** maintainability-reviewer (approve, 0 findings) and scope-completeness-reviewer
(block, 5 blockers + 1 minor). Trivial-inert routing: the sole changed path is a Markdown doc
outside `.claude/`, so security / performance / complexity / test-coverage were not selected.
a11y and the design-fidelity dimension were not routed — no changed path matches
`stageParams.webComponentGlobs` (unset, resolving to the shipped `apps/web/**` default).

---

## Verdict: needs-work — one blocker

The probe itself is good work, and the decision to stop was the right one. The blocker is not
about what the document says; it is about what merging it would do to the ticket.

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — the probe, recorded per candidate per criterion (D-2, D-3) | **satisfied** | The criteria table reproduces D-3's six criteria verbatim, and candidates A/B/C are exactly D-2's enumeration. Every claim I could re-measure holds: CLI `2.1.233`; `tmux` absent; the `--bg` refusal text is quoted exactly as the CLI emits it; `--tmux` does require `--worktree` per its own help. One accuracy warning below. |
| AC-2 — the stop, and what it is asking for (OR-1) | **satisfied** | OR-1's trigger condition is met, its `pause-and-ask` disposition is honored, the question is posted on the issue (bot comment, 2026-08-16T20:05Z), and no production file is touched. |
| AC-3 — nothing is claimed that was not measured | **satisfied** | Verified against the diff: one document, no behavior, no seam, no asserted improvement. D-6's exit criterion is declared unmet rather than finessed. |

All three ACs of the committed spec hold. The blocker sits at the merge boundary, not in the
AC set — which is why it is a blocker rather than an unsatisfied AC.

---

## Blocker

### B-1 — the PR auto-closes #549 while the question that decides its scope is unanswered

The PR body carries `Closes #549`, so merging closes the ticket. But AC-2 asks the operator a
question with two answers that lead to opposite dispositions, and it is unanswered:

- **Answer 2 (close as answered)** — merging is correct, and the ticket is done.
- **Answer 1 (completion contract in scope)** — the spec itself says this "is a re-scope, not a
  continuation of this ticket as written". Merging first closes the ticket that is supposed to be
  re-scoped.

Underneath that, six binding-receipt decisions and three Testing obligations currently have **no
written disposition anywhere**: D-1 (winner becomes the default via a `spawn()` capability check),
D-4 (the stream split holds verbatim under the new transport), D-5 (`LEAN_PHASE_TRANSPORT` plus
the nested-child scrub, and `build-lean/SKILL.md`'s two-branch in-flight rule), D-7 (recoverable
rc), D-8 (all three spawn sites move together), D-10 (the P10 identity assertions), and the
`## Testing` trio (extend the `LEAN_SPAWN_BIN` fake, run #531's stream-split assertions under both
transports, re-baseline the re-keyed mutation ordinals). `orchestrate-lean.sh`,
`orchestrate-lean-selftest.sh`, `build-lean/SKILL.md`, `tools/mutation-baseline.tsv` and
`tools/mutation-catalog.tsv` are all absent from the diff.

Each of those is genuinely *conditional on a surviving candidate*, and no candidate survived — so
this is not "the build skipped work". It is that a merge would dispose of all nine **by closure**,
silently, while the operator question that should decide them is still open. The receipt parks
exactly this under D-13 ("whether no surviving candidate is a failure or a landing") and leaves it
`open`.

**Remedy — and specifically not "delete `Closes #549`".** That trailer is how the lane resolves the
issue key, so removing it breaks the next round. Instead: hold the merge until OR-1 is answered on
the issue, then record the answer's disposition for the nine items in the spec — one line each is
enough, and under answer 2 that line is "closed as answered, no transport lands". The scope gate
then has a written deferral to read instead of an unchanged `spawn()`.

---

## Warnings

### W-1 — the withdrawn 10-AC spec and the reverted implementation are unreferenced, and one of them is gone

AC-2 states that a complete implementation of candidate D's EOF configuration was "written and
reverted": capability check, renderer, `LEAN_PHASE_TRANSPORT`, the `SEAM_SCRUB_ENV` scrub, both
SKILL.md two-branch rules, six new selftest cases, all green. Two things follow that the document
does not say:

1. **The spec's own AC set was replaced, not just corrected.** At `608e57c` this file carried
   **AC-1 through AC-10** — a full implementation spec, with the streaming transport as the default
   and candidate D scored "Survives all six". `5bd3654` replaced it with today's three ACs. The
   "Correction" section discloses the misread 200s row, which is the honest and important half; it
   does not disclose that ten acceptance criteria were withdrawn. A reader of the merged file
   cannot tell that this ticket ever had an implementation spec.
2. **The implementation is not recoverable.** I checked: the branch has two commits, the reflog
   holds no revert of that work (its only reset predates the first spec commit), there is no stash
   and no dangling object carrying it. It was discarded uncommitted.

That matters precisely under answer 1. If the operator re-scopes for a completion contract, the
held-open configuration reuses most of that work — including the `spawn_prompt` accessor that
decouples the suite's argv-bound prompt assertions, which is a non-obvious fix someone will
otherwise rediscover the hard way. The revert was the right call for *landing*; discarding and
preserving were separate decisions, and only the first was taken.

**Remedy:** one sentence in the Correction section naming `608e57c` as the withdrawn ten-AC
version, so the design for a re-scope is one `git show` away. If the working tree is still
recoverable anywhere, a side branch or a committed patch file is worth more than the sentence.

### W-2 — candidate C's criteria ii–v are collapsed into one row, and scored as failures

D-3 asks for a record per candidate per criterion. Candidates A, B and D carry one row per
criterion; C merges ii–v into a single row reading "Unreachable behind i" and marks it **✗**. Two
problems, both small and both in a document whose whole value is accuracy:

- "Unreachable" is not "fails". Marking it ✗ claims four measurements that were not taken — which
  is the one thing AC-3 says this document does not do.
- The document already has the right convention: candidate B scores its unreachable criterion iii
  as **—**, with "Moot: nothing exits". C should render the same way.

Neither changes C's outcome — criterion i disqualifies it on its own.

### W-3 — none of the probe's evidence is committed

Every number in AC-1 is unreproducible from the repo: the 15.0s / 42.7s / 45.2s settle sequence,
`SLEPT-200` at 210.5s, rc=0 at 138s and 152s, 13 ANSI escapes in the first 1302 bytes. No probe
scripts, no raw transcripts, no timing logs.

This does not make AC-1 unsatisfied — D-3 asks for the per-criterion record, and the tables are
that record. It is a durability point: this dataset has **already produced one wrong conclusion**,
caught only because the author re-read their own notes. With the notes gone, a second such error
is undetectable by anyone, and the document is the sole surviving artifact of a measurement
campaign whose conclusion is "stop".

---

## Suggestion

### S-1 — criterion (iv) for candidate D reads stronger than the earlier draft supported

The table scores candidate D ✓ on the stream split, "renderable to text and tee'd to today's two
sinks". The withdrawn AC-3 at `608e57c` was more precise: the payload **must** be rendered to human
text first, because "a wall of stream-json in the transcript would satisfy the letter of the split
and destroy the thing it exists for". So (iv) holds *given a renderer that does not exist* — a
distinction the merged table drops. The ✓ is still defensible (D's payload reaches a pipe the
scheduler holds; candidate A's genuinely does not), but the caveat is worth restoring.

---

## Strengths

- **The probe is honestly negative, and that is the hard version to write.** It reports a fourth
  candidate the receipt never enumerated, finds that its two configurations disagree, and resists
  the reading that would have let the ticket land.
- **The correction is recorded rather than quietly absorbed.** "An earlier reading of this evidence
  was wrong and is corrected here" names the specific confound — stdin disposition varying across
  arms that were supposed to differ only in transport. Most runs would have shipped the first read.
- **The `result`-at-every-settle finding is the genuinely reusable result here.** It is a property
  of the harness, not of this ticket, and it will bound any future design that tries to detect
  phase completion from the event stream.
- **Every falsifiable claim I re-measured was exact** — including the `--bg` refusal quoted to the
  word. Nothing was rounded in the author's favor.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Fail | 6 | 84–99 |
| Maintainability | Pass | 0 | — |

Fidelity: **not-applicable** — the repo configures no design provider (`design: null`) and the
spec carries no `## Design` section, so the gate's arming condition is not met.

## Verification cross-checks (reviewer-run)

- `check-frozen-files.sh main` — clean, no release-owned files touched.
- `check-changelog-trailer.sh main` — no `plugins/**` change, trailer not required; both commits
  carry `Changelog: none` regardless.
- Both commits carry the bot identity as author and committer.
- Commit verbs are `docs(dev-pipeline):`, which is the honest type for a docs-only branch.
- The mutation sweep's "nothing to sweep" is correct here rather than a wrong-tree artifact: the
  diff adds no guard.
- No orphan intent-gap file and no dangling reference to one — correct, since candidate D was not
  adopted.
