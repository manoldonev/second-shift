# Lean spec — #346: the receipt discovers intent

Child of the block-decomposition epic (#343), predecessor #345. Makes P8/P9 mechanical:
intake stops emitting finished drafts ahead of ratified decisions, the receipt has to say
what it decided and what it deliberately left open, and a decision that surfaces during
BUILD routes back as a countable record instead of a silent choice.

## Design

### 1. The Kind axis (why a new column, not a new provenance value)

The ratification bar needs to distinguish *a decision about intent* from *a derived fact*.
Provenance alone cannot: the failure mode is a row that resolves intent while wearing a
`codebase-derived` label, so any rule keyed on provenance is circular. The receipt
therefore carries a fifth column, `Kind`, over a closed three-value enum:

| Kind | Legal provenance | Meaning |
| --- | --- | --- |
| `intent` | `user-answered`, `user-delegated` | the human resolved it |
| `fact` | `codebase-derived`, `ticket-sourced` | derived from code or a cited comment |
| `open` | `deferred` | parked, and mapped to a declared open region |

The provenance enum itself is **untouched** — this extends behavior, it does not fork the
vocabulary, so both `scripts/lockstep-manifest.tsv` provenance rows stay green by
construction.

The Kind column is **receipt-mode only**. `ledger-lint.sh` without `--receipt` keeps
requiring exactly four columns, so `plan-lint.sh`, `exitplan-ledger-gate.sh`, and every
in-plan Decision Ledger are unaffected. Blast radius is one new code path, not a schema
migration.

### 2. Open regions are receipt content

Receipt mode requires an `## Open Regions` section carrying either `| OR-n |` rows or the
explicit empty form. Each row is `| ID | Region | Disposition |` over the closed
disposition enum `pause-and-ask | reversible-default-and-flag`. Every `open`-kind ledger
row must cite an `OR-n` that the section actually declares; a dangling citation is a
violation, because an unmapped `deferred` row is exactly the silent assumption the ledger
exists to prevent.

Zero open regions is *permitted by the lint and flagged by the reviewer* — over-claimed
completeness is a judgment call about scope size, not something a script can decide.

### 3. Intent-gap record

Location, derived once and pinned like the other two lean artifacts:
`<plansDir>/<slug>-<issue>-lean-intent-gap.md`. It is suffix-distinct from `-lean.md` and
`-lean-verdict.md`, so no existing scan double-classifies it.

BUILD writes it when implementation surfaces a decision the ledger does not cover, follows
the region's declared disposition, and commits it with `ratified: no`. The operator
ratifies out-of-band (a comment on the issue — the reversible default recorded as an open
region on the issue itself); the record then carries `ratified: yes` plus the comment URL.

The refusal lives at the **merge boundary** (`scripts/check-lean-chain.sh`), not in
`lean-gate.sh`. Same D-47 posture as every other lean evidence arm: the binding check is
the model-free one the run cannot reach, and adding a second in-run copy would be
duplicate machinery, not defense in depth.

### 4. Implementability probe

A fresh-context agent (`plugins/intake-toolkit/agents/implementability-probe.md`) that
receives the spec ALONE — no interview transcript, no ledger, no orchestrator findings —
derives an implementation plan, and enumerates every point it would have to guess. It
resolves nothing: each guess-point becomes an interview question or a declared open
region. It is the *proxy* rung, added because the critic rung demonstrably is not
sufficient on its own — a pre-queue spec-review pass has approved a spec that then broke in
implementation. The run stays the oracle.

Its eval is operator-run and model-billed, so it stays out of CI — CI is model-free by
design.

## Acceptance criteria

- **AC-1** (oracle — `ledger-lint-selftest.sh`): `ledger-lint.sh --receipt` fails a receipt
  whose `intent`-kind row carries `codebase-derived`, `ticket-sourced`, or `deferred`, and
  fails an `open`-kind row citing no declared `OR-n`. It passes a receipt whose `intent`
  rows are `user-answered`/`user-delegated`, whose `fact` rows are
  `codebase-derived`/`ticket-sourced`, and whose `open` rows map to declared open regions.
  Default (non-receipt) mode is byte-for-byte unchanged in behavior — the existing suite
  stays green with no fixture edits.
- **AC-2** (oracle — `check-lean-chain-selftest.sh`): the chain gate fails an applicable PR
  carrying an intent-gap record that reads `ratified: no`, and fails one reading
  `ratified: yes` with no `ratified_by:` URL. It passes once the record is ratified with a
  cited operator comment, and is silent-free (prints a notice, never a silent pass) when no
  record exists.
- **AC-3** (proxy — operator-run eval, not CI): the probe, run against
  `plugins/intake-toolkit/evals/implementability-probe-eval/fixtures/underspecified-spec.md`
  with its seeded-gap answer key withheld, reports the seeded gaps. The result is recorded
  as an eval baseline in `BASELINE.md` and in the PR body.
- **AC-4** (critic — skill diff): `intake-interviewer` and `intake-orchestrator` carry the
  no-draft-first contract (artifacts assembled from ledger rows; propose per decision,
  dispose per decision), and `spec-reviewer`'s checklist tests discovery coverage —
  ratified-provenance share, a verification rung named per AC, open regions declared with
  dispositions, zero-open-regions-on-non-trivial-scope as a finding.
- **AC-5** (oracle — CI): both `provenance-enum` lockstep rows stay green; the generic
  mutation survivor ordinals of every guard this diff edits are checked against
  `tools/mutation-baseline.tsv` and re-baselined **if they moved**, with the site-level
  evidence recorded in the PR body either way — "no re-key needed" is a finding to
  demonstrate, not to assume; the `ledger-lint-empty-decision` catalog row stays anchored to
  a pattern that still matches.
- **AC-6** (critic): the PR carries a `Changelog:` trailer.
- **AC-7** (critic — doc scope): `interviewing-baseline` — the canonical source for the
  Decision Ledger schema — carries the Kind axis, the ratification bar, the Open Regions
  contract, and the intent-gap record schema; `run-lean`'s SKILL.md names when BUILD writes
  one and what the merge boundary does with it. Without this the canonical doc is stale the
  moment AC-1 lands.

## Open regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether an intent-gap record may carry more than one gap before re-ratification | reversible-default-and-flag |
| OR-2 | Whether the probe becomes a mandatory intake-exit dispatch or stays operator-invoked | reversible-default-and-flag |

OR-1's reversible default: one record per issue, one `ratified:` key covering it whole; a
second gap resets it to `no`. Reversible because widening to per-gap ratification is a
lint change with no artifact migration.

OR-2's reversible default: `intake-orchestrator` dispatches it on the feature/refactor
path where the spec is non-trivial, and the eval measures it before anything is made
unconditional. Reversible because making it unconditional is a prose edit at one site.
