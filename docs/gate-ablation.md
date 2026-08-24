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
The pin committed here was cut against three (`546 609 611`). The operator's own `--exclude` named
one of them; all three were found by a lane registry that #566 retired along with milestone 3's
supervision stratum, so on this recipe the other two would simply have been missed — which is the
whole reason the instruction above is in bold. A lane you forget is not silently dropped — its
record joins the corpus and the next `emit` refuses on its drift.

`emit` verifies every manifest row against the live corpus and **exits 3 naming any record that
drifted or went missing**, so a regeneration either reproduces the tables byte-for-byte or says which
record moved. It also exits 4 if its own output carries a session id or an absolute local path.

## Findings

> **The corpus was RE-CUT by #642** (74 records pinned, 70 scored, 192 firings, 31 declared decision
> points) so that the next report measures the surface #642 left. The generated block below is that
> re-cut; the numbered findings that follow are the ORIGINAL analysis over the 52-record pin, kept
> verbatim because they are what #642 acted on and what its PR is checkable against. Read them as
> dated, and read the block for current figures. Two of the changes #642 made are visible in it
> directly: `m1/spec-absent`, `m4/verdict-absent`, `m5/progress-current`,
> `m5/exit-artifacts:no-open-pr`, `m5/verdict-reference:closing-comment` and `m5/identity-stamp`
> now record under the `absent` verb, and the 33 declared points are 31 — `m4/head-missing` and
> `m4/head-tree-diff` were deleted as structurally dead.


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
| scored records (artifact schema) | 70 |
| firings scored | 192 |
| declared decision points | 31 |
| `obligation` rows in the corpus | 25 |
| `advisory` rows in the corpus | 31 (milestone-2: 31) |
| records reaching `milestone-4 satisfied` | 31 |
| records reaching `milestone-5 satisfied` | 27 |
| corpus manifest | `docs/gate-ablation-manifest.tsv` |

### Decision points

Every point the reason-class table declares, whether or not it ever fired. `mechanical` and
`adjudicated` are the two labeled columns of AC-2; `eval s` and `rework s` are the measured
cost, each with the number of firings it could be measured over.

| gate point | ms | obligation | firings | attempt / absent | mechanical | adjudicated | eval s | rework s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `m1/spec-absent` | 1 | — | 83 | 51 / 32 | 83 unmeasured | 83 unchanged | 2 (31/83) | 18062 (31/83) |
| `m1/spec-no-ac` | 1 | — | — | — / — | — | — | — | — |
| `m1/ledger-lint` | 1 | — | 4 | 4 / — | 4 unmeasured | 4 undetermined | 0 (4/4) | 91 (4/4) |
| `m1/preflight-reconcile` | 1 | — | 2 | 2 / — | 2 unmeasured | 2 undetermined | 0 (2/2) | 68 (2/2) |
| `m1/pause-and-ask` | 1 | — | 3 | 3 / — | 3 unmeasured | 3 undetermined | 5 (3/3) | 11272 (3/3) |
| `m1/design-form` | 1 | — | — | — / — | — | — | — | — |
| `m2/frozen-files` | 2 | — | — | — / — | — | — | — | — |
| `m2/changelog-trailer` | 2 | — | — | — / — | — | — | — | — |
| `m3/lint` | 3 | — | — | — / — | — | — | — | — |
| `m3/typecheck` | 3 | — | — | — / — | — | — | — | — |
| `m3/test` | 3 | — | 36 | 36 / — | 5 no-response, 31 unmeasured | 36 changed | 6677 (10/36) | 19821 (9/36) |
| `m3/extra-lane` | 3 | — | 8 | 8 / — | 1 no-response, 7 unmeasured | 8 changed | 1457 (4/8) | 667 (4/8) |
| `m3/setup-lane` | 3 | — | — | — / — | — | — | — | — |
| `m3/no-verify-lane` | 3 | — | — | — / — | — | — | — | — |
| `m3/design-render` | 3 | — | — | — / — | — | — | — | — |
| `m4/verdict-absent` | 4 | — | 24 | 24 / — | 1 moved, 23 unmeasured | 24 unchanged | — | — |
| `m4/verdict-not-approve` | 4 | — | 4 | 4 / — | 2 moved, 2 unmeasured | 4 changed | 0 (2/4) | — |
| `m4/verdict-keys` | 4 | — | — | — / — | — | — | — | — |
| `m4/verdict-uncommitted` | 4 | — | — | — / — | — | — | — | — |
| `m4/identity` | 4 | — | — | — / — | — | — | — | — |
| `m4/chain-break` | 4 | — | — | — / — | — | — | — | — |
| `m4/patch-stale` | 4 | — | — | — / — | — | — | — | — |
| `m4/fidelity` | 4 | — | — | — / — | — | — | — | — |
| `m5/progress-current` | 5 | — | — | — / — | — | — | — | — |
| `m5/exit-artifacts:no-open-pr` | 5 | `exit-artifacts` | 17 | 17 / — | 4 no-response, 13 unmeasured | 17 unchanged | 2 (2/17) | — |
| `m5/exit-artifacts:draft` | 5 | `exit-artifacts` | — | — / — | — | — | — | — |
| `m5/exit-artifacts:closes` | 5 | `exit-artifacts` | — | — / — | — | — | — | — |
| `m5/exit-artifacts:spec-link` | 5 | `exit-artifacts` | — | — / — | — | — | — | — |
| `m5/verdict-reference:closing-comment` | 5 | `verdict-reference` | 8 | 8 / — | 8 unmeasured | 8 unchanged | 6 (6/8) | 457 (6/8) |
| `m5/verdict-reference:body-ref` | 5 | `verdict-reference` | — | — / — | — | — | — | — |
| `m5/identity-stamp` | 5 | — | 3 | 3 / — | 3 unmeasured | 3 unchanged | 4 (3/3) | 1146 (3/3) |

