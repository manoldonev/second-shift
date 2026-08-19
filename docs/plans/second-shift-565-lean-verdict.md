# lean review verdict — #565

verdict=approve
run_id: review-565-1
session_id: 6768b6f9-2e14-418f-8141-de44a93bdca7
rounds: 1
pr: #603
reviewed_head: 1e802984e9ea91c4e8b6791726b6c80ef7d1b649
reviewed_patch_id: ea3675e7844a6f6a86e3fdc2414b691a4fb32352
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #603 (issue #565)

**Verdict: approve.** No blockers. Range read: `06e48be..1e80298` (root round, whole branch
diff — the gate printed FULL, nothing verifiable to inherit). Panel: 7 reviewers selected, 7
returned; none dark. Scope-completeness gate: PASS.

The change does what it claims and the two things the PR body asked to be read carefully both
hold up under independent checking. `corpus` and `open-prs` are structurally untouched — the
only shared surface the diff enters is the `SUB` case, the `--help` window, and the header
comment, so AC-16's byte-stability is a property of the diff's shape, not just of a passing
fixture. AC-2c is the strongest part of the change: it pins a case the ticket left undefined,
it narrows the implementation rather than excusing it, and the `914` fixture reproduces
`109-lean-progress.md`'s stamps to the second — I ran the tool against the real record and got
the same vector the fixture asserts (`1=81,2=-58,3=14,4=42`, wall `81`), including the floor
(`-58`, not the `-57` a truncating `/` would give).

## Findings

| # | Sev | Site | Finding |
| --- | --- | --- | --- |
| W1 | Warning | `plugins/dev-pipeline/skills/perf-retro/SKILL.md` (Step 2 table, `no-chronology` row) | The row says the flag excludes a run from "**everything**". AC-19 requires Step 2 to state that `no-chronology` "exclude[s] a run from wall-clock aggregates while its spans remain usable". The doc's statement is the *correct* one — a `no-chronology` record has no parseable timestamped row, so `milestone_ts` matches nothing and `spans` is `{}` by construction — but it is an undeclared divergence from the committed spec. This build amended the spec three times (AC-2c, AC-7d, AC-18b) for exactly this reason; the fourth case was left unrecorded. Fix by adding an AC-19b noting the clause is vacuous, not by weakening the doc. |
| W2 | Warning | `plugins/dev-pipeline/skills/perf-retro/SKILL.md` (Step 3, "Review rounds" bullet); `retro-corpus.sh` `rounds` | `rounds` is null on every current-grammar record in the live corpus. 11 of 63 records carry a `round=` token and **all 11 are old-grammar** — the token only ever appeared on the pre-`started`/`concluded` `milestone-4 \| verdict=approve \| round=N` row. `timing --window 8` returns `-` for `rounds` on all eight recent runs. AC-10/AC-11 are satisfied (the derivation is right and the null is documented), but Step 3's "a round count above one is the first thing to check" is unreachable on any run the lane writes today — the same shape of defect this PR exists to remove from Step 2 (`pauseSpans[]`, `pipelineSessions[]`). Either say so at the bullet, or route it to OR-2's follow-up alongside record truncation. |
| W3 | Warning | `plugins/dev-pipeline/tools/retro-corpus.sh:340-360`; SKILL.md Step 3 "Re-verification churn" | `reverifyMin` can exceed `wallClockMin`, and does on the live corpus: `575` reports reverify `82` against wall `40`; `141` reports `169` against `79`. A `milestone-4 \| concluded` row that follows `milestone-4 \| satisfied` lands entirely **after** the run's defined end (AC-4), so it measures the same close-out bookkeeping AC-7d excludes milestone 5 for. AC-7 is met literally, and Step 3 correctly says the value is never summed with spans — but a reader seeing `reverify 82 / wall 40` will read it as an arithmetic error. One sentence in the Step 3 bullet stating it can exceed the wall-clock, and why, closes it. |
| S1 | Suggestion | `plugins/dev-pipeline/tools/retro-corpus.sh:346` | Comment cites `(AC-7d/AC-8b)`. `AC-7d` exists in the committed spec; `AC-8b` does not. |
| S2 | Suggestion | `docs/plans/acme-303.md:109` | The annotation opens "The row above stays as written", but the row directly above it is D-49; D-36 is at `:94`, fifteen rows up. AC-21 is satisfied — the row is annotated and not rewritten, and the bold lead names D-36 — but the deictic points at the wrong row. |
| S3 | Suggestion | `plugins/dev-pipeline/tools/retro-corpus-selftest.sh:772` | The AC-1 window case asserts `KEYS = "914,912"` but its `fail` message reads `expected 912,911`. Only surfaces on a red, which is when it is least helpful to be wrong. |
| S4 | Suggestion | `plugins/dev-pipeline/skills/perf-retro/SKILL.md:24` | Still resolves the corpus "the way the state helper resolves it". No state helper exists in the tree — same dead-reference class this PR removes from Step 2. AC-18b declares one Step 1 edit, so this is out of the change's stated scope; noting it so it is not lost. |
| S5 | Suggestion | `plugins/dev-pipeline/skills/perf-retro/SKILL.md:131` | The report template heading still reads `## Profile (trusted runs only)` while the text under it now says runs with a null wall-clock still appear with their spans and flags. |
| S6 | Suggestion | `plugins/dev-pipeline/tools/retro-corpus.sh:318,~350` | The `\|\| continue` arms on `iso_to_epoch` are unexercised — every fixture stamp matches `TS_RE` and converts. Defensive rather than live, since `milestone_ts` gates the input, but a mutant dropping either arm survives. (Raised by the mutation reviewer; I agree it is not blocker-class.) |

