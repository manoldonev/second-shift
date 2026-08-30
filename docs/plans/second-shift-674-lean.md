# #674 — the config schema's exit-3 claim, corrected and then held to the code

**Issue:** https://github.com/manoldonev/second-shift/issues/674 (sibling of #670; both escaped
blockers from #644's bare-session measurement, PR 673 round 1, verdict `1ce1bd7`)

## Goal

`docs/config-schema.md:22-34` states the cross-repo reserved-exit-`3` contract and claims it
covers four lane families. The shipped dispatch covers one. Correct the doc, and add the guard
whose absence let the claim outlive the change — a derivation from `lean-gate.sh`'s own dispatch,
so the next lane promotion or demotion reds the doc instead of quietly outdating it.

## Measurement at head (`808aa29`)

The ticket's citation is `:22-33`; at head the bullet runs `:22-34`. Otherwise the finding
reproduces exactly.

**Doc side**, `docs/config-schema.md:23-24`:

> It applies to the fixed `lint`/`typecheck`/`test` keys and to every `extraLanes` entry (setup
> `lanes[]` are already infra-classed, and are out of it).

**Code side.** `git grep -n lane_failure_class plugins/` returns two lines in
`plugins/dev-pipeline/skills/build-lean/lean-gate.sh`: the definition at `:4115`, and one
invocation at `:4200`:

```
      typecheck) fail_milestone 3 "$key failed (rc=$rc)" "$(lane_failure_class "$rc")"; return $? ;;
```

`lint`, `test` (`:4201`, the `*)` arm) and every `extraLanes` command (`:4289`) route to
`lane_advisory` instead: since #642 they record `| milestone-3 | advisory |` and the milestone
continues, so on those lanes an exit `3` is one red among any other and classifies nothing.
Setup `lanes[]` (`:4182`) call `fail_milestone 3` with **no** class argument, taking the `${3:-1}`
default — they never reach the classifier either.

So the reserved code has exactly one live reader: `typecheck`.

**Two sibling sites, both already correct — neither is edited by this slice.**
`docs/testing.md:146` already says "Since #642 that is `typecheck` alone — `lint`, `test` and
extraLanes report without refusing", and points at `config-schema.md` as the cross-repo contract;
it was the pointer, not the pointee, that rotted. `lean-gate.sh:331-332` likewise says "since #642
that is `typecheck` alone". `docs/skill-ablation.md:176-182` is a measurement record of this very
finding and is deliberately left in its as-measured tense.

## Why the doc rotted, and what the fix has to be

Nothing coupled the sentence to the dispatch. #642 changed the dispatch, three review rounds and a
full panel read the diff, and the sentence — in a file the diff never touched — stayed true-looking.
A corrected sentence with no guard buys exactly one release of accuracy.

The `writing-tests` tier map routes "prose in a markdown file" to **nothing**, and routes "two
copies of one contract staying identical" to a `LOCKSTEP` marker. Neither fits: there is no second
verbatim copy of this paragraph to hold it to, and the thing that must not drift is not another
paragraph — it is the **caller set**, which lives in shell. What fits is the third row read
sideways: a per-tool behavioral guard whose "tool" is the dispatch itself. The doc states the
reserved set in an enumerable form; the guard derives the same set from `lean-gate.sh` and refuses
when they disagree. That is a derivation, not a prose-presence grep: it fails for a reason no
reader of the doc diff could see, because the fact it checks is in another file.

**The guard fails closed on a dispatch shape it cannot model.** A completeness guard that
recognises two shapes over three is a guard that reads as complete while being blind (the lesson
#695 round 1 paid for). So every `lane_failure_class` call site must satisfy the modelled shape —
a `case "$key"` arm label on the call's own line — and anything else (a call under a different
`case` subject, a call not in an arm at all, a glob arm, zero call sites) reds naming the line,
rather than being silently dropped from the derived set.

## Decision Ledger

