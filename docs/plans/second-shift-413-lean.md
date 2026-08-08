# run-lean branch names use the staged lane's formula (#413)

The lean lane's branch name is `<branchPrefix><key>` — the same formula the staged lane
already uses — and the lean/staged discriminator moves off the branch name onto the
committed lean spec.

Two defects die together. `lean_branch_prefix()` re-rooted the configured prefix under a
`lean/` namespace no other lane uses, and the unset-`branchPrefix` default `claude/acme-`
leaked a placeholder org slug into real branch names. Both are replaced by one shared
resolver that fails loudly rather than guessing.

## Binding inputs

`.claude/pipeline-state/413-ledger.md` (pre-flight) is binding. It narrows the issue in three
places, all carried below: D-1 scopes the shared resolver to the two **live** consumers
(`lean-gate.sh`, `retro-corpus.sh`) and leaves the deprecated staged lane's prose in
`stages/2-worktree.md` untouched; D-2 fixes what counts as a detection candidate; D-3 fixes
the precision of the pipeline gate's lean exclusion. D-9's claim that no transition window is
needed was **re-confirmed empirically at spec time**: `gh pr list --state open` returns one
PR (`#412 release/next`), so zero `lean/`-prefixed PRs are in flight.

One decision the receipt did not cover was put to the operator before implementation began
and is recorded here as the twelfth ledger entry:

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-12 | How far the artifact discriminator extends, now that both lanes share one branch namespace | **All three discriminating sites**, not just `check-pipeline-chain.sh`. D-3's key-matched-lean-spec rule is mirrored into `check-lean-chain.sh`'s applicability arm and into `retro-corpus.sh`'s `open-prs` candidate filter. This is a deliberate deviation from the issue's "the lean-spec-in-diff arm alone" wording (proposal 3), taken because dropping the branch-prefix discriminator without adding key precision leaves every gate claiming PRs the other one owns — the exact double-classification D-3 exists to prevent, reintroduced from the other side. | user-answered | intent |

`OR-1` (open region, disposition `reversible-default-and-flag`) is resolved by **AC-12**: a
lean PR carrying no spec in its own diff is claimed by neither gate's lean arm and reds on
`check-pipeline-chain.sh`'s stage markers. That is the ledger's stated default — fail-closed
is the correct bias at a merge boundary — and it is flagged in the PR body. The region asked
for the reopened-PR case to be confirmed rather than reasoned about; AC-12 makes that
confirmation a selftest case driven through the real gate, not prose.

## Scope

`tools/mutation-slow-suites.tsv` (added after the first CI run — see AC-16),
`plugins/dev-pipeline/skills/run-lean/branch-prefix.sh` **[NEW]** and its selftest,
`plugins/dev-pipeline/skills/run-lean/lean-gate.sh` + `lean-gate-selftest.sh`,
`plugins/dev-pipeline/skills/run-lean/SKILL.md`,
`plugins/dev-pipeline/skills/run/tools/retro-corpus.sh` + its selftest,
`plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh`,
`plugins/dev-pipeline/skills/pipeline-retro/SKILL.md`,
`scripts/check-lean-chain.sh` + its selftest,
`scripts/check-pipeline-chain.sh` + its selftest,
`scripts/lockstep-manifest.tsv`, `.github/workflows/ci.yml`,
`docs/pipeline-manifesto.md`, `tools/mutation-baseline.tsv`,
`.claude/prose-budget.baseline.tsv`.

Out of scope, per the issue and D-5: the artifact suffixes keep the `-lean` token
(`-lean.md`, `-lean-verdict.md`, `-lean-renders.md`, `-lean-intent-gap.md`,
`-lean-progress.md`). They are cited across every committed spec and verdict under
`docs/plans/`, and no lane can red on a citation a rename left stale. Also out of scope per
D-1: `plugins/dev-pipeline/skills/run/stages/2-worktree.md` and the jira adapter README keep
their existing prose — the staged lane is deprecated and its detection paragraph is
specification, not a live consumer.

