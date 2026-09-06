# lean review verdict — #748

verdict=approve
run_id: review-748-1
session_id: 03074cd0-e265-4e02-9017-5bdec7ada4b9
rounds: 1
pr: #797
reviewed_head: 7ac5d8c56535ecef0a6701438722328494ab1e08
reviewed_patch_id: 84798bc2b308f847f0dbae890172880feb5f9f92
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 1 — PR #797 / #748 (arm 2b: attributing `review-lean`'s delta to units)

Range read: `bcedb2a1..7ac5d8c5` (root round — full branch diff; `G delta` printed FULL range).
23 files, +2318/-9, entirely under `docs/`. No executable surface.

Panel: `review-toolkit:scope-completeness-reviewer` (approve, 0 findings, 1 suppressed @ 65).
Performance / complexity / maintainability / test-coverage / security reviewed by the lead pass —
the security conditional did not fire (no auth, tenancy, session, upload or query-construction
surface in a docs-only diff; no `review-context/security-reviewer.md` in the repo), so the lead
pass owns that dimension. a11y + design-fidelity not routed: no changed path matched the repo's
web-component surface, and the spec carries no `## Design` section.

## Verdict

**approve** — no blockers. Two warnings and two nits below; none falsifies an AC.

## What I verified independently

- **The pin is real.** `8d5d0897c3b57ea0d5349787edfd86c3e4ee46ff` exists and
  `plugins/dev-pipeline/skills/review-lean/SKILL.md` is exactly **127 lines** there. `188` at
  `8200f1c3` is also exact; head is 191, so "it has grown since" holds.
- **All 17 unit ranges match §C, and each transcript declares the range it removed.** U-P 6–22
  (§C's frontmatter exception), U-1 26–28, U-2 29–30, U-3 31–37, U-4 38–47, U-5 48–55, U-5b 56–66,
  U-5c 67–76, U-6 77–85, U-7 86–89, U-8 90–96, R-1 100–107, R-2 108–109, R-3 110–114, R-4 115–116,
  R-5 117–121, R-6 122–127. Cross-checked the §C table, `ablation-units.tsv` and each file's own
  `# C2-a — ablation arm …: lines N–M removed` header against the pinned file: U-5 48–55 is the
  Review step, R-4 115–116 is "Approve on the diff", the `## Rules` heading is 98 so U-8 ends at
  96. Three sources agree on all 17.
- **Run counts reconcile to 28.** `## r<n>` headings: control 3, U-5 3, R-3 3, R-4 5, the other
  fourteen 1 each. 3 + 3 + 3 + 5 + 14 = 28, matching §C's 26-before-escalation plus R-4's
  registered n=5 escalation on a 2-of-3 split.
- **The void condition really cleared 3 of 3.** Control r1, r2 and r3 each name
  `check-gate-buckets.sh:109`, the `(^|[;&|(){}])` class, the omitted reserved words,
  `lean-gate.sh:420`'s `else envfail`, and the denominator consequence. r1 carries the 59/57 count
  §2 quotes.
- **All 14 `not-reached` arms kept the finding.** Read four in full (U-P, U-3, U-8, R-6) and
  mechanism-matched the other ten; R-6's hit is its blocker 2, not its blocker 1, and is still a
  hit. The reach prediction's falsification probe is genuinely unbroken.
- **R-4 r1's miss is quoted verbatim and correctly adjudicated.** §2's block quote is byte-for-byte
  the transcript's blocker-1 headline, and under the frozen hit rule (same file, same consequence,
  different mechanism) it is a miss.
- **AC-7's five stale line-count claims are all discharged.** At the base they were `:31`, `:487`,
  `:491`, `:586`, `:613`; all five are now pinned by commit or rewritten, and `:203`/`:211`
  ("127 committed lean specs" — a corpus size) are correctly left alone. No surviving `127` in
  `docs/skill-ablation.md` names an unpinned file length.
- **AC-8 holds absolutely** — `git diff --stat bcedb2a1..HEAD -- plugins/` is empty. So is the diff
  against `docs/skill-ablation-pre-registration.md` and `c2-review/scoring.tsv`, both of which the
  spec's Out-of-scope block freezes. The addendum edit is the single D-2 write.
- **Frozen files and trailers.** No plugin `version`, no `CHANGELOG.md`, no marketplace
  `metadata.version`. All four commits carry `Changelog: none`.

