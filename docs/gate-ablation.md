# Gate ablation over the lean run corpus

Which of the lane's blocking gates has ever changed what shipped, measured rather than argued.

The mutation sweep holds every shell guard to one bar: name the regression class only you catch.
The lane's own gates have never been held to it. `docs/pipeline-manifesto.md`'s **V1** states the
thesis — strictness that cannot change the merge decision does not get to block — and until this
report there was nothing behind it, so every pruning argument was rhetorical.

This is the transplant of the mutation-testing idea onto the gates: disable one on paper and ask
whether any historical run's merge decision changes.

**Nothing here changes any gate.** It is the evidence the census-triage slice consumes.

## Method

### What is measured

Every lean run leaves `{issue}-lean-progress.md` — append-only, timestamped, and gitignored. Its
`attempt` and `absent` rows **are** the gate's firings; its `obligation` rows name the sub-milestone
identity where the gate writes one. Those records are the corpus, and `tools/gate-ablation.sh` scores
each firing in two deliberately different columns:

| column | kind | how to distrust it |
| --- | --- | --- |
| `mechanical` | computed from the corpus by the generator | re-run it — see *Reproducing* below |
| `adjudicated` | read from `tools/gate-ablation-adjudication.tsv`, each row citing a record | read the cited record |

The adjudicated column answers one question, and only this one: **did the demanded fix alter what
shipped?** Not *would the merge have gone the other way* — that needs the redundancy analysis under
*Routing*, and it is the successor slice's question. A refusal whose remedy is an act the checklist
already prescribes — write the spec, hand off the review, post the closing comment — altered nothing:
the run was going to do it anyway, and the refusal announced an ordering.

The sub-milestone identity comes from `tools/gate-ablation-classes.tsv`, committed as part of this
deliverable. Each row is a decision point. A recorded reason that matches no row is a hard failure
naming the record, never an `other` bucket — that is what stops a new refusal class from joining the
corpus without ever being enumerated.

### What is not recomputable, and is therefore not claimed

**A true per-firing content diff does not exist in the record.** The lane's branches are
squash-merged and deleted, so no branch history survives on the base branch, and the progress record
carries no commit sha at any row. The only committed patch-identity observation anywhere is the
verdict record's `inherited_patch_id` / `reviewed_patch_id` pair, which covers one round boundary per
run. So the mechanical column resolves to a real content diff for **six** firings and reports
`unmeasured` or `no-response` for the rest. `unmeasured` is a limit on this report's reach. **It is
never an implied pass.**

Two further honesty notes on that column:

- Where a run's record is truncated, the round boundary is attributed to the **last recorded**
  milestone-4 firing, which may not be the firing it actually followed.
- `no-response` means *this record shows no later evaluation of that milestone*. Given that only 10
  of 52 records reach `milestone-4 satisfied` and 6 reach `milestone-5 satisfied`, it is mostly a
  statement about record truncation — the close-out happens in a later session, or the lane ends at
  a handoff — and not about the lane.

**Refusal classes that write no record are unmeasured by construction.** They are listed here rather
than left out, because a gate absent from a table reads as a gate that never fired:

| refusal | why no record | consequence |
| --- | --- | --- |
| the wrong-tree refusal (`rc=9`) | refuses before touching the progress file, by design | its fire count is unknown; it may be the lane's most frequent refusal |
| the unattested-entry refusal | `entry` records only its success | unknown |
| usage and environment errors (`envfail`) | deliberately outside the fix budget, so nothing is appended | unknown |
| every scheduler decision (`run-lean`) | the scheduler reads exit codes and authors nothing | unknown; the scheduler is not in this corpus at all |
| `teardown` and `handoff` rows | recorded, but neither is a gate refusing | out of scope, not unmeasured |

**Out of corpus.** 47 stage-era records (`{issue}.json`, a top-level `stages` key) describe gates
that no longer exist; they are counted and never scored. Three lanes were in flight when the manifest
was cut and are named in its header — their records were still being appended to, so pinning them
would have pinned a moving file.