## Merge state — read this before acting on the approval

The branch is `CONFLICTING` against `origin/main`, which has moved to `602b0f0` (`#598`, `#596`)
since the branch point. The conflict is `scripts/lockstep-manifest.tsv`: both sides appended
rows to the end of the file. It is a mechanical resolution with no code content.

The consequence is procedural, not technical. This record is patch-bound to `1e80298`, and the
rebase that resolves the conflict will change lines and void it. The next round is therefore a
**re-stamp of an already-approved diff**, not a re-review — unless the resolution touches more
than the manifest append, in which case the delta is genuinely new and should be read as such.

## AC scoring — 27 of 27 satisfied

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Structural `verdict_record:` selection (never a filename literal); `--window`/`--json`/`--state-dir` share `corpus`'s parser verbatim; missing state dir exits 2; newest-first sort precedes the slice. Verified live and by suite cases. |
| AC-2 | satisfied | `for n in 1 2 3 4`; `base_e` walks the most recent lower satisfied, falling back to the first timestamped row; unsatisfied milestone `continue`s and is absent, not zero; each span floored independently. |
| AC-2c | satisfied | **Verified against the real record.** `109-lean-progress.md` → `2=-58`, emitted, floored toward negative infinity, unclamped. The `914` fixture reproduces the stamps and pins the floor/truncate distinction explicitly. |
| AC-2b | satisfied | The span loop's bound is the literal `1 2 3 4`; no milestone-5 path exists to disable. |
| AC-3 | satisfied | `milestone_ts \| head -n1`; no "latest"/"last" selection anywhere. Suite case drives a duplicated `satisfied` row. |
| AC-4 | satisfied | `wall = floor_min(sat4_e - sa_e)`, gated on both being present. |
| AC-5 | satisfied | Null wall and null reverify; spans still emitted; `unterminated` when a `milestone-4` row exists (matched anywhere on the line, so an un-timestamped one still counts as "got there"), `truncated-record` when none does. Both suite-covered. |
| AC-6 | satisfied | No merge-time, approval-time, git-metadata, mtime or last-row path exists in `cmd_timing`. Suite case asserts null despite later rows and despite `concluded` rows. |
| AC-7 | satisfied | Per milestone, `satisfied` → the last following `concluded`; contributes nothing where none follows; documented and rendered as a diagnostic outside every sum. See W3 for the consequence. |
| AC-7b | satisfied | `rev` is set only when a timestamped `concluded` row exists, so every `old-grammar` record reads null; stated in the SKILL.md flag table and in the code comment. |
| AC-7c | satisfied | No field or line claims the equality; Step 3 states the opposite explicitly and gives the reason (independent flooring). |
| AC-7d | satisfied | Both the reverify loop and the `re-run` scan are bounded `1 2 3 4`. |
| AC-8 | satisfied | `re-run` set on any `started`/`concluded` strictly greater than `satisfied`; the flag is written after the span loop has already closed, so no span can move as a result. |
| AC-9 | satisfied | `old-grammar` keyed on the absence of any `started`/`concluded` row; suite case yields wall 65 and spans with reverify null. No gate-call-latency field exists for any run. |
| AC-10 | satisfied | `grep -oE 'round=[0-9]+' \| sort -n \| tail -n1`, matched anywhere on the line; null when absent. Suite covers the un-timestamped row and the no-token case. (W2 is a property of the corpus, not of the derivation.) |
| AC-11 | satisfied | No `attempt`/`started`/`verdict=` counting path exists. |
| AC-12 | satisfied | Globs `<state-dir>/{issue}-lean-spawn-*.log` in the same resolved dir. Suite covers present and absent. |
| AC-13 | satisfied | The string `manual` is never assigned; `orch` initialises to `indeterminate` and only ever moves to `orchestrated`. Suite asserts it. |
| AC-14 | satisfied | `-gt 86400` on `sat4_e - sa_e`, not on the record's extent. Suite distinguishes a 27-hour run from a 41-minute run carrying a next-day milestone-5. |
| AC-15 | satisfied | Grepped the whole `cmd_timing` range for vendor tokens (`claude\|sonnet\|opus\|haiku\|gpt\|anthropic`) — none. `model` rides through unmapped; `unknown-model` flagged; not used to bucket or filter. |
| AC-16 | satisfied | **Structural, not just fixture-based.** The diff's five hunks are the header, the `SUB` guard, the `--help` window, the new `cmd_timing`, and the dispatch arm — `cmd_corpus` and `cmd_open_prs` bodies have zero changed lines, so byte-stability cannot be broken by this diff. Suite case additionally pins the 4-column TSV and the exact JSON key set. |
| AC-17 | satisfied | `--help` prints `Usage:`, includes `retro-corpus.sh timing`, and stops inside the header (the leak check confirms `set -uo pipefail` never appears). |
| AC-17b | satisfied, with a correction to the AC | Window `2,40p`→`2,56p` (+16, exactly the header's growth), `HELP_LINES` bound moved to `≤ 55` (the window prints 55 lines), and the `! grep -qF 'set -uo pipefail'` leak check is intact and unweakened. **The AC's parenthetical is wrong about the tree:** line 57 is a header comment, not `set -uo pipefail` — and line 41 was likewise a comment before the change. The invariant that actually holds, and that the assertion actually guards, is "the printed window stops inside the header", which is what the selftest's own comment says. No regression; the AC misdescribes, the code does not. |
| AC-18 | satisfied | Grepped the whole file: Step 2 names none of `pauseSpans[]`, `pipelineSessions[]`, or `.mode`. |
| AC-18b | satisfied | Step 1 now names `session_id:` plus the `| session |` rows; the sole surviving `pipelineSessions[]` mention is the parenthetical explaining why it is gone, which is in Step 1 and is historical. Era enumeration untouched. |
| AC-19 | satisfied in substance | The per-flag exclusion table is present; `over-24h` reads exactly as the AC requires; `re-run` is explicitly "**neither**" with the idempotence rationale; Step 3 sources per-run time from `retro-corpus.sh timing`; the hard rule no longer credits "the state helper". One clause diverges — see W1. |
| AC-20 | satisfied | Step 3 states an artifact-only corpus is a normal input producing a populated table, and names both "not applicable" and an empty table as wrong answers. |
| AC-21 | satisfied | Five sites, all annotated: `cost-tracking-setup.md` ×2, the two D-36 comments in `pipeline-cost-block.sh`, and `acme-303.md` — the last annotated adjacent to the ledger and explicitly **not rewritten**. D-25 records the four-vs-five discrepancy honestly. See S2 for the deictic. |
| AC-22 | satisfied | **Verified mechanically.** Filtering the `pipeline-cost-block.sh` diff to non-comment changed lines returns nothing. The header stays line-count-neutral: `set -uo pipefail` is line 66 on both sides, so the `sed -n '2,64p'` window is untouched. `cost-block-selftest.sh` is absent from the diff and runs 28 passed / 0 failed at this head. |
| AC-23 | satisfied | The changed-file list names nothing under `skills/build-lean/`, `skills/review-lean/`, `skills/run-lean/`, or `lean-gate.sh`. |
| AC-24 | satisfied | **Ran both lanes.** 41 passed / 0 failed under bash 5, and 41 passed / 0 failed under stock `/bin/bash 3.2.57(1)-release`. The suite additionally asserts the tool carries no `declare -A`, no case-modification expansion and no `mapfile`/`readarray`. |
| AC-25 | satisfied | The `-u` is present on the BSD arm and the copy is verbatim; `scripts/lockstep-manifest.tsv` carries the `iso-to-epoch` row and `check-lockstep-pairs.sh` reports 23 pairs, 0 failed, naming this pair. |
| AC-26 | satisfied | 41 cases. Fixtures cover both grammar generations, truncated, unterminated, re-run, over-24h, no-chronology, spawn-log present and absent, and an un-timestamped `round=N` row — plus `914`, the out-of-order record AC-2c added. |
| AC-27 (doc) | satisfied | `docs/testing.md` is absent from the diff, and correctly so: cases added to an existing per-tool suite and one row in an existing lockstep manifest, both tiers already described there. No new cache row is claimed. |

## Verification run at this head

- `retro-corpus-selftest.sh`: 41 passed, 0 failed — bash 5 **and** stock `/bin/bash` 3.2.57.
- `cost-block-selftest.sh`: 28 passed, 0 failed (unmodified, per AC-22).
- `check-lockstep-pairs.sh`: 23 pairs, 0 failed.
- `shellcheck -e SC1091,SC2015,SC2181` on `retro-corpus.sh`, `retro-corpus-selftest.sh`,
  `pipeline-cost-block.sh`: clean.
- `retro-corpus.sh timing` against the live 63-record corpus: 8-row window renders, and `109`'s
  negative span reproduces the fixture exactly.
- `tools/mutation-catalog.tsv` carries no row anchored on `retro-corpus.sh`, so the guard edits
  in this diff incur no re-anchor obligation.
- `Changelog:` trailer present on the branch.

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope completeness | Pass | 2 minor/nit (both adopted above as W1, S1) |
| Security | Pass | 0 (2 suppressed, <80) |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Maintainability | Pass | 0 (1 suppressed, <80) |
| Test coverage | Pass | 0 |
| Unit-test mutation | Pass | 2 minor (S6 adopted; the AC-16 "no mutant in this diff" observation is correct but the case is a deliberate byte-stability guard, so it stays) |

`a11y-reviewer` and the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`). Not a coverage gap —
this is a shell/markdown diff. No reviewer went dark.
