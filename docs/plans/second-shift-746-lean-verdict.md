# lean review verdict — #746

verdict=approve
run_id: review-746-2
session_id: c3ff15f5-849e-41bf-af5f-4696d8a61c4c
rounds: 2
pr: #762
reviewed_head: 8ac670c8b90ece26d14aa9c0787f7879b1827194
reviewed_patch_id: 6509ea168ecc3dc5d2d05a2561db8f93c3ecdc9f
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

# Review round 2 — PR #762 (issue #746)

Range read: `d8add882..8ac670c8` — the full branch diff. `bash G delta 746` printed FULL range with
"nothing verifiable to inherit": round 1 wrote no verdict record (the writer refused an
`**AC-n** —` spec), so there is nothing to inherit and this round is a root round again. 15 files,
docs-and-evidence only, no executable surface. Spec declares no `## Design` section, so fidelity is
`not-applicable`.

CI at the reviewed head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
`mutation-sweep-pr` pass, `install-topology` skipped (no packaging paths). `pr-gates` fails on
`[lean-evidence] ✗ no committed verdict record` and nothing else — that is the chain gate observing
this round's own absent artifact, not evidence about the code.

## Round 1's four blockers — all discharged, each re-verified independently

**B4 (ACs unreadable by the verdict writer) — fixed.** `docs/plans/second-shift-746-lean.md`:24-45
declares `- AC-1:` … `- AC-7:`. Probed against the reader rather than assumed:

```
printf '## AC scorecard\n\n| AC-n | score | evidence |\n…' \
  | bash plugins/dev-pipeline/skills/build-lean/lean-evidence.sh scorecard \
      --spec docs/plans/second-shift-746-lean.md --verdict approve    # rc=0
```

The wording is genuinely unchanged: I normalised whitespace and diffed all seven against the issue
body's `**AC-n** —` paragraphs — **seven of seven identical**. This is a form change, not a spec
amended to match the diff.

**B1 ("17 committed lean specs") — fixed, and the replacement re-derives.**
`docs/skill-ablation.md`:202-211 now carries 126 at `dfd68a47` and 127 at `b657907f`, with the
oracle inline. Both reproduce exactly. The only surviving `17` in the file is at `:405-406`, a
different quantity in §3.

**B2 (the four-sealed generalisation) — fixed in both carriers.** `docs/skill-ablation.md`:213-229
and `consumer-substrate.md`:161-172 now say **three of four**, name sealed-min 636 as the session
that reached nothing, and count it separately.

**B3 (M6 wordings unquoted) — fixed, all four, and the quotes are faithful.**
`docs/skill-ablation.md`:160-189. I opened each cited line: `consumer-sealed-636-plan.md`:95-96,
`consumer-sealed-min-636-plan.md`:72, `consumer-sealed-647-plan.md`:72,
`consumer-sealed-min-647-plan.md`:28 — all four quoted verbatim, all four citations land on the
right line. The two contrast quotes at `:193-195` (`bare-ablated-636-plan.md`:83,
`bare-636-plan.md`:94) verify too. The two near-misses that name `Closes` are distinguished from the
two clean misses, which is the discrimination the frozen clause exists to preserve.

## What I re-derived from the raw evidence

Every number this arm rests on was recomputed from the session logs, not read off the page. Per
round 1's own lesson, each scored session was matched to its log **by final assistant message**
before any count was taken, because each project directory holds both the first (confined) pass and
the scored one.

- **All eight committed transcripts are byte-identical to their session's last assistant message.**
  Matched: `max-636`→`f54eb633`, `max-647`→`ca543687`, `min-636`→`eaf3f110`, `min-647`→`ec36a240`,
  `sealed-636`→`0d5ad1c8`, `sealed-647`→`ce6134e9`, `sealedmin-636`→`069aadcc`,
  `sealedmin-647`→`bb472095`.
- **The read-count table (`consumer-substrate.md`:144-153) reproduces on all 24 cells.** The
  `git show HEAD:` column counts `git show HEAD:` plus `git grep … HEAD …` per tool call
  (12/23/16/23/0/0/0/0); the cache column is per tool call (0/0/0/0/7/9/0/4); the `docs/plans/`
  column counts `docs/plans` including the bare-directory form (2/0/5/4/2/3/0/0). Every figure
  matches.
- **"Not one of the eight opened `build-lean/SKILL.md` from the cache" is true** — 0 references in
  the full tool-input JSON of all eight scored sessions.
- **"All four registered-arm sessions read it out of the object store" is true** —
  `git show HEAD:plugins/dev-pipeline/skills/build-lean/SKILL.md` appears 4 / 1 / 2 / 1 times in
  max 636 / max 647 / min 636 / min 647, and none of those four touched the cache at all.
