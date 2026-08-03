# run-lean jira tracker adapter — spec

Issue: #362. Lane: `/dev-pipeline:run-lean`.

## Problem

`run-lean` is the default lane since the staged run was deprecated, but it was written
github-only. Three checklist items are unreachable on a `tracker.type: jira` /
`tracker.writes: false` consumer: the step-1 queue-label confirm has no jira meaning,
`cmd_claim` performs two forbidden tracker writes (and hard-fails on `GH_BOT`), and
`cmd_5` gates on `Closes #<n>` plus a closing tracker comment that cannot exist. An
otherwise-clean jira run burns its 3-attempt milestone-5 budget to `rc=4` *after* paying
for the full implementation and review.

## Scope

`lean-gate.sh` resolves `tracker.type` (absent ⇒ `github`) once and branches at exactly
three sites — the entry note, `cmd_claim`, and `cmd_5`. Milestones 1–4 are
adapter-insensitive and stay untouched. SKILL.md and the two tracker READMEs state the
delta. No new config keys; no `configVersion` change.

**Rebased mid-run onto the P10 authorship separation.** `main` gained the `verdict`
subcommand and out-of-session verdict authorship while this was in review. `cmd_verdict`
makes **no tracker call** — verified, not assumed — so it is not a fourth adapter-sensitive
site and the three-site claim stands. P10 is deliberately *not* adapter-scoped: the adapter
moves the tracker write, never the authorship check, and `(lean-jira-p10)` asserts a
build-authored verdict is refused on the jira arm exactly as on github. Consequence for this
run: the delivering session cannot author its own verdict, so it ends at a milestone-4
handoff for `/dev-pipeline:review-lean`.

## Acceptance criteria

- **AC-1** (oracle — `lean-gate-selftest.sh`): under a jira fixture config, `claim` exits
  0 making zero tracker calls with **no `GH_BOT` in the environment**; milestone 5 passes
  on a ready PR whose body carries `Closes [<KEY>]` in a `Jira Items` section and the
  verdict-record path, against an **empty** comment trail; and fails when the body omits
  either.
- **AC-2** (oracle — `lean-gate-selftest.sh`): the github arm is behaviorally unchanged —
  every pre-existing case still passes, including the `Closes #<n>` and
  closing-comment cases.
- **AC-3** (oracle — `lean-gate-selftest.sh`): with `tracker.type` absent the gate behaves
  exactly as github — the default is asserted, not assumed. An unrecognized
  `tracker.type` is a loud environment error (`rc=2`), never a silent fall-through to the
  github arm.
- **AC-4** (critic): `SKILL.md` and `tools/tracker/README.md` + `tools/tracker/jira/README.md`
  state the jira deltas, and no rule in `SKILL.md` asserts a tracker write as universal.
  `SKILL.md` stays within its 60-line cap (asserted by case `(f)`).
- **AC-5** (oracle — CI): frozen-files and changelog-trailer gates green; the PR carries a
  `Changelog:` trailer.
- **AC-6** (oracle — diff-scoped mutation sweep): the baseline is re-keyed from the sweep's
  own output rather than by hand, if the ordinals move. Measured on the **rebased** tree
  (`applied=10 killed=6 survived=4`), the survivor ids are byte-identical to the four
  `lean-gate.sh` rows now in `tools/mutation-baseline.tsv` — #361 retired the fifth
  (`detector::1`) — so nothing is owed and the file is untouched.
  **Read that green honestly.** `K_BUDGET=2` means only ordinals 1–2 per operator are
  mutated, and every one of those sites sits *above* every insertion point in this diff — so
  the sweep structurally cannot reach the new branch points, and its green is not evidence
  they are covered. Their coverage is behavioral: `(n0)`–`(n15)`, the `(lean-jira)` liveness
  leg, and twelve hand-applied mutants at the new sites (adapter-default flip, validation
  removal, claim-branch disable, both heading-regex halves, case-folding revert,
  verdict-in-body bypass, spec-link bypass, fixture-builder no-op) — all killed. Genuinely
  sweeping the branch sites would need `mutation-catalog.tsv` rows, not a raised `K`.
- **AC-7** (critic): no consumer-identity or operator-identity tokens in code, fixtures, or
  docs.
