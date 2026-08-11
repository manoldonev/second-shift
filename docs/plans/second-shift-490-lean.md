# Lean spec — #490: a downgraded review model is accepted with no stated basis

## Context

`orchestrate-lean.sh` justifies its two model-tier knobs on different terms. `--build-model`
is required with no default and `--model-basis` records why an unlabeled ticket was sized the
way it was. `--review-model` defaults to `opus` ("REVIEW is the higher-stakes read") but a
departure from that default costs nothing: it parses, passes the sole non-empty check, and
runs — the only trace left is a `say` line and the verdict record's `model:` key, neither of
which carries a reason. A reader of an old verdict record cannot tell whether a downgraded
review tier was an ablation arm, a rate-limit workaround, or a typo. This ticket makes the
departure stated, without hardcoding the tier (the seam stays for #350 vendor-neutrality, the
#284 ablation, and the #245 `fable` override path).

## Decision Ledger (from the pre-flight ledger)

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | AC-3's "the tier name occurs exactly once in the file" — `opus` occurs three times today (`:42` help line, `:70` default, `:94` build refusal's `opus/sonnet` label cue) | Scoped to the REVIEW default's referent. `REVIEW_MODEL_DEFAULT="opus"` is the sole place the review default is spelled, with `REVIEW_MODEL="$REVIEW_MODEL_DEFAULT"`; `:42` is reworded to name no tier ("Defaults to the shipped review tier"); `:94` is UNCHANGED — its `opus/sonnet` names the build sizing labels, a different referent the ticket fences off. The AC-2 refusal interpolates `'$REVIEW_MODEL_DEFAULT'` so the operator learns the default at the moment it matters, recovering what `:42` loses | user-answered |
| D-2 | What `:184` logs for a default-tier run with no `--review-model-basis` (AC-7's untouched happy path) | The basis parenthetical is appended only when non-empty: `review model: opus · rounds: 3` with none, `review model: sonnet (basis: <text>) · rounds: 3` with one. Neither `(basis: )` nor a synthesized "shipped default" — either would make an unstated basis indistinguishable from a stated one in the log | user-answered |
| D-3 | The ticket's "Notes for the run" claim that `orchestrate-lean.sh` has no rows in `tools/mutation-baseline.tsv` | FALSE on the baseline half, true on the catalog half. `tools/mutation-baseline.tsv:115` carries `orchestrate-lean.sh::default::1` — the PROSE `${GH:-gh}` in the Seams header at `:55`. It keeps ordinal 1 iff the diff adds no `${NAME:-value}` site above `:55`, so the new `--review-model-basis` help block must not contain one; the new parse arm `REVIEW_MODEL_BASIS="${2:-}"` is not such a site (the operator's ERE requires a letter after `${`) | codebase-derived |
| D-4 | Where the AC-2 refusal fires | Beside the existing usage assertions, after the `[ -n "$REVIEW_MODEL" ]` empty-value check and before preflight — so a refusal costs zero probes, zero tracker reads, zero worktree resolution | codebase-derived |
| D-5 | `--review-model-basis ''` supplied alongside a non-default `--review-model` | A refusal — AC-2's letter is "non-empty", so the guard is a non-empty test on the value, not a flag-was-seen test | codebase-derived |
| D-6 | AC-5's guard | Already exists — selftest case `(n)` asserts `--help` prints through `Exit: 0 = approved` and stops before `set -uo pipefail`, so it reds on a window too narrow or too wide. No new case is owed for AC-5 | codebase-derived |
| D-7 | `check-emit-deadline-selftest.sh` case B6 reds milestone 3 on two consecutive attempts, on a branch that touches only `run-lean` | Scope widened by one AC (AC-8) rather than worked around. B6 stages its fixture at `<mktemp>/lonely/scripts`, so the tool's shape-2 anchor `$HERE/../../../*/` globs `$TMPDIR` itself; `install-topology-selftest.sh` re-runs all 60 shipped suites, so a second instance of this same file stages `<mktemp>/plugin-wrong-prefix` as a `$TMPDIR` sibling and resolves for the first — the failure names exactly that fixture. Alternative considered and rejected: excluding install-topology from the gate's local test lane, which leaves the latent bug live and edits config shared across worktrees. Answered mid-run in session rather than in the pre-flight ledger — this lane has no pre-flight channel for a decision the run itself surfaces, recorded as a finding in the retro | user-answered |

## Acceptance Criteria

- AC-1: `orchestrate-lean.sh` accepts `--review-model-basis <text>`, free text, no default,
  recorded in the run log beside the review model per D-2's format.
- AC-2: a `--review-model` value that differs from `REVIEW_MODEL_DEFAULT` is a usage refusal
  (exit 2, nothing spawned) unless `--review-model-basis` is non-empty (D-5). The refusal names
  `--review-model-basis` and interpolates the actual default, in the register of the existing
  `--build-model` refusal. Fires per D-4's placement.
- AC-3: the comparison is against `REVIEW_MODEL_DEFAULT`, not a literal, per D-1's scope — the
  review default's value is spelled in exactly one place in the file.
- AC-4: `--review-model opus` (or whatever `REVIEW_MODEL_DEFAULT` is) passed explicitly is the
  default, not a departure, and needs no basis; a basis volunteered alongside it is accepted and
  echoed, never refused.
- AC-5: the `--help` window (`sed -n '2,Np' "$0"`) is widened by exactly the number of new
  comment lines, so the `Exit:` block is neither truncated nor leaks code. Covered by existing
  case `(n)` per D-6 — no new selftest case owed.
- AC-6: existing selftest case `(k1)` is updated to pass `--review-model-basis` alongside its
  non-default `--review-model sonnet` (otherwise AC-2 turns it into a refusal), and keeps
  asserting the override reaches the spawn.
- AC-7: new `orchestrate-lean-selftest.sh` cases cover: the refusal (non-default tier, no
  basis → rc=2, `spawn_count` 0, naming `--review-model-basis`); the accepted departure (basis
  echoed into the log per D-2's format); and the untouched happy path (no `--review-model` at
  all → no basis required, review spawn still gets `REVIEW_MODEL_DEFAULT`). AC-4's two claims
  (explicit-default needs no basis; a volunteered basis on the default is accepted and echoed)
  get their own cases too.

- AC-8: `check-emit-deadline-selftest.sh` case B6 stages its fixture below a private parent dir,
  so the tool's shape-2 anchor cannot glob `$TMPDIR` and pick up a concurrently-running second
  instance of this same suite (D-7). The case keeps asserting the same contract — an
  unresolvable live scan fails loudly naming the resolution miss — and the suite passes both
  serially and under the concurrent lane that reds it today.

## Out of scope

- `run-lean/SKILL.md` — unchanged; the flag belongs in `--help`, not the front door's line
  budget.
- The verdict record schema — unchanged; the record already stamps `model:`.
- `--model-basis` — untouched; a different flag answering a different question.