`plugins/dev-pipeline/skills/run-lean/lean-reconcile.sh` was inspected and needs **no**
change: it resolves the verdict-record path from `plansDir` + repo slug + key and never
touches a branch prefix. The issue's proposal 5 lists it as a consumer to follow; following
it resolves to nothing.

## Design

Design: none — no `design.provider` is configured for this repo, and the change touches no
rendered surface.

## Acceptance criteria

- **AC-1.** With `tracker.branchPrefix` set, the lean lane's branch is `<branchPrefix><key>`,
  byte-identical to what the staged lane's formula (`stages/2-worktree.md:31`) yields for the
  same key. No `lean/` path segment appears in any branch name the lane creates or looks up,
  and `lean_branch_prefix()` exists in neither `lean-gate.sh` nor `retro-corpus.sh`.

- **AC-2.** With `tracker.type: jira`, the key is lowercased in the branch name, matching the
  staged lane's jira rule (`tools/tracker/jira/README.md:44`).

- **AC-3.** With `tracker.branchPrefix` unset and existing remote branches carrying a single
  dominant `<identifier>/` prefix, both lanes resolve that identifier. `claude/acme-` is
  never written into a branch name as a fallback — the placeholder default is gone from every
  branch-name resolution path.

- **AC-4.** With `tracker.branchPrefix` unset and no dominant prefix detectable — zero
  candidates, or a tie for the top count — resolution exits non-zero with a message naming
  the candidates it considered (and, when there are none, what it scanned).

- **AC-5.** One detection implementation, called by both live consumers (D-1). A second copy
  of the derivation in `lean-gate.sh` or `retro-corpus.sh` is a regression.

- **AC-6.** `check-lean-chain.sh` classifies a lean PR whose branch carries the staged prefix,
  via the artifact arm, with no `LEAN_BRANCH_PREFIX` in its environment. The variable is
  absent from the script, from `.github/workflows/ci.yml`, and from the manifesto's account of
  the `pr-gates` constants.

- **AC-7.** `check-pipeline-chain.sh` reports not-applicable for that same PR, and is
  unchanged in its verdict for a staged PR carrying no lean spec.

- **AC-8.** The lean-spec-suffix coupling between the two gates has a
  `scripts/lockstep-manifest.tsv` row, and `scripts/check-lockstep-pairs.sh` passes. The
  manifest's now-obsolete `lean branch prefix` DROPPED note is replaced rather than left
  describing a constant that no longer exists.

- **AC-9.** A lean PR opened on a `lean/`-prefixed branch before this change still classifies
  correctly under `check-lean-chain.sh` via the artifact arm — confirmed by driving the gate
  with such a head ref, not by assertion.

- **AC-10.** `check-pipeline-chain.sh` exempts a prefix-matched PR **only** when its diff
  carries a non-fixture `*-<key>-lean.md` whose key equals the branch key it already extracts
  (D-3). A prefix-matched PR whose diff carries a lean spec for a *different* key stays fully
  gated.

- **AC-11.** `check-lean-chain.sh` applies **only** when the diff carries a non-fixture lean
  spec whose key equals the key resolved from the PR body, and `retro-corpus.sh open-prs`
  counts a PR as a lean candidate only under the same key-matched-lean-spec rule (D-12). No
  PR is applicable to both chain gates. A PR carrying a lean spec but no resolvable
  `Closes #N` / `Part of #N` still **fails** rather than being exempted — the pre-existing
  refusal is preserved, not traded away for the new precision.

- **AC-12.** (OR-1) A PR whose branch is prefix-matched and whose diff carries *no* lean spec
  is not applicable to `check-lean-chain.sh` and **is** applicable to
  `check-pipeline-chain.sh`, where it reds on the missing stage markers. Driven through both
  real gates as a selftest case, which is the empirical confirmation OR-1 asked for.

- **AC-13.** (docs) `run-lean/SKILL.md` step 3 no longer says "lean prefix", and stays within
  its 60-line cap. `pipeline-retro/SKILL.md`'s `gh pr list --head` recipe uses the new
  formula. `docs/pipeline-manifesto.md`'s "A third constant" section is rewritten to describe
  the boundary that now exists — two constants, and a lean gate that classifies by artifact
  alone — instead of a third constant that has been deleted.