### Firings

Every firing in the corpus, with its citation. `record • milestone • timestamp` locates the
row; the records themselves are host-local and pinned by the manifest.

| # | citation | gate point | verb | mechanical | adjudicated | repeat |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `72-lean-progress.md` • milestone-1 • `2026-08-01T13:01:53Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 2 | `72-lean-progress.md` • milestone-1 • `2026-08-01T13:08:27Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 3 | `72-lean-progress.md` • milestone-1 • `2026-08-01T13:08:44Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 4 | `72-lean-progress.md` • milestone-3 • `2026-08-01T13:20:11Z` | `m3/test` | attempt | unmeasured | changed | — |
| 5 | `72-lean-progress.md` • milestone-3 • `2026-08-01T13:25:15Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 6 | `72-lean-progress.md` • milestone-4 • `2026-08-01T13:33:46Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 7 | `72-lean-progress.md` • milestone-4 • `2026-08-01T13:36:22Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | yes |
| 8 | `83-lean-progress.md` • milestone-1 • `2026-08-01T11:56:06Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 9 | `83-lean-progress.md` • milestone-3 • `2026-08-01T12:25:16Z` | `m3/test` | attempt | unmeasured | changed | — |
| 10 | `83-lean-progress.md` • milestone-3 • `2026-08-01T12:41:04Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 11 | `83-lean-progress.md` • milestone-3 • `2026-08-01T12:58:29Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 12 | `83-lean-progress.md` • milestone-4 • `2026-08-01T13:06:39Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 13 | `83-lean-progress.md` • milestone-5 • `2026-08-01T13:39:32Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 14 | `83-lean-progress.md` • milestone-5 • `2026-08-01T14:01:58Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | yes |
| 15 | `92-lean-progress.md` • milestone-4 • `2026-08-02T14:51:05Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 16 | `103-lean-progress.md` • milestone-1 • `2026-08-01T12:16:12Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 17 | `103-lean-progress.md` • milestone-1 • `2026-08-01T12:16:50Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 18 | `103-lean-progress.md` • milestone-3 • `2026-08-01T12:26:29Z` | `m3/test` | attempt | unmeasured | changed | — |
| 19 | `103-lean-progress.md` • milestone-3 • `2026-08-01T12:33:33Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 20 | `103-lean-progress.md` • milestone-4 • `2026-08-01T12:48:12Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 21 | `103-lean-progress.md` • milestone-5 • `2026-08-01T13:01:41Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 22 | `107-lean-progress.md` • milestone-1 • `2026-08-01T17:43:37Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 23 | `107-lean-progress.md` • milestone-4 • `2026-08-01T18:00:01Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 24 | `107-lean-progress.md` • milestone-5 • `2026-08-01T18:13:28Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 25 | `109-lean-progress.md` • milestone-1 • `2026-08-01T11:30:16Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 26 | `109-lean-progress.md` • milestone-3 • `2026-08-01T12:00:53Z` | `m3/test` | attempt | unmeasured | changed | — |
| 27 | `109-lean-progress.md` • milestone-4 • `2026-08-01T12:09:43Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 28 | `113-lean-progress.md` • milestone-1 • `2026-08-01T17:48:20Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 29 | `113-lean-progress.md` • milestone-4 • `2026-08-01T18:19:59Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 30 | `115-lean-progress.md` • milestone-1 • `2026-08-01T12:30:58Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 31 | `115-lean-progress.md` • milestone-1 • `2026-08-01T12:35:24Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 32 | `115-lean-progress.md` • milestone-3 • `2026-08-01T12:50:15Z` | `m3/test` | attempt | unmeasured | changed | — |
| 33 | `115-lean-progress.md` • milestone-4 • `2026-08-01T13:06:50Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 34 | `141-lean-progress.md` • milestone-1 • `2026-08-19T22:15:07Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 35 | `141-lean-progress.md` • milestone-5 • `2026-08-19T23:33:50Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 36 | `141-lean-progress.md` • milestone-5 • `2026-08-19T23:37:06Z` | `m5/identity-stamp` | attempt | unmeasured | unchanged | — |
| 37 | `149-lean-progress.md` • milestone-1 • `2026-08-01T11:16:29Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 38 | `149-lean-progress.md` • milestone-1 • `2026-08-01T11:24:48Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 39 | `149-lean-progress.md` • milestone-3 • `2026-08-01T11:49:04Z` | `m3/test` | attempt | unmeasured | changed | — |
| 40 | `149-lean-progress.md` • milestone-3 • `2026-08-01T11:56:49Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 41 | `149-lean-progress.md` • milestone-4 • `2026-08-01T12:09:42Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 42 | `207-lean-progress.md` • milestone-1 • `2026-08-01T11:16:24Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 43 | `207-lean-progress.md` • milestone-4 • `2026-08-01T11:36:40Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 44 | `207-lean-progress.md` • milestone-5 • `2026-08-01T12:11:13Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 45 | `228-lean-progress.md` • milestone-1 • `2026-08-01T17:47:16Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 46 | `228-lean-progress.md` • milestone-1 • `2026-08-01T17:56:30Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 47 | `228-lean-progress.md` • milestone-4 • `2026-08-01T18:03:12Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 48 | `228-lean-progress.md` • milestone-4 • `2026-08-01T18:10:53Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | yes |
| 49 | `228-lean-progress.md` • milestone-4 • `2026-08-01T18:58:43Z` | `m4/verdict-not-approve` | attempt | unmeasured | changed | — |
| 50 | `229-lean-progress.md` • milestone-1 • `2026-08-01T11:15:26Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 51 | `229-lean-progress.md` • milestone-5 • `2026-08-01T11:50:16Z` | `m5/exit-artifacts:no-open-pr` | attempt | no-response | unchanged | — |
| 52 | `237-lean-progress.md` • milestone-1 • `2026-08-01T10:19:15Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 53 | `237-lean-progress.md` • milestone-1 • `2026-08-01T10:25:58Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 54 | `237-lean-progress.md` • milestone-1 • `2026-08-01T10:26:13Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 55 | `237-lean-progress.md` • milestone-3 • `2026-08-01T11:07:19Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 56 | `237-lean-progress.md` • milestone-4 • `2026-08-01T11:15:35Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 57 | `237-lean-progress.md` • milestone-5 • `2026-08-01T12:07:16Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 58 | `237-lean-progress.md` • milestone-5 • `2026-08-01T12:08:01Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 59 | `247-lean-progress.md` • milestone-1 • `2026-08-01T11:03:48Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 60 | `247-lean-progress.md` • milestone-1 • `2026-08-01T11:05:52Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 61 | `247-lean-progress.md` • milestone-4 • `2026-08-01T11:22:09Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 62 | `247-lean-progress.md` • milestone-5 • `2026-08-01T11:37:33Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 63 | `271-lean-progress.md` • milestone-1 • `2026-08-01T17:48:17Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 64 | `271-lean-progress.md` • milestone-1 • `2026-08-01T17:50:56Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 65 | `271-lean-progress.md` • milestone-4 • `2026-08-01T17:57:48Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 66 | `271-lean-progress.md` • milestone-5 • `2026-08-01T18:12:05Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 67 | `277-lean-progress.md` • milestone-1 • `2026-08-01T10:18:35Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 68 | `277-lean-progress.md` • milestone-4 • `2026-08-01T10:54:51Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 69 | `277-lean-progress.md` • milestone-4 • `2026-08-01T11:18:14Z` | `m4/verdict-not-approve` | attempt | unmeasured | changed | — |
| 70 | `277-lean-progress.md` • milestone-5 • `2026-08-01T11:19:04Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 71 | `283-lean-progress.md` • milestone-1 • `2026-07-31T22:26:51Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 72 | `283-lean-progress.md` • milestone-4 • `2026-07-31T22:52:55Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 73 | `283-lean-progress.md` • milestone-5 • `2026-07-31T23:14:16Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 74 | `289-lean-progress.md` • milestone-1 • `2026-08-10T22:10:45Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 75 | `297-lean-progress.md` • milestone-1 • `2026-08-10T22:10:49Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 76 | `298-lean-progress.md` • milestone-1 • `2026-08-10T22:13:22Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 77 | `299-lean-progress.md` • milestone-1 • `2026-08-01T10:18:04Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 78 | `299-lean-progress.md` • milestone-4 • `2026-08-01T10:57:41Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 79 | `299-lean-progress.md` • milestone-5 • `2026-08-01T11:04:03Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 80 | `306-lean-progress.md` • milestone-1 • `2026-08-01T10:17:23Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 81 | `306-lean-progress.md` • milestone-4 • `2026-08-01T10:27:47Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 82 | `306-lean-progress.md` • milestone-5 • `2026-08-01T10:36:54Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 83 | `344-lean-progress.md` • milestone-1 • `2026-08-02T12:00:07Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 84 | `344-lean-progress.md` • milestone-4 • `2026-08-02T12:17:34Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | — |
| 85 | `344-lean-progress.md` • milestone-4 • `2026-08-02T12:27:52Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | yes |
| 86 | `344-lean-progress.md` • milestone-4 • `2026-08-02T12:47:34Z` | `m4/verdict-absent` | attempt | unmeasured | unchanged | yes |
| 87 | `344-lean-progress.md` • milestone-5 • `2026-08-02T13:16:58Z` | `m5/exit-artifacts:no-open-pr` | attempt | unmeasured | unchanged | — |
| 88 | `344-lean-progress.md` • milestone-5 • `2026-08-02T13:19:45Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 89 | `348-lean-progress.md` • milestone-1 • `2026-08-16T20:52:08Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 90 | `348-lean-progress.md` • milestone-1 • `2026-08-16T20:57:38Z` | `m1/pause-and-ask` | attempt | unmeasured | undetermined | — |
| 91 | `348-lean-progress.md` • milestone-1 • `2026-08-16T22:38:17Z` | `m1/pause-and-ask` | attempt | unmeasured | undetermined | yes |
| 92 | `348-lean-progress.md` • milestone-3 • `2026-08-16T22:47:23Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 93 | `351-lean-progress.md` • milestone-1 • `2026-08-19T15:24:12Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 94 | `351-lean-progress.md` • milestone-1 • `2026-08-19T15:53:53Z` | `m1/spec-absent` | absent | unmeasured | unchanged | yes |
| 95 | `397-lean-progress.md` • milestone-1 • `2026-08-10T22:24:38Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 96 | `397-lean-progress.md` • milestone-3 • `2026-08-10T23:02:00Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 97 | `426-lean-progress.md` • milestone-1 • `2026-08-09T21:57:46Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 98 | `426-lean-progress.md` • milestone-1 • `2026-08-09T22:00:19Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 99 | `427-lean-progress.md` • milestone-1 • `2026-08-09T22:00:59Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 100 | `427-lean-progress.md` • milestone-3 • `2026-08-09T23:25:24Z` | `m3/extra-lane` | attempt | no-response | changed | — |
| 101 | `432-lean-progress.md` • milestone-1 • `2026-08-09T10:56:32Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 102 | `432-lean-progress.md` • milestone-3 • `2026-08-09T12:09:11Z` | `m3/test` | attempt | unmeasured | changed | — |
| 103 | `432-lean-progress.md` • milestone-3 • `2026-08-09T12:37:31Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 104 | `432-lean-progress.md` • milestone-3 • `2026-08-09T13:04:32Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 105 | `439-lean-progress.md` • milestone-1 • `2026-08-09T10:55:32Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 106 | `439-lean-progress.md` • milestone-3 • `2026-08-09T11:50:20Z` | `m3/test` | attempt | unmeasured | changed | — |
| 107 | `439-lean-progress.md` • milestone-4 • `2026-08-09T12:57:35Z` | `m4/verdict-absent` | attempt | content-moved | unchanged | — |
| 108 | `439-lean-progress.md` • milestone-3 • `2026-08-09T14:07:12Z` | `m3/test` | attempt | no-response | changed | — |
| 109 | `440-lean-progress.md` • milestone-1 • `2026-08-09T10:58:31Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 110 | `440-lean-progress.md` • milestone-3 • `2026-08-09T12:00:13Z` | `m3/test` | attempt | unmeasured | changed | — |
| 111 | `440-lean-progress.md` • milestone-3 • `2026-08-09T13:08:18Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 112 | `441-lean-progress.md` • milestone-1 • `2026-08-09T11:23:43Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 113 | `441-lean-progress.md` • milestone-1 • `2026-08-09T11:27:32Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 114 | `441-lean-progress.md` • milestone-3 • `2026-08-09T12:10:09Z` | `m3/test` | attempt | unmeasured | changed | — |
| 115 | `441-lean-progress.md` • milestone-3 • `2026-08-09T12:41:38Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 116 | `441-lean-progress.md` • milestone-3 • `2026-08-09T13:07:41Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 117 | `442-lean-progress.md` • milestone-1 • `2026-08-09T10:54:38Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 118 | `442-lean-progress.md` • milestone-3 • `2026-08-09T12:37:37Z` | `m3/test` | attempt | no-response | changed | — |
| 119 | `442-lean-progress.md` • milestone-3 • `2026-08-09T13:10:04Z` | `m3/test` | attempt | no-response | changed | yes |
| 120 | `443-lean-progress.md` • milestone-1 • `2026-08-09T10:37:40Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 121 | `443-lean-progress.md` • milestone-3 • `2026-08-09T11:17:20Z` | `m3/test` | attempt | unmeasured | changed | — |
| 122 | `444-lean-progress.md` • milestone-1 • `2026-08-09T10:37:36Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 123 | `445-lean-progress.md` • milestone-1 • `2026-08-09T23:11:19Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 124 | `446-lean-progress.md` • milestone-1 • `2026-08-09T10:59:21Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 125 | `446-lean-progress.md` • milestone-3 • `2026-08-09T12:45:11Z` | `m3/test` | attempt | unmeasured | changed | — |
| 126 | `446-lean-progress.md` • milestone-3 • `2026-08-09T13:08:42Z` | `m3/test` | attempt | unmeasured | changed | yes |
| 127 | `447-lean-progress.md` • milestone-1 • `2026-08-09T10:51:37Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 128 | `447-lean-progress.md` • milestone-3 • `2026-08-09T12:00:37Z` | `m3/test` | attempt | no-response | changed | — |
| 129 | `448-lean-progress.md` • milestone-1 • `2026-08-09T13:46:52Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 130 | `448-lean-progress.md` • milestone-1 • `2026-08-09T13:53:01Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | yes |
| 131 | `449-lean-progress.md` • milestone-1 • `2026-08-09T21:53:24Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 132 | `450-lean-progress.md` • milestone-1 • `2026-08-09T21:53:35Z` | `m1/spec-absent` | attempt | unmeasured | unchanged | — |
| 133 | `503-lean-progress.md` • milestone-1 • `2026-08-11T20:57:16Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 134 | `517-lean-progress.md` • milestone-1 • `2026-08-18T21:11:10Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 135 | `517-lean-progress.md` • milestone-5 • `2026-08-18T23:10:41Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 136 | `517-lean-progress.md` • milestone-5 • `2026-08-18T23:11:47Z` | `m5/identity-stamp` | attempt | unmeasured | unchanged | — |
| 137 | `530-lean-progress.md` • milestone-1 • `2026-08-16T16:30:57Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 138 | `530-lean-progress.md` • milestone-3 • `2026-08-16T16:51:40Z` | `m3/test` | attempt | unmeasured | changed | — |
| 139 | `530-lean-progress.md` • milestone-3 • `2026-08-16T17:34:12Z` | `m3/test` | attempt | unmeasured | changed | — |
| 140 | `530-lean-progress.md` • milestone-3 • `2026-08-16T18:53:48Z` | `m3/test` | attempt | no-response | changed | — |
| 141 | `533-lean-progress.md` • milestone-1 • `2026-08-16T16:29:54Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 142 | `533-lean-progress.md` • milestone-5 • `2026-08-16T17:41:10Z` | `m5/exit-artifacts:no-open-pr` | attempt | no-response | unchanged | — |
| 143 | `542-lean-progress.md` • milestone-1 • `2026-08-17T21:17:24Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 144 | `542-lean-progress.md` • milestone-3 • `2026-08-17T21:34:34Z` | `m3/test` | attempt | unmeasured | changed | — |
| 145 | `542-lean-progress.md` • milestone-3 • `2026-08-17T21:41:38Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 146 | `542-lean-progress.md` • milestone-3 • `2026-08-17T21:49:36Z` | `m3/extra-lane` | attempt | unmeasured | changed | yes |
| 147 | `542-lean-progress.md` • milestone-5 • `2026-08-17T22:13:01Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 148 | `549-lean-progress.md` • milestone-1 • `2026-08-16T18:54:41Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 149 | `549-lean-progress.md` • milestone-5 • `2026-08-16T20:52:57Z` | `m5/exit-artifacts:no-open-pr` | attempt | no-response | unchanged | — |
| 150 | `552-lean-progress.md` • milestone-1 • `2026-08-16T19:10:30Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 151 | `562-lean-progress.md` • milestone-1 • `2026-08-17T21:05:27Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 152 | `563-lean-progress.md` • milestone-1 • `2026-08-18T16:37:14Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 153 | `563-lean-progress.md` • milestone-1 • `2026-08-18T17:00:36Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 154 | `565-lean-progress.md` • milestone-1 • `2026-08-19T22:46:11Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 155 | `565-lean-progress.md` • milestone-3 • `2026-08-19T23:11:17Z` | `m3/test` | attempt | unmeasured | changed | — |
| 156 | `565-lean-progress.md` • milestone-3 • `2026-08-19T23:19:55Z` | `m3/extra-lane` | attempt | unmeasured | changed | — |
| 157 | `566-lean-progress.md` • milestone-1 • `2026-08-20T19:45:06Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 158 | `566-lean-progress.md` • milestone-1 • `2026-08-20T19:46:37Z` | `m1/preflight-reconcile` | attempt | unmeasured | undetermined | — |
| 159 | `566-lean-progress.md` • milestone-3 • `2026-08-20T20:32:32Z` | `m3/test` | attempt | unmeasured | changed | — |
| 160 | `566-lean-progress.md` • milestone-4 • `2026-08-21T11:50:48Z` | `m4/verdict-not-approve` | attempt | content-moved | changed | — |
| 161 | `569-lean-progress.md` • milestone-1 • `2026-08-17T18:46:38Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 162 | `574-lean-progress.md` • milestone-1 • `2026-08-18T16:53:59Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 163 | `574-lean-progress.md` • milestone-3 • `2026-08-18T17:47:32Z` | `m3/test` | attempt | unmeasured | changed | — |
| 164 | `575-lean-progress.md` • milestone-1 • `2026-08-19T22:46:20Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 165 | `575-lean-progress.md` • milestone-5 • `2026-08-19T23:31:55Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 166 | `575-lean-progress.md` • milestone-5 • `2026-08-19T23:32:35Z` | `m5/identity-stamp` | attempt | unmeasured | unchanged | — |
| 167 | `579-lean-progress.md` • milestone-1 • `2026-08-18T19:59:51Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 168 | `580-lean-progress.md` • milestone-1 • `2026-08-19T15:24:53Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 169 | `581-lean-progress.md` • milestone-1 • `2026-08-19T22:50:34Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 170 | `582-lean-progress.md` • milestone-1 • `2026-08-19T22:08:50Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 171 | `583-lean-progress.md` • milestone-1 • `2026-08-18T21:35:44Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 172 | `583-lean-progress.md` • milestone-3 • `2026-08-18T22:36:53Z` | `m3/test` | attempt | unmeasured | changed | — |
| 173 | `583-lean-progress.md` • milestone-3 • `2026-08-19T16:41:45Z` | `m3/test` | attempt | unmeasured | changed | — |
| 174 | `583-lean-progress.md` • milestone-5 • `2026-08-19T21:42:10Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 175 | `585-lean-progress.md` • milestone-1 • `2026-08-18T18:34:26Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 176 | `585-lean-progress.md` • milestone-1 • `2026-08-18T18:37:45Z` | `m1/pause-and-ask` | attempt | unmeasured | undetermined | — |
| 177 | `585-lean-progress.md` • milestone-5 • `2026-08-18T21:08:48Z` | `m5/verdict-reference:closing-comment` | attempt | unmeasured | unchanged | — |
| 178 | `597-lean-progress.md` • milestone-1 • `2026-08-19T22:41:07Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 179 | `597-lean-progress.md` • milestone-1 • `2026-08-19T22:46:51Z` | `m1/preflight-reconcile` | attempt | unmeasured | undetermined | — |
| 180 | `597-lean-progress.md` • milestone-1 • `2026-08-19T22:47:24Z` | `m1/ledger-lint` | attempt | unmeasured | undetermined | — |
| 181 | `597-lean-progress.md` • milestone-4 • `2026-08-20T15:30:58Z` | `m4/verdict-not-approve` | attempt | content-moved | changed | — |
| 182 | `604-lean-progress.md` • milestone-1 • `2026-08-20T15:45:01Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 183 | `636-lean-progress.md` • milestone-1 • `2026-08-23T19:00:20Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 184 | `641-lean-progress.md` • milestone-1 • `2026-08-22T15:22:33Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 185 | `641-lean-progress.md` • milestone-1 • `2026-08-22T15:31:05Z` | `m1/ledger-lint` | attempt | unmeasured | undetermined | — |
| 186 | `641-lean-progress.md` • milestone-5 • `2026-08-23T11:27:53Z` | `m5/exit-artifacts:no-open-pr` | attempt | no-response | unchanged | — |
| 187 | `643-lean-progress.md` • milestone-1 • `2026-08-23T11:49:13Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 188 | `643-lean-progress.md` • milestone-1 • `2026-08-23T11:51:15Z` | `m1/ledger-lint` | attempt | unmeasured | undetermined | — |
| 189 | `647-lean-progress.md` • milestone-1 • `2026-08-23T21:56:25Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |
| 190 | `647-lean-progress.md` • milestone-1 • `2026-08-23T22:00:43Z` | `m1/ledger-lint` | attempt | unmeasured | undetermined | — |
| 191 | `647-lean-progress.md` • milestone-3 • `2026-08-24T09:22:10Z` | `m3/test` | attempt | unmeasured | changed | — |
| 192 | `650-lean-progress.md` • milestone-1 • `2026-08-23T15:37:22Z` | `m1/spec-absent` | absent | unmeasured | unchanged | — |

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
| 1 | `m1/spec-absent` | 83 | 83 | — | 2 (31/83) | 18062 (31/83) |
| 2 | `m4/verdict-absent` | 24 | 24 | — | — | — |
| 3 | `m5/exit-artifacts:no-open-pr` | 17 | 17 | — | 2 (2/17) | — |
| 4 | `m5/verdict-reference:closing-comment` | 8 | 8 | — | 6 (6/8) | 457 (6/8) |
| 5 | `m5/identity-stamp` | 3 | 3 | — | 4 (3/3) | 1146 (3/3) |

