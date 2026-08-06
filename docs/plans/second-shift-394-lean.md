# design live-render verification has no gate in the lean lane

Spec of record for issue #394. The definition of done is the `AC-n` set below.

## Problem

`design.liveRender` arms exactly one thing: the staged lane's Stage-5 live-render verify gate.
Nothing in the lean lane reads `design.*` — `lean-gate.sh` has no design awareness at all, and
`docs/live-render.md`'s "Lean-lane wiring" section tells consumers to re-arm the same render
harness as an `extraLanes` entry, which is opaque to the gate: it runs a command and reads an
exit code. No screenshot is retained, no state is named, nothing binds the evidence to a review.

A design-driven run in a consumer repo produced three failure classes this spec makes
structurally impossible in the lean lane:

1. a **non-blocking** render degrade shipped a PR carrying five real visual defects;
2. a **passing** render captured the screen's default collapsed state and so verified nothing;
3. the **design-blind** panel reviewer passed while explicitly disclaiming it could not verify
   against the design frame.

Each maps to one arm below: (1) blocking posture on the shared fix budget, (2) a spec-declared
render-state table plus a `{state}` placeholder and an identical-hash collision red, (3) a
`fidelity` verdict key scored by a design-sighted review session.

This is also the **#348 unblock**. Its merge precondition is one design-driven FE ticket green
through the full lean cycle with a fidelity verdict in the committed record. A premise
correction for #348's plan rides along: `stages/8-code-review.md:100-109` is not the only home
of fidelity-reviewer routing — review-lead's Reviewer Routing carries a config-resolved provider
map that survives the staged lane's retirement. What lean lacks is the **per-ticket guarantee**
and the **verdict field**. This issue adds both.

## Binding pre-flight input

`.claude/pipeline-state/394-ledger.md` is the intake receipt for this run and is binding
(run-lean step 4). Its ten decisions D-1..D-10 are ratified and are transcribed below where they
bear on the design; none of them contradicts the issue body, and none opens a region. The
issue's own "Open regions: none" holds: the real-renderer end-to-end proof is deliberately
deferred to #348's own merge precondition, so every new selftest case here is **stub-driven**.

## Design

Design: none — this repo declares no `design.provider`, so its own lean lane is structurally
unarmed and no handoff exists to bind. The armed path is exercised by fixtures (AC-1..AC-7).

## Files in scope

`plugins/dev-pipeline/skills/run-lean/lean-gate.sh` + `lean-gate-selftest.sh`,
`plugins/dev-pipeline/skills/run-lean/lean-reconcile.sh` (the mechanical third copy of the
parameterized header-anchored helper only), `scripts/check-lean-chain.sh` +
`check-lean-chain-selftest.sh`, `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh`,
`plugins/dev-pipeline/skills/run-lean/SKILL.md`,
`plugins/dev-pipeline/skills/review-lean/SKILL.md`,
`plugins/review-toolkit/skills/review-lead/SKILL.md`, `docs/live-render.md`,
`docs/config-schema.md`, `schema/second-shift.config.schema.json`,
`scripts/lockstep-manifest.tsv`, `tools/mutation-baseline.tsv`, `.gitignore`, and this spec.

**Deliberately NOT** `config-lint.sh` — it pins no placeholders on `design.liveRender.command`,
so `{state}` is additive and needs no lint change (and no `configVersion` migration: no new
key). **Deliberately NOT** the orchestrator, `statectl`, the a11y surface, or any tracker write.
**Deliberately NOT** `lean-reconcile.sh`'s receipt arm — a follow-up; its only edit here is the
helper copy the lockstep rows already bind.

## Arming contract (D-8)

Design-armed **iff** config `design.provider` is set **AND** the committed lean spec carries an
armed `## Design` section. The conjunction is load-bearing in both directions:

- `## Design` present with **no** configured provider arms nothing (a consumer may document a
  design intent in a repo with no design axis).
- A configured provider with **no** `## Design` section is a **milestone-1 red** — the section
  is required whenever the provider is set, so arming is a per-ticket decision made on purpose
  rather than a default nobody chose.

Two accepted section forms:

- **Armed** — a provider handoff link (shape check only; the zero-network gate never resolves
  it) plus a render-state table with ≥ 1 row:
  `| RS-n | route | state (what must be visible) | AC refs |`
- **Explicit-empty** — `Design: none — <reason>`. A conscious per-ticket disarm.

**The disarm is state-locked.** Every armed milestone-3 evaluation — pass or fail — writes an
idempotent `| milestone-3 | armed |` progress row. That row is deliberately outside the
`| attempt |` substring `attempt_count()` greps, so arming never consumes fix budget. A spec
that transitions armed → explicit-empty while that row exists reds at **milestone 1 and
milestone 3**: mid-run disarm is the one escape this design must not leave open.

## Gate placement (D-1)

No new milestone number, no separate gate, no orchestrator routing change. Armed assertions red
through `fail_milestone` and ride the existing 3-attempt / `rc=4` budget.