- **AC-8** (critic — doc, added during implementation per the lane's AC-scoped doc rule):
  `docs/onboarding.md`'s "the entry gate rejects a missing audit ledger or queue label"
  claim is scoped to the GitHub tracker. Making the lane runnable under jira is exactly
  what turns that sentence stale, so it is fixed in the same diff rather than left behind.
- **AC-9** (oracle — `scenario-liveness-selftest.sh`, added during implementation per
  CLAUDE.md's "a new gate contract extends the liveness scenario for every verdict path it
  touches"): a composed jira leg drives `claim → 1 → 2 → 3 → 4 → 5` with no `GH_BOT` and an
  empty comment trail, asserting that the progress file `cmd_claim` creates write-free is the
  same one milestones 1–5 satisfy, and that the adapter-insensitive milestones hold under an
  alphanumeric ticket key. Two reds keep it honest: `(lean-jira-nv)` strips the verdict path
  from the PR body, and `(lean-jira-p10)` re-authors the verdict with the **build** session id
  and requires milestone 4 to refuse it — the adapter must not become an authorship loophole.
  The per-tool `(n*)` cases prove the branch sites in isolation; only this proves they chain.

## Decisions taken during implementation

- **`Closes [<KEY>]` is matched section-scoped, at any heading level.** The contract is
  "the template's `### Jira Items` section"; the gate extracts the lines under a
  `^#+ Jira Items$` heading up to the next heading and matches inside that slice. Any
  heading level is accepted because the depth is a repo-template detail, not a contract;
  the *section* is the contract. A body carrying `Closes [KEY]` outside the section fails.
  The open and close patterns **both** require the space after the hashes, so they encode
  one definition of "heading" (CommonMark's — `###Notes` is literal text). An asymmetric
  pair is a false-ACCEPT: an optional-space open starts a pseudo-section that a
  required-space close never ends. Pinned in both directions by cases `(n13)`/`(n14)`.
  The heading match folds case (`(n15)`), matching the `-i` already on the ticket-reference
  grep: the repo's own jira prose caps the acronym, so `### JIRA Items` is a likelier
  consumer template than the canonical spelling, and rejecting it would burn milestone 5's
  whole budget after the work is paid for. A **nested** heading closes the section too —
  depth is ignored when opening (the template's level is the repo's choice) and any heading
  closes, because a flat "runs to the next heading" rule is the predictable one.
  **Not** widened further, deliberately: up-to-3 leading spaces and a trailing `###` closing
  sequence are CommonMark-legal and would false-REJECT, as would a fenced block whose first
  line begins `# `. All three need interval expressions (`{0,3}`) that are not portable
  across the awks this ships on — the same portability constraint the depth rule already
  bends to — and none appears in the template the contract names. Recorded rather than
  fixed so the boundary is a decision, not an oversight.
- **The claim branch keys on `tracker.type`, not `tracker.writes`.** Elsewhere in the
  toolkit (`preflight.sh`, `statectl.sh`) write-suppression reads `tracker.writes` with
  type as the fallback, so a `github` + `writes: false` config would suppress writes there
  and not here. That combination is off the documented adapter model — the two adapters are
  type/writes pairs — and honoring it in `cmd_claim` alone would leave milestone 5 still
  demanding a closing comment the run was told not to post. Keying both on `type` keeps the
  lane internally consistent, matches the issue's stated scope, and the SKILL.md rule now
  names `tracker.type: jira` as the discriminator rather than `writes: false`. A genuinely
  writes-keyed model spanning claim *and* exit is a separate change.
- **The spec-link assertion stays shared.** The issue enumerates the jira `cmd_5` asserts
  as ready-PR + `Closes [<KEY>]` + verdict-record reference. The committed-spec link is
  adapter-insensitive (a repo path at a pinned location under both adapters), so it is
  kept on both arms rather than dropped from jira — a superset of the enumeration, not a
  departure from it.
- **Open region resolved as specified:** jira `cmd_5` does **not** additionally assert
  that the progress file's run-id matches the verdict record's. Milestone 4 already gates
  the verdict record's `run_id:` key, and cross-record run-id consistency is
  `lean-reconcile.sh`'s job, not the gate's.
- **The derived lean branch prefix is unchanged under jira.** `lean_branch_prefix()` is
  the pinned single derivation shared with `check-lean-chain.sh`; the `run` lane's
  lowercase-key jira branch convention is that lane's, and duplicating it here would
  create a second name authority. Out of scope.

## Explicit non-goals

- `check-lean-chain.sh` stays dogfood-scoped — its own header declares it unportable
  *because* it reconciles against tracker comments. Consumer-side enforcement is filed
  separately.
- `lean-reconcile.sh` is unchanged, and it does **not** degrade gracefully under jira: it
  reads a bot-authored `lean-claimed` comment for its run-id triangulation, and a missing
  one calls `bad`, so it reports a **hard reconciliation failure on every jira run** until
  it is adapted — not a quieter two-source check. The progress-file anchor this change
  preserves is what that adaptation would build on. Flagged, not fixed: it is operator-side
  and outside the issue's scope. The consumer-facing statement of this — that a jira run has
  **no reconciliation backstop at all**, since `check-lean-chain.sh` keys off the same absent
  comment — is in `tools/tracker/README.md` and `SKILL.md`, not only here. The follow-up is
  surfaced in the PR body for the operator to file: opening an issue in-run would be a third
  tracker write, which the lane's two-writes rule forbids.