### Never fired

Declared decision points with zero firings across the corpus. A point that never fired is a
different finding from one that fires and changes nothing, so the two are not merged.

| gate point | ms | obligation |
| --- | --- | --- |
| `m1/spec-no-ac` | 1 | — |
| `m1/design-form` | 1 | — |
| `m2/frozen-files` | 2 | — |
| `m2/changelog-trailer` | 2 | — |
| `m3/lint` | 3 | — |
| `m3/typecheck` | 3 | — |
| `m3/setup-lane` | 3 | — |
| `m3/no-verify-lane` | 3 | — |
| `m3/design-render` | 3 | — |
| `m4/verdict-keys` | 4 | — |
| `m4/verdict-uncommitted` | 4 | — |
| `m4/identity` | 4 | — |
| `m4/chain-break` | 4 | — |
| `m4/patch-stale` | 4 | — |
| `m4/fidelity` | 4 | — |
| `m5/progress-current` | 5 | — |
| `m5/exit-artifacts:draft` | 5 | `exit-artifacts` |
| `m5/exit-artifacts:closes` | 5 | `exit-artifacts` |
| `m5/exit-artifacts:spec-link` | 5 | `exit-artifacts` |
| `m5/verdict-reference:body-ref` | 5 | `verdict-reference` |

### Earn-your-keep

