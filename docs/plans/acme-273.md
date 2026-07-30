# Plan — #273: pipeline-chain reconciliation in `pr-gates` + server-side workflow freeze

Part of #268 (T0 remainder + T2 rung 1). Program: harness-attested pipeline enforcement.

## Context / problem framing

The epic's trust-boundary statement (#268 D-2) says nothing inside the session is proof: the agent
executes with file access, so state files, receipts and even the hook-written audit ledger are at
best tamper-*evident*. The tamper-*proof* line is the merge boundary — CI checks plus branch
protection, which the agent cannot edit from a run. That boundary is a precondition this repo only
half satisfies: two branch rulesets are active (`default`, `main-protection`), but
`.github/workflows/**` is unfrozen, so a same-repo PR can edit the very job that judges it.

This issue lands two things:

1. **T0 remainder** — a server-side freeze of `.github/workflows/**` via a push ruleset, plus a
   fast-feedback *advisory* row in `check-frozen-files.sh`. The CI row is deliberately **not** the
   enforcer: it runs inside the workflow it would freeze, so an agent could neuter the step while
   keeping the required check green.
2. **T2 rung 1** — `scripts/check-pipeline-chain.sh` [NEW], wired into `pr-gates`, failing a
   pipeline-authored PR unless the stage-marker trail visible at PR-open time exists and is
   mutually key-consistent.

