# lean review verdict — #661

verdict=approve
run_id: review-661-1
session_id: a3654ecb-c70e-49ed-9df5-02cb9747debe
rounds: 1
pr: #679
reviewed_head: cf838c916e90b7ba0958d291afb7ff2d3370318e
reviewed_patch_id: 973a70cf291a5416224a493ce7cf325aa4b27707
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review summary

Round 1 covers the whole branch diff (`29890c90..HEAD`, 6 files / +343/-1) — no prior round to
inherit from, so nothing is carried by reference.

This PR's central claim is arithmetic, so it was audited as arithmetic rather than read as prose.
The pinned derivation was **re-run independently** and reproduces exactly: 255 record-versions in
all history, **68** in the `>= 2026-08-16` window, collapsing to **56 distinct blobs**. The 56
blob ids in the per-round table are a **1:1 set match** with the 56 the command yields — no row in
the table is absent from the derivation, and no derived version is missing from the table.

The per-panelist aggregate was then **recomputed from the per-round rows by an independent parser**
rather than checked by eye. Every one of the 48 cells reproduces: dispatches
(scope 47, maint 47, sec 41, tcov 41, comp 38, perf 35, utm 10, pipe 1 = **260**), dark
(tcov 10, maint 1, utm 1 = **12**), degraded (**2**), blockers raised (**15**), blockers upheld
(**5**), findings carried (**38**), and 47 roster-named rounds + 9 excluded = 56. The cost table's
`(dispatches + dark) x cap` convention reproduces every row and both totals (**4,950** / **390**),
and the derived percentages — 24.4%, 2.1%, 7.9%, 77%, and the "other six panelists' 172
dispatches" — are each correct to the stated precision.

Faithfulness to the source records was sampled rather than assumed, on the rows that carry weight:
the two upheld security blockers, the scope blocker raised-and-upheld, the utm blocker refuted on
execution, five of the ten test-coverage dark events, the three-dark round, the degraded scope
return, and one record from each excluded class. Every sampled row matches what the record
actually says, including the subtle ones — the "degraded" definition is drawn verbatim from a
record that called a reviewer "dark in substance" over an interim-block artifact, and the
complexity-reviewer row that P-6 rests on really is a confidence-55 item dismissed below threshold.

The mitigation's kill criteria were **probed, not accepted**. Five mutants in an isolated
worktree at the reviewed head: un-enrolling either new name reds B13 while B1 stays green
(the per-agent `ok:`-line anchor doing exactly what its comment claims); deleting either agent's
deadline reds B1 and B13 together; and two control mutants on the above-cap reviewer — deleting its
deadline, and lowering its cap out of jurisdiction — are killed by B1 and B2 respectively. An
initial control mutant was **vacuous** (the sed literal missed the `**` bold markers) and was
re-run before being scored; a survivor there would have been a harness artifact, not a gap.

CI is green on every arm that can be green pre-verdict: `lint-and-selftests`, `selftests (macos,
bash 3.2)` and `mutation-sweep-pr` all pass. `pr-gates` reds **only** on the absent verdict record
this review writes — confirmed from the job log, not inferred. The sweep is non-vacuous: it applied
13 mutants to the changed guard and killed 12, its single survivor being a pre-existing
`tools/mutation-baseline.tsv` row seeded by the canonical seed run, not something this branch
introduced.

The panel: 7 reviewers selected, **7 returned, none dark** — security, performance,
maintainability, complexity, test-coverage, scope-completeness and unit-test-mutation. All seven
returned `approve` with zero findings; security self-suppressed one item at confidence 30 (the
`DEADLINE_AT_DEFAULT` env seam, a pre-existing and deliberately documented override) which is
correctly below threshold. `a11y` + design-fidelity not routed: no changed path matched
`stageParams.webComponentGlobs` (unset; resolved default `apps/web/**/*.{tsx,jsx}`). db and
pipeline reviewers not triggered — no DB layer and no queue worker in this diff.

**Verdict: approve** — no blockers, one warning.

## Strengths

- **The dedup-on-blob decision is load-bearing and it is stated as such**, with the collapse
  (68 → 56) published rather than buried. Counting commits instead of contents would have inflated
  every denominator, and the document says so in the place a reader checking the number will look.
- **The excluded rounds are enumerated by class with their attributed yield still reported.** Six
  `count-only`, two `no-panel`, one `no-record` — and the four findings those rounds do attribute
  are carried into the prose instead of vanishing with the rows. A denominator that silently drops
  what it could not read is the failure this explicitly refuses.
- **The B13 anchor is chosen for its kill criteria, not for convenience.** Anchoring on the
  per-agent `ok:` line rather than the bare name that the two neighboring cases grep for is what
  gives it two independent kill directions; the comment predicts exactly this, and the probe
  confirms the bare-name form would have survived the un-enrollment mutant.
- **The new deadline text is stronger than the idiom it copies.** Both additions carry a clause the
  existing enrolled agents lack — a review cut short by the deadline must not return `approve` with
  zero findings — which closes the failure mode where a truncated read is recorded as a clean pass.
  That is the more dangerous half of the dark-reviewer class, and nothing obliged this PR to fix it.
- **The decisions decline to over-reach.** Four panelists the corpus never dispatched are recorded
  as `not decided` rather than scored, every `demote` leaves the agent registered and spawnable, and
  the two `demote` rows resting on an empty findings column say plainly that the emptiness is a
  fact about this repo's diff shape and not about the reviewer.