- **The per-arm coverage figures reconcile with `scoring.tsv` cell for cell**: 9/9, 9/9, 3/9, 4/9,
  1/9, 0/9 over the nine discriminating items (M5 excluded), which is exactly the arm table's
  `9 / 9`, `9 / 9`, `3 / 4`, `1 / 0`. The AC-6 cut-list table's ✓/✗ grid matches the TSV row by row,
  M3 and M9 are the only splits, and `keep` is correctly not claimed.
- **AC-7**: `git diff --name-only d8add882..HEAD -- plugins/` is empty; `SKILL.md` is 48 lines.

## Findings

No blockers. Three majors and three minors, all in prose the round-1 fix wrote, none of which moves
a score, a disposition, a cut-list row, or a headline finding.

| # | severity | where | finding |
| --- | --- | --- | --- |
| 1 | major | `consumer-substrate.md`:163-165, `docs/skill-ablation.md`:218-219 | **sealed 647 never read `orchestrate-lean.sh`.** Both files say it did. Its only two references to that file are `find … -name 'orchestrate-lean*'` over the cache — a path lookup that returns no content — plus one `grep -rl` inside the repo, not the cache. What it actually read from the cache is `lean-gate.sh` (`grep -n`, `sed -n` ×3, `wc -l`), **`lean-gate-selftest.sh`** (`wc -l`, `grep -n`) and the doctor fixture `settings-green.json` (`cat`). The selftest is not named; the orchestrator is named and was not read. |
| 2 | major | `consumer-substrate.md`:165, `docs/skill-ablation.md`:219 | **"sealed-min 647 to `lean-gate.sh` alone" / "read `lean-gate.sh` only" is false.** That session also read `lean-gate-selftest.sh` — `wc -l lean-gate.sh lean-gate-selftest.sh` then `grep -n "647\|seed_lane_worktree_settings\|settings.local" lean-gate-selftest.sh`. "alone" and "only" are completeness words and both fail. (A weaker instance of the same imprecision sits beside them: sealed 636's three named files were reached by `grep -c ""` — a line count, no content — except `orchestrate-lean.sh`, which it did `sed -n`; and `operator-override.sh` was line-counted identically and is omitted from the list.) |
| 3 | major | `consumer-substrate.md`:168 | **"records `lean-gate.sh` and `orchestrate-lean.sh` as absent and stops" — the cited transcript does not stop.** `consumer-sealed-min-636-plan.md` is 78 lines and continues past the cited `:19` into a full 13-step "Plan of record" plus an "If the corpus stays absent" section. The arm's own M9 credit for that session (`scoring.tsv`, `consumer_sealedmin_636` = `covered:unaided`) is drawn from `:72`, below the point the prose says it stopped. The sibling sentence at `docs/skill-ablation.md`:221-222 states the same fact correctly ("declares the work blocked on materialising the kit") and does not say "stops". The load-bearing half — 0 cache references, so it is not evidence for the finding — is correct and unaffected. |
| 4 | minor | `consumer-substrate.md`:80 | Under a heading reading "Per-run realisation, **verified**", the row `**plugin cache reachable** \| **yes** \| **yes** \| **yes** \| **yes**` is unqualified, while the paragraph at `:93-103` establishes that five of the eight runs verify nothing about it from their own tool calls. The disclosure is right there and points at that row, which is why this is not a blocker — but marking the apparatus-based cells in the row itself (`yes — apparatus`) would stop the table needing a paragraph read alongside it to be accurate. |
| 5 | minor | `docs/skill-ablation.md`:29, `:429` | The Verdicts row and §4's row both report "bare covers **3 and 4 of 9**", which is the *post-hoc* pair only. Neither signals that the *registered* arms scored 9/9 and are reported-but-inconclusive. §1 explains this immediately below, but the summary table's stated job is to be readable alone. One clause — "(sealed arms; the registered pair is inconclusive, §1)" — closes it. |
| 6 | minor | PR #762 body | The PR description still carries round 1's uncorrected generalisation: "though the sealed ones had it in their allowlist **and walked to `lean-gate.sh`**". That is the claim B2 corrected — sealed-min 636 walked nowhere. The branch is right and the description is a release behind it. |

**Verbatim fixes for the three majors**, if a follow-up takes them:

- `consumer-substrate.md`:163-165 / `docs/skill-ablation.md`:218-219 — "sealed 647 to `lean-gate.sh`,
  `lean-gate-selftest.sh` and a doctor fixture; sealed-min 647 to `lean-gate.sh` and
  `lean-gate-selftest.sh`."
- `consumer-substrate.md`:168 — replace "and stops" with "and declares the work blocked on
  materialising the kit", matching the wording already used in `docs/skill-ablation.md`:221-222.

## Why this is `approve` and not a third round

Every AC is met on the diff, and I verified each against the raw evidence rather than the page. The
three majors are a per-session inventory of *which* cached script each session opened. They change
no cell in `scoring.tsv`, no row of the cut list, no arm total, and none of the four load-bearing
claims in the sentence that carries them — "all four had the cache in their allowlist", "**three**
walked into it", "**not one of those** opened `build-lean/SKILL.md`", "sealed 636 listed the
directory it sits in" — every one of which I re-derived and every one of which is true. The true
item list supports the finding exactly as well as the printed one does: `lean-gate-selftest.sh` is
no more prose than `orchestrate-lean.sh` is.

Withholding an approval every AC has earned, in order to force three word-level corrections in an
enumeration, costs a full build-and-review pair against a permanent artifact nobody would act on
differently. Same reading as #666 round 4, which recorded a false clause as a major on a prose-only
ping-pong rather than spending a round on it. The fixes are stated verbatim above so a follow-up can
take them without re-deriving anything.

## Strengths

- **The arm reports the finding that invalidates its own registered construction before it reports
  anything else**, and round 2 did not soften it. The registered pair was the pre-registered
  deliverable; publishing "the construction does not realise the substrate" instead of "9/9, cut
  licensed" is the whole reason this evidence is worth citing.
- **The round-1 fix corrected the prose down to what the tables already said, rather than adjusting
  the tables.** The 126/127 figures replace a transplanted 17 and are pinned to immutable commits, so
  they cannot rot the way the addendum's own base-relative count explicitly warned it would; the
  four-sealed claim was demoted to three-of-four and the fourth is reported as the case that did not
  look. Both are re-derivable from the page.
- **Provenance-per-cell (`covered:tree` / `covered:cache` / `covered:unaided`) is what makes the arm
  legible at all** — without it, "bare covered M1" and "bare read the kit out of the object store"
  would be the same row, and the leak that voids the registered arms would have been invisible.
- **The reachability basis is now split by strength rather than averaged.** Three sessions prove it
  from their own tool calls; five rest on the apparatus, and the weaker basis is labelled the weaker
  thing with D-33 cited as why the distinction is kept.
- The six unretained first-pass sessions are disclosed rather than left for a reader to notice.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `prompt-template.txt`, `ticket-636.md` and `ticket-647.md` carry exactly one commit between them, `8d5d0897` — the commit §1 was scored on — so the prompt inputs are unchanged from the registered run. Both samples re-run in all four arms; eight scored transcripts committed. |
| AC-2 | satisfied | `consumer-substrate.md`:69-109. Absent paths recorded per arm; the sealed arms' object-store closure verified by `diff -rq` against `git archive`; the A1-min fourth removal recorded `not-reached` with the reason. Cache reachability is now split by basis — three sessions from their own tool calls (7 / 9 / 4 cache calls, all three counts re-derived exactly), five from the identical invocation plus the `--add-dir` probe, "recorded as the weaker thing". Finding 4 is a presentation nit on the summary row, not a gap in the record. |
| AC-3 | satisfied | Every consumer cell in `scoring.tsv` is `covered:<provenance>` or `absent` — no third value, no partial credit; M5 scored and marked `non-discriminating` in both the item column and the verdict column. The M6 quoting obligation, the round-1 blocker, is discharged for all four `absent` cells at `docs/skill-ablation.md`:160-189, verbatim and correctly cited, with the two `Closes`-naming near-misses distinguished from the clean misses. I re-checked the scores themselves against the whole-item rule at `skill-ablation-pre-registration.md`:95; no re-score is owed. |
| AC-4 | satisfied | All eight transcripts byte-identical to their scored session's final assistant message (matched by that message first, since each project directory holds both passes). One file per session, family `consumer-<arm>-<n>-plan.md`, distinct from `bare-<n>-plan.md` and `bare-ablated-<n>-plan.md`. `README.md`:10-20 describes the new family and the superseded first pass in the same register as the other two. |
| AC-5 | satisfied | `scoring.tsv` gains eight per-item arm columns plus `consumer_verdict`, alongside — not replacing — the registered and ablated columns. `docs/skill-ablation.md` updated in all three required places: §1 (`:103-248`), Verdicts row 1 (`:29`), §4's `dev-pipeline/build-lean` row (`:429`). Finding 5 is a legibility nit on two of those rows, not a missing update. |
| AC-6 | satisfied | `docs/skill-ablation.md`:130-151 states the disposition per M-item — M1, M2, M4, M6, M7, M8, M10 inside the delta and kept; M3 and M9 split at n=2 and `undetermined`, so not cut-eligible — and concludes the cut is empty. I re-derived every row from `scoring.tsv`; the grid matches cell for cell and the arm totals (9/9, 9/9, 3/4, 1/0) recompute. `cut-to-delta` retained, `keep` correctly not claimed per the frozen threshold table. |
| AC-7 | satisfied | `git diff --name-only d8add882..HEAD -- plugins/` is empty; `plugins/dev-pipeline/skills/build-lean/SKILL.md` is 48 lines at the reviewed head. |