## Warnings (should fix)

**W1 — [Maintainability] The `no-effect` score's second conjunct is never determined per unit, and
the disclosure's conclusion is asserted rather than shown.**
`docs/skill-ablation.md`, "What bounds this arm". §C defines `no-effect` as a conjunction: the
blocker is reproduced at the arm's majority **and** "the arm's blocker set is otherwise
indistinguishable from the control's". The diff records clause 1 for all three in-reach units and
then discloses that clause 2 is confounded by control-to-control variance — and concludes
"Cut-eligibility still resolves, because only `no-effect` is eligible; the gap is in the
vocabulary, not the outcome." That conclusion is exactly what needed showing, because if the three
units cannot be scored `no-effect` the cut list is empty, not three units long — the departure
resolves in the direction of a larger deliverable.

I checked it and it holds, but only under one of the two available readings. Arm blocker sets:

| arm | r1 | r2 | r3 | r4 | r5 |
| --- | --- | --- | --- | --- | --- |
| control | {enumerator} | {enumerator} | {`tsv:220` attendance, enumerator, g18b/g18d vacuous} | — | — |
| U-5 | {enumerator, `gate-buckets.tsv:58`} | {enumerator} | {enumerator} | — | — |
| R-3 | {`:93-97` helper-less, enumerator, `exit 256` wrap} | {enumerator, g18b/g18d} | {enumerator, g18d, g18b} | — | — |
| R-4 | {3-of-5-files denominator (MISS), selftest `:294`/`:302`} | {enumerator} | {enumerator, `:93-97`} | {enumerator} | {enumerator, g18b/g18d} |

Under a **majority** reading of "the arm's blocker set" every in-reach arm reduces to `{enumerator}`
— matching the control's majority — so clause 2 holds and `no-effect` is right. Under a **union**
reading it fails for U-5 (r1 gained `gate-buckets.tsv:58`, which no control run raised) and for R-3
(r1 gained `:93-97` and the `exit 256` wrap, likewise). §C fixes "majority" for clause 1 and is
silent for clause 2. The rest of the rubric is majority-based, so the majority reading is the right
one — but that argument, and the table above, are the work the artifact should carry. As committed,
the three-unit cut list rests on a co-equal conjunct that the same document says it could not
evaluate.

Fix is additive and needs no re-run: record the per-arm set comparison and state which reading of
clause 2 the score was taken under.

**W2 — [Complexity / methodology] The cut list is three units; leave-one-out licenses one deletion,
not three.**
`docs/skill-ablation.md`, "The cut list (AC-6)". Every arm removed exactly one unit, so the evidence
establishes that each of U-5, R-3 and R-4 is individually inert. It does not establish that they are
jointly inert: if the instruction content is redundantly encoded across them — plausible here, since
U-5's "`approve` iff there are no blockers … do not soften" and R-4's "an unmet `AC-n` is a blocker"
overlap in substance — removing all three could lose the finding while removing any one does not.
A successor reading this list will delete the three together, which is precisely the inference the
runs do not support.

No AC mandates the caveat, and the deletion is a further successor that gets its own review, so this
is not a blocker. But it belongs in "What bounds this arm" beside the three limitations already
there, which are held to exactly this standard. One sentence.

## Nits

**N1** — `docs/skill-ablation-addendum.md`:531. The D-2 rewrite keeps "at **this branch's base**
`8200f1c3`". `8200f1c3` was the addendum's own authoring base; this branch's base is `bcedb2a1`
(191 lines). The count is pinned by SHA and is exact, so AC-7's "no reader is left with a line count
that matches no version of the file" is satisfied either way — but the phrase now points a reader at
the wrong ref. Dropping the two words fixes it.

**N2** — `docs/plans/second-shift-748-lean.md`, D-6. Its coordinates do not resolve: it names
`:31`, `:334`, `:338`, `:430`, `:457` for the line-count claims and `:202`/`:210` for the corpus
mentions, where the base file carries them at `:31`, `:487`, `:491`, `:586`, `:613` and
`:203`/`:211`. The *treatment* D-6 decides is right and was applied completely (verified above); only
the ledger's line numbers are wrong. Recorded because the ledger is the artifact a later slice reads
back — the decision survives, the anchors do not.

## Recorded, not a blocker

