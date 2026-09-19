# Skill-vs-bare-session ablation — addendum 3: `intake-orchestrator` and `intake-interviewer`

**This file EXTENDS the frozen protocol and addenda 1–2; it amends none of them.** Registered
2026-09-19, before any run of the arms it governs exists. Where a frozen or addendum rule already
governs, that rule wins. #672. The ordering stays checkable:

```bash
git log --oneline -- docs/skill-ablation-pre-registration.md   # first
git log --oneline -- docs/skill-ablation-addendum-3.md         # this file, before any result
git log --oneline -- docs/plans/skill-ablation/c4-intake/      # the numbers, later still
```

**No results and no arm output live here.** Every number below is a pin or a threshold.

## Why this exists

§3 of [`docs/skill-ablation.md`](skill-ablation.md) left both skills `not adjudicated`:
`intake-orchestrator` (711 lines) produces decomposition, which C3's ledger-recall metric does not
reach, and `intake-interviewer` (279 lines) was never run on its own input. Each exits here with a
measured basis or an explicit `no basis` record, in both §3 and the §4 table — never silence.

## The substrate — private, numbers-only

The roles run against the lane bench's private synthetic substrate (the app repository pinned at
`263bd4ba9f6b56bffd5a6ccbe90b4f948ced3cca`). Role bodies, gold keys and detectors live in the
private bench repository at commit `f90bd943c1d132525731caae6a004f12d0088859`, under `intake/`.
**No role text, detector, or arm output lands in this repository**; only the hashes below and the
per-gap numbers do.

| file | sha256 |
| --- | --- |
| `o1/body.md` | `062cc1711f3f46aefd18a07fcd68dc554026ec9f7b23c3380ee7eb16bb1002aa` |
| `o1/gold.tsv` | `220096c8f40a7a25cbbaff2da27bcfdea1d41e2bdb4e690b8ff403832da3b042` |
| `o2/body.md` | `3b0edbab59b6d86b881f4249dc9b422efa9e0e218818649c9365ca7e405e8e10` |
| `o2/gold.tsv` | `4278fda7346d69937c186ce1d11ddaae54ff7df7e5965ce6a36ef03c9f901247` |
| `o3/body.md` | `9f7c07759e3d802d7a7fb261c6141b284d33a2d49197dfec00a0195b1b8dc001` |
| `o3/gold.tsv` | `c5d0778d2874ba2bb4d865f968351678e481ac3f5f6cecfd4e25065c7b38d275` |
| `i1/body.md` | `303e1e7d6fa44c2329d419ee6732f3991a904048b99d328f97092890f254eaab` |
| `i1/gold.tsv` | `ed34ff73a473312a2868d8e9889e7f088abe2afcbaf07d174f17e9beb79586e4` |
| `i2/body.md` | `b4975900ef81090d01f8a59d6b998ba95c334ec290b661899316346f243033f3` |
| `i2/gold.tsv` | `2935a456790b9efce881df5137008f2cdcf99f3b5d245b6a3d3e5c6e4e0b4323` |
| `i3/body.md` | `46f69573c502b1a6795a7e5c1235dc66046075de35ba67840234e2528da392bd` |
| `i3/gold.tsv` | `27f40d9a911ae33f1ac925c6d2c28c50372e55e388fe5c7c5936741a055cfd30` |
| `run-arm.sh` | `cf51ca092ead7a7457f46159bbbe5d351756ea20e01a2f705054ae3381fe9b17` |
| `score.py` | `5cb4fbecd4dca6a37deef6509d1f12fbad7412bd2409602aa3a34c7af7482924` |
| `invoked.py` | `448805bb3cf7310debbde41944e945f26c38820097b32d23552a43ce686907ba` |

Each detector was checked before registration to have **zero hits on its own role body**
(`score.py --selfcheck`), so no arm scores by echoing the input.

## The subjects

- `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md`, 711 lines, and
  `plugins/intake-toolkit/skills/intake-interviewer/SKILL.md`, 279 lines, both last changed at
  `cafe6b2b`. The loaded trees are this branch's base: `plugins/intake-toolkit` tree
  `00c5265339fb999bbb77fcf8aadad6375416be0a`, `plugins/review-toolkit` tree
  `797f30b2ff65748aa4a09dfb0b065262d25b7b03`, copied verbatim to a scratch path before the batch.

## Construction — one one-shot session per run