**Milestone 1** — the `## Design` requirement, grep-shaped like the existing `AC-n` assertion.

**Milestone 3** — when armed, a **blocking** render pass placed after `extraLanes` and before
the mutation sweep (D-2). Environmental failures red with the harness's own actionable message
on the shared budget; `readyProbe` is honored as a fast-fail, and the env prerequisites are
documented so an environmental red is cheap rather than mysterious. Specifics:

- `liveRender.cwd` naming a topology repo that is not the host of this run is a red naming the
  limitation: *run the lean lane from the repo that owns the render harness*.
- The render child runs under the existing `SEAM_SCRUB_ENV` scrub, exactly like every other
  lane command milestone 3 spawns.
- A `command` template missing `{out}` is a red. A template missing `{state}` is a red **only
  when a non-default RS row is declared** — a single-state ticket needs no state machinery.

**Milestone 4** — on armed runs, refuses a verdict whose `fidelity` is not `pass`, and refuses a
**stale manifest** (`rendered_from` ≠ the current render binding). Unarmed runs tolerate a
missing `fidelity` key (a transition allowance, stated in-code); a key that is *present* on an
unarmed run must read `not-applicable`.

## Render receipt (D-3, D-4, D-9)

- `design.liveRender.command` gains an optional `{state}` placeholder. Additive; the harness
  maps RS id → prep and the gate stays opaque-command, with the state machine-named per
  invocation.
- **`render_patch_id`** is the existing `branch_patch_id` computation with the manifest path
  additionally excluded (self-reference exclusion, exactly as `VERDICT_REL` is excluded today).
  The manifest stays **inside** `reviewed_patch_id`, so verdict ↔ evidence binding rides the
  mechanism that already exists rather than a second one.
- **Manifest**, gate-authored, at the pinned path `<plansDir>/<key>-lean-renders.md`. The
  suffix is chosen to miss the merge boundary's `-lean.md` first-match spec scan; it joins the
  gate's pinned name table and the chain gate's pattern block. Header
  `rendered_from: <render_patch_id>`; rows `| RS-n | route | state | pngPath | sha256 |`.
- **PNG bytes never enter history.** Outputs land under `.claude/lean-renders/<key>/`, asserted
  ignored via `git check-ignore`; a red prints the exact `.gitignore` line to add. This repo's
  own `.gitignore` gains that line so the assertion is satisfiable here too, even though this
  repo can never arm.
- **Milestone-3 armed logic, idempotent**, in this order:
  - **(a) post-approve** — `rendered_from` matching the current `render_patch_id` passes on its
    own, with no PNG-byte dependency. The mandated pre-close `bash G all` sweep therefore never
    re-renders after an approve, so there is no livelock (a re-render rewrites shas, the
    manifest is inside `reviewed_patch_id`, and the verdict it just earned would be voided).
    Safe after a fresh-worktree resume, where the PNGs do not exist at all.
  - **(b) pre-verdict** — the id match **plus** every listed PNG existing, non-empty, and
    sha-matching its manifest cell.
  - **(c) otherwise** — render every RS row; assert exit 0 and a non-empty PNG per row; red if
    two distinct RS rows hash identically (the `{state}`-blind-harness detector — this assumes
    byte-deterministic rendering, documented, with the legitimate-collision remedy being
    merging or re-scoping the rows); emit the manifest (sha via the `shasum`/`sha256sum` picker
    idiom `tools/mutation-sweep.sh` already uses — bash-3.2/macOS lane); red until committed.
  - `render_patch_id` moves on **any** commit, so every fix round re-renders before the handoff.
    Accepted cost of the blocking posture (D-2).

## Review side (D-5, D-6, D-7)

- **Routing home**: review-lead's Reviewer Routing (the config-resolved provider map) — verified
  to exist and to survive #348. One sentence is amended so the pixel-loop allocation names the
  review-lean fidelity arm on armed lean runs. No new reviewer, no panel change.
- The fidelity verdict is scored **by the review-lean session**, design-sighted, from a checkout
  whose HEAD **is** the reviewed head. Order of operations:
  1. **staleness first** — `rendered_from` against the checkout's current `render_patch_id`.
     This catches round-1 evidence sitting under round-2 code *before* the round is spent;
     milestone 4's refusal is the backstop, not the primary detector.
  2. **hash-verify** each PNG against the manifest. A mismatch in the same checkout is an
     evidence-inconsistency **blocker**.
  3. fetch the design frame through the provider surface, compare per RS row, and score
     **per-RS** in the summary.
  There is no free-form foreign-checkout fallback: a re-render is permitted only at the reviewed
  head, the mode is recorded, and no "mismatch expected" pre-excuse is written.