### Reproducing

The records are host-local, so the corpus cannot be committed. `docs/gate-ablation-manifest.tsv`
pins it instead — one row per record, with a sha256 — and that file is what "unchanged corpus" means.

```bash
bash tools/gate-ablation.sh check     # regenerate and diff against the block below
bash tools/gate-ablation.sh emit      # print the block
bash tools/gate-ablation.sh manifest --exclude <live lanes>   # re-cut the corpus pin
```

`--exclude` is the only exclusion source, so **name every lane that is in flight when you re-cut**.
The pin committed here was cut against three (`546 609 611`); two of them were found automatically,
by a lane registry that #566 retired along with milestone 3's supervision stratum. A lane you forget
is not silently dropped — its record joins the corpus and the next `emit` refuses on its drift.

`emit` verifies every manifest row against the live corpus and **exits 3 naming any record that
drifted or went missing**, so a regeneration either reproduces the tables byte-for-byte or says which
record moved. It also exits 4 if its own output carries a session id or an absolute local path.

## Findings

**1. Milestone 2 has never fired.** Zero firings across 52 records, against 52 satisfactions and 12
`advisory` rows — every one of them the frozen-files workflow-edit notice. A milestone whose only
recorded output is advisory is a different finding from one that merely happens to be quiet, and both
of its constituent checks are re-run at the merge boundary (see *Routing*).

**2. The largest firing class demands nothing.** `m1/spec-absent` is 54 of 109 firings — half the
corpus — and every one is adjudicated `unchanged`: the gate refuses because the run has not written
its spec yet, which is the step the checklist sends you to it to learn the path for. The lane has
already half-demoted it: 18 of the 54 are recorded under the `absent` verb, which spends no fix
budget, against 36 under the older `attempt` verb which did. This report's contribution is that the
demotion was right and is not finished.

**3. Announcement-class refusals dominate.** `m1/spec-absent` (54), `m5/verdict-reference:closing-comment`
(8), `m4/verdict-absent` (4), `m5/progress-current` (3), `m5/identity-stamp` (2) and
`m5/exit-artifacts:no-open-pr` (1) — **72 of 109 firings**, two thirds of everything the corpus
records, all adjudicated as changing nothing. Each fires because the checklist's *next* step has not
happened yet.

**4. Six points earn their keep, and each carries a dated incident.** `m3/test` (13),
`m3/extra-lane` (12), `m4/verdict-not-approve` (6), `m3/lint` (2), `m4/chain-break` (1) and
`m4/patch-stale` (1) — 35 firings between them. The two sharpest are single incidents, not volume:
`m4/patch-stale` (2026-08-03) caught an approve bound to `05c05a4` while 15 files had landed after
it, one of them the CI workflow that judges the PR; `m4/chain-break` (2026-08-04) caught a round
claiming inherited coverage from a patch id no committed record carries.

**5. Twenty of 33 declared decision points have never fired at all.** They are listed rather than
dropped: a point with no firings cannot be shown to change a decision, but neither can it be shown
not to, and several guard states this repo simply never enters (the whole design-render tier, the
identity checks, `m4/head-missing`).

**6. False-red floor: one firing.** Milestone 5 on #531 refused with *no open PR found* while
`docs/plans/second-shift-531-lean-verdict.md` records `pr: #548` for that same run — the PR merged
mid-close-out. The floor counts only refusals a committed record explicitly contradicts, so it is a
floor and not an estimate; the repeat-firing diagnostic below is its labeled upper-bound counterpart
and over-counts by construction.

## Routing — not part of the measurement

The adjudicated column says a milestone-3 failure altered what shipped. It does not say the *merge
decision* would have differed, because most of what these gates check is re-run at the merge
boundary. That map is an assertion about `.github/workflows/ci.yml`, verifiable by reading it, and it
is the successor slice's starting point rather than a result of this one:

