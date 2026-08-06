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
