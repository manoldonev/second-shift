# Plan: acme-205 (PR 2 of 2) — lockstep manifest + containment policy

## Context

PR 1 built the composed-path liveness harness and deleted the prose-presence guard class.
This slice supplies the replacement it promised — a mechanical check for contracts that are
duplicated across files and can only drift silently — plus the policy that stops the weak
class from regrowing.

Some contracts must be duplicated: `scope-completeness-reviewer`'s independence contract
forbids it from reading pipeline docs, so it keeps an inline copy of the AC-ID rule; the
Workflow runtime gives `.mjs` scripts no import, so three of them each declare
`FINDINGS_SCHEMA`. Every one of those sites says "keep verbatim" in prose. Nothing checked it.

Slice scope is AC-6..AC-9. AC-1..AC-5 landed in PR 1.

## Assumptions

- The `lint-and-selftests` CI job is the right home (pairs span plugins, so the checker lives
  in repo-level `scripts/`, next to the existing namespace-direction check).
- Marker comments are inert everywhere they land: `#` in shell, `//` in `.mjs`, `<!-- -->` in
  markdown. `text-contract-selftest.sh`'s extractor takes only arrow-function bodies, so
  wrapping an object literal cannot collide with it.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Manifest entry 2 (AC-ID rule) — conditional or unconditional? | Unconditional. Byte-parity is reachable: the two sites differ only in a parenthetical prefix, so the BEGIN marker goes at the END of each prefix line. Markdown renders adjacent lines as one paragraph, so the rendered doc is unchanged. | codebase-derived |
| D-2 | Where is a dropped entry recorded? | As a commented row in `scripts/lockstep-manifest.tsv`, with the reason. AC-7 required a named artifact and did not name one. | codebase-derived |
| D-3 | Manifest entry 4 (preflight vs verifyctl zero-lane predicate) — include? | **Dropped to reviewer-guarded.** `preflight.sh` computes an aggregated `VERIFYING` count inline; `verifyctl.sh` reads `allowUnverified`/`lanes`/`extraLanes` into separate variables under a different jq arg name. No byte-identical block exists and reaching one means restructuring working code for its own guard — the issue's stated default on doubt. | codebase-derived |
| D-4 | The stage-8 mirror is not byte-identical to its stage doc over the whole loop. | Pin the largest genuinely contiguous identical span — the preamble plus the clean-worktree assertion — and record the remainder as reviewer-guarded. Past that point the stage doc interleaves in-session review prose the bash mirror deliberately omits, so no contiguous block spans the rest. Comment-only differences inside the pinned span were aligned. | codebase-derived |
| D-5 | The stage-7 mirror had genuinely drifted from its doc (two missing comment lines). | Fix it here rather than pin the drift. A block labelled "verbatim mirror" that is not verbatim is the exact defect this check exists to surface, and it was found by introducing the check. | codebase-derived |
| D-6 | How is a triple (`FINDINGS_SCHEMA` × 3) expressed in a pair-based manifest? | Two rows against the same canonical leg (`code-review.mjs`), rather than adding an n-ary relation. Confirmed all three copies are already byte-identical, so no drift needed fixing. | codebase-derived |

## Affected files/modules