| gate point | re-run at the merge boundary by |
| --- | --- |
| `m2/frozen-files` | `pr-gates` → *frozen files guard* |
| `m2/changelog-trailer` | `pr-gates` → *changelog trailer guard* |
| `m3/lint` | `lint-and-selftests` → *shellcheck* |
| `m3/test` | `lint-and-selftests` → *run all selftests* |
| `m3/extra-lane` (mutation) | `mutation-sweep-pr` |
| every `m4/*` | `pr-gates` → *lean chain reconciliation* (`check-lean-chain.sh`) |
| every `m1/*` and `m5/*` | nothing — these are lane-local by construction |

What a milestone-3 gate buys, on this evidence, is **when** a failure is caught, not whether. What
milestone 1 and milestone 5 buy is the only thing nothing else checks — and both are dominated by
announcement-class firings.

<!-- BEGIN GENERATED: gate-ablation -->

### Corpus

| | |
| --- | --- |
| scored records (artifact schema) | 52 |
| firings scored | 109 |
| declared decision points | 33 |
| `obligation` rows in the corpus | 1 |
| `advisory` rows in the corpus | 12 (milestone-2: 12) |
| records reaching `milestone-4 satisfied` | 10 |
| records reaching `milestone-5 satisfied` | 6 |
| corpus manifest | `docs/gate-ablation-manifest.tsv` |

### Decision points

Every point the reason-class table declares, whether or not it ever fired. `mechanical` and
`adjudicated` are the two labeled columns of AC-2; `eval s` and `rework s` are the measured
cost, each with the number of firings it could be measured over.

| gate point | ms | obligation | firings | attempt / absent | mechanical | adjudicated | eval s | rework s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `m1/spec-absent` | 1 | — | 54 | 36 / 18 | 54 unmeasured | 54 unchanged | 2 (14/54) | 178697 (15/54) |
| `m1/spec-no-ac` | 1 | — | — | — / — | — | — | — | — |
| `m1/ledger-lint` | 1 | — | — | — / — | — | — | — | — |
| `m1/preflight-reconcile` | 1 | — | — | — / — | — | — | — | — |
| `m1/pause-and-ask` | 1 | — | 2 | 2 / — | 2 no-response | 2 undetermined | — | — |
| `m1/design-form` | 1 | — | — | — / — | — | — | — | — |
| `m2/frozen-files` | 2 | — | — | — / — | — | — | — | — |
| `m2/changelog-trailer` | 2 | — | — | — / — | — | — | — | — |
| `m3/lint` | 3 | — | 2 | 2 / — | 2 unmeasured | 2 changed | 23 (1/2) | 45 (1/2) |
| `m3/typecheck` | 3 | — | — | — / — | — | — | — | — |
| `m3/test` | 3 | — | 13 | 13 / — | 13 unmeasured | 13 changed | 2884 (4/13) | 3704 (4/13) |
| `m3/extra-lane` | 3 | — | 12 | 12 / — | 12 unmeasured | 12 changed | 6624 (5/12) | 7932 (5/12) |
| `m3/setup-lane` | 3 | — | — | — / — | — | — | — | — |
| `m3/no-verify-lane` | 3 | — | — | — / — | — | — | — | — |
| `m3/design-render` | 3 | — | — | — / — | — | — | — | — |
| `m4/verdict-absent` | 4 | — | 4 | 4 / — | 1 moved, 2 no-response, 1 unmeasured | 4 unchanged | — | — |
| `m4/verdict-not-approve` | 4 | — | 6 | 6 / — | 4 moved, 2 no-response | 6 changed | 0 (1/6) | — |
| `m4/verdict-keys` | 4 | — | — | — / — | — | — | — | — |
| `m4/verdict-uncommitted` | 4 | — | — | — / — | — | — | — | — |
| `m4/identity` | 4 | — | — | — / — | — | — | — | — |
| `m4/chain-break` | 4 | — | 1 | 1 / — | 1 moved | 1 changed | — | — |
| `m4/patch-stale` | 4 | — | 1 | 1 / — | 1 unmeasured | 1 changed | — | — |
| `m4/head-missing` | 4 | — | — | — / — | — | — | — | — |
| `m4/head-tree-diff` | 4 | — | — | — / — | — | — | — | — |
| `m4/fidelity` | 4 | — | — | — / — | — | — | — | — |
| `m5/progress-current` | 5 | — | 3 | 3 / — | 3 no-response | 3 unchanged | — | — |
| `m5/exit-artifacts:no-open-pr` | 5 | `exit-artifacts` | 1 | 1 / — | 1 no-response | 1 unchanged | 1 (1/1) | — |
| `m5/exit-artifacts:draft` | 5 | `exit-artifacts` | — | — / — | — | — | — | — |
| `m5/exit-artifacts:closes` | 5 | `exit-artifacts` | — | — / — | — | — | — | — |
| `m5/exit-artifacts:spec-link` | 5 | `exit-artifacts` | — | — / — | — | — | — | — |
| `m5/verdict-reference:closing-comment` | 5 | `verdict-reference` | 8 | 8 / — | 1 no-response, 7 unmeasured | 8 unchanged | 10 (7/8) | 646 (6/8) |
| `m5/verdict-reference:body-ref` | 5 | `verdict-reference` | — | — / — | — | — | — | — |
| `m5/identity-stamp` | 5 | — | 2 | 2 / — | 2 unmeasured | 2 unchanged | 1 (1/2) | 51 (1/2) |