- **`G verdict` gains `--fidelity <pass|fail|not-applicable>`.** Enum-validated; defaulting to
  `not-applicable` when omitted, which is fail-closed on an armed run (milestone 4 requires
  `pass`). `fail` exists so a finding round records the truth rather than omitting the key;
  `fail` × `approve` is refused at the writer. The key is emitted **unconditionally**, and both
  readers extract it **header-anchored** — an optional-valued key cannot be read first-match,
  for exactly the reason `inherited_patch_id` could not.
- **The helper is parameterized, not forked.** The existing `inherited_key` awk program becomes
  a `header_key <key>` helper with `inherited_key` retained as its `none`-normalizing wrapper,
  both inside the same `LOCKSTEP-BEGIN lean-inherited-key` block. All three verbatim copies
  (`lean-gate.sh`, `check-lean-chain.sh`, `lean-reconcile.sh`) move together, so the two
  existing lockstep rows stay satisfied and no second header-anchoring program is forked.
- **review-lean blockers**, stated in its SKILL.md: a fidelity failure; a same-checkout hash
  mismatch; an unjustified `Design: none` on a provider repo; and an RS table that under-declares
  the states the handoff frames show.

## Merge boundary

Armed-ness derives from the **committed spec alone** — config never reaches CI.
`check-lean-chain.sh` gains one evidence arm: armed spec ⇒ manifest present (diff scan, tree
`find` fallback, fixture-path exclusion, matching the spec/verdict lookups it already does) ⇒
header-anchored `fidelity: pass` ⇒ manifest `rendered_from` matching the head's render patch id.

**Scoped honestly**: this holds for the armed path. A spec that never carries a `## Design`
section is boundary-indistinguishable from honest unarmed work; the residual defense is the
review-side unjustified-disarm blocker above. The chain gate stays second-shift-scoped, and
consumer portability remains #359's.

## Out of scope

No comparison machinery in the gate — comparison is review judgment. No tracker writes, no state
file, no orchestrator or a11y change. The gate writes exactly two new things: the manifest and
the ignored PNGs. Never the spec, never the verdict.

## ACs

- **AC-1** (oracle — `lean-gate-selftest.sh`): milestone-1 forms. Provider configured with no
  `## Design` section reds; the explicit-empty form is green; provider absent with a section
  present is unarmed and green — the third case is what kills the AND→OR mutant.
- **AC-2** (oracle — selftest): the disarm state-lock. The `| milestone-3 | armed |` row is
  written on a **passing** armed run; a disarm-after-armed-row spec reds at milestone 1 **and**
  milestone 3; armed evaluations leave the fix-budget counter unchanged.
- **AC-3** (oracle — selftest): the render pass. An armed ≥ 2-row fixture with an arg-asserting
  stub (it asserts the `{route}` and `{state}` it received) produces two distinct PNGs and two
  manifest rows; a sha recompute of a stub PNG matches its manifest cell; identical-hash
  collision reds; a zero-byte PNG reds; a nonzero stub exit reds; a template missing `{state}`
  (with a non-default RS row) and a template missing `{out}` each red; the `check-ignore`
  assertion is driven **red and green**.
- **AC-4** (oracle — selftest): idempotence. A pre-verdict re-run does not re-render; a
  post-approve evaluation passes on `rendered_from` alone with the PNGs deleted.
- **AC-5** (oracle — selftest): the verdict key. `--fidelity` is enum-validated; the key is
  emitted unconditionally; it is read header-anchored; `fail` × `approve` is refused; an armed
  run requires `pass`; an unarmed run tolerates the key's absence.
- **AC-6** (oracle — `check-lean-chain-selftest.sh`): the boundary arm. Armed spec with no
  manifest reds; a stale `rendered_from` reds; an unarmed spec is untouched and green.
- **AC-7** (oracle — `scenario-liveness-selftest.sh`): three armed legs composed — a render red
  walking attempts to `rc=4`; a fidelity/staleness refusal routing to handoff; a post-approve
  green reaching the milestone-5 terminal write.
- **AC-8** (critic): docs. `docs/live-render.md`'s lean section is rewritten (the extraLane
  workaround is superseded; `{state}`, determinism and env-prerequisite guidance land) including
  its **two out-of-section stale assertions** — the "no Stage-5 and no `design.liveRender` key"
  pointer above the Config section, and the unqualified "Failure is non-blocking" bullet in the
  command contract. `docs/config-schema.md` and the JSON schema state the per-lane
  failure-posture split on `liveRender` and the `{state}` placeholder. `run-lean/SKILL.md` edits
  re-flow within its hard **60-line** cap. The review-lean and review-lead sentences land. A
  `Changelog:` trailer is present on the branch.
- **AC-9** (oracle — diff-scoped mutation sweep): re-keyed generic survivor ordinals on
  `lean-gate.sh` and `check-lean-chain.sh` are re-baselined in the same diff; the lockstep
  verdict-record-schema DROPPED note's key list and coverage case ids are updated for
  `fidelity:`; all three `inherited_key` copies move together and
  `scripts/check-lockstep-pairs.sh` stays green.