`pr-gates` is red on `lean-evidence`: *"no committed verdict record (a file named
`*-748-lean-verdict.md`)"*. That is this round's own output — the chain cannot be green before this
record lands. `mutation-sweep-pr` passed; `lint-and-selftests` and `selftests (macos, bash 3.2)`
were still pending at review time and carry no code surface on a docs-only diff.

## Strengths

- **The falsification probe is the study's best move and it was actually run.** Ablating all
  fourteen `not-reached` units at n=1 costs almost nothing and is the only thing standing between a
  reach *prediction* and a reach *exemption*. All fourteen kept the finding, so the table that
  prevents a fourteen-of-seventeen false cut is now evidence rather than an assumption wearing a
  label.
- **The refusals are where the value is.** Three separate places where the easy move was available
  and declined: the fourteen units are recorded `not-reached — no basis` rather than `no-effect`;
  the `/code-review` comparator column is recorded as degenerate rather than read as licence to cut
  all seventeen; and the cut list is emitted without the deletion.
- **The integrity check is real, and stronger than it looks.** Counting tool inputs naming
  `review-lean` per run — `0` across all 28 — rules out a session reading the unablated SKILL off the
  clone's working tree, and it holds *despite* the `--allowedTools` breach that let every arm run
  `Bash`. Filing that breach (#796) instead of quietly correcting the recipe is the right call.
- **The killed control batch is disclosed with hashes, not summarised.** Bytes and sha256 per
  capture, with an explicit statement that the captures live in machine-local scratch and no reader
  of this repo can resolve the path — a reading that stays repudiable on a machine that still holds
  the files.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | 17 units, one per run, at the §C line ranges over the pinned file. `8d5d0897` verified to exist and to carry a 127-line `review-lean/SKILL.md`; all 17 ranges cross-checked across §C's table, `ablation-units.tsv` and each transcript's own header — three sources, no disagreement. `##`-heading ablation excluded at registration. |
| AC-2 | satisfied | Every arm's realised invocation pins the throwaway clone at `cfba102` and the prompt's diff at `dfd68a47..cfba1022`; both objects resolve in this repo. #654's ground-truth blocker (command-position class omitting keyword-preceded calls, `lean-gate.sh:420` outside the denominator) is the fixed subject the control reproduces 3/3. |
| AC-3 | satisfied | `ablation-units.tsv` gives every one of the 17 units exactly one score — 3 × `no-effect`, 14 × `not-reached--no-basis`, both registered forms — with `runs_valid`/`runs_indet`/`hits` and a committed per-arm transcript behind each. No unit is scored from reading: all 17 were ablated and run. See W1 on the second conjunct of `no-effect`. |
| AC-4 | satisfied | `ablation-units.tsv` carries `vs_bare` and `vs_codereview` columns for all 17 rows, and §2's cut list records both: bare binds (D-1), and the `/code-review` column is recorded as degenerate — arm 2a hit C2-a, so reading it as licence would cut all seventeen on one sample. |
| AC-5 | satisfied | 18 files committed flat under `docs/plans/skill-ablation/c2-review/` — control plus one per unit — each with the realised invocation, a per-run apparatus table, and every replicate verbatim under `## r<n>`. README.md gains a paragraph describing the `ablated-*` family and one describing `ablation-units.tsv`. Raw stream-json captures are not committed, matching the existing bare/challenger convention for this family. |
| AC-6 | satisfied | §2's "The cut list (AC-6)" table gives the disposition of all 17: three cut-eligible, fourteen "no basis", with the basis stated per row. The mandated unmeasured-region statement is present and, per D-7, carries no count — "every line added to `review-lean/SKILL.md` since `8d5d0897` is unmeasured". See W2 on joint deletion. |
| AC-7 | satisfied | All five stale length claims discharged: `:31` and the §4 row now read `127 … at 8d5d0897`, `:487` re-labelled, `:491` and `:613` rewritten, and §5's successor list corrected from "Arm 2b (#748) is outstanding" to done. §2, the §4 `dev-pipeline/review-lean` row and §5 all carry the localisation. The two corpus-size `127`s at `:203`/`:211` are correctly untouched. Grepped the file at HEAD: no surviving `127` names an unpinned file length. |
| AC-8 | satisfied | `git diff --stat bcedb2a1..HEAD -- plugins/` is empty — the diff touches no file under `plugins/` at all, so the prohibition is satisfied by the diff not doing it. |