Points carrying at least one firing adjudicated as changing what shipped, with the dated
incident that earns the block.

| gate point | first decision-changing firing | adjudication row | what changed |
| --- | --- | --- | --- |
| `m3/test` | `2026-08-01T13:20:11Z` | `m3/test` | a red selftest sweep; the remedy is a source or fixture edit, and 528 took three of them across four sessions |
| `m3/extra-lane` | `2026-08-01T11:56:49Z` | `m3/extra-lane` | a red mutation sweep; the remedy is a strengthened guard or an accepted baseline row, and both land in the diff |
| `m4/verdict-not-approve` | `2026-08-01T18:58:43Z` | `m4/verdict-not-approve` | round 3 blockers on that run; the committed verdict record reaches four rounds and its final round boundary moves the reviewed patch id |

### False reds — lower bound

Counts only firings a committed record explicitly contradicts. It is a floor, not an
estimate: a refusal nothing committed speaks to is absent from this table rather than
assumed correct.

| gate point | firings | first | adjudication row | contradicted by |
| --- | --- | --- | --- | --- |
| — | — | — | — | — |

**Lower bound: 0 firings.**

### Repeat firings — upper bound

The same point re-firing with no intervening evaluation of another milestone and no session
change. An over-count by construction: a reaped call that never concluded and an idempotent
re-invocation both land here, and neither is a second independent refusal.

| gate point | repeat firings | of total |
| --- | --- | --- |
| `m1/spec-absent` | 14 | 83 |
| `m1/pause-and-ask` | 1 | 3 |
| `m3/test` | 11 | 36 |
| `m3/extra-lane` | 1 | 8 |
| `m4/verdict-absent` | 4 | 24 |
| `m5/exit-artifacts:no-open-pr` | 1 | 17 |

**Upper bound: 32 firings.**

<!-- END GENERATED: gate-ablation -->
