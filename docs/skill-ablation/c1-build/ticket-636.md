# Classify every lean-lane gate as gates-llm, gates-signal or gates-process, with a coverage guard

Part of #605. The epic's **item 2**: every gate declares its bucket, and a guard fails on an
unclassified one. Routed here by #611's plan ("a classification register for gates-llm vs
gates-process; a later slice of the parent epic owns it") and by #613's out-of-scope list.

## Problem

`docs/pipeline-manifesto.md:118-135` defines the buckets in prose — `gates-llm` never yields,
`gates-process` may yield when a human is present — and #613 shipped the yield mechanism. What
does not exist is any statement of **which gate is which**. `OVERRIDE_GATES` carries two values
chosen by the slice that introduced them. Nothing says the other gates were considered, and
nothing reds when a new gate joins the lane unclassified.

Not more yielding. A **countable** classification.

## The predicate is not total — a third bucket

Walking all 33 declared decision points in `tools/gate-ablation-classes.tsv` against the ratified
binary predicate, **8 fit neither**: `m2/frozen-files`, `m2/changelog-trailer`, `m3/lint`,
`m3/typecheck`, `m3/test`, `m3/extra-lane`, `m3/setup-lane`, `m3/no-verify-lane`. A red test lane
is not a fabrication defense and is not premised on an absent human — it is an objective build
signal, and four of these are among the six points `docs/gate-ablation.md` says earn their keep.

| bucket | premise | yields when attended |
| --- | --- | --- |
| `gates-llm` | fabrication / self-approval defense | never |
| `gates-signal` | the fact is objective (a lane is red, a file is frozen) | never |
| `gates-process` | "no human is available to answer this" | may |

`gates-signal` is what makes "no gate is unclassified" satisfiable without making a red suite
operator-waivable, which forcing those 8 into `gates-process` would do.

## Architecture — the shipped precedent

`scripts/check-fail-open-shapes.sh` + `scripts/fail-open-sites.tsv` is already this shape and is
the pattern of record: an enumerator whose `--list` output **IS the denominator by definition**, a
TSV that must cover it exactly, anchors on distinctive line **text** (never line numbers), and
three independent reds — undispositioned site, anchor drift, row that outlived its site.

