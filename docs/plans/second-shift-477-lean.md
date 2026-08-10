# 477 — No onboard-surfaced text names a mechanism the default lane does not execute

Consumer-facing config-grill findings and onboard elicitation prose still advertise staged-lane
mechanisms (`Stage-5 unit-test mutation gate`, `Stage-6 visual capture`) to repos that run the
default lane. Following the remediation buys a config key and zero executions. This ticket makes
the emitted text name only what the default lane runs, and installs an oracle so the class cannot
silently return.

Pre-flight receipt: `.claude/pipeline-state/477-ledger.md` (binding input). OR-2 — which config
keys retire, and the `configVersion` bump behind it — is deferred to the config-schema
assessment; every reword here must stay correct under both outcomes, so no emitted string is
allowed to depend on a key surviving.

## Acceptance criteria

- **AC-1** (oracle): no grill finding's remediation names a mechanism the default lane does not
  execute. Enforced by a universal assertion in `config-grill-selftest.sh`, not by inspection.
- **AC-3**: onboard's elicitation prose names only mechanisms the default lane executes — the
  mutation question and the `unitTestScope`/`testFile` provenance + re-onboard carry-forward
  framing both elicit the repo-carried sweep rather than the staged gate. The emitted config
  shape is unchanged.
- **AC-4**: `T4.mutation-plumbing.<repoId>` survives **id-continuously** as the
  declared-intent-without-sweep check, plus a durable advisory adoption row in `unadopted[]`;
  `T4.testfile-plumbing` and `T2.visualCaptureTriggerGlobs` are deleted; `T4.design-liverender`
  and the three `T1.extension-points` proposals survive with only their mechanism naming changed.
- **AC-8**: the AC-1 oracle enumerates every emitted-envelope string via static call-site scan,
  with a documented deny-list and no per-finding exemptions; every pinned consumer of the edited
  ids/substrings is re-pointed (grill selftest controls incl. the negative control and the
  UNwaived control, `doctor-selftest.sh`'s pinned literal and the doctor fixtures, the
  `scripts/lockstep-manifest.tsv` DROPPED entry); the sweep CLI contract is documented in
  `docs/onboarding.md`.

## Design

Design: none — the change is shell, selftest and docs text; no rendered surface, no route.

## What changes

### `config-grill.sh`

| Id | Before | After |
| --- | --- | --- |
| `T4.mutation-plumbing.<repoId>` | `gates.mutation` not `false` **and** `unitTestScope` null → "Stage 5 prints `gate OFF`" | config **declares mutation intent** (`unitTestScope` set, **or** `gates.mutation` not literal `false`) **and** `tools/mutation-sweep.sh` absent at the evaluated root |
| `T1.mutation-sweep.<repoId>` | — (new) | `unadopted[]` advisory: `commands.<repoId>.test` configured **and** the sweep absent |
| `T4.testfile-plumbing.<repoId>` | fires on `unitTestScope` set + `testFile` null | **deleted** — its obligation is inert on the default lane (`lean-gate.sh` reads neither key) |
| `T2.visualCaptureTriggerGlobs` | trigger-2 row + render-surface `DEFAULT_GLOBS`/`CANDIDATES` | **deleted** — visual capture is dropped; `extraLanes` is the consumer home, already advertised by `T1.extension-points` |
| `T4.design-liverender` | "the Stage-5 gate degrades to render-verify-unavailable" | names milestone 3's render lane; finding logic untouched |
| `T1.extension-points` | "at a chosen stage", "routes Stage-5 work", "at Stage 4" | lane-neutral mechanism naming; finding logic untouched |

Two tiers for the mutation seam, deliberately **independent** rather than mutually exclusive:
the `findings[]` red is keyed on config keys that the config-schema assessment may retire, so it
dies with them; the `unadopted[]` advisory is keyed on `commands.<repo>.test`, which does not.
They carry separate waiver ids, so a consumer disposes of both in one pass — coupling them would
mean waiving one makes the other appear, which reads as a broken tool.

