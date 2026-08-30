# lean review verdict — #708

verdict=approve
run_id: review-708-1
session_id: e2b67f86-a5e7-4ad2-a9df-7dccb5d55972
rounds: 1
pr: #729
reviewed_head: f50347ce484bded73a8f5cd4d9c281be9e3bb5a7
reviewed_patch_id: d7ec16d75b03fd3e3865377553f5314d3cb43c78
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
panel: none
model: unknown
capabilities: pr-marker

# Round 1 — PR #729 (#708): the fidelity reviewer is mandatory on an armed run

**Verdict: approve.** No blockers. Three warnings and one suggestion, all in the prose
contract between `review-lead` and `review-lean`; every one of them fails CLOSED at the
`bash G verdict` writer, so none can produce the certified-but-unreviewed record this
ticket exists to prevent.

Coverage: full branch diff `a928f5a..HEAD` (round 1, `G delta` printed FULL — nothing to
inherit), 13 files, +911/-32, at head `f50347ce`.

## How each claim was verified

| Claim | Oracle |
| --- | --- |
| the new selftest cases pass | CI run 33327984301 at head `f50347ce` — `lint-and-selftests` pass (4m41s), `selftests (macos, bash 3.2)` pass (5m36s); both run `run-selftests.sh --full`. Cited, not re-run. |
| the 8 new `mutation-catalog.tsv` rows are killed | **`mutation-sweep-pr` graded NOTHING** (11s; both in-scope guards `deferred-to-nightly` as slow suites), so the PR has no oracle for AC-7. All 8 probed by hand in throwaway worktrees at `f50347c`, green baseline first, scored on the suite token. |
| the two `lean-design-provider-family` copies agree | `check-lockstep-pairs.sh` run locally: 30 anchors, 0 failed. |
| `check-reviewer-references.sh` stays green (AC-1) | run locally, rc=0. |
| milestone 1's host arms | `design_state` driven directly in library mode against an unrecognised-host spec under `design.provider: figma` — it returns `error:…`, never `armed` (see S1). |
| no release-owned file touched | `check-frozen-files.sh origin/main` clean. |

### Mutation probe — 8/8 killed, each by the cases its note names

Three throwaway `git worktree` checkouts at `f50347c`, unmutated baseline `all green` first;
mutants applied with `sed -E`, exactly as `mutation-sweep.sh:1878` applies them.

| Row | Killed by (measured) | Note claims |
| --- | --- | --- |
| `lean-gate-panel-required` | (fp1) | (fp1) ✔ |
| `lean-gate-panel-mandatory-reviewer` | (fp2)(fp3)(fp4) | (fp2)(fp3)(fp4) ✔ |
| `lean-gate-panel-milestone4` | (fp5)(fp6) | (fp5)(fp6) ✔ |
| `lean-gate-design-family-from-config` | (dz8)(dz9) | (dz8)(dz9) ✔ |
| `lean-gate-panel-token-anchors` | (fp3) | (fp3) ✔ |
| `lean-chain-panel-arm` | (X8)(X8b)(X10) | (X8)(X8b)(X10) ✔ |
| `lean-chain-panel-absent` | (X9)(X9b) | (X9)(X9b) ✔ |
| `lean-chain-design-family-default` | (X11) | (X11) ✔ |

8/8 killed, every one by exactly the cases its note names. Two rows are worth calling out as
non-trivial: `lean-gate-panel-token-anchors` (comma anchors dropped from `panel_has`) dies on
(fp3) alone — no shipped reviewer name is a substring of another, so (fp3)'s deliberately
crafted `acme:pre-design-toolkit:figma-faithful-reviewer-v2` is the whole kill criterion — and
`lean-chain-design-family-default` dies on (X11) alone, which is the only case that pairs an
unrecognised host with a panel that WOULD pass, so the red can only be the derivation.

## Findings

No blockers. The three warnings below are all in the prose contract between `review-lead`
and `review-lean`, and each one fails CLOSED at `bash G verdict`: a round that lost the
mandatory reviewer cannot write a record, whatever the prose says. That is why they are
warnings and not blockers — the certified-but-unreviewed record this ticket exists to
prevent is unreachable through any of them.

### W1 — `review-lean` 5c attributes the went-dark void to `review-lead`, which does not perform it

`review-lean/SKILL.md:90` now reads: "`review-lead` voids a round in either of two cases:
**every** reviewer it selected went dark, **or** — on an armed spec — the provider's
mandatory fidelity reviewer went dark, however many of the others returned. **It then emits
a 'review did not run' report naming the dark set**".

`review-lead/SKILL.md` was not changed to match, and says the opposite for that second case:

- `:316` "**Threshold — strictly zero.** The round is void when **no** selected reviewer
  produced a usable result"
- `:321` "One usable result is enough to leave the round intact. A **partial**-dark panel
  keeps Step 4b's behavior exactly — the `[Coverage gap]` line, the `Dark (no output)`
  rows, **no verdict change**."
- `:448` "a round voided under Step 4b-void (**every selected reviewer dark**) answers it
  not at all"