**Critically, that precedent's disposition column has FOUR values, not three** (`converted | safe |
out-of-scope | not-a-site`), precisely because a shape enumerator over-enumerates. This register
does the same: the three buckets **plus** `not-a-gate`, which is not a bucket and carries a
mandatory reason. Without it the closed enum has no home for the `envfail` usage/environment
refusals (`PR_HEAD_SHA is unset`, `mktemp failed`, `unknown argument`) and the success-path
`terminal … 0` calls that the shape predicate provably enumerates.

**`tools/gate-ablation-classes.tsv` is NOT the key.** It classifies recorded reason *strings* by
ERE; no gate emits its own point id; and all 33 rows are `lean-gate.sh` milestones.

## Scope — five files

`plugins/dev-pipeline/skills/build-lean/lean-gate.sh`, `scripts/check-lean-chain.sh`,
`plugins/dev-pipeline/skills/build-lean/lean-evidence.sh`,
`plugins/dev-pipeline/tools/operator-override.sh`,
`plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh`.

`lean-evidence.sh` is in scope because it is where the merge-boundary evidence checks **actually
run** — `check-lean-chain.sh:424` delegates the verdict/identity/ratification/patch-id arms to it,
and it carries the lockstep twin of `OVERRIDE_GATES`. A register claiming to cover the merge
boundary while classifying `check-lean-chain.sh`'s two `fail()` sites and delegating the rest would
be exactly the vacuous coverage this slice exists to prevent.

Out, **named as a residual**: the ~19 `scripts/`+`tools/` CI guards and the `.mjs` workflow gates.

## Acceptance Criteria

- AC-1: A register TSV declares, for every enumerated site, exactly one disposition over the
  **closed** enum `gates-llm | gates-signal | gates-process | not-a-gate`, plus a text anchor, a
  yield cell, and a `why` naming the mechanism that makes it true. An unknown value is an error. A
  `not-a-gate` row states what it is instead (environment refusal, usage error, success path).
- AC-2: The guard enumerates from the tree by shape and exits non-zero on each of three
  disagreements **independently**: an enumerated site with no row; an anchor matching nothing
  (drift); a row covering no live site. `--list` prints the denominator and checks nothing. A
  selftest covers each arm plus the all-green arm.
- AC-3: The enumerator names **every** refusal primitive per file rather than assuming one —
  measured today: `lean-gate.sh` `fail_milestone`/`envfail`/`ticket_refuse`/`fail_obligation`/
  `block_milestone`; `check-lean-chain.sh` `note_violation` (18 sites) and `fail` (2);
  `operator-override.sh` `envfail`; `orchestrate-lean.sh` `terminal` **with a non-zero exit
  argument** (the success calls at `:764`/`:923`/`:982` are enumerated and dispositioned
  `not-a-gate`). Helper *definitions* that match their own shape are self-excluded by name, as the
  precedent does at `check-fail-open-shapes.sh:69`, and each exclusion is stated in the header —
  an unstated exclusion is a hole in the "output IS the denominator" claim.
- AC-4: Row granularity is **one row per enumerated site**, and an anchor MAY cover several sites
  (the precedent counts `hits > 0`). The guard prints the covered-site count per row so a loose
  anchor that would swallow a future refusal is visible rather than silent. A row covering zero
  sites reds as drift.
- AC-5: **The safety arm is register-internal, not code-proximity.** A `gates-llm`, `gates-signal`
  or `not-a-gate` row MUST carry an empty yield cell; a row whose yield cell names an
  `OVERRIDE_GATES` value MUST be `gates-process`. This is mechanically checkable and non-vacuous,
  and it is what stops a future edit from wiring a red test lane to an operator yield. (Proximity
  readings were rejected at intake: file-scope makes the register unsatisfiable because
  `lean-gate.sh` consults the override at all; line-scope passes vacuously because no refusal line
  mentions it.)
- AC-6: Every `gates-process` row's yield cell either names its `OVERRIDE_GATES`/`OVERRIDE_SCOPES`
  value or reads `unwired — <reason>`. The guard checks the **form**, not the existence of a
  follow-up ticket; only two yield values exist today and both are intake-side, so most
  `gates-process` rows will legitimately be `unwired`.
- AC-7: The guard runs in CI on every PR, in the always-on guard job that already runs
  `check-lockstep-pairs.sh` and `check-eval-model-identity.sh` — **not** in `pr-gates`, which
  carries a large env block this guard does not need. #610 D-9 left `prose-blockers.sh check`
  unwired because "the parent's register owns the living coverage guard"; this is that guard.
- AC-8: The header records the out-of-scope residual and every self-exclusion, so a reader can tell
  an excluded surface from a forgotten one.
- AC-9: `docs/pipeline-manifesto.md`'s bucket section gains `gates-signal` and a pointer to the
  register. Per P5 the manifesto states the principle; it does not restate the enforcement.
- AC-10: Obligations paid: a `tools/gate-ablation-classes.tsv` row per new refusal reason; new
  fail-closed branches reconciled against `scripts/fail-open-sites.tsv`; `scenario-liveness-selftest.sh`
  extended for every verdict path touched, with a non-vacuity case.

## Settled at intake — do not re-litigate

- Three buckets **plus** `not-a-gate`. The fourth value is not a bucket and does not weaken the
  classification; it is what the precedent already does and what makes the enum closable.
- AC-5 is register-internal. Both proximity readings were examined and rejected on the evidence.
- The register **adopts** the triage record's existing `path::name` enforcer key unchanged. #610 D-5
  declared it reversible; that is a licence, not an obligation, and re-keying costs a coordinated
  edit of the tool, 35 rows, the validating arm and its selftest for no stated benefit.
- Corpus is the five files above. `lean-evidence.sh`'s inclusion is not optional — it is where the
  boundary checks run.

## Open regions (BUILD flags, does not pause)

- OR-1: whether `envfail` sites are dispositioned individually or by one anchor per class.
  `reversible-default-and-flag`: default one row per class with AC-4's covered-count printing, so
  ~95 mechanical rows do not drown the register.
- OR-2: whether a `gates-process` row may be `unwired` indefinitely. `reversible-default-and-flag`,
  default yes per AC-6; the epic owns any wiring follow-up.

## Out of scope

- Demoting any gate — the epic recorded at this intake that the demotion evidence does not support
  a slice (its headline candidate is already demoted).
- The severity/impact axis and amendment governance (#622).
- Non-lane attendance reachability (#631) — a `gates-process` row whose consumer sits outside the
  lean lane cites #631 rather than pretending the path works.
- The `scripts/`+`tools/` CI guards and `.mjs` workflow gates.
- Widening the prose census to agent contracts — its own slice.

