# Decision record — #1135 The planted corpus promotes the pilot candidates a plain review gets wrong

Receipt: v4

## Summary

Six of the 32 pilot candidates enter the scored corpus: qb3hzm, fx6cim, kx5vdb, mn7cuh, ug5nrb and la2swf. The other 26 are deleted, ba4kxe among them, because its misses are a truth-range artifact. `check` keeps the outside-every-hunk rule on the promoted ids through a named id set. The pilot machinery stays with an empty `PILOT`.

Open regions: OR-1 the promoted id set is named `PROMOTED`. OR-2 the pilot checks inject fixture ids through new `check` parameters.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which candidates are promoted | The six with real misses: qb3hzm, fx6cim, kx5vdb, mn7cuh, ug5nrb, la2swf. ba4kxe is dropped as mis-scored. Fewer than 8 is accepted, and no new candidate is authored. | user-answered | intent |
| D-2 | What a pilot miss is | A run whose `score.right` is 0, in the one judging the pilot has. The PR body says the rescore replayed cached verdicts. | user-answered | intent |
| D-3 | PM-1 when it fails | The operator files a follow-up ticket with the per-case numbers. The promoted cases stay. | user-answered | intent |
| D-4 | The run PM-1 reads | `planted.py run --case <each kept id> --runs 3` on both arms, read with `planted.py cases`. It writes a changelog row like any normal run. | user-answered | intent |
| D-5 | The pilot machinery after promotion | It stays with an empty `PILOT`. `check` prints `pilot 0 P4`. The corpus-selftest pilot checks move to fixture ids. | user-answered | intent |
| D-6 | The outside-every-hunk rule after promotion | `check` applies it to `PILOT` and to a named set of the promoted ids. The older P4 cases stay outside it. | user-answered | intent |
| D-7 | Where the build reads the pilot result | The ticket body carries the per-candidate table, so the build reads no results file. | user-answered | intent |
| D-8 | AC-6 test intent | AC-6 is exempt. The review scores the PR body. | user-answered | intent |
| D-9 | The corpus after promotion | 49 cases, P4 16: rejects-held-input 3, dead-guard 3, two-hop-caller 2, omitted-option 4. Every pattern keeps at least 2 scored cases. The probe ran on a copy with the 26 removed and an empty `PILOT`. run: `python3 -I planted.py check` → `check: ok (P1 16, P2 4, P3 4, P4 16, P5 4, control 5; P4 patterns: rejects-held-input 3, dead-guard 3, two-hop-caller 2, omitted-option 4)` | codebase-derived | fact |
| D-10 | Overlays and NOTICE lines to delete | None. The kept cases come from vite, prettier and vuejs/core, the three candidate upstreams. run: `jq -r .upstream cases/{qb3hzm,fx6cim,kx5vdb,mn7cuh,ug5nrb,la2swf}/case.json \| sort -u` → vite, prettier, vuejs/core | codebase-derived | fact |
| D-11 | The upstream cap after promotion | dayjs holds 16 of 49 cases, about 33%, under 40%. The probe ran on the promoted copy. run: `jq -r .upstream cases/*/case.json \| sort \| uniq -c` → 16 dayjs of 49 | codebase-derived | fact |
| D-12 | Where the hunk rule is gated today | On `cid in PILOT`. run: `grep -n 'if cid in PILOT and locs and not outside' planted.py` → 420 | codebase-derived | fact |
| D-13 | The rule on every non-frozen P4 case | Two older cases fail it. The probe re-keyed line 420 on non-frozen P4 in a copy. run: `python3 -I planted.py check` → e7k3wb and w9d3ra fail the rule | codebase-derived | fact |
| D-14 | The pilot's second judging | A replay of the judge cache. run: `cmp planted-results-20261027T183508Z.json planted-results-20261027T191251Z.json; echo $?` → 0 | codebase-derived | fact |
| D-15 | Why ba4kxe is an artifact | Every plain run blocks on the planted mechanism at `ssrVModel.ts:68`. Its truth ranges are 42-44 and two other files. run: `jq -r '.records[]\|select(.case=="ba4kxe")\|.findings[0].text[0:52]' planted-results-20261027T191251Z.json` → `packages/compiler-ssr/src/transforms/ssrVModel.ts:68` three times | codebase-derived | fact |
| D-16 | corpus-selftest on the promoted corpus | 10 assertions fail: two pins, two pattern-floor fixtures, two cap fixtures, four pilot fixtures. The probe ran on the promoted copy. run: `bash corpus-selftest.sh` → `61 passed, 10 failed` | codebase-derived | fact |
| D-17 | score-selftest and render-selftest | Neither needs an edit. score-selftest injects its own pilot ids. run: `grep -n "pilot_ids=frozenset" score-selftest.sh` → `pilot_ids=frozenset({'plcase'})` | codebase-derived | fact |
| D-18 | The name of the promoted id set | Parked under OR-1 (owner: the build, by its default) | deferred | open |
| D-19 | The fixture for the pilot checks | Parked under OR-2 (owner: the build, by its default) | deferred | open |
| D-20 | `run --pilot` with an empty `PILOT` | It exits non-zero before any model call, saying there are no pilot cases. A score-selftest case covers it. | user-answered | intent |