- **AC-14.** (tests) The new resolver has a behavioral selftest covering: configured-prefix
  passthrough, detection from a dominant identifier, the zero-candidate refusal, the tie
  refusal, and the jira key-pattern arm. `scenario-liveness-selftest.sh` gains a lean leg for
  every verdict path this change touches (D-10). Both chain-gate selftests keep their existing
  cases green, with the prefix-only cases replaced rather than deleted.

  **Amended at review round 3 (blocker B-2).** The enumeration above omitted
  `lean-gate-selftest.sh`, and the omission is where the round-3 defect lived, so the AC now
  names it: `(e5)` — the case asserting that the branch-name check stays out of milestones 1-4 —
  must REACH milestone 1's body. `main`'s `require_entry_attested` (#416/#422) guards the
  subcommand at dispatch, so a fixture that trips the precondition observes nothing inside
  `cmd_1` and the case cannot fail for its own reason. The case therefore seeds the attestation
  through the prefixed config and evaluates under the prefix-less one, varying only the thing
  under test, and is verified by injecting `require_branch_name` into `cmd_1` — the exact
  regression its comment names — and confirming it is the only red.

- **AC-15.** (verification) `shellcheck` clean over all shell, `jq empty` clean over all JSON,
  and the full `*-selftest.sh` sweep green — run without `SKIP_STRESS` and with the session-id
  environment leak cleared. `tools/mutation-baseline.tsv` rows whose ordinals this diff re-keys
  are re-baselined in the same diff, and the new guard's own accepted survivors are enumerated
  by probing every first-`K` mutant against its paired selftest rather than by assertion.

  `.claude/prose-budget.baseline.tsv` is deliberately **not** touched, and the measurement is
  recorded here rather than left as a silent omission: that baseline is already stale repo-wide
  on the base branch — 19 failing rows, including both files this change edits
  (`run-lean/SKILL.md` 575 → 972, `pipeline-retro/SKILL.md` 2377 → 3227, measured at
  `origin/main`). This change moves them to 992 and 3296, altering no row's pass/fail state and
  leaving the repo-wide fail count at 19. Splicing two rows would reset budgets this change did
  not blow and would read as a claim it had.

- **AC-16.** (added mid-run, after CI) The PR-lane mutation sweep completes inside its
  `timeout-minutes: 15` step bound. `tools/mutation-slow-suites.tsv` gains the two paired
  suites that meet its own stated ≥ 5s membership criterion but were missing from it —
  `lean-gate-selftest.sh` and `check-lean-chain-selftest.sh` — so the lane's existing deferral
  valve can fire on them. The guard this change **introduces** (`branch-prefix.sh`) is still
  swept on the PR lane, not deferred. The step timeout is **not** raised: the bound was not
  wrong, the data feeding it was absent.

  Rationale, so the coverage cost is a decision and not a side effect: the first CI run
  cancelled `lint-and-selftests` at that step. This diff touches five guards, and two of their
  killers run 38s and 16s — a 53-mutant enumeration against them. Those two suites were being
  treated as fast solely because the list did not name them, so the PR lane swept guards its
  own policy says to defer. The consequence is that `lean-gate.sh` and `check-lean-chain.sh`
  now defer to nightly on every PR, which is the policy the repo already wrote for
  `statectl.sh` and `scenario-liveness-selftest.sh`; it simply was not being applied.

- **AC-17.** (added at review round 1, blocker B-1) **No PR is exempted by both chain gates.**
  The two gates resolve the issue key from different sources — `check-lean-chain.sh` from the
  PR body's `Closes #N` / `Part of #N`, `check-pipeline-chain.sh` from the branch — so when the
  two disagree and the diff commits the **branch** key's lean spec, the sibling exempts on
  exactly that spec and this gate must **not** decline onto it. It fails, naming both keys and
  the spec that split them. Scoped to that cell: the same key disagreement with no branch-key
  spec in the diff still declines, because there the hand-off is real. Driven through both real
  gates from one input set, in both suites — `check-lean-chain-selftest.sh` (D3)/(D3b) and
  `check-pipeline-chain-selftest.sh` (l8).

- **AC-18.** (added at review round 1, warning W-2) Run with no `--config`, no
  `SECOND_SHIFT_CONFIG` and no `--repo-root`, `branch-prefix.sh` reads the config from the
  **main** checkout (`--git-common-dir`), the same root both of its callers resolve. The
  runtime config is gitignored, so no worktree carries a copy; anchoring on `--show-toplevel`
  put the bare invocation on a root its callers never use, where it silently took the detection
  path and answered with whatever namespace the repo's remotes happened to favor.

- **AC-19.** (added at review round 3, blocker B-1) **The two chain gates derive the issue key
  in lockstep, not merely match on it.** `lean-gate.sh` milestone 5 asserts that
  `Closes #<issue>` appears in the PR body **at least once** and never that it is first, so
  `check-lean-chain.sh` resolving the body key by FIRST match reads a different key than the one
  the lane guaranteed. It therefore resolves to the **branch** key whenever the body closes it,
  falling back to the first match only when the body never names the branch key at all. A body
  that mentions another `Closes #N` in prose or a code span is then classified by the work it
  authored rather than by a phantom key lifted out of quoted text — while AC-17's refusal is
  untouched in the cell it was written for, since a body that never closes the branch key is a
  real disagreement rather than a quoting artifact.

  This is AC-11's own generalizable lesson applied to the gate that taught it: proving the two
  gates agree on the *pattern* the key feeds does not prove they agree on the *key*. It is not
  hypothetical — before this AC the mechanism false-red **this PR**, whose body documents the
  AC-11 counterexample verbatim, and the failure mode reproduces for any future lean PR whose
  body legitimately quotes the token (a review narrative about this bug class being the likeliest
  such body).

  Driven in `check-lean-chain-selftest.sh`: `(D3c)` pins the quoting artifact classifying to the
  branch key, `(D3d)` pins that the preference does **not** degrade into ignoring the body — a
  body that never closes the branch key must still hit AC-17's refusal. Both probed in both
  directions; `(D3c)` is the only red when the preference is disabled, and `(D3)`/`(D3d)` are the
  reds when it is made unconditional. The one first-`K` mutation ordinal the edit re-keys
  (`scripts/check-lean-chain.sh::detector::2`) was probed with the verbatim operator flip and is
  **killed**, so no baseline row is added or moved.

### AC-11, restated (review round 1)

AC-11 above claimed "**No** PR is applicable to both chain gates." That direction was verified
and holds for every PR whose body key agrees with its branch key, but as a universal statement
it is false and was never driven: a PR on branch `<prefix>500` whose body says `Closes #392`
and whose diff carries `…-392-lean.md` is applicable to both — the lean gate on the body key,
the pipeline gate because no `…-500-lean.md` is present. Both then red, so it is not a hole; it
is an over-claim. The property that actually holds, and the one AC-17 asserts, is the
complement the original set never stated: **no PR is exempt from both.** Where the two keys
agree, exactly one gate applies. Where they disagree, both may fire and neither may be silent —
fail-closed, which is the correct bias at a merge boundary.

The generalizable form, recorded in `docs/pipeline-manifesto.md` alongside the gate it bit:
when one classification is split across two checks, hold the **key derivation** in lockstep, not
only the pattern the key feeds. Proving disjointness in one direction reads as if it proved the
complement; it does not.

### Test tier for AC-17 (D-10, stated rather than skipped)

D-10 mandates a `scenario-liveness-selftest.sh` leg for every verdict path a gate contract
touches. AC-17's path is in `check-lean-chain.sh`, a **GitHub-Actions-side reader**, and that
suite is scoped to statectl-composed verdict paths — the same tier justification both chain-gate
selftests already carry in their headers, and the reason those two suites exist at all. AC-17 is
therefore covered by the paired per-tool suites on both sides plus their cross-references, and no
scenario leg is added. Recorded here so the absence is a decision rather than an omission.