### Firings

Every firing in the corpus, with its citation. `record • milestone • timestamp` locates the
row; the records themselves are host-local and pinned by the manifest.

| # | citation | gate point | verb | mechanical | adjudicated | repeat |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `345-lean-progress.md` • milestone-3 • `2026-08-03T12:39:04Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 2 | `345-lean-progress.md` • milestone-4 • `2026-08-03T15:03:21Z` | `m4/patch-stale` | attempt | unmeasured | changed | — |
| 3 | `346-lean-progress.md` • milestone-1 • `2026-08-03T17:54:20Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 4 | `346-lean-progress.md` • milestone-5 • `2026-08-03T18:46:20Z` | `m5/progress-current` | attempt | no-response | unchanged | — |
| 5 | `346-lean-progress.md` • milestone-4 • `2026-08-03T21:22:08Z` | `m4/verdict-not-approve` | attempt | no-response | changed | — |
| 6 | `346-lean-progress.md` • milestone-5 • `2026-08-03T21:22:08Z` | `m5/progress-current` | attempt | no-response | unchanged | — |
| 7 | `347-lean-progress.md` • milestone-1 • `2026-08-03T18:08:04Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 8 | `347-lean-progress.md` • milestone-3 • `2026-08-03T18:36:24Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 9 | `356-lean-progress.md` • milestone-1 • `2026-08-10T11:47:48Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 10 | `356-lean-progress.md` • milestone-3 • `2026-08-10T12:03:12Z` | `m3/lint` | attempt | unmeasured | changed | — |
| 11 | `356-lean-progress.md` • milestone-3 • `2026-08-10T12:13:49Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 12 | `357-lean-progress.md` • milestone-1 • `2026-08-06T20:02:38Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 13 | `357-lean-progress.md` • milestone-3 • `2026-08-06T21:37:09Z` | `m3/test` | attempt | unmeasured | changed | — |
| 14 | `357-lean-progress.md` • milestone-4 • `2026-08-06T21:57:40Z` | `m4/verdict-absent` | attempt | no-response | unchanged | — |
| 15 | `359-lean-progress.md` • milestone-1 • `2026-08-06T20:01:48Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 16 | `359-lean-progress.md` • milestone-3 • `2026-08-06T21:46:21Z` | `m3/test` | attempt | unmeasured | changed | — |
| 17 | `362-lean-progress.md` • milestone-1 • `2026-08-03T14:07:58Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 18 | `362-lean-progress.md` • milestone-4 • `2026-08-03T16:13:51Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 19 | `363-lean-progress.md` • milestone-1 • `2026-08-03T17:45:07Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 20 | `372-lean-progress.md` • milestone-1 • `2026-08-03T22:22:31Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 21 | `372-lean-progress.md` • milestone-4 • `2026-08-04T10:04:13Z` | `m4/verdict-not-approve` | attempt | no-response | changed | — |
| 22 | `374-lean-progress.md` • milestone-1 • `2026-08-04T11:13:16Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 23 | `374-lean-progress.md` • milestone-3 • `2026-08-04T11:40:01Z` | `m3/test` | attempt | unmeasured | changed | — |
| 24 | `374-lean-progress.md` • milestone-5 • `2026-08-04T12:12:51Z` | `m5/progress-current` | attempt | no-response | unchanged | — |
| 25 | `375-lean-progress.md` • milestone-1 • `2026-08-04T11:12:46Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 26 | `375-lean-progress.md` • milestone-3 • `2026-08-04T11:52:28Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 27 | `375-lean-progress.md` • milestone-4 • `2026-08-04T13:29:10Z` | `m4/chain-break` | attempt | content-moved | changed | — |
| 28 | `375-lean-progress.md` • milestone-1 • `2026-08-04T21:00:04Z` | `m1/pause-and-ask` | attempt | no-response | undetermined | — |
| 29 | `375-lean-progress.md` • milestone-1 • `2026-08-04T21:00:44Z` | `m1/pause-and-ask` | attempt | no-response | undetermined | yes |
| 30 | `378-lean-progress.md` • milestone-1 • `2026-08-04T22:08:37Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 31 | `378-lean-progress.md` • milestone-4 • `2026-08-05T06:35:16Z` | `m4/verdict-not-approve` | attempt | content-moved | changed | — |
| 32 | `379-lean-progress.md` • milestone-1 • `2026-08-04T22:09:30Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 33 | `379-lean-progress.md` • milestone-4 • `2026-08-04T22:57:39Z` | `m4/verdict-absent` | attempt | content-moved | unchanged | — |
| 34 | `381-lean-progress.md` • milestone-1 • `2026-08-04T21:44:05Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 35 | `388-lean-progress.md` • milestone-1 • `2026-08-05T12:18:51Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 36 | `392-lean-progress.md` • milestone-1 • `2026-08-05T22:32:33Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 37 | `392-lean-progress.md` • milestone-3 • `2026-08-05T22:54:27Z` | `m3/test` | attempt | unmeasured | changed | — |
| 38 | `393-lean-progress.md` • milestone-1 • `2026-08-05T22:37:40Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 39 | `393-lean-progress.md` • milestone-3 • `2026-08-05T22:55:29Z` | `m3/test` | attempt | unmeasured | changed | — |
| 40 | `394-lean-progress.md` • milestone-1 • `2026-08-06T09:19:38Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 41 | `395-lean-progress.md` • milestone-1 • `2026-08-05T22:44:42Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 42 | `395-lean-progress.md` • milestone-4 • `2026-08-05T22:58:22Z` | `m4/verdict-absent` | attempt | no-response | unchanged | — |
| 43 | `398-lean-progress.md` • milestone-1 • `2026-08-06T11:16:39Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 44 | `403-lean-progress.md` • milestone-1 • `2026-08-06T10:18:49Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 45 | `408-lean-progress.md` • milestone-1 • `2026-08-06T14:48:58Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 46 | `410-lean-progress.md` • milestone-1 • `2026-08-06T13:21:20Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 47 | `413-lean-progress.md` • milestone-1 • `2026-08-08T19:01:14Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 48 | `416-lean-progress.md` • milestone-1 • `2026-08-06T18:02:16Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 49 | `417-lean-progress.md` • milestone-1 • `2026-08-06T17:52:43Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 50 | `417-lean-progress.md` • milestone-4 • `2026-08-08T17:05:05Z` | `m4/verdict-not-approve` | attempt | content-moved | changed | — |
| 51 | `419-lean-progress.md` • milestone-1 • `2026-08-06T18:31:28Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 52 | `423-lean-progress.md` • milestone-1 • `2026-08-06T20:00:29Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 53 | `423-lean-progress.md` • milestone-3 • `2026-08-06T20:44:20Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 54 | `431-lean-progress.md` • milestone-1 • `2026-08-07T13:24:15Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 55 | `434-lean-progress.md` • milestone-1 • `2026-08-08T18:29:50Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 56 | `464-lean-progress.md` • milestone-1 • `2026-08-10T11:45:37Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 57 | `473-lean-progress.md` • milestone-1 • `2026-08-10T12:22:40Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 58 | `473-lean-progress.md` • milestone-3 • `2026-08-10T12:45:34Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 59 | `476-lean-progress.md` • milestone-1 • `2026-08-10T12:44:19Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 60 | `476-lean-progress.md` • milestone-4 • `2026-08-10T15:30:51Z` | `m4/verdict-not-approve` | attempt | content-moved | changed | — |
| 61 | `477-lean-progress.md` • milestone-1 • `2026-08-10T12:44:45Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 62 | `490-lean-progress.md` • milestone-1 • `2026-08-11T12:30:48Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 63 | `490-lean-progress.md` • milestone-1 • `2026-08-11T12:31:01Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 64 | `490-lean-progress.md` • milestone-3 • `2026-08-11T12:47:18Z` | `m3/test` | attempt | unmeasured | changed | — |
| 65 | `490-lean-progress.md` • milestone-3 • `2026-08-11T12:53:35Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 66 | `492-lean-progress.md` • milestone-3 • `2026-08-11T15:22:29Z` | `m3/test` | attempt | unmeasured | changed | — |
| 67 | `493-lean-progress.md` • milestone-1 • `2026-08-11T14:50:42Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 68 | `493-lean-progress.md` • milestone-3 • `2026-08-11T15:23:36Z` | `m3/test` | attempt | unmeasured | changed | — |
| 69 | `496-lean-progress.md` • milestone-1 • `2026-08-11T20:48:29Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 70 | `497-lean-progress.md` • milestone-1 • `2026-08-12T10:35:13Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 71 | `500-lean-progress.md` • milestone-1 • `2026-08-12T10:35:45Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 72 | `500-lean-progress.md` • milestone-5 • `2026-08-12T12:00:45Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 73 | `500-lean-progress.md` • milestone-5 • `2026-08-12T12:01:32Z` | `m5/identity-stamp` | attempt | unmeasured | unchanged | — |
| 74 | `502-lean-progress.md` • milestone-1 • `2026-08-12T10:37:28Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 75 | `502-lean-progress.md` • milestone-3 • `2026-08-12T12:09:17Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 76 | `511-lean-progress.md` • milestone-1 • `2026-08-13T11:26:41Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 77 | `511-lean-progress.md` • milestone-3 • `2026-08-13T12:42:27Z` | `m3/test` | attempt | unmeasured | changed | — |
| 78 | `511-lean-progress.md` • milestone-3 • `2026-08-13T13:34:39Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 79 | `511-lean-progress.md` • milestone-5 • `2026-08-13T23:00:22Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 80 | `514-lean-progress.md` • milestone-1 • `2026-08-13T11:22:48Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 81 | `514-lean-progress.md` • milestone-3 • `2026-08-13T12:21:55Z` | `m3/test` | attempt | unmeasured | changed | — |
| 82 | `515-lean-progress.md` • milestone-1 • `2026-08-13T11:31:58Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 83 | `515-lean-progress.md` • milestone-3 • `2026-08-13T12:39:03Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 84 | `515-lean-progress.md` • milestone-5 • `2026-08-13T15:53:09Z` | `m5/verdict-reference:closing-comment` | attempt | no-response | unchanged | — |
| 85 | `516-lean-progress.md` • milestone-1 • `2026-08-13T11:48:22Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 86 | `516-lean-progress.md` • milestone-1 • `2026-08-13T12:03:36Z` | `m1/spec-absent` | absent | unmeasured | unchanged | yes |
| 87 | `516-lean-progress.md` • milestone-3 • `2026-08-13T12:45:35Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 88 | `516-lean-progress.md` • milestone-1 • `2026-08-13T14:22:25Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 89 | `516-lean-progress.md` • milestone-5 • `2026-08-13T15:04:57Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 90 | `516-lean-progress.md` • milestone-5 • `2026-08-13T15:08:23Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 91 | `516-lean-progress.md` • milestone-5 • `2026-08-13T15:09:09Z` | `m5/identity-stamp` | attempt | unmeasured | unchanged | — |
| 92 | `526-lean-progress.md` • milestone-1 • `2026-08-13T14:20:02Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 93 | `527-lean-progress.md` • milestone-1 • `2026-08-14T17:07:35Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 94 | `527-lean-progress.md` • milestone-5 • `2026-08-14T18:44:34Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 95 | `528-lean-progress.md` • milestone-1 • `2026-08-13T23:43:44Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 96 | `528-lean-progress.md` • milestone-1 • `2026-08-13T23:44:09Z` | `m1/spec-absent` | absent | unmeasured | unchanged | yes |
| 97 | `528-lean-progress.md` • milestone-3 • `2026-08-14T00:53:38Z` | `m3/test` | attempt | unmeasured | changed | — |
| 98 | `528-lean-progress.md` • milestone-3 • `2026-08-14T11:00:27Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 99 | `528-lean-progress.md` • milestone-4 • `2026-08-14T12:43:49Z` | `m4/verdict-not-approve` | attempt | content-moved | changed | — |
| 100 | `528-lean-progress.md` • milestone-3 • `2026-08-14T16:08:52Z` | `m3/test` | attempt | unmeasured | changed | — |
| 101 | `531-lean-progress.md` • milestone-1 • `2026-08-16T14:43:49Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 102 | `531-lean-progress.md` • milestone-5 • `2026-08-16T16:05:32Z` | `m5/exit-artifacts:no-open-pr` | attempt | no-response | unchanged | — |
| 103 | `532-lean-progress.md` • milestone-1 • `2026-08-13T23:43:30Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 104 | `532-lean-progress.md` • milestone-3 • `2026-08-14T00:31:15Z` | `m3/lint` | attempt | unmeasured | changed | — |
| 105 | `532-lean-progress.md` • milestone-3 • `2026-08-14T01:13:41Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 106 | `532-lean-progress.md` • milestone-5 • `2026-08-14T02:40:06Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 107 | `539-lean-progress.md` • milestone-1 • `2026-08-14T22:13:41Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 108 | `539-lean-progress.md` • milestone-1 • `2026-08-16T11:03:22Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 109 | `539-lean-progress.md` • milestone-5 • `2026-08-16T13:01:02Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |

### Demotion candidates

Points that fired and whose every firing is adjudicated as changing no merge decision.
Ranked by that count, then by evaluation cost. A point with even one decision-changing
firing is not here — it is in the earn-your-keep table below — and neither is a point whose
firings are all `undetermined`, which the decision-points table above still counts.

`eval s` is the time the gate spent evaluating, summed over the firings it could be measured
over, and it is the secondary key. `rework s` is wall-clock between a firing and the next
evaluation of that milestone: it is reported because it is measured, but it swallows every
interval where the operator was simply away and so ranks nothing.

| rank | gate point | zero-decision-change firings | of total | undetermined | eval s | rework s |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `m1/spec-absent` | 54 | 54 | — | 2 (14/54) | 178697 (15/54) |
| 2 | `m5/verdict-reference:closing-comment` | 8 | 8 | — | 10 (7/8) | 646 (6/8) |
| 3 | `m4/verdict-absent` | 4 | 4 | — | — | — |
| 4 | `m5/progress-current` | 3 | 3 | — | — | — |
| 5 | `m5/identity-stamp` | 2 | 2 | — | 1 (1/2) | 51 (1/2) |
| 6 | `m5/exit-artifacts:no-open-pr` | 1 | 1 | — | 1 (1/1) | — |

### Never fired