Every run is a fresh clone of the substrate at its pin with its remote removed, so no tracker write
can land. The command is the frozen bare arm (`docs/skill-ablation-pre-registration.md` "The bare
arm": the `env -u` scrub, `claude -p --model opus --setting-sources ''`) with
`--output-format stream-json --verbose`, the prompt piped in.

| arm | plugin load | prompt |
| --- | --- | --- |
| kit, orchestrator | `--plugin-dir` intake-toolkit **and** review-toolkit | an instruction to invoke `intake-toolkit:intake-orchestrator` with the Skill tool, then the task, then the role body |
| bare, orchestrator | none | the task, then the role body |
| kit, interviewer | `--plugin-dir` intake-toolkit | an instruction to invoke `intake-toolkit:intake-interviewer` with the Skill tool, then the task, then the role body |
| bare, interviewer | none | the task, then the role body |

The task text is identical across arms and fixed in `run-arm.sh`. The orchestrator task ends in a
`CHILDREN` section (one line per child) and a `NOTES` section; the interviewer task ends in its
questions and an `OPEN` section.

**The kit arm loads review-toolkit too**, because the orchestrator's evidence fan-out dispatches
`spec-reviewer` and `codebase-explorer` from it: that is the minimal loadable unit that makes the
skill functional (addendum 2's rule). A difference is attributable to the kit, not to the SKILL text
alone — a bound, recorded now.

### Invocation — the delivery bar (addendum 2, "Loaded is not invoked")

Each run records, from its stream-json tool events, whether a `Skill` call naming the skill under
test occurred (`invoked.py`). **If any role's kit replicates invoke it in fewer than 2 of 3, that
skill exits `no basis — construction not delivered`** and scores nothing. A session's prose is not
evidence of invocation.

## The two metrics

### `intake-orchestrator` — coverage-gap recall (outcome metric)

Three epic roles, two planted cross-child gaps each, six in all, drawn from the ticket's three
classes and fixed before any run (the default the pre-flight named, flagged in the PR body):

| role | gaps | classes |
| --- | --- | --- |
| O1 | O1-G1, O1-G2 | between-children, no-owner follow-up |
| O2 | O2-G1, O2-G2 | between-children, no-owner follow-up |
| O3 | O3-G1, O3-G2 | vacuous child, vacuous child |

A between-children or no-owner gap is **caught** when its detector matches the run's final result
text. A vacuous-child gap is **caught** when no `CHILDREN` line matches its child detector, or its
flag detector matches the whole text — the arm either did not cut the vacuous child, or cut it and
said it was empty. Both arms are scored against the same gold, so the kit arm is admissible here,
unlike C3.

### `intake-interviewer` — ambiguity recall (proxy, labelled as one)

Three rough-request roles, two material ambiguities each, six in all. An ambiguity is **caught**
when its detector matches the run's final result text — the questions plus the `OPEN` items.

**Registered consequence: this proxy cannot license `keep`.** First-turn question recall is a step
removed from the skill's outcome (an issue-ready body after a full interview), exactly as
comparison 1's artifact-coverage proxy was. Its reachable verdicts are `cut-to-delta` and `delete`.

## Replicates, majority, thresholds

3 replicates per role per arm: 18 runs per skill, 36 in all. A gap counts for an arm when it is
caught in **2 of 3** of that role's valid runs.

**Indeterminate:** a run whose capture is not an exit-0 `COMPLETE` under `tools/classify-capture.sh`,
or whose final text lacks the required `CHILDREN` section (orchestrator), is `indeterminate`, is
recorded with its failure mode, and is re-run once. A role with fewer than 2 valid runs in an arm
is `undetermined` and contributes no gap to either arm's count; if that leaves a skill with fewer
than four scoreable gaps, it exits `no basis — sample not delivered`. `n` is never reduced mid-arm.

| skill | `keep` | `delete` | otherwise |
| --- | --- | --- | --- |
| `intake-orchestrator` | kit catches **≥ 2 more** gaps than bare | bare catches **≥ kit and all 6** | `cut-to-delta`, scoped to the gaps bare missed |
| `intake-interviewer` | unavailable (proxy) | bare catches **≥ kit and all 6** | `cut-to-delta`, scoped to the ambiguities bare missed |

The burden of proof is on the skill: absence of evidence is `cut-to-delta`, and "roughly equal, but
ours is more thorough" is a loss.

## Where the results go

Per-run numbers (rc, capture bytes, sha256, classifier verdict, invocation count, per-gap hits) go
to [`docs/plans/skill-ablation/c4-intake/`](plans/skill-ablation/c4-intake/), numbers and gap ids
only. The verdicts replace the two `not adjudicated` rows in `docs/skill-ablation.md` §3 and §4.
This slice deletes nothing; a non-empty cut is filed as a successor ticket.
