# Spec — #449 · onboard names the benefit for every unadopted capability, and forces a disposition

Trigger 1 of the grill posture deferred out of #441: **an optional key is absent and the repo
plausibly wants it, so onboard names what you get for it and forces a disposition rather than
defaulting silently.**

Binding input: `.claude/pipeline-state/449-ledger.md` (D-1 … D-10, OR-1 … OR-3). Where this
spec and the issue body disagree, the ledger wins and this spec follows it.

## What #441 already shipped, and what this adds

`config-grill.sh` emits `{ findings: [], notEvaluated: [] }` and suppresses waived checks
inside itself; doctor renders a finding as a FAIL and a `notEvaluated` entry as a note;
onboard renders findings as blocking lines and gates acceptance on "no unwaived findings".

Trigger 1 does not fit either array. A finding is a **defect** — doctor's FAIL severity is
"only coherent because waivers exist". An unadopted optional key is a **default**, and routing
it through `findings[]` makes every long-onboarded consumer go non-zero forever for
capabilities most will never want. A `notEvaluated` entry is the other extreme: it carries no
proposal and cannot be waived, so it can never force a disposition. Hence a third array.

## Non-goals

- **No schema change and no `configVersion` bump** (D-8). `grillWaivers` already accepts
  arbitrary check ids, and `stageWorkflows` / `implementDelegates` / `planGates` are already
  schema keys. No migration doc.
- **No new `AskUserQuestion` item** (D-2). Onboard's "at most one batch" rule and its "a diff
  review of a 90%-correct document, not a wizard" framing stand unamended.
- **No tree-shape predicate** (D-5). Deriving "this repo wants `implementDelegates`" from
  `db/migrations/**` would mint evidence the repo never gave, which `docs/extending.md` §1
  forbids.

## Acceptance criteria

**AC-1 — `config-grill.sh` grows a third output array.** The emitted document is
`{ findings: [...], notEvaluated: [...], unadopted: [...] }`. `unadopted` is present and empty
when nothing fires — never absent, so a caller can read it unconditionally. Each entry carries
the same four fields as a finding (`id`, `key`, `evidence`, `proposal`), unlike a
`notEvaluated` entry, which has no proposal by contract. The script still exits 0 whenever it
ran, and 3 on usage/IO error. (D-1, D-7)

**AC-2 — one unconditional check over the three never-elicited extension points.** A single
check, id `T1.extension-points`, fires into `unadopted[]` when **all three** of top-level
`stageWorkflows`, `implementDelegates` and `planGates` are absent or null, and is **silent as
soon as any one of them is set** — a config that already uses one of the seams proves the
human knows the family exists (D-5, OR-2). It is otherwise unconditional: there is no
mechanical predicate for "this repo plausibly wants it", and absence is the normal state of an
optional key. Its `evidence` states which keys are absent; its `proposal` **names all three
keys and what each one buys**, and ends with the same waiver hint every other check emits.
(D-2, D-5, D-6)

**AC-3 — the entry is waivable, and suppression lives in the checker.** A `grillWaivers` entry
keyed `T1.extension-points` suppresses it, in the same place and by the same mechanism that
suppresses a finding, so both callers suppress identically. The id carries **no repo id**: all
three keys are top-level and have no per-repo form, so a repo-scoped id would be a lie about
the check's scope. (D-3, D-6, D-7)

**AC-4 — doctor renders `unadopted[]` as a note and never moves the exit code.** Each entry
prints with its id, evidence and proposal, on the same informational channel as a
`notEvaluated` entry. A repo whose only grill output is an unadopted entry reaches
`summary: 0 failed check(s)` and exits 0. This is the severity split D-1 turns on: adopting or
waiving is a *disposition*, and a note is what forces one without breaking every already-green
consumer on the first run after this ships (OR-1). (D-1)

**AC-5 — onboard renders `unadopted[]` as blocking lines and folds it into the accept
predicate.** On the accept-or-edit screen an unadopted entry renders exactly as a finding does
— evidence, then proposal verbatim — and the accept predicate becomes "no unwaived findings
**and no unwaived unadopted entries**". Disposition is captured by the human editing the
screen they are already editing: adopting the key, or typing the `grillWaivers` entry. Onboard
must still never author or propose a waiver reason. (D-1, D-2, D-3)

**AC-6 — the five already-elicited capabilities gain benefit copy on their existing
questions.** In `plugins/second-shift/skills/onboard/SKILL.md`, questions 4 (gates/mutation),
5 (design provider + `liveRender`), 6 (reviewer deltas), 8 (the `review-context.md` scaffold
offer) and 9 (the CI-workflow offer) each gain a **one-clause statement of what the consumer
gets**, plus a pointer to the document that owns the worked example — never a restated
paragraph. No new detection and no new question: today they ask *whether* you want the key and
never *what you get* for it, and a bare key name motivates nobody. (D-2, D-4)

**AC-7 — the prose↔docs coupling is recorded as DROPPED, not left forgotten.** The AC-6
clauses summarize text that `docs/extending.md` and `docs/extension-points.md` own, and
nothing can fail when a summary drifts from what it summarizes — grepping a literal out of a
markdown file asserts only that prose contains words. `scripts/lockstep-manifest.tsv` gains a
**DROPPED** entry stating the coupling, why no anchored pair expresses it, and what to revisit
it on. (D-4, OR-3, CLAUDE.md "no prose-presence guards")

**AC-8 — behavioral guards, per the CLAUDE.md tier map.**
`plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh` gains cases proving:
the check fires when all three keys are absent; it is **silent** when any one of the three is
set (one case per key, so a predicate that hard-codes a single key cannot pass); a
`grillWaivers` entry suppresses it; the entry never leaks into `findings[]`; and `unadopted[]`
is present-and-empty on a config that has adopted a seam.
`plugins/second-shift/skills/doctor/tools/doctor-selftest.sh` gains a case proving an
`unadopted[]` entry prints as a note **and leaves the exit code at 0** — the pairing is the
whole of AC-4, and a text-only assertion would pass on a FAIL. (D-9)

**AC-9 — the mutation register is re-keyed in this diff.** This work edits guards
(`config-grill.sh`, `doctor.sh`). Any re-keyed generic survivor ordinals for those files are
re-baselined in `tools/mutation-baseline.tsv`, and any `tools/mutation-catalog.tsv` row
addressing either file is re-anchored, in this same diff. (ledger "Obligations")

## Design

Design: none — no user-facing rendered surface. The change is a CLI checker's JSON envelope,
two callers' terminal output, and skill/doc prose. `design.provider` is not configured in this
repo's `.claude/second-shift.config.json`.

## Decomposition

One slice (D-10). The tool change, its two callers' rendering, the SKILL benefit clauses and
the lockstep entry are one mechanism; the prose half has no guardable deliverable apart from
the code that makes it true, so splitting it produces a slice nothing can test.