Declared decision points with zero firings across the corpus. A point that never fired is a
different finding from one that fires and changes nothing, so the two are not merged.

| gate point | ms | obligation |
| --- | --- | --- |
| `m1/spec-no-ac` | 1 | — |
| `m1/ledger-lint` | 1 | — |
| `m1/preflight-reconcile` | 1 | — |
| `m1/design-form` | 1 | — |
| `m2/frozen-files` | 2 | — |
| `m2/changelog-trailer` | 2 | — |
| `m3/typecheck` | 3 | — |
| `m3/setup-lane` | 3 | — |
| `m3/no-verify-lane` | 3 | — |
| `m3/design-render` | 3 | — |
| `m4/verdict-keys` | 4 | — |
| `m4/verdict-uncommitted` | 4 | — |
| `m4/identity` | 4 | — |
| `m4/head-missing` | 4 | — |
| `m4/head-tree-diff` | 4 | — |
| `m4/fidelity` | 4 | — |
| `m5/exit-artifacts:draft` | 5 | `exit-artifacts` |
| `m5/exit-artifacts:closes` | 5 | `exit-artifacts` |
| `m5/exit-artifacts:spec-link` | 5 | `exit-artifacts` |
| `m5/verdict-reference:body-ref` | 5 | `verdict-reference` |