Options weighed:

- D-1: the six real misses, all seven per the old rule, a one-miss bar, or new authoring. The operator chose the six.
- D-2: one judging with the limit stated, or a second judging that bypasses the cache. The operator chose one judging.
- D-3: a follow-up ticket, a revert, or dropping the cases plain got right. The operator chose the follow-up.
- D-4: the six kept ids on both arms, or the full corpus on both arms. The operator chose the six ids.
- D-5: keep the machinery with an empty `PILOT`, or retire it. The operator chose to keep it.
- D-6: a named set of promoted ids, letting the rule lapse, or every non-frozen P4 with two cases fixed. The operator chose the named set.
- D-7: the table in the ticket body, or results file paths. The operator chose the table.
- D-8: exempt AC-6, or keep it tested. The operator chose exempt.
- D-20: refuse early, or run empty and spend a judge calibration. The operator chose to refuse early.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The name of the promoted id set | reversible-default-and-flag |
| OR-2 | The fixture for the corpus-selftest pilot checks | reversible-default-and-flag |

- OR-1 default: `PROMOTED`, a frozenset beside `FROZEN` and `PILOT`. The intake chose it. Reversing it is a rename.
- OR-2 default: `check_corpus` and `check_case` take `pilot_ids` and promoted-id parameters that default to the constants, as `select_cases` does. Each of the seven pilot checks copies a case under a new fixture id and drives `check` through them. The intake chose it. Reversing it is a test edit.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6 AC-7

AC-1: `planted.py check` on the shipped corpus reports 49 cases with P4 16 and the four pattern counts, and the six ids are not in `PILOT`
AC-2: no case directory of the 26 dropped candidates exists, and `check` passes with every overlay and NOTICE line in place
AC-3: a copy whose promoted case has every truth range inside a hunk fails `check` naming the case
AC-4: `check` prints `pilot 0 P4`, and a copy that adds a fixture id to `PILOT` still runs the pilot rules on it
AC-5: corpus-selftest passes on the promoted corpus with its pins and cap fixtures rebased, and docs/testing.md states the promoted counts
AC-6: exempt — it is PR body text, and the review scores it from the PR
AC-7: `run --pilot` with an empty `PILOT` exits non-zero with a no-pilot-cases message, and no judge or review call is made

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `planted.py check` output | decided (D-9) |
| S-2 | `corpus-selftest.sh` output | decided (D-16) |
| S-3 | docs/testing.md planted-mode counts | decided (D-9) |
| S-4 | The PR body's pilot table | decided (D-7) |
| S-5 | `run --pilot` with an empty `PILOT` | decided (D-20) |
| S-6 | `planted/changelog.md` | out-of-scope — the build runs no model; PM-1 writes the next row. |
| S-7 | The lane and plain review prompts | out-of-scope — the render code does not change. |

## Checks

- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh`
- `python3 plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py check`

## Intake steps

Requirements: the ticket as filed. spec-reviewer found three blockers and six warnings. The interview closed them, and the operator approved a rewritten body. The implementability probe raised one question, which added AC-7.

Split: not triggered. The ticket has no epic label and one deliverable.

Explore: done. Read the check, rescore and cases paths, the selftests, NOTICE and the two pilot results files. Probed the promotion on a scratch copy.

Fan-out: ran — 27 items, see Fan-out

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no AC moved. PM-1 was already a post-merge check.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: miss-rule-rederivation opus 6/6 · promotion-dry-run fable 6/6 · downstream-consumers opus 6/6 · measurement-validity fable 4/6 · premortem fable 5/6
Tally: rows added 4 · snapshot claims overturned 1 · questions added 3

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | miss-rule-rederivation | Recomputed misses match the pilot table exactly (`fanout-1135-probes/misses.py`). | already-had | confirmed D-1 |
| F-2 | miss-rule-rederivation | The two results files are byte-identical; the rescore replayed the judge cache (`bench.py:256-261`). | overturned (both judgings agree on every miss) | became D-14 |
| F-3 | miss-rule-rederivation | `cases` reads one file and does no pairing (`planted.py:941-961`). | new | moot under D-2 |
| F-4 | miss-rule-rederivation | A rescore keeps (arm, case, run), so files pair on that key (`planted.py:1095-1104`). | not material | moot under D-2 |
| F-5 | miss-rule-rederivation | No missed run is an approve; three hinge on note severity (`planted.py:845-855`). | new | informed D-1 |
| F-6 | miss-rule-rederivation | Intake must restate AC-1, bypass the cache, or accept the limit (`bench.py:256`). | new | became D-2 |
| F-7 | promotion-dry-run | The seven-case promotion passes `check` and orphans no overlay (`fanout-1135-probes/promote.py`). | already-had | became D-10 |
| F-8 | promotion-dry-run | The pattern floor is one case; base cases already cover each pattern (`planted.py:474-476`). | new | informed D-1 |
| F-9 | promotion-dry-run | corpus-selftest gives 61 passed, 10 failed on the promoted corpus (`corpus-selftest.sh`). | new | became D-16 |
| F-10 | promotion-dry-run | The hunk rule is gated on `PILOT`, so promotion drops it (`planted.py:420`). | already-had | became D-6 |
| F-11 | promotion-dry-run | Kept ids could leave `PILOT` while the rest stay pilot (`planted.py:455-456`). | not material | D-1 deletes the rest |
| F-12 | promotion-dry-run | docs/testing.md counts and an empty `--pilot` run are unaddressed (`docs/testing.md:749,760,776`). | already-had | became D-5 |
| F-13 | downstream-consumers | Promotion fails 10 of corpus-selftest's 73 assertions (`corpus-selftest.sh:32-193`). | new | became D-16 |
| F-14 | downstream-consumers | The promoted corpus passes `check` and stays under the cap (`planted.py:448-486`). | already-had | became D-11 |
| F-15 | downstream-consumers | Two check rules key on `PILOT`; re-key on non-frozen P4 (`planted.py:336,420`). | already-had | became D-6 |
| F-16 | downstream-consumers | A model-free `verify` on the kept ids builds both arms with no stop (`planted.py:1271-1313`). | new | not material |
| F-17 | downstream-consumers | score-selftest and render-selftest need no edit; changelog rows pin 43 (`score-selftest.sh:147-174`). | new | became D-17 |
| F-18 | downstream-consumers | The ticket does not say whether the machinery stays (`planted.py:64-67`). | already-had | became D-5 |
| F-19 | measurement-validity | The rescored file equals the first; the disagree branch is empty (`cmp` on the two files). | overturned (both judgings agree on every miss) | became D-14 |
| F-20 | measurement-validity | mn7cuh is kept on two note-severity misses (`planted.py:848-853`). | new | informed D-1 |
| F-21 | measurement-validity | PM-1's 50% bound is loose; the kept set ran 14% right (`planted.py:941-958`). | new | informed D-3 |
| F-22 | measurement-validity | After promotion every pattern has at least two scored cases (`planted.py check`). | new | informed D-1 |
| F-23 | premortem | Any rescore under the same judge replays the cache (`bench.py:251-257`). | already-had | became D-2 |
| F-24 | premortem | ba4kxe's misses are a truth-window artifact at `ssrVModel.ts:68` (`cases/ba4kxe/case.json`). | new | became D-15 |
| F-25 | premortem | corpus-selftest hard-codes pilot ids the ticket moves (`corpus-selftest.sh:178-187`). | already-had | became D-16 |
| F-26 | premortem | The structural ACs are cheap; AC-3's overlay clause removes nothing (`planted.py:446-486`). | already-had | became D-10 |
| F-27 | premortem | PM-1 as written is a 300-case-run normal run (`planted.py:1055`). | new | became D-4 |

### Snapshot

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Which candidates the pilot keeps | Fact: 7 of 32 at 2+ both-judging misses. Both judgings agree on every miss. |
    | D-2 | How the build gets the pilot data | Open: put the per-case, per-run table in the ticket body. |
    | D-3 | Fewer than 8 kept, two patterns at 1 | Open: promote 7, lower the bar, or author more. Question. |
    | D-4 | PM-1 failure disposition | Open. Question. |
    | D-5 | PILOT after promotion | Keep machinery with an empty PILOT vs retire. Question. |
    | D-6 | Outside-every-hunk rule after promotion | Gated on `cid in PILOT`; every non-frozen P4 fails e7k3wb and w9d3ra. Question. |
    | D-7 | AC-3 deletion scope | Fact: no overlay or NOTICE line is used only by dropped candidates. |
    | D-8 | Upstream cap after promotion | Fact: dayjs 16/50, under 40%. |
    | D-9 | Selftest and doc churn | Fact: pins, cap fixtures, pilot tests, docs/testing.md. |
    | D-10 | "Right" and pairing of judgings | Fact: right >= 1; `cases` reads one file. |

</details>
