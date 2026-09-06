# Skill-vs-bare-session ablation — addendum 2: the `review-lead`-loaded re-measurement of U-5 and R-3

**This file EXTENDS the frozen protocol and [`docs/skill-ablation-addendum.md`](skill-ablation-addendum.md);
it amends neither.** Registered 2026-09-07, before any run of the arm it governs exists. Where a
frozen rule or an addendum-1 rule already governs, **that rule wins**, and this file mirrors it
verbatim rather than restating it loosely.

Addendum 1's own preamble fixes where this belongs: *"New rules go in new files; this is the first
of them."* This is the second. The ordering stays checkable:

```bash
git log --oneline -- docs/skill-ablation-pre-registration.md   # exactly one commit, first
git log --oneline -- docs/skill-ablation-addendum.md           # addendum 1, later
git log --oneline -- docs/skill-ablation-addendum-2.md         # this file, later still
```

## Why this exists

Arm 2b (#748) registered one confound in advance and stated it plainly: **`review-lead` is not
loaded in any arm, including the control.** U-5 names `review-lead` as the Review step's
implementation, so a unit that matters only by routing to it reads as `no-effect` under a harness
that never loads it. #807 extended that bound to R-3, which is exposed by the mirror-image
mechanism: `plugins/review-toolkit/skills/review-lead/SKILL.md:533` defers to R-3 by name as *"the
caller's inheritance contract"*, so a unit that matters only by being **read by** `review-lead` is
equally invisible.

Executing arm 2b's cut list (#800) therefore kept both units on an inherited caveat rather than a
measurement. This arm supplies the measurement.

It is registered in a new file rather than as an edit to addendum 1 for the reason addendum 1 gives
for its own existence: a construction or a rubric fixed *after* results exist is a post-hoc rubric.
Addendum 1's arms have run; editing it now would make its "no results" claim unreadable.

## What this file must never contain

**No results, and no arm output.** Every number below is a *pin* — a commit, a line range, a path, a
replicate count — or a *threshold fixed before the arm runs*. None is an outcome.

A few measured facts appear, and every one of them is about the **apparatus** rather than about
anything an arm found. Each is labelled, dated, and re-runnable from the command printed beside it.

## The construction — one variable moves

Arm 2b's §C harness is kept **verbatim**: a one-shot piped prompt in a throwaway clone detached at
`cfba102`, `--setting-sources ''`, `--model opus`, `--output-format stream-json --verbose`, the
registered `env -u` scrub, nothing committed, no gate called. The prompt assembly is unchanged —
the ablated SKILL text, then [`c2-review/prompt-template.txt`](plans/skill-ablation/c2-review/prompt-template.txt)
verbatim, then the pinned diff `dfd68a47..cfba1022`.

**The single addition is `--plugin-dir plugins/review-toolkit`.**

`review-lead` is thereby **discoverable, not pre-read**. That distinction is what makes U-5
measurable at all: U-5 is the only text in the pinned `review-lean` that names `review-lead`, so
ablating U-5 removes the routing and the session must find the skill or not. Pre-reading it into
the prompt would deliver the implementation to every arm and destroy the contrast.

*Apparatus fact, measured 2026-09-07 on CLI 2.1.263, before any run:*

```bash
claude -p --setting-sources '' --plugin-dir plugins/review-toolkit \
  'Answer exactly two lines: REVIEWLEAD:<yes|no> if a skill named review-lead is available to you, SECONDSHIFT:<yes|no> if any dev-pipeline skill is.'
# → REVIEWLEAD:yes / SECONDSHIFT:no
```

### What the plugin brings beyond `review-lead` itself

The whole `review-toolkit` plugin loads: three skills (`review-lead`, `reviewer-baseline`,
`mutation-review`) and its agent set under `plugins/review-toolkit/agents/`. That is the **minimal
loadable unit that makes `review-lead` functional** — `review-lead` dispatches those agents, and a
trimmed plugin directory would be a fabricated artifact measuring something that does not ship.

The additional surfaces are registered here as a **bound of the construction**, not smoothed over:
this arm compares `review-lean` against `review-lean` + the review-toolkit plugin, and cannot
attribute a difference to `review-lead` alone.

### Which `review-toolkit` — the shipping one, not the clone's copy

The clone at `cfba102` carries its own `plugins/review-toolkit` on disk — that copy is why arm 2b
tracks an integrity column at all. It is **not** the one loaded. `--plugin-dir` is given an absolute
path to the **shipping** plugin: the tree at `plugins/review-toolkit` on this branch, git tree
`549b0d17683b6196028995baafeb9a60869b73d2`, copied verbatim to a scratch path so the apparatus
cannot move under the batch.

The reason is the mechanism under test. `review-lead` at `cfba102` is 446 lines and predates #730 —
it carries **no** *"The caller's inheritance contract governs"* rule, so it never reads R-3. Loading
that copy would re-create, one layer down, the exact confound this arm exists to remove: R-3 would
again be scored against an apparatus that cannot exhibit its function.

**This is still one variable.** Arm 2b loaded *no* plugin, so "which era of `review-toolkit`" had no
value there to move away from. What moves is whether the shipping `review-toolkit` is loaded at all.

Recorded as a bound rather than smoothed over: the measured `review-lean` text is pinned at
`8d5d0897` and the sample at `cfba102`, while the loaded implementation is current. The construction
is deliberately **not** era-consistent. It asks whether the pinned prose routes to the implementation
that ships — which is the question #800's two keeps turn on.

*Apparatus fact, measured 2026-09-07 on CLI 2.1.263, before any run.* The clone's own copy sitting on
disk makes this non-obvious, so it is verified rather than assumed: with a nonce inserted into a
scratch copy's `review-lead` frontmatter `description`, a session launched **from inside the clone**
under `--setting-sources ''` and `--plugin-dir <that copy>` reports the nonce back. The flag governs,
and the clone's `plugins/` is not loaded.

```bash
cd <clone at cfba102>
printf '%s' 'Without reading any file, answer in exactly one line: DESC:<the first 12 characters of the description of the review-lead skill available to you, or none>' \
  | claude -p --setting-sources '' --plugin-dir <scratch copy with the nonce>
# → DESC:NONCE7Q2X. O
```

A session's own claim about which file backs a skill is **not** evidence for this: asked for the
absolute path instead, the same construction answered with the clone's path — which the nonce
falsifies. Recorded because the cheaper probe is the one a later reader would reach for first.

## Subject pin, sample, and the two units

Identical to §C, so the scores are readable beside arm 2b's:

- **Subject:** `plugins/dev-pipeline/skills/review-lean/SKILL.md` at
  **`8d5d0897c3b57ea0d5349787edfd86c3e4ee46ff`** — 127 lines, the measured surface.
- **Sample:** C2-a — PR #654 @ `cfba102`, diff range `dfd68a47..cfba1022`.
- **Oracle:** the frozen C2-a ground-truth blocker, quoted from §C so the hit rule has a fixed
  subject: *the gate-bucket enumerator's command-position class omits keyword-preceded calls, so a
  live refusal site sits outside the denominator the guard claims is its output.*
- **Hit rule:** the frozen C2 rule verbatim — the finding names the **same mechanism and the same
  consequence**; naming the same file with a different defect is a miss
  (`docs/skill-ablation-pre-registration.md`:147-152).

| unit | lines @ `8d5d0897` | what it claims |
| --- | --- | --- |
| U-5 | 48–55 | the Review step — `review-lead` is the implementation, read prior findings, score each `AC-n`, `approve` iff no blockers, do not soften |
| R-3 | 110–114 | inheritance narrows what you READ, never what you must find; read wider whenever the delta looks misleading |

Ablating a unit means deleting exactly its line range, as in §C.

**The head text is not used.** `review-lean/SKILL.md` is 190 lines at this branch's base. Moving the
subject and the harness in the same arm would make a moved score unattributable, which is the
question this arm asks. A consequence is recorded rather than avoided: U-5's measured text was
partly superseded at head by #755's `## AC scorecard` block, so this arm measures the pinned unit,
not the unit as it now ships.

**R-4 is not re-measured.** It was cut at #800 and no longer exists at head; re-scoring a deleted
unit would produce a number with nothing to bind.

## Replicates, majority, escalation, void condition

Mirrors §C exactly. A different `n` would make this arm's scores unreadable beside arm 2b's.

| arm | runs |
| --- | --- |
| control (full unablated 127-line text) | 3 |
| U-5 ablated | 3 |
| R-3 ablated | 3 |

- **Majority rule:** an arm's result is the majority of its valid runs.
- **Escalation:** any arm whose valid runs split escalates to **n=5**, and the majority of the five
  governs. Nothing is called on a split.
- **Indeterminate:** a run that errors, is truncated, refuses, or emits no `BLOCKERS` section is
  `indeterminate`, is recorded verbatim with its failure mode, and is **re-run once**. **An arm with
  fewer than 2 valid runs is `undetermined`, and is never scored `no-effect`.** Absence of a run is
  not evidence of no effect.
- **`n` is never reduced mid-arm.** A replicate count chosen after seeing how long the runs took is
  a post-hoc rubric.

**Void condition (the finding):** if the control does not reproduce the C2-a ground-truth blocker in
**at least 2 of 3** runs, this arm is void for this construction. It exits **`no basis`**, records
that, and scores no unit. This is §C's own fallback 2 applied to the construction §C's fallback 1
names.

## Loaded is not invoked — the validity asymmetry

`--plugin-dir` makes `review-lead` available. It does not make a session use it. So each run records,
from its stream-json tool events, **whether `review-lead` was actually invoked**, and that fact is
read asymmetrically — registered now, before any run, because the asymmetry is exactly the kind of
rule that looks like special pleading if it arrives after a result:

- **Control:** invocation is what proves the construction was delivered. If **fewer than 2 of 3**
  control runs invoke `review-lead`, the arm exits **`no basis` — construction not delivered**, and
  scores nothing. A control that never reaches the implementation is arm 2b's harness with an extra
  flag, and would license nothing arm 2b did not already license.
- **Ablated arms:** non-invocation is **the mechanism under test**. U-5 is the only text naming
  `review-lead`; a U-5-ablated run that never finds it is the effect, not a fault. Non-invocation
  never voids an ablated run.

## What a `no-effect` or a `carrier` licenses

**A basis, and nothing more.** This arm removes the inherited caveat from #800's two keeps; it does
not re-open the deletion #800 declined. Both cases are registered now so neither reads as a
conclusion shaped by the result:

- A **`no-effect`** under this construction says the unit does not carry the C2-a finding *even when
  the implementation it routes to is loaded*. It does not license a cut, because #800's keeps rest
  on reasons an ablation cannot overturn: R-3's referent at `review-lead/SKILL.md:533` is unpaired by
  any `LOCKSTEP` marker, so deleting R-3 silently strands `review-lead`'s rule 5; U-5's head text
  interleaves with #755's scorecard block and #683's CI-citation rule.
- A **`carrier`** changes the report and nothing else: arm 2b's headline "No unit carries the 0.20"
  becomes scoped to the `review-lead`-absent construction, #800's keep is reinforced, and
  `c2-review/ablation-units.tsv` stays frozen.

## The coarse 18th unit — a sighting, not a score

§C's void-condition fallback 1 promotes `review-lead`-as-a-whole to a coarse 18th unit when the
control is re-run with it available. That is this construction. **It is recorded as a sighting and
explicitly not scored.**

The two controls — arm 2b's and this one — differ by one flag, but they are **4 days and two CLI
versions apart** (2.1.241 for arm 2b, 2.1.263 here), so any cross-batch difference conflates
`review-lead`'s presence with drift. §C already recorded that its own three control runs disagreed
with each other, which makes control-to-control variance a known unattributable term in this study.
A number carrying two uncontrolled sources at once is not a score. It is reported side by side with
that limitation named.

## The routing-prose rule — future-binding

Registered here, before the runs, so it cannot be a conclusion shaped by the result:

> **A unit whose function is routing to an implementation the harness does not load is
> apparatus-bound. It scores `not-reached — no basis`, never `no-effect`.**

This generalizes past U-5 and R-3, the two instances that motivated it. It applies symmetrically to
a unit that matters by being *read by* an unloaded implementation — R-3's exposure — and it binds
this arm and every future one, whatever this arm's runs return.

It is the unit-level counterpart of the rule §C already fixed for its `not-reached` class: *a
surface kept because a metric could not see it is recorded as `not-reached — no basis`, never as a
pass.* What §C did not have is a name for the case where the metric's blindness comes from the
**harness's load set** rather than from the metric's outcome variable.

**Arm 2b's `c2-review/ablation-units.tsv` stays frozen.** It is a correct description of what the
pinned run produced under the construction it names. The rule above is registered *instead of*
re-labelling that file, so no reader has to reconcile a file with its own history.

## What gets recorded regardless of outcome

Per run: rc, capture bytes, sha256, the `tools/classify-capture.sh` verdict, the `result` event
count, tool-call counts, whether `review-lead` was invoked, and arm 2b's integrity column — **the
count of tool inputs naming `review-lean`, which must be 0**, since the clone keeps `plugins/` on
disk and a session that read the unablated SKILL off disk would defeat the line-range ablation.

Also recorded: **whether `--allowedTools` restricted this batch.** #796 recorded that it did not on
CLI 2.1.241; the CLI has moved since. Nothing is changed to force parity with arm 2b's realised
condition — adding flags to reproduce an old leak would be manufacturing an apparatus rather than
measuring one — so a difference is recorded as a difference.

**Only an exit-0 `COMPLETE` capture under `tools/classify-capture.sh` is scored.** A truncated
capture read at face value is a clean negative, which is the failure that tool exists to make
impossible.

No runner script is checked in. The commands live in the evidence README, per the standing rule at
[`docs/plans/skill-ablation/README.md`](plans/skill-ablation/README.md): a checked-in script here
would owe a selftest under `CLAUDE.md`, which is machinery to measure whether there is too much
machinery.

## Where the results go

Not here. Into [`docs/skill-ablation.md`](skill-ablation.md) §2 and §5, with the raw evidence under
`docs/plans/skill-ablation/c2-review-reviewlead/` — a **sibling** of arm 2b's `c2-review/`, so no
reader can mistake a file from one construction for the other. A registration co-located with the
results it scores is not a registration.
