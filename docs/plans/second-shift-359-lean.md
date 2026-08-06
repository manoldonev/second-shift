# Lean spec — #359: consumer-side lean chain gate ships as plugin payload

The merge-boundary evidence a lean run leaves behind is currently checkable only inside this
repo: `scripts/check-lean-chain.sh` is second-shift-only by construction, and its own header
says so ("Do not ship this to the consumer CI template"). A consumer adopting the lean lane
therefore gets the harness and none of the enforcement — the promotion prerequisite the epic
(#343) named. This issue moves the portable half of that evidence set into plugin payload a
consumer's CI fetches at its pinned ref, and rewires this repo's gate to consume the same
bytes so there is one implementation rather than two that drift.

Binding input: the pre-flight receipt at `.claude/pipeline-state/359-ledger.md` (D-1..D-13,
OR-1/OR-2). It overrides the issue's framing where they disagree — D-2 (identity source) and
D-6 (which arms the core carries) both widen or supersede what the issue body assumed.

## Design

Design: none — this is shell/CI plumbing with no rendered surface. The repo configures no
`design.provider`, and nothing here changes a user-visible screen.

## Architecture

**The payload** — `plugins/dev-pipeline/skills/run-lean/lean-evidence.sh` (D-9: beside
`lean-gate.sh`, the lane owning its own gate). Model-free, network only for the PR comment
fetch, bash 3.2-compatible. Three entry shapes:

| Invocation | Does |
| --- | --- |
| `classify` | prints `applicable=`, `trigger=`, `key=`, `spec_in_diff=`; exit 0 |
| `check --key N [--arms …]` | runs the named arms against the resolved key |
| `all` (default) | classify, then check every arm — or exit 0 with a not-applicable line |

**Arms it carries (D-6).** Verdict (record exists, reads `verdict=approve`, carries both
reconciliation keys); identity distinctness (D-2/D-4); freshness via the declared
`reviewed_patch_id` arm; intent-gap ratification. The inheritance-chain and design-render arms
are **out** — OR-1, reversible-default-and-flag, and they stay in `check-lean-chain.sh`.

**Identity source (D-2).** A bot-authored marker comment on the **PR**, never the issue.
Source control is GitHub for every adapter, so this is the one write surface that needs no
`tracker.writes` branching. The comparison is against **every** bot marker on the PR, not the
first (D-4) — a second build session on the same PR would otherwise be measured against the
first session's marker and could author its own review.

**Zero markers is a violation under `tracker.type: github`**, not a vacuous pass: "differs
from every element of the empty set" is true and useless, and the gate's posture throughout is
that a check which cannot run must not report one. Under `tracker.type: jira` the arm is
**unavailable at reduced strength and printed** (D-5) — `config-lint.sh` rejects `tracker.bot`
under jira, so such a consumer has no authenticated writer and its marker would fail the
`.user.type == "Bot"` trust filter. The degrade is per-arm: every other arm still gates.

**The writer (D-3).** `lean-gate.sh` gains a `mark <issue>` subcommand posting one
bot-authored marker carrying `run_id` + `session_id`. See "Deviation from D-3" below for why
it fires at step 7 rather than only at milestone 5.

**Delegation (D-1).** `scripts/check-lean-chain.sh` calls the payload for classification and
for the verdict / identity / intent-gap arms, and for the freshness arm **only on the branch
that already exists** for it — the `#403` precedence branch where the record declares
`reviewed_patch_id`. Records predating that key keep this repo's legacy inferred and
`reviewed_head` paths untouched, so no in-flight or already-merged record changes verdict. Its
tracker-coupled arms stay: the bot `lean-claimed` comment on the **issue**, and the identity
comparison against that comment. Keeping the latter is strictly additive — this repo's gate
ends up stronger than the consumer core, which is a disclosable asymmetry, not a divergence.

**Consumer wiring (D-8, D-10, D-11, D-12).** Extend the existing `second-shift-ci.yml` rather
than adding a second workflow — a second workflow is a second required status check every
consumer must wire into branch protection, and the template already documents that a committed
workflow cannot require itself. The check script fetches the payload with
`gh api repos/<repo>/contents/<path>?ref=<ref>` at the lockfile's pinned ref; HTTP 404 is
FAIL, never WARN. Prefixes and `tracker.type` come from the committed
`.claude/second-shift.config.json` (consumers commit it; this repo gitignores its own, which
is why `ci.yml` needs env constants and a consumer does not).

**Exit-code mapping.** The payload's `1` (evidence violation) and `2` (environment error) both
map to the consumer script's FAIL. `2` is a FAIL and not the template's usual "could not
verify" WARN because the template supplies every input the payload needs (D-12): an env error
means template and payload are out of lockstep at the pinned ref, which is the same drift class
D-10 makes fatal. A network/auth failure of the *fetch itself* stays a WARN, unchanged.

## Deviation from D-3

D-3 places the marker write at milestone 5. A PR comment does not fire a `pull_request` event,
so it does not re-run `pr-gates`; the last CI run on a lean PR is the review session's
verdict-record push, and nothing pushes after it. A marker written at milestone 5 is invisible
to that run, so every lean PR reds until someone re-runs the job manually. D-3's stated
justification ("the PR exists by then") holds from step 7 onward, so the writer fires at step 7
and `cmd_5` re-calls it idempotently. Recorded as an intent-gap record
(`docs/plans/second-shift-359-lean-intent-gap.md`), region `undeclared`, ratified out of band
before the review handoff.

## ACs

- **AC-1 (oracle — payload selftest).** `lean-evidence.sh` ships at the D-9 path with a
  hermetic `lean-evidence-selftest.sh` (no network; the PR trail arrives through a
  `--pr-comments-file` fixture seam) asserting: complete evidence exits 0; a missing verdict
  record exits 1; a verdict whose `run_id` equals a bot marker's exits 1; a verdict whose
  `session_id` equals a bot marker's exits 1; zero bot markers under `tracker.type: github`
  exits 1; an operator-authored (non-`Bot`) marker does not satisfy the arm; an intent-gap
  record reading `ratified: no` exits 1, and one reading `ratified: yes` with no `ratified_by:`
  URL exits 1; an absent or mismatched `reviewed_patch_id` exits 1; a non-lean branch carrying
  no lean spec exits 0 as not-applicable.
- **AC-2 (oracle — template selftest).** `second-shift-ci.yml` and `second-shift-ci-check.sh`
  invoke the payload fetched at the lockfile's pinned ref, and
  `second-shift-ci-check-selftest.sh` asserts: a stubbed HTTP 404 on the payload path is FAIL
  naming the 404 (a moved path is drift, never a silent pass); a network/auth error stays a
  non-fatal WARN; a fetched payload reporting a violation is FAIL; a non-lean PR reports
  not-applicable and adds no FAIL; and the YAML carries `fetch-depth: 0` plus the
  `PR_HEAD_REF` / `PR_HEAD_SHA` / `PR_BASE_REF` / `PR_BODY` / `PR_NUMBER` / `GH_REPO` step env
  the payload's arms require.
- **AC-3 (oracle — delegation).** `scripts/check-lean-chain.sh` obtains classification and the
  verdict / identity / intent-gap arms from the payload, and the freshness arm from it whenever
  the record declares `reviewed_patch_id`, holding no second copy of any of them.
  `check-lean-chain-selftest.sh` stays green and gains a case pinning that a PR with otherwise
  complete evidence but **no bot PR marker** is refused.
- **AC-4 (oracle — writer).** `lean-gate.sh mark <issue>` posts exactly one bot-authored PR
  marker carrying `run_id` and `session_id`; a second call posts nothing (idempotent); under
  `tracker.type: jira` it writes nothing and prints the reduced-strength note. `cmd_5` calls
  it. `lean-gate-selftest.sh` covers post, idempotent no-op, and the jira skip.
- **AC-5 (oracle — config resolution).** The payload resolves `LEAN_BRANCH_PREFIX`,
  `PIPELINE_BRANCH_PREFIX` and `tracker.type` from the caller's environment when supplied and
  from the committed `.claude/second-shift.config.json` otherwise, deriving the lean prefix by
  replacing the first path segment of `tracker.branchPrefix` with `lean` and refusing a pair
  that is not mutually non-prefix-matching. Both resolution paths are driven by the selftest.
- **AC-6 (oracle — jira degrade).** Under `tracker.type: jira` the identity arm prints an
  explicit reduced-strength line and is not evaluated, while every other arm still gates — the
  selftest asserts both halves (the line is present, and a jira fixture with a missing verdict
  still exits 1).
- **AC-7 (mutation baseline).** Editing `check-lean-chain.sh`, `lean-gate.sh` and
  `second-shift-ci-check.sh` re-keys their generic survivor ordinals: the affected
  `tools/mutation-baseline.tsv` rows are re-baselined in this same diff, and any
  `tools/mutation-catalog.tsv` row addressing those guards is re-anchored (D-13).
- **AC-8 (doc).** `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` documents the new
  arm and its required-status-check wiring; `plugins/dev-pipeline/skills/run-lean/SKILL.md`
  step 7 names the `mark` call; `scripts/lockstep-manifest.tsv` carries the marker-shape row
  binding the writer in `lean-gate.sh` to the reader in `lean-evidence.sh`.
- **AC-9 (critic).** Every commit carries a `Changelog:` trailer, and no consumer identity —
  repo names, org names, or company ticket keys — appears in any fixture, doc or message.

## Out of scope

OR-1's inheritance-chain and design-render arms (they stay in `check-lean-chain.sh`; their
absence from the consumer core degrades to an unverified inheritance claim and an unscored
render, never an opened primary evidence path). OR-2's `tracker.bot` axis decoupling — a
`configVersion` schema change carrying a migration doc, filed as a successor rather than
ridden here. The attestation disclosure register's gate-strength entry (#353) is additive and
not a dependency.