Id continuity for `T4.mutation-plumbing.<repoId>` is load-bearing: `grillWaivers` keys on finding
id, so a new id silently voids every consumer's existing waiver and flips a doctor-green repo to
FAIL. The waiver's meaning ("accepted: no mutation coverage here") is continuous across the
semantic change, which is what makes keeping the id honest.

Sweep presence is evaluated at the **evaluated repo root** only, under the existing `REPO_ID`
scoping — a pair sibling is reported, never reached.

### The AC-1 oracle (`config-grill-selftest.sh`)

A lint over shell source, not a prose-presence guard. It starts at the emitting call sites
(`add_finding`, `add_unadopted`, `add_noteval`, and `t2_key`, which forwards its benefit sentence
into a proposal), captures each full statement including backslash continuations, then closes
over one-level-at-a-time variable assignments and function bodies referenced from those
statements until the corpus stops growing — that is what reaches `$ev`/`$pr`/`$mut_desc`, whose
literals live away from the call site. Comments are never captured: they legitimately describe
the other lane's runtime semantics, and a whole-file grep would ban that.

Deny-list, documented at the assertion: `[Ss]tage[ -][0-9]` and `stages/[0-9]` (staged-lane
phrasing), plus the named retired-mechanism tokens `visualCapture` / `visual capture` /
`screenshot`. No per-finding exemptions — after the rewords no correct string needs one.
`T2.webComponentGlobs` and `T2.formatGlob` are truthful under the default lane (a11y and
design-fidelity route through the review half's `review-lead`; the format lane is
lean-executed) and survive the oracle untouched.

Four controls, because an oracle that captures nothing reads exactly like an oracle that found
nothing:

1. **Closure** — every sink invocation line in the source is captured; a count mismatch fails.
2. **Sentinel** — the corpus must contain a known direct literal *and* a known indirect one
   (reached only through the variable-closure arm).
3. **Mutants** — a banned token injected at a direct emitted literal, and one injected at an
   indirect (`ev=`) literal, must each be caught.
4. **Comment immunity** — a banned token injected into a comment must NOT be caught, which pins
   the design as call-site-scoped rather than a whole-file grep.

### Re-points

`config-grill-selftest.sh` cases keyed on the deleted ids (including the trigger-2 negative
control and the waiver UNwaived control) move to surviving ids; the "fully plumbed" case gains a
fixture-carried sweep, since a plumbed config without one is now exactly what fires.
`doctor-selftest.sh`'s pinned `T4.testfile-plumbing.app` literal becomes `T4.mutation-plumbing.app`
— the same fixture (`unitTestScope` set, no sweep at the fixture root) still produces one
unwaived finding and rc=1, so the FAIL-moves-the-exit-code pairing is preserved. The two doctor
fixtures already waive `T4.mutation-plumbing.app`; their reasons are reworded to the seam.
The `scripts/lockstep-manifest.tsv` DROPPED entry drops its `triggerGlobs` restatement clause.

### Docs

`docs/onboarding.md` gains the sweep CLI contract on the consumer surface: invocation shape,
rc semantics (0 = pass, non-zero reds the green gate), absent-is-a-printed-skip, and the
deterministic / no-model-call expectation.

## Out of scope

- The parity register and its deletion guard (sibling ticket under the same parent).
- Config-key retirement (`testFile`, `unitTestScope`, `gates.mutation`,
  `stageParams.visualCapture`) and the `configVersion` bump — OR-2.
- `check-config-shadowing.sh`'s stage-file row.
- A starter/reference sweep for consumers.

**Residual, recorded not resolved:** the three `T1.extension-points` seams are executed by the
staged lane only. This ticket's ratified scope for them is naming (D-22), so their proposals are
made lane-neutral rather than deleted or re-pointed; whether the seams themselves are ported is
the parity register's subject, not a naming ticket's.

## Coordination

The sibling web-surface-gating change landed first (`main` @ `3849ef5`). Its applicability probe
now guards both trigger-2 web rows; deleting the `visualCapture` row is a mechanical reconcile —
the probe call site is untouched, only one of its two consumers goes away.