The only armed-void `review-lead` gained is at `:196`, and it is a different case:
toolkit-**absent** (never dispatched, detected pre-dispatch at Routing), not went-dark
(dispatched, `{result: null}`). So on an armed run whose fidelity reviewer dies after retry,
the shipped `review-lead` produces a complete report with a `Dark (no output)` row and an
answered "Ready to merge?" — and `review-lean` 5c describes a void report that will not be
there.

Recoverable, which is why it is not a blocker: 5c's operative sentence keys on the *case*
holding ("When either case holds, stop before step 6"), and the case is readable off the
`Dark (no output)` row. And D-11's design means the writer refuses the record anyway. But a
session that looks for the void report 5c promises will not find one.

Fix: either widen `review-lead`'s Step 4b-void (and the `:448` parenthetical) to carry the
armed-fidelity case, or reword 5c so the second case is `review-lean`'s own reading of a
partial-dark panel rather than something `review-lead` emits.

### W2 — `review-lead:196` names a trigger the report's own definition excludes

Same root, inside one file. `:196` instructs the armed toolkit-absent case to "Emit the Step
4b-void 'review did not run' report instead", but Step 4b-void's `:316` threshold and the
`:448` Rules parenthetical still define that report as reserved for a strictly-zero panel.
A reader who reaches Step 4b-void by its own heading is told the round is not void. Also
note `Step 4c` still closes at `:334` with "Both are **a note, never a blocker, and never
silent**" — its design-toolkit bullet is scoped by "A changed path *did* match", so it does
not literally cover the armed path, but the sentence reads unconditionally.

### W3 — the armed always-spawn trigger has no guaranteed input in the lean lane

`review-lead`'s new row fires "When Process step 4's plan/spec awareness turns up a lean spec
whose `## Design` section is **armed**", and Plan/Spec Awareness is conditional: "If a
plan/spec was provided as input, read it." `review-lean` step 5 says only "`review-lead` is
the implementation" — nothing in this diff, or in the file, instructs the review session to
hand `review-lead` the lean spec path it resolved at step 2. On an armed lean run where the
spec is not passed, `review-lead` takes the unarmed glob path — the exact model-judgment
routing this ticket replaces.