No pre-flight ledger exists for #674; the rows below are this session's, all `codebase-derived`.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Lockstep marker, or a derivation guard? | Derivation. A lockstep group holds two prose copies identical; it cannot notice a `case` arm gaining `lint`. The issue offers "a lockstep **or** behavioral case"; only the behavioral one is on the axis the defect is on. | codebase-derived |
| D-2 | How does the doc state the reserved set machine-readably? | A marker-delimited nested list under the existing bullet, one row per lane family, each row carrying `**reserved**` or `**not reserved**`. Not a second declaration beside prose — the rows *are* the claim, and the surrounding prose stops enumerating lanes. | codebase-derived |
| D-3 | Repo `scripts/` or inside the plugin? | `scripts/`. The contract spans `docs/` and `plugins/dev-pipeline/`, which is `check-lockstep-pairs.sh`'s stated reason for living there. A consumer's copy of the plugin has no `docs/config-schema.md` to check. | codebase-derived |
| D-4 | Check the doc's *not*-reserved rows against the code too? | No, and the limit is stated in the guard header. `extraLanes[]` and setup `lanes[]` are config-driven families with no enumerable list in the gate; only the fixed keys are derivable, and those are covered by the completeness arm below. | codebase-derived |
| D-5 | Does the guard also assert the doc enumerates every fixed key? | Yes. `for key in lint typecheck test` is derivable, so a fourth fixed key added with no doc row reds — the arm that makes "the doc's set" a claim about the whole lane surface and not just about `typecheck`. | codebase-derived |
| D-6 | Correct the exit-3 claim at `docs/testing.md:146` and `docs/skill-ablation.md:176` too? | No — neither carries the defect. Both were re-read at head: testing.md already says "Since #642 that is `typecheck` alone", and skill-ablation.md is a dated measurement record of this very finding. (`docs/testing.md` **is** edited by this branch, under AC-7, in a different section and for a different reason.) | codebase-derived |
| D-7 | Wire the guard into CI? | Yes, `ci.yml`'s contract-checks job, beside `check-lockstep-pairs.sh`. A guard only its own selftest runs is a guard that reds after the merge it should have blocked. | codebase-derived |
| D-8 | The `writing-tests` tier map routes this class to "nothing". Leave it, or extend it? | Extend it, as AC-7 — added after milestone 1, before milestone 5. Leaving it is how the next instance of this defect gets filed instead of guarded; the map is the thing an author actually reads. | codebase-derived |
| D-9 | `mutation-sweep-pr`'s two `default` survivors (review r1 B1): baseline them as unkillable, or delete the `${…:-…}` sites? | Delete. The awk `END` block emits `sites` and `fixedsites` unconditionally with `%d` and `+ 0`, so both defaults were provably dead syntax — a baseline row would have recorded a permanent exception for a line that should not exist. Deleting also drops the sites from enumeration, so no row is owed. **This alone does not clear the lane**: at `k=2` it promotes `${verdict:-}` and `${lanes:-}` into the swept window, and both were probed surviving. D-10 is what actually kills them. | codebase-derived |
| D-10 | Review r1 W1 — four fail-closed arms no case drives: add cases, or declare them deliberately unguarded in the header? | Add cases (m)–(p). Declaring them unguarded is the wrong answer on a branch whose thesis is that an unchecked claim rots, and writing case (p) proved the arms were not merely undriven: `IFS=$'\t' read -r verdict lanes row` collapses runs of tabs (tab is IFS *whitespace*), so on the one row shape that arm exists to catch — empty middle field — the row text slid into `lanes` and the arm was structurally dead. Split positionally instead. Closing W1 is also what makes D-9's two promoted sites killable. | codebase-derived |

## Acceptance Criteria

- **AC-1 — the doc's claim matches the measured caller set.** `docs/config-schema.md`'s exit-`3`
  bullet no longer claims the reservation covers `lint`, `test` or `extraLanes`. It carries a
  marker-delimited row per lane family (`typecheck`, `lint`, `test`, `extraLanes[]`, setup
  `lanes[]`), exactly one of them marked `**reserved**`, and that one is `typecheck`.
- **AC-2 — a guard derives the reserved set from the dispatch and reds on drift.**
  `scripts/check-lane-class-doc.sh` derives, from
  `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`, the lane keys whose milestone-3 failure
  routes through `lane_failure_class`, and exits non-zero when that set differs from the doc's
  `**reserved**` rows — in either direction, naming the delta.
- **AC-3 — the guard fails closed on an unmodelled dispatch.** It reds, rather than deriving a
  smaller set, when a `lane_failure_class` call site is not a `case "$key"` arm label on the
  call's own line, when the arm label is a glob, when the enclosing `case` subject is not `$key`,
  or when there are zero call sites.
- **AC-4 — the completeness arm.** The guard derives the fixed-key list from milestone 3's
  `for key in …` loop and reds when a fixed key has no row in the doc's region.
- **AC-5 — the guard is exercised, and every refusal it implements is driven.**
  `scripts/check-lane-class-doc-selftest.sh` runs the guard green against the live tree and RED
  against a synthetic fixture for every refusal the guard can emit — not only those AC-2, AC-3 and
  AC-4 enumerate — each case asserting the exit code *and* the message that names the cause.
  *(Widened in the round-1 fix from "every refusal in AC-2, AC-3 and AC-4". The four arms outside
  that enumeration were reported as review W1; driving them found one that could not fire at all,
  which is the evidence that "outside the spec's enumeration" is not a safe place to leave an arm.)*
- **AC-6 — the guard runs at the merge boundary.** `.github/workflows/ci.yml` invokes
  `scripts/check-lane-class-doc.sh` in the same job as the other repo-level contract checks.
- **AC-7 — the route is written down.** The tier map that sent this class to "nothing" now has a
  row for it: `docs/testing.md`'s Contract tier names the guard, a subsection states the class and
  the two properties that make it safe to reuse, and the `writing-tests` skill's tier map carries
  the matching row. Without this the next author facing the same defect reads "prose in a markdown
  file → nothing" and files no guard.
- **AC-8 (critic) — `Changelog:` trailer**, and a `Guard-mass:` trailer, since the branch adds
  two guard/test scripts.