## Warnings

### W1 — the enrollment comment states a dark-column fact its own cited document contradicts

`plugins/review-toolkit/scripts/check-emit-deadline.sh:104-110`, and the same omission at
`docs/review-panel-yield.md`'s "Mitigation that lands with the measurement".

The comment reads:

> `test-coverage-reviewer` and `maintainability-reviewer` are the **two** PANEL reviewers that
> clear that bar [...] **No other panelist has a non-zero dark column there**, and none of them is
> enrolled here — the dark column IS the enrollment predicate, and a zero in it is a refusal.

The document it cites records a **third** panelist with a non-zero dark column:
`unit-test-mutation-reviewer`, dark 1 of 10, from the `#642` round whose record spells it out
(`| Unit Test Mutation | Dark (no output) | — |`). The aggregate table two sections above the
mitigation carries that 1, and the prose that reads "10 of 12 dark events" depends on it — 10 for
test-coverage plus 1 for maintainability is 11, and the twelfth is precisely the panelist the
comment says does not exist.

**The enrollment set is nonetheless correct, which is why this is a warning and not a blocker.**
`unit-test-mutation-reviewer` sits at `maxTurns: 30`, above `DEFAULT_CAP=15`, so it is already in
this lint's jurisdiction by the cap rule and needs no `DEADLINE_AT_DEFAULT` entry; it carries a
conforming turn-20 deadline today (`ok: unit-test-mutation-reviewer.md — cap 30, writes by turn
20`), and I probed both of its kill criteria — deleting the deadline reds B1, lowering the cap out
of jurisdiction reds B2. Nothing shipped depends on the false clause.

What the clause costs is a reader. Someone auditing the enrollment against the stated predicate
("the dark column IS the enrollment predicate") finds a 1 with no enrollment beside it and has to
re-derive the cap rule to discover there is no contradiction. In a change whose whole argument is
*measured, not anecdote*, the one sentence that misstates the measurement is the sentence worth
correcting. The document's own mitigation paragraph has the milder form of the same gap: "no
panelist with a zero in that column is enrolled" is true, and silently passes over the panelist
with a non-zero that is also not enrolled.

Both sites are fixed by naming the cap rule once, e.g. *"the only other panelist with a non-zero
dark column, `unit-test-mutation-reviewer`, is already in jurisdiction at cap 30 and needs no
entry here."* No round needs to be spent on it — it is a one-clause docs edit that can ride the
next commit to touch either file.

## Acceptance criteria

Scored against the committed lean spec (`docs/plans/second-shift-661-lean.md`), which is the
definition of done. The spec's ACs are strictly tighter than the issue's, not looser.

| AC | Score | Basis |
| --- | --- | --- |
| **AC-1** (oracle) — committed measurement, six columns per panelist, runnable derivation, unattributable rounds enumerated by class and count | **satisfied** | `docs/review-panel-yield.md` carries all six columns. Derivation re-run: 68 versions → 56 blobs, and the 56 table rows are a set match with the 56 derived blobs. Aggregate recomputed independently from the per-round rows — all 48 cells reproduce. Nine unattributable rounds enumerated as 6 `count-only` / 2 `no-panel` / 1 `no-record`, with their 4 attributed findings still reported. |
| **AC-2** (critic) — every decision cites its own row; nothing rests on an out-of-corpus round; out-of-window evidence labeled as corroboration; no dispatch-routing edit | **satisfied** | All eight decision rows cite figures I re-verified against the aggregate (47/3/19, 10/6, 41/2/3, 41/0/6/10, 47/0/4/1, 38/0/0, 35/0/0/0, and 1/0/0/0). The two out-of-window maintainability deaths are dated 2026-08-05, sit outside the `>= 2026-08-16` window, are labeled corroboration, and are excluded from every rate — verified in both records. The diff touches no dispatch surface: no `review-lead/SKILL.md`, no `code-review.mjs`. |
| **AC-3** (oracle) — every dark panelist in jurisdiction with a conforming deadline, pinned by a case that reds if enrollment **or** deadline is removed; full sweep green | **satisfied** | All three panelists the measurement records dark are in jurisdiction and conforming: test-coverage (turn 10 / cap 15) and maintainability (turn 10 / cap 15) via the new enrollment, unit-test-mutation (turn 20 / cap 30) via the pre-existing above-cap rule. Both kill directions probed for each of the three — five mutants, five kills. Sweep green in both CI selftest jobs; `mutation-sweep-pr` graded the changed guard non-vacuously (13 applied, 12 killed, 1 pre-existing baselined survivor). |
| **AC-4** (critic) — a `Changelog:` trailer on the branch | **satisfied** | Present on all four commits; `check-changelog-trailer.sh` and `check-frozen-files.sh` both clean. `Guard-mass: +32` matches the measured delta exactly (base 51761, HEAD 51793). |

Design fidelity: `not-applicable` — the spec arms no `## Design` section and the repo declares no
`design.provider`.

## Note, outside the AC set and outside the pinned corpus

This round is itself a datapoint for the thesis under review, and it is recorded here as an
observation rather than as evidence: seven reviewers, none dark, **zero findings between them**,
on a diff that does contain a correctable factual error in a shipped guard comment. The one
warning above was hand-derived by re-running the measurement rather than by pattern-matching the
diff — the same shape the ticket was filed over. It is deliberately **not** folded into
`docs/review-panel-yield.md`: the corpus is pinned, and a round cannot be added to the window it
is measuring.