Again fail-closed rather than silent: the panel then omits the mandatory reviewer, and the
writer refuses. The cost is a stranded round, not a bad record. One clause in step 5 ("pass
`review-lead` the spec path from step 2") closes it.

### S1 — two unreachable refusal arms, one of them carrying a `gate-buckets.tsv` row

`lean-gate.sh:4610` (milestone 4) and `:4863` (the writer) both open with

```
if ! p_rev="$(design_family_reviewer "$(design_family < "$REPO_ROOT/$SPEC_REL")")"; then
```

and both sit inside `[ "$(design_state …)" = "armed" ]`. `design_state` returns `armed` only
after `n_fam` is non-empty AND `n_fam = $DESIGN_PROVIDER`; `design_family` emits only `figma`
or `claude-design`, and `design_family_reviewer` accepts exactly those two. So the failure
branch cannot be taken on either site. Measured, in library mode against a spec whose handoff
is `https://design.example.invalid/f/a` under `design.provider: figma`:

```
DESIGN_PROVIDER=[figma]   design_family=[]   design_state=[error:… none this lane recognises …]
```

`design_state` never says `armed` there — milestone 1 is the only site that can report it,
which is what (dz8) and the liveness leg (c) actually pin. The boundary's copy IS reachable
(the boundary has no config to cross-check against) and is genuinely killed by (X11); the two
gate-side arms are dead. `scripts/gate-buckets.tsv` gained a row for the milestone-4 one,
which reads as a live enforcement site. Fail-closed dead code is not a defect, but either
delete the two branches or say in the comment that they are belt-and-braces behind
`design_state`.

## Recorded, not blocking

- **`pr-gates` is red on `check-guard-budget.sh` only** — "guard/test shell mass grew by 740
  lines with no reason recorded". That is a POLICY gate at the merge boundary, not evidence
  about the code, so per review-lean's rules it is recorded rather than made `needs-work`:
  refusing here would buy *when* the `Guard-mass:` trailer lands, not *whether*. The remedy
  is a trailer commit, which changes none of the lines this record hashes, so this verdict
  survives it. `lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr`
  — the correctness lanes — are all green at `f50347ce`.
- **`Changelog: none.` in `f50347c` will render beside the real trailer in `90ca9fa`.**
  Trailers concatenate at squash and the presence-only gate passes either way; drop the
  `none.` line in the merge dialog.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `review-lead/SKILL.md:169` routing row is **ALWAYS on an armed lean spec**, and `:176-178` states not glob-gated / not depth-suppressed / host-selected, with the glob trigger kept for unarmed diffs (`:180` "Trigger (unarmed diffs)"). Toolkit-absent on an armed spec is a void at `:196`. `check-reviewer-references.sh` run locally, rc=0. See W2/W3 for what the row still leans on. |
| AC-2 | satisfied | 5c widened at `review-lean/SKILL.md:90-97`; the hand-back names the reviewer ("Say **which** reviewer went dark in the hand-back"); "write **no** verdict record" retained. See W1 on the attribution. |
| AC-3 | satisfied | Writer refusals at `lean-gate.sh:4862-4877`: missing `--panel` (fp1, probed — mutant `lean-gate-panel-required` killed by fp1), non-member panel (fp2/fp3/fp4). `panel: ${VERDICT_PANEL:-none}` emitted unconditionally at `:4967`. `panel_key` reads the whole value back — (fp0) asserts equality against the full qualified list through the gate's own reader, not a fixture grep. `panel` is in `LEAN_VERDICT_HEADER_KEYS`. |
| AC-4 | satisfied | `check-lean-chain.sh:948-968`, arm 8. Probed: `lean-chain-panel-arm` killed by (X8)(X8b)(X10); `lean-chain-panel-absent` by (X9)(X9b); `lean-chain-design-family-default` by (X11). (X11) asserts the unrecognised host reds *and* that the panel-omission wording is absent, so an unrecognised host is a violation in its own right. `lean-evidence.sh` untouched (0-line diff); its OR-1 note at `:35` already excludes the design arms. |
| AC-5 | satisfied | `check-lockstep-pairs.sh` locally: 30 anchors checked, 0 failed, including `lean-design-provider-family` across `lean-gate.sh` + `check-lean-chain.sh`. `design_state` milestone-1 arms verified directly in library mode (unrecognised host → `error:…`) and by (dz8)/(dz9), with (dz10) proving the derivation has two answers rather than refusing every `claude.ai` handoff. |
| AC-6 | satisfied | `scenario-liveness-selftest.sh` design leg 4: (a) writer refuses both no-panel and dark-panel with the committed record byte-identical; (b) milestone 4 goes 0 → 5 and the boundary's output goes from not-naming to naming the reviewer, over ONE changed fact; (c) the unrecognised host at milestone 1. The green half runs first in each pair. |
| AC-7 | satisfied | 8 catalog rows, all 8 probed by hand and killed by exactly the cases their notes name (table above) — necessary because `mutation-sweep-pr` deferred both guards and graded nothing. 5 new `gate-buckets.tsv` rows for the 5 new refusal sites, 2 existing anchors tightened. `check-gate-buckets.sh` green in CI. |
| AC-8 | satisfied | `docs/live-render.md` states mandatory-on-armed, `panel:` as the attestation, and host-derived family; `docs/testing.md`'s key-schema entry names `panel:` and gives the `header_key` truncation reason for a reader of its own. |
| AC-9 | satisfied | `90ca9fa` is `feat(dev-pipeline):` with a real `Changelog:` trailer; `check-frozen-files.sh origin/main` clean — no `version`, no `CHANGELOG.md`. |

**Design fidelity: not-applicable.** The spec disarms with `Design: none — this slice changes
gate/boundary shell and two skill contracts… this repo configures no `design.provider`". Checked
against the repo's own gitignored config: `.design` is absent, and no committed spec under
`docs/plans/` carries an `| RS-n |` row. The disarm is justified, so step 5b does not run.

## Panel

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs`
(unset here, so the shipped default `apps/web/**/*.{tsx,jsx}`), and this repo's spec is
disarmed. `db-reviewer`, `pipeline-reviewer` and `unit-test-mutation-reviewer` not triggered.
Nothing went dark; the round is not void.

Security suppressed one worth keeping (confidence 40): `design_family`'s URL scheme match is
case-sensitive, so `HTTPS://www.figma.com/…` classifies as unrecognised. It fails CLOSED — a
milestone-1 refusal with a message that names the fix — so it is robustness, not a hole.

## Strengths

- **The pairs are actually paired.** Nearly every new case ships with its green counterpart
  and in the right order: (X7) before (X8)/(X9), (X10b) beside (X10), (dz10) beside
  (dz8)/(dz9), (fp7)'s unarmed consumer beside (fp0)-(fp6), and (X11z) restoring the disarmed
  tree the following blocks were written against. A block whose only passing member is a
  violation would stay green under an arm that fired unconditionally; none of these would.
- **(fp0) asserts the property, not the bytes.** It reads `panel:` back through the gate's own
  `panel_key` in library mode rather than grepping the file, so it tests that a READER gets
  the whole qualified comma-separated list — which is the entire reason the key has a reader
  of its own. A `grep` there would have proved only that the bytes are on disk.
- **Fixture-vacuity guards throughout.** (dz10-fixture), (fp5-fixture), (fp6-fixture) and
  (fp5)'s "milestone 4 was not green before the edit" all red rather than silently asserting
  nothing — and they earned their keep in this probe: three of them fired as cascades under
  the mutants, which is exactly the visibility they exist for.
- **`header_key` was not widened.** The truncation is documented at both the reader and the
  `LEAN_VERDICT_HEADER_KEYS` list, with the reason the key stays in that list anyway (the loop
  proves line anchoring, which a truncated comparison detects identically). That is the right
  trade against changing how every key in a three-member lockstep schema is read.