- `scripts/check-lockstep-pairs.sh` **[NEW]** — the checker.
- `scripts/lockstep-manifest.tsv` **[NEW]** — the pair rows plus the recorded drops.
- `scripts/check-lockstep-pairs-selftest.sh` **[NEW]** — red-on-mutation proof.
- `.github/workflows/ci.yml` — one step in the `lint-and-selftests` job.
- `CLAUDE.md` — the scenario-first / no-prose-presence-guards policy.
- `plugins/review-toolkit/agents/test-coverage-reviewer.md` — reviewer-contract bullets.
- `plugins/review-toolkit/agents/plan-reviewer.md` — reviewer-contract bullet.
- Marker-comment sites (content otherwise unchanged, except D-5's drift fix):
  `plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh`,
  `plugins/dev-pipeline/skills/run/tools/plan-lint.sh`,
  `plugins/dev-pipeline/skills/run/state-schema.md`,
  `plugins/review-toolkit/agents/scope-completeness-reviewer.md`,
  `plugins/dev-pipeline/skills/run/workflows/{code-review,stall-probe,tool-discipline-probe}.mjs`,
  `plugins/dev-pipeline/skills/run/stages/{7-doc-update,8-code-review}.md`,
  `plugins/dev-pipeline/skills/run/stage7-perrepo-checkpoint-selftest.sh`,
  `plugins/dev-pipeline/skills/run/stage8-perrepo-review-selftest.sh`.

## Reuse inventory

- `scripts/check-intake-tracker-namespaces-selftest.sh` — the sed-mutation red/green selftest
  idiom the new selftest follows. (The issue cited this file as
  `check-scope-tracker-namespaces-selftest.sh`; that name does not exist.)
- `plugins/dev-pipeline/skills/run/tools/text-contract-selftest.sh` — the
  collapse-whitespace-then-compare normalization idiom the `verbatim` relation reuses.
- The existing `>>> BEGIN verbatim mirror` blocks in the stage-7/8 selftests — already
  delimited; the `LOCKSTEP-*` markers sit inside them rather than replacing them.
- No new helpers introduced beyond the three new files above.

## Implementation steps

1. Write `scripts/check-lockstep-pairs.sh`: parse the TSV, extract marker-delimited blocks,
   implement `verbatim` (normalize then compare) and `subset-of` (first `'…|…'` literal,
   split on `|`, assert containment). A missing marker or file is a FAILURE, never a skip.
2. Add `LOCKSTEP-BEGIN/END` markers at each leg. For the AC-ID rule, place BEGIN at the end
   of the prefix line per D-1. For stage 7, also fix the real drift found (D-5).
3. Write `scripts/lockstep-manifest.tsv` with the six enforced rows and the three recorded
   drops (D-2, D-3, D-4).
4. Write `scripts/check-lockstep-pairs-selftest.sh` against a throwaway tree copy: green
   baseline, then `verbatim` drift, `subset-of` violation, deleted marker, and missing file
   each go red; plus a check that `subset-of` tolerates a legitimate narrowing.
5. Wire the checker as a step in the `lint-and-selftests` CI job.
6. Add the CLAUDE.md policy and the two reviewer-contract bullets.

## Test strategy

Verify-after — this slice is verification machinery, so the selftest is the deliverable's own
proof.

- **Red-on-mutation is the load-bearing test** (AC-8). A guard never observed failing is
  indistinguishable from one that cannot fail — the precise defect of the class being replaced.
  Both relations get a mutation case, plus a deleted-marker case, because "silently stops
  checking" is the failure mode that matters most.
- The checker runs against a **copy** of the tree, so mutations never touch the working tree.

Unit-test surface: `skip`. The repo declares `unitTestScope: null`.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| ----- | ----------------- | ------- | ------- |
| AC-6 | Checker + manifest + selftest exist, support both relations, extract markers, run in CI | 1, 3, 4, 5 | check-lockstep-pairs-selftest (AC-6) |
| AC-7 | Manifest enforces provenance-enum, FINDINGS_SCHEMA triple, stage-7/8 mirrors; conditional entries land or are recorded as dropped | 2, 3 | check-lockstep-pairs-selftest (AC-7) |
| AC-8 | Red-on-mutation demonstrated | 4 | check-lockstep-pairs-selftest (AC-8) |
| AC-9 | CLAUDE.md policy + both reviewer-contract bullets | 6 | — no test (non-functional) |

## Verification commands

- `bash scripts/check-lockstep-pairs.sh`
- `bash scripts/check-lockstep-pairs-selftest.sh`
- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty`
- `find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}`

## Risks / rollback notes

- **Marker comments land in eight files.** All are inert in their host syntax; the `.mjs`
  markers were checked against `text-contract-selftest.sh`'s extractor, which reads only
  arrow-function bodies.
- **The AC-ID marker splits a markdown paragraph across two source lines.** Adjacent lines
  render as one paragraph, so the rendered doc is byte-identical in output.
- **A future contributor deletes a marker to silence the check.** Case (f) of the selftest
  makes that a failure rather than a silent skip.
- **Rollback:** the checker is one CI step and one script; removing the step disables it
  without touching the marked files.

## Out-of-scope

- Any change to the liveness harness or `scenario-lib.sh` (PR 1).
- A selftest-LOC budget script — deliberately rejected by the issue; containment is policy
  plus the reviewer contract.
- The two CI-dark suites `plugins/design-toolkit/skills/design-faithful/lib/{emit,extractor}.test.mjs`.
  Surfaced during PR 1's review and left unaddressed here: no AC covers them, and the `.mjs`
  CI shim added in PR 1 is scoped to `workflows/`.
- Re-mechanizing the pairs already enforced elsewhere (model tiers, reviewer registry, section
  catalog, statectl codegen byte-match, text-contract carriers, config-lint vs schema).