Honest altitude, restated from the epic: every record rung 1 reads is agent-written, so this is
**tamper-evidence, not proof**. Attestation is rung 2 (needs #244 + #243 §3); state-file receipts
are explicitly rung-2 material per epic D-6.

This is also the program's first PR, so it commits `docs/pipeline-manifesto.md` [NEW] — the single home
for P1–P7, which #268 requires before the rest of the program can cite it.

## Assumptions

- The repo is user-owned and public (`manoldonev/second-shift`); the operator's `gh` credential
  carries `repo` scope. Whether **push**-target rulesets are accepted for a user-owned repo is
  unknown — that is precisely what D-7's probe determines, and both outcomes are handled.
- `pr-gates` is a required check with no bypass actors, so any hard-failing row it gains also
  red-lines every future sanctioned workflow change. This is why the frozen-files row is advisory.
- Stage-comment markers are a closed enum documented in
  `plugins/dev-pipeline/skills/run/state-schema.md` (`claimed`, `intake`, `plan`, `plan-review`,
  `verify`, `doc-update`, `code-review`, `pr`) and generator-validated. The new check consumes that
  vocabulary; it does not redefine it.
- All five required markers are receipt-gated before their stage closes (`comment-add` +
  `set-stage --status completed` refuses without the receipt), so PR-open visibility is guaranteed
  rather than assumed. Verified at intake against `stages/8-code-review.md:257` and the SKILL.md
  non-gating-writes section.
- `commands.second-shift.unitTestScope` is `null` — this repo declares no mutation surface, so the
  unit-test surface gate is `skip`.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Workflow-freeze mechanism | Push ruleset (probe-first), no bypass actors, operator-toggled for sanctioned changes; CODEOWNERS rejected — it requires an approving review a solo-maintainer repo cannot self-provide. Sourced from the ticket body: https://github.com/manoldonev/second-shift/issues/273 | ticket-sourced |
| D-2 | Rung-1 applicability | Head-branch match against the CI `env:` `branchPrefix` constant only; other PRs pass with a visible not-applicable notice. Ticket: https://github.com/manoldonev/second-shift/issues/273 | ticket-sourced |
| D-3 | Failure posture | A pipeline-authored PR with a broken/missing chain fails `pr-gates`; no waiver in rung 1 — the remedy is completing the missing stage or re-running, not bypassing. Ticket: https://github.com/manoldonev/second-shift/issues/273 | ticket-sourced |
| D-4 | CI-visible config source | `env:` constants on the `pr-gates` job (runtime config is gitignored and absent in CI); fail-closed when unresolvable — vacuous-green is the worst outcome. Ticket: https://github.com/manoldonev/second-shift/issues/273 | ticket-sourced |
| D-5 | Observation point + family | Chain as of PR open (`claimed`/`intake`/`plan`/`doc-update`/`code-review`); active family = newest `claimed` marker's `run_id`. Ticket: https://github.com/manoldonev/second-shift/issues/273 | ticket-sourced |
| D-6b | Issue resolution + key consistency | `Closes #N` or `Part of #N`; three-way check across PR-body ref, branch suffix, and plan filename. Ticket: https://github.com/manoldonev/second-shift/issues/273 | ticket-sourced |
| D-7 | Push-ruleset availability | Probe at `enforcement: disabled` before activating; if rejected on this owner type, record the gap on #268 and ship without a fake freeze. Ticket: https://github.com/manoldonev/second-shift/issues/273 | ticket-sourced |
| D-8 | Freeze fast-feedback posture | `check-frozen-files.sh` row is advisory (warn-only): the ruleset is the enforcer. Ticket: https://github.com/manoldonev/second-shift/issues/273 | ticket-sourced |
| D-9 | Family-selection tiebreak (resolves the D-5 internal conflict) | "As of PR open" wins over bare recency: filter the comment trail to `created_at <= pull_request.created_at`, then take the newest `claimed` **in that window**. `pr-gates` is an unrestricted `pull_request` job, so it re-executes on every synchronize and manual re-run; bare recency would let a later re-claim retroactively red-line an already-green PR, with no remedy available under D-3's no-waiver rule. A PR's `created_at` is immutable, so the window makes the gate idempotent. | codebase-derived |
| D-10 | AC-1 evidence artifact and activation ordering | The run performs the probe itself. The evidence artifact is the manifesto's T0 note, recording the probe result verbatim on **both** branches (ruleset id + enforcement on success; the API rejection body on failure), so AC-1 is checkable from the diff either way. Activation is the run's **last** mutation, after the final branch push — this PR edits `.github/workflows/**`, and an active no-bypass push ruleset would otherwise block its own push. | codebase-derived |
| D-11 | Undefined fail-open holes | An applicable PR whose body carries neither `Closes #N` nor `Part of #N` **fails (exit 1)** — a pipeline branch with no traceable source issue is exactly the class this check exists to catch. A failed comment fetch **exits 2** (usage/environment error), never a silent pass. Mirrors `check-frozen-files.sh`'s existing exit convention (`0` clean / `1` violation / `2` environment). | codebase-derived |
| D-12 | Multiple issue references in one PR body | `Closes #N` wins over `Part of #N` when both appear; first occurrence within the winning form. This repo's PR bodies routinely carry both (`Closes #273` for the worked ticket plus `Part of #268` for the epic), so bare first-match would resolve to the epic and fail the branch-suffix comparison on every program PR. | codebase-derived |
| D-13 | `run_id` disclosure in public CI logs | Failure output prints only the `run_id`'s trailing random hex segment, never the full `{timestamp}-{hostname}-{hex}` form. Sufficient to distinguish families; no machine identifier reaches a world-readable Actions log. | codebase-derived |
| D-14 | Dynamic CI inputs transport | PR body, head ref, number and `created_at` ride in `env:`, never spliced into the `run:` body — the convention `ci.yml` already documents for `BASE_REF`. A PR body is far more attacker-controllable than a ref name, so the existing rationale applies with more force. | codebase-derived |

## Affected files/modules

| Path | Action |
| --- | --- |
| `docs/pipeline-manifesto.md` | `[NEW]` — P1–P7 text + T0 operator notes |
| `CLAUDE.md` | modify — one pointer line |
| `scripts/check-pipeline-chain.sh` | `[NEW]` — the rung-1 reconciliation check |
| `scripts/check-pipeline-chain-selftest.sh` | `[NEW]` — per-tool behavioral suite, zero network |
| `scripts/check-frozen-files.sh` | modify — advisory `.github/workflows/**` row + amended header + summary line |
| `scripts/derive-release-selftest.sh` | modify — advisory-row cases |
| `.github/workflows/ci.yml` | modify — `permissions:` block, job `env:` constants, new `pr-gates` step |

Server-side, not a file: one push ruleset on `manoldonev/second-shift` (probe → activate).

## Reuse inventory

- `scripts/check-frozen-files.sh` — the exit-code convention (`0` clean / `1` violation / `2`
  usage-or-environment) and the `cd "$(git rev-parse --show-toplevel)"` entry idiom. Reused verbatim
  by the new script rather than inventing a second convention.
- `scripts/derive-release-selftest.sh` — the `ok()`/`bad()` counter harness and throwaway-`git init`
  fixture shape. The new selftest mirrors this structure.
- `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh` — the PATH-mock recording-`gh`
  precedent. The new selftest uses the same technique for the live-fetch path, plus the
  `--comments-file` flag for the trail itself.
- `.github/workflows/ci.yml` `pr-gates` `BASE_REF` step — the `env:`-not-`${{ }}` transport
  convention (D-14).
- `plugins/dev-pipeline/skills/run/state-schema.md` — the authoritative stage-marker enum. Consumed,
  not re-derived.
- New helpers introduced: none beyond the two `[NEW]` scripts above.

## Implementation steps

1. **`docs/pipeline-manifesto.md`** `[NEW]` — P1–P7 verbatim from #268, the one-home statement, the
   P7 posture note, and a **T0 note** covering: the push-ruleset mechanism and why CODEOWNERS was
   rejected; the sanctioned-change toggle procedure (flip to `disabled`, merge, flip back) with the
   literal `gh api` commands; the probe result recorded verbatim (filled in step 7); and the
   statement that the manifesto is a judgment aid, not a gate — no lint polices it.
2. **`CLAUDE.md`** — one pointer line in the same style as the existing `docs/testing.md` /
   `docs/releasing.md` pointers.
3. **`scripts/check-frozen-files.sh`** — add the advisory row: if the diff touches
   `.github/workflows/**`, print a notice and increment a separate `advisories` counter that never
   feeds `fails`. Rewrite the header contract block to document the advisory tier (the current
   header states a binary 0/1 contract that the change falsifies). Change the terminal success line
   to distinguish `clean` from `clean — N advisory notice(s)`.
4. **`scripts/derive-release-selftest.sh`** — extend the `== PR gates ==` block with: a workflow-only
   PR passes (exit 0) **and** its output carries the advisory notice; a workflow edit combined with a
   real frozen-file violation still exits 1 (the advisory row does not mask a hard failure).
5. **`scripts/check-pipeline-chain.sh`** `[NEW]` — see the contract below.
6. **`scripts/check-pipeline-chain-selftest.sh`** `[NEW]` — see the case list below.
7. **Push-ruleset probe (D-7/D-10)** — create the ruleset at `enforcement: disabled` with a
   `file_path_restriction` on `.github/workflows/**` and no bypass actors. Record the API response
   verbatim into the manifesto's T0 note. On rejection: record the rejection body instead, plus the
   open-risk statement (rung 1 is then self-neutralizable — the `env:` constants live in the same
   agent-editable workflow file the gate runs from), and post that risk to #268. **No fake freeze.**
8. **`.github/workflows/ci.yml`** — add to `pr-gates`: a `permissions:` block
   (`contents: read`, `issues: read`, `pull-requests: read` — `contents: read` must be restated or
   checkout breaks, since a `permissions:` key replaces the defaults wholesale), job-level `env:`
   constants (`PIPELINE_BRANCH_PREFIX`, `PIPELINE_PLAN_PATTERN`), and the new step with
   `GH_TOKEN` + the dynamic PR inputs, all via `env:` per D-14.
9. **Activation (last mutation, D-10)** — after the final branch push, flip the ruleset to `active`
   if the probe succeeded, and re-record the resulting enforcement in the T0 note.

### `check-pipeline-chain.sh` contract

Inputs — env constants: `PIPELINE_BRANCH_PREFIX`, `PIPELINE_PLAN_PATTERN`. Dynamic env:
`PR_HEAD_REF`, `PR_BODY`, `PR_CREATED_AT`, `GH_REPO`. Seams: `${GH:-gh}` for the live fetch and
`--comments-file <path>` for a fixture trail.

Exit codes, mirroring `check-frozen-files.sh`: `0` pass or not-applicable, `1` chain violation,
`2` usage or environment error.

1. Either env constant unset or empty → **exit 2** (fail closed; never degrade to "non-pipeline,
   exempt").
2. `PR_HEAD_REF` does not start with the prefix → print `non-pipeline change — chain check not
   applicable`, **exit 0**.
3. Prefix matches but the suffix does not parse as `^[0-9]+(-pr[0-9]+)?$` → exempt-with-notice,
   **exit 0**. Yields `KEY_BRANCH` and an optional `-pr<N>` slice suffix.
4. Resolve `KEY_BODY` from `PR_BODY`: first `Closes #N`, else first `Part of #N` (D-12). Neither
   present → **exit 1** (D-11).
5. Three-way key consistency, each with its own message so each failure mode is independently
   testable: (a) `KEY_BODY` vs `KEY_BRANCH`; (b) the plan file exists at the pattern-derived path
   for `KEY_BRANCH` + slice; (c) the plan file exists at the pattern-derived path for `KEY_BODY` +
   slice, and is the same path as (b).
6. Fetch the comment trail — `--comments-file` when given, else
   `${GH:-gh} api "repos/$GH_REPO/issues/$KEY/comments" --paginate`. Non-zero fetch → **exit 2**
   (D-11).
7. Window the trail to `created_at <= PR_CREATED_AT` (D-9). Select the newest in-window comment
   carrying `<!-- stage: claimed -->`; its `<!-- run_id: … -->` is the active family. No in-window
   `claimed` → **exit 1**.
8. For each of `claimed`, `intake`, `plan`, `doc-update`, `code-review`: require at least one
   in-window comment carrying both that `stage:` marker and the active `run_id`. Missing → **exit
   1**, naming the marker and distinguishing "absent entirely" from "present only in another
   family". Family identifiers in output are truncated to the trailing hex (D-13).
9. All present → print a one-line pass summary, **exit 0**.

Header carries the consumer-unportability note: a read-only tracker (`tracker.writes: false`) posts
no comments by contract, so this check is second-shift-only per epic D-9 — under such a consumer it
would be inert by design.

## Test strategy

Verify-after (infra/CI change, no runtime behavior in a product surface). Tier per `CLAUDE.md`'s map:
**one script's behavior against fixtures → a per-tool `*-selftest.sh` next to the tool.** Tier
justification, as the ticket requires: the scenario-liveness suite is scoped to statectl-composed
verdict paths and cannot compose a GitHub-Actions-side reader, so no scenario covers this invariant;
and this is not a two-copies-of-one-contract case, so it is not a lockstep row.

`scripts/check-pipeline-chain-selftest.sh` [NEW] — throwaway `git init` fixture with committed plan files,
fixture comment trails as JSON, zero network:

1. Complete in-family chain, key-consistent → exit 0.
2. Each of the five required markers missing in turn → exit 1, naming that marker (five cases).
3. Marker present but only under a foreign `run_id` → exit 1 as wrong-family.
4. Two `claimed` families where the newer one post-dates `PR_CREATED_AT` → the in-window family is
   selected and the run passes (the D-9 idempotency case).
5. Missing `code-review` marker → exit 1 (AC-4's falsifiability case, kept explicit even though
   case 2 covers it structurally).
6. Prefix-matched branch with a non-key suffix → exit 0 with the exempt notice.
7. Branch not matching the prefix → exit 0 with the not-applicable notice.
8. Key inconsistency, each of the three pairs → exit 1 (three cases).
9. `Part of #N` resolution works with no `Closes` present; and `Closes` wins when both are present
   (D-12).
10. PR body with no resolvable reference → exit 1.
11. Failed `gh` fetch (mock exits non-zero) → exit 2.
12. Either env constant unset, and either empty → exit 2 (four cases).
13. **Anti-vacuity:** a hard precondition asserting the script exists and is executable (exit 2 with
    a distinct message if not), plus case 1 as the positive control — deleting
    `check-pipeline-chain.sh` turns the suite red rather than letting every "should fail" case pass
    on exit 127.

`scripts/derive-release-selftest.sh` gains the two advisory-row cases from step 4.

The `.github/workflows/ci.yml` edit is covered by `actionlint` in CI plus
`scripts/check-workflows-selftest.sh` locally (the YAML-syntax floor), and by AC-5's observation that
the existing `pr-gates` steps still pass on this very PR.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Push ruleset probed; active with no bypass, or gap recorded on #268 (evidence: the T0 note records the probe verbatim, D-10) | 1, 7, 9 | — no test (infra-only) |
| AC-2 | Complete key-consistent chain passes; missing/wrong-family marker or key mismatch fails | 5, 8 | selftest cases 1, 2, 3, 8 |
| AC-3 | Non-prefix PR passes with notice; unset/empty env constants fail closed | 5 | selftest cases 7, 12 |
| AC-4 | `code-review` leg is falsifiable | 5 | selftest case 5 |
| AC-5 | Job permissions + `GH_TOKEN`; checkout and existing steps still pass (observed on this PR's own `pr-gates` run; `actionlint` covers the syntax) | 8 | — no test (infra-only) |
| AC-6 | Advisory row warns without failing; chain selftest zero-network incl. anti-vacuity; sweep green | 3, 4, 6 | `derive-release-selftest.sh` advisory cases; selftest cases 1–13; full sweep |
| AC-7 | Manifesto exists with P1–P7 + T0 notes; `CLAUDE.md` pointer (per `CLAUDE.md`, prose gets no presence guard) | 1, 2 | — no test (non-functional) |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
bash scripts/check-pipeline-chain-selftest.sh
bash scripts/derive-release-selftest.sh
bash scripts/check-workflows-selftest.sh
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} bash {}
```

The sweep runs **without** `SKIP_STRESS=1` — only CI's ubuntu lane exercises the stress legs, so a
local run that skips them is not the green this repo's gate means.

## Risks / rollback notes

- **The ruleset can lock out the pipeline itself.** Once active, any future run that edits
  `.github/workflows/**` fails to push. Mitigation: the T0 note documents the toggle procedure with
  literal commands. Rollback: delete the ruleset (`gh api -X DELETE
  repos/{owner}/{repo}/rulesets/<id>`).
- **This gate binds this PR.** `claude/second-shift-273` matches the prefix, so this PR's own chain
  must be complete and its body must carry `Closes #273` before `Part of #268` matters (D-12 makes
  the ordering safe). If the gate is wrong, the PR cannot merge — which is the intended failure
  direction, but it means the selftest must be right before the wiring lands.
- **Push rulesets may be unavailable for user-owned repos.** Handled by D-7's probe; the fallback
  path ships an honestly-recorded gap rather than a fake freeze. If it fires, rung 1 is
  self-neutralizable and that limitation is recorded on #268.
- **Window selection depends on `created_at` ordering.** If GitHub ever returned comments without
  `created_at`, the window would empty and every applicable PR would fail. Acceptable: fail-closed is
  the intended direction, and the field is guaranteed by the REST schema.

Unverified references: none. Every path in the Affected-files table was read or `ls`-confirmed in
the pinned checkout; the two `[NEW]` scripts and the manifesto are created by this change.

## Out-of-scope

- Rung 2 (attested evidence, state-file receipts) — needs #244 + #243 §3; epic D-6 owns the
  CI-visibility mechanism.
- Shipping this gate to consumer repos (epic D-9 — dogfooding first; the check is structurally
  unportable to read-only trackers).
- The P7 prose-copy substitution in `intake-orchestrator` / `decomposition-reviewer` — #263's scope.
- Any lint policing the manifesto's prose (P5/T7 forbid it).
- Branch-protection ruleset changes (already active; T0's first half landed).
