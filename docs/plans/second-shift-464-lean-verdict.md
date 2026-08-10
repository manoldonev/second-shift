# lean review verdict — #464

verdict=approve
run_id: review-464-1
session_id: 2a9133b8-e4be-44ba-90ec-6bce329adfc7
rounds: 1
pr: #474
reviewed_head: 75bfcfdd7f18be3fef91a0b6365b4c87c94932b8
reviewed_patch_id: c6311bf14090834f44aeb3a55be03347cca204bb
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review summary

Round 1, full branch range `1413ca7..75bfcfd` (3 files, +207/-7). Seven reviewers dispatched
(security, performance, maintainability, complexity, test-coverage, unit-test-mutation,
scope-completeness); none went dark. `a11y-reviewer` and the design-fidelity dimension were not
routed — no changed path matches `stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`,
the resolved default; this repo sets no value, which is the very fact the PR is about).

The change is tight and the reasoning is carried in the code, not only in the spec. The probe sits
in the one place where the evidence is already in hand, the `notEvaluated`-vs-`unadopted` choice is
argued at the call site, and `PROBE_GLOBS=()` on the `formatGlob` row is a reset rather than an
omission — with a leak guard on the only fixture in the suite that can catch it.

Verified independently, not taken on report:

- The motivating outcome. Running the branch's `config-grill.sh` against this repo's real config
  emits `findings: T4.mutation-plumbing.second-shift` with both web keys in `notEvaluated[]`;
  `main`'s copy on the same config emits `T2.webComponentGlobs, T2.visualCaptureTriggerGlobs,
  T4.mutation-plumbing.second-shift`. The two FAILs are gone and nothing else moved.
- Mutants I applied and scored against the paired suite: dropping `svelte` from the probe set
  (killed, and it fails *exactly* its own case, as AC-1 claims); deleting the `formatGlob`
  `PROBE_GLOBS=()` reset (killed by the leak guard, 3 failures); flipping the probe condition
  `-eq 0` → `-gt 0` (killed, 26); neutralizing the probe arm (killed, 10); adding `ts` and adding
  `js` back to the probe set (each killed by exactly its own exclusion case, 2 apiece).
- CI on this exact head (`75bfcfd`): `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
  `mutation-sweep-pr` pass (`config-grill.sh` — applied=7 killed=7 survived=0).
  `pr-gates` fails on one line only: no committed verdict record. That is this artifact.
- AC-4's load-bearing premise, checked rather than reasoned about: a `mktemp -d` fixture root is
  not a git work tree, so `config-grill.sh` there still returns the `TRACKED_OK` reason
  `not a git work tree — tracked files cannot be enumerated`. The `grill-noteval` scenario is
  therefore asserting the same classification it asserted before the probe existed.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 — probe converts the two web keys on a repo that renders nothing | satisfied | `t2-renders-nothing` yields `notEvaluated` for both ids and no `findings[]` entry for either, rc 0; the reason names the probe set. Each of the 10 members has its own fixture and each of the 2 exclusions has its own; removing or adding one fails exactly its own case (measured). |
| AC-2 — a real web surface still fires, both arms | satisfied | Candidate-matches arm: `t2-web-default` still fires with `src/**/*.{tsx,jsx}` / `matches 2 tracked file(s)`, and the hand-set case on the same tree still fires. No-candidate arm: re-pointed to `t2-web-nocand` (`pkg/ui/Widget.tsx`), which keeps both the `no candidate from the shipped list matched` proposal and the comma-joined four-literal `triggerGlobs` default. The re-pointing is as the spec describes — `t2-no-alt` became AC-1's fixture and the hand-set `triggerGlobs` case moved onto a tree with a web surface, nothing deleted. |
| AC-3 — `formatGlob` unchanged, probe does not leak into it | satisfied | Slash-free and hand-set `formatGlob` cases untouched and green. The leak guard fires on `t2-format-go`, the only no-web-surface tree in the suite: `formatGlob` still fires in the same call where both web keys convert, and there is an explicit assertion that `T2.formatGlob` never appears in `notEvaluated[]`. Deleting the reset kills it. |
| AC-4 — doctor's rendering unchanged | satisfied | `doctor-selftest.sh` all green, `grill-noteval` unmodified and still asserting `not evaluated [T2.webComponentGlobs]` at rc 0. The fixture's classification did not move (verified above), so no re-anchoring was owed. |

Design fidelity: `not-applicable`. The spec arms no `## Design` section, this repo configures no
`design.provider`, and the diff touches no rendering surface — the disarm is justified rather than
convenient.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `config-grill.sh:210` | The probe set rendered into the `notEvaluated` reason is unasserted, so a wrong one reads as correct. Every `expect_noteval` in the suite matches only the fixed phrase `applicability probe`, never the joined list. I applied three mutants to the reason string — `join_c "${PROBE_GLOBS[@]}"` → `"${globs[@]}"`, → `"${DEFAULT_GLOBS[@]}"`, and dropping the list entirely — and **all three survive the full suite green**. The first is the one that matters: it would render `applicability probe (apps/web/**/*.{tsx,jsx})`, naming the globs that scored *zero* as if they were the probe, which is precisely the confusion the sentence exists to prevent. AC-1 asks for a line "diagnosable on its own"; the shipped code does render it correctly (confirmed live on this repo's config), so this is guard strength, not behavior. One-line fix: add the probe-set substring as the third argument to the two AC-1 `expect_noteval` calls. |
| 2 | Warning | `config-grill.sh:203-211` | Probe-vs-candidate precedence is undeclared and unpinned. The probe returns before the `CANDIDATES` loop, so a matching candidate can never rescue a row the probe converts. I built the variant that inverts that call — probe fires only when no candidate matched (`[[ -z "$alt" ]]`, block moved after the loop) — and **the whole suite stays green**, while behavior differs on a reachable tree: on `src/app/*.ts` with no tracked `.html`/`.css` (Angular with inline templates and styles), shipped code emits `notEvaluated` reading "the surface this key scopes does not exist in this repo", whereas the variant emits a finding proposing `src/app/**/*.{html,ts}` — a candidate the shipped list already carries and that matches 2 files. AC-1's `.ts` exclusion says the shipped direction is intended, so this is not an unmet AC; but the suite's only `.ts` fixture is root-level `app.ts`, where no candidate reaches, so it cannot tell the two apart and a later edit could flip the precedence silently. One-line fix: a fixture at `src/app/x.ts` asserting `notEvaluated`. |
| 3 | Nit | `config-grill.sh:206` | `${#PROBE_GLOBS[@]}` on an *unset* array is an unbound-variable error under `set -u` in bash 3.2 (verified on 3.2.57), unlike the `${CANDIDATES[@]+…}` guarded form two lines below. Unreachable today — the first `t2_key` caller assigns it — and the header comment already states the obligation, so this is a note about the failure mode a future fourth row would hit, not a defect in this diff. |

Suppressed (below threshold, from the panel): config-supplied globs reaching `grep -cE` as regex
fragments (conf. 30, pre-existing and untouched); unquoted `CANDIDATES` expansion (conf. 40,
pre-existing, repo-local literals only).

Both warnings are guard-strength gaps on newly added logic with one-line remedies, and neither
contradicts an AC or the shipped behavior. Nothing here blocks the merge.