### Earn-your-keep

Points carrying at least one firing adjudicated as changing what shipped, with the dated
incident that earns the block.

| gate point | first decision-changing firing | adjudication row | what changed |
| --- | --- | --- | --- |
| `m3/lint` | `2026-08-10T12:03:12Z` | `m3/lint` | a red shellcheck lane; the remedy is a source edit, so the branch that merged is not the branch that fired |
| `m3/test` | `2026-08-06T21:37:09Z` | `m3/test` | a red selftest sweep; the remedy is a source or fixture edit, and 528 took three of them across four sessions |
| `m3/extra-lane` | `2026-08-03T12:39:04Z` | `m3/extra-lane` | a red mutation sweep; the remedy is a strengthened guard or an accepted baseline row, and both land in the diff |
| `m4/verdict-not-approve` | `2026-08-03T21:22:08Z` | `m4/verdict-not-approve` | round 3 blockers on that run; the committed verdict record reaches four rounds and its final round boundary moves the reviewed patch id |
| `m4/chain-break` | `2026-08-04T13:29:10Z` | `m4/chain-break` | round 1 claimed inherited coverage from a patch id no committed record carries; without the refusal PR 377 merges on a verdict attesting a diff nobody read |
| `m4/patch-stale` | `2026-08-03T15:03:21Z` | `m4/patch-stale` | an approve bound to 05c05a4 while 15 files had landed after it, one of them the CI workflow that judges the PR; the second round covered them and milestone 4 satisfied 30 minutes later |

### False reds — lower bound

Counts only firings a committed record explicitly contradicts. It is a floor, not an
estimate: a refusal nothing committed speaks to is absent from this table rather than
assumed correct.

| gate point | firings | first | adjudication row | contradicted by |
| --- | --- | --- | --- | --- |
| `m5/exit-artifacts:no-open-pr` | 1 | `2026-08-16T16:05:32Z` | `531:m5/exit-artifacts:no-open-pr` | docs/plans/second-shift-531-lean-verdict.md, which records `pr: #548` for that run |

**Lower bound: 1 firing.**

### Repeat firings — upper bound

The same point re-firing with no intervening evaluation of another milestone and no session
change. An over-count by construction: a reaped call that never concluded and an idempotent
re-invocation both land here, and neither is a second independent refusal.

| gate point | repeat firings | of total |
| --- | --- | --- |
| `m1/spec-absent` | 3 | 54 |
| `m1/pause-and-ask` | 1 | 2 |
| `m3/test` | 1 | 13 |

**Upper bound: 5 firings.**

<!-- END GENERATED: gate-ablation -->
