# second-shift #419 — plan-lint-selftest is not hermetic; ship a class guard for it

## Problem

`plugins/dev-pipeline/skills/run/tools/plan-lint-selftest.sh` case `pl-n3` fails wherever the
suite is run from its marketplace install. Because `pipeline-doctor.sh` runs the suite, this
surfaces as a `FAIL` in `preflight.sh` during onboarding, on a repo whose own config is clean.

**The root cause is not the one the issue states, and the pre-flight receipt
(`.claude/pipeline-state/419-ledger.md`) is binding where the two disagree.** The trigger is the
*harness's own location*, not the consumer repo's tree:

- `plan-lint-selftest.sh:313` puts the `pl-n1..n5` fixtures at `NTMP="$HERE/.plan-lint-newtag-tmp"`
  — inside the selftest's own directory.
- Installed from the marketplace that directory is
  `~/.claude/plugins/cache/second-shift/dev-pipeline/<ver>/skills/run/tools`, which has **no git
  repo above it**, so `PLAN_ROOT` (`plan-lint.sh:326`,
  `git -C "$(dirname "$PLAN")" rev-parse --show-toplevel`) resolves empty and check 5a is skipped
  wholesale. The ghost path is never evaluated.

Reproduced on this branch's base, from the 4.0.0 install cache:

```
$ (cd /tmp && bash ~/.claude/plugins/cache/second-shift/dev-pipeline/4.0.0/…/plan-lint-selftest.sh)
  FAIL: (pl-n3) ghost path — rc=0 err=
[plan-lint-selftest] summary: 42 passed, 1 failed
$ (cd <this repo> && bash <same path>)          # a tree that DOES have top-level plugins/
  FAIL: (pl-n3) ghost path — rc=0 err=
```

Identical from both cwds, which is what rules the issue's stated cause out as the trigger: it is
real only in the vendored-in-tree topology (`--plugin-dir`). One hermetic fixture covers both.

`pl-n4` and `pl-n5` are collateral of the same defect. With 5a never running, both `→ 0`
assertions pass **vacuously**: n4 never exercises the `[NEW]` tag path, n5 never exercises the
top-dir precision guard it documents.

The defect is a class, not an instance: a shipped suite silently depends on the tree it is
authored in, and nothing in CI runs any suite from the shape a consumer actually installs.
`design-sync-selftest.mjs` has the same class of defect
(`join(HERE,'..','..','..','..','design-toolkit',…)` assumes the monorepo `plugins/<name>/`
layout, `design-sync-selftest.mjs:41`) and is red under the install topology while green in-repo.

## Binding decisions (transcribed from the pre-flight receipt)

The receipt's ten decisions are the design. Reproduced here because a reviewer reads the spec, not
the state dir. Where a decision overrides the issue as filed, it is marked.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Width of the hermetic rewrite | All five `pl-n1..n5` cases move into ONE `git init`'d `mktemp -d` repo containing a real top dir. Fixes the red, de-vacuums n4/n5, and stops the suite writing a scratch dir into its own install directory. n3's `rc=1` in that repo is the standing witness that check 5a is live, so n4/n5's zeros mean something again. **Overrides the issue**, which scoped the fix to n3/n4. | user-answered |
| D-2 | Whether the sibling suites that are also red off-repo are in scope | In scope: fold in `design-sync-selftest.mjs` and add a class guard. The other reds are deferred — see D-6. | user-answered |
| D-3 | Which install topology the class guard reproduces | Version-keyed install cache: each plugin staged at `<root>/<plugin>/<version>/`, outside any git repo. Strict superset — it reproduces both the absent-git-repo property (#419) and sibling separation (`design-sync`). A detached copy of `plugins/` keeps siblings adjacent and structurally cannot catch the second defect. | user-answered |
| D-4 | What a shipped suite does when a repo-only artifact it needs is absent | Named, counted SKIP under the install topology; unchanged hard FAIL in-repo. The lockstep is a repo-time contract — a consumer cannot act on a drift they cannot see — but the skip must be printed and counted, never silently green. | user-answered |
| D-5 | How the class guard is wired | A plain `tools/install-topology-selftest.sh`. CI's existing `find . -name '*-selftest.sh'` (`ci.yml:85-92`) discovers it; no CI edit, no new job, no registration. It stages `plugins/` only, and `tools/` is not under `plugins/`, so it cannot stage itself — no recursion guard needed. | user-answered |
| D-6 | How the guard lands while 4 unrelated suites are still red | `tools/install-topology-known-red.tsv`, same idiom as `tools/mutation-baseline.tsv`: the guard reds only on a suite absent from the list. #419 fixes `plan-lint` and `design-sync` and files no rows for them. The remaining reds get a follow-up ticket. | user-answered |
| D-7 | How `design-sync-selftest.mjs` resolves its cross-plugin path | Mirror `resolve_sibling` (`pipeline-doctor.sh:30-41`) in `.mjs`: monorepo path → same-version sibling in the cache → newest sibling version. | codebase-derived |
| D-8 | Guard must bound each suite's runtime | Per-suite timeout, non-zero on expiry. `statectl-selftest.sh` ran 5:25 against a ~94s norm during probing; this repo has a known `until ! pgrep -f` waiter that deadlocks against a second matching copy, so a hang is a live failure mode and an unbounded guard would hang CI rather than red it. | codebase-derived |
| D-9 | Seeding of the known-red list | Deferred to the guard's first clean run under D-3's topology — parked under OR-1. | deferred |
| D-10 | Diagnosis of `audit-toolkit/scripts/audit-selftest.sh`'s red | Deferred to the follow-up ticket — parked under OR-2. | deferred |

**Open Regions.** OR-1 (the full red set under the version-keyed topology is unmeasured) and OR-2
(`audit-selftest.sh` fails off-repo for an undiagnosed reason) both carry disposition
`reversible-default-and-flag`. Their defaults are taken as written: seed the list from the guard's
first run under D-3's topology, and mark any row whose cause is unknown `undiagnosed` rather than
inventing a rationale. Reversal is one line in a TSV either way.

**One D-8 premise did not survive contact with the tree.** Its stated mechanism — "this repo has a
known `until ! pgrep -f` waiter that deadlocks against a second matching copy" — is not true of
this checkout: `grep -rn pgrep --include='*.sh'` finds exactly one use, `mutation-sweep-selftest.sh`'s
orphan *count*, and no waiter anywhere. The decision itself stands on its other, measured leg
(statectl at 244s against a ~94s norm, and an unbounded suite taking the CI job timeout rather
than reding), so the bound ships — but the guard and `docs/testing.md` state the real reason, and
neither repeats the waiter claim.

**D-4 is deferred with the reds it governs.** It states policy for a suite that needs a repo-only
artifact; both such suites (`check-review-context-sections-selftest.sh`, `config-lint-selftest.sh`)
are in D-6's deferred set, so D-4 ships with the follow-up ticket, not here. Its *principle* —
a skip is printed and counted, never silently green — is applied inside the guard itself (AC-6).

## Mechanism

**The hermetic fixture (AC-1, AC-2).** `pl-n1..n5` build their plans in, and lint them from, one
`git init`'d `mktemp -d` repo that contains a real top directory of the fixture's own making. The
established sibling idiom is `git init -q` inside `mktemp -d` (`preflight-selftest.sh:52`). The
ghost path then cites a top dir that exists *in the fixture*, so check 5a's precision guard admits
it wherever the suite is installed, and n3's `rc=1` becomes a standing witness that 5a is live in
that repo — which is exactly what restores meaning to n4's and n5's zeros.

**The sibling ladder (AC-3).** `design-sync-selftest.mjs` grows a `resolveSibling()` mirroring
`pipeline-doctor.sh`'s three rungs. Note the install cache carries *different* versions per plugin
(measured: `dev-pipeline 4.0.0` alongside `design-toolkit 2.2.1`), so rung 2 misses in a real
install and rung 3 is the one that hits — the guard stages each plugin at its own declared
`plugin.json` version precisely so that rung is exercised rather than assumed.

**The class guard (AC-4..AC-6).** `tools/install-topology-selftest.sh` stages `plugins/<name>/` to
`<mktemp root>/<name>/<version>/`, asserts no git repo resolves above that root, and runs every
staged `*-selftest.sh` and `*-selftest.mjs` with cwd set to a separate `git init`'d consumer
directory holding none of this repo's tree. That cwd is the second half of the reproduction: it is
what a consumer repo *is*, and it is where the issue's own stated symptom would appear.

Runtime is bounded per suite (D-8) by a `kill -0` watchdog rather than `timeout(1)`, which is not
present on stock macOS. Expiry is reported as a named timeout, distinct from a suite that ran and
failed. The guard runs suites with `SKIP_STRESS=1`: D-8's mandate is to bound runtime, the class
under test is path resolution rather than stress behavior, and the in-repo CI lane already
exercises the stress legs.

## Acceptance criteria

- **AC-1** — `pl-n1` … `pl-n5` in `plan-lint-selftest.sh` are hermetic: every one of the five plans
  is written into, and linted from, a single `git init`'d `mktemp -d` repository containing a real
  top directory created by the fixture. The suite creates no scratch directory under `$HERE` (its
  own install directory). `plan-lint-selftest.sh` exits 0 when run from a version-keyed install
  cache with no git repo above it, from **both** an out-of-repo cwd and an in-repo cwd.

- **AC-2** — In that fixture repo the three check-5a assertions are non-vacuous and say so in a
  comment: `pl-n3` (untagged ghost path beneath the fixture's real top dir) → `rc=1` naming
  `does not exist`; `pl-n4` (the same path `[NEW]`-tagged) → `rc=0`; `pl-n5` (a path whose top dir
  is absent from the fixture repo, plus a branch-name shape) → `rc=0`. n3's non-zero is the
  standing witness that makes n4's and n5's zeros mean something.

- **AC-3** — `design-sync-selftest.mjs` resolves `contract-types.mjs` through a three-rung ladder
  mirroring `resolve_sibling` (`pipeline-doctor.sh:30-41`): monorepo `<plugins>/<sib>/<rel>`, then
  the same-version sibling in the cache, then the newest sibling version carrying the file. The
  suite exits 0 both in-repo and under AC-4's staged topology, where the two plugins carry
  different versions. When no rung resolves, the failure names the sibling and every path tried.

- **AC-4** — `tools/install-topology-selftest.sh` exists and, on one run: stages each
  `plugins/<name>/` at `<root>/<name>/<version>/` with `<version>` read from that plugin's
  `.claude-plugin/plugin.json`; asserts `<root>` has no git repository above it; and runs every
  staged `*-selftest.sh` and `*-selftest.mjs` with cwd set to a separate `git init`'d directory
  containing none of this repo's tree. Every suite runs under a per-suite wall-clock bound whose
  expiry is a non-zero result reported as a named timeout, never a hang.

  *(Amended before milestone 5: `INSTALL_TOPOLOGY_TIMEOUT` defaults to 1200s, not 600s. The AC's
  contract is unchanged — the bound's job is to make a hang attributable — but at 600s ambient
  machine load could cross it: `statectl-selftest.sh` inside the guard timed out under a
  stress-inclusive outer sweep at `-P 4`, and did not on a later sweep of the same tree. A bound
  that only sometimes fires on a healthy tree is a flaky test wearing a hang detector's clothes,
  and it is unattributable by construction. The stated rule that sets the value — ≈2x the worst
  contended run observed — is what moved it, because under the stress-inclusive form the
  contending load is the whole sweep rather than a single second copy.)*

- **AC-5** — The guard's verdict: a staged suite that fails or times out reds the guard **unless**
  its **repo-relative** path (`plugins/<name>/<rel>`) appears in
  `tools/install-topology-known-red.tsv`. A listed suite that passes is a printed warning, never
  red — the "shrink the list" direction, mirroring `mutation-baseline.tsv` — and so is a row that
  matches no staged suite. The run prints counts for ran / passed / known-red / skipped / stale /
  red, and every red is named with its cause line.

  *(Amended before milestone 5: the key is repo-relative, not staged-relative as first written. A
  staged path carries the version segment, so every row would rot at the next release.)*

- **AC-6** — A suite the guard cannot run for an environmental reason (no `node` for a `.mjs`
  suite) is a **named, counted skip** — printed, never silently folded into "passed" (D-4's
  principle). The skip count appears in the summary line.

- **AC-7** — `tools/install-topology-known-red.tsv` is seeded from this guard's first clean run
  under AC-4's topology (OR-1's default), **corroborated in a second environment before the
  counts are stated anywhere**. It carries **no** row for `plan-lint-selftest.sh` or
  `design-sync-selftest.mjs`. Every row states a one-line cause; a row whose cause is not known
  reads `undiagnosed` rather than an invented rationale (OR-1's flag).

  *(Amended before milestone 5, and the amendment is the finding. OR-1's default said "seed from
  the guard's first clean run" and did not say clean **where**. The first run was clean only on
  the authoring machine: CI scored two more failures on the same commit, in both lanes. A guard
  whose whole purpose is to report on the environment cannot be seeded from one environment, so
  the AC now requires a second before any count is published — and the two extra rows are the
  seeding defect's output, not new defects.)*

  *(OR-2, measured: `audit-selftest.sh` passes under this topology and gets no row. The receipt's
  detached-arm sweep saw it red for a reason the version-keyed arm does not reproduce; the guard's
  own run is the authority D-9 named, so the region closes on evidence rather than on an
  `undiagnosed` row.)*

  *(The two rows the second environment added, both diagnosed rather than `undiagnosed`, and both
  ENVIRONMENT-DEPENDENT — which is why the list's header now tells a reader not to drop a row on a
  single green run. `preflight-selftest.sh` is a class-B fixed hop (`$SCRIPT_DIR/../../../../review-toolkit`),
  identical in kind to `doctor-selftest.sh`'s row: from an install it resolves to nothing, so
  `preflight.sh` falls through to its `claude plugin list` rung, which hits only where the Claude
  CLI is installed. Reproduced by REMOVING `claude` from `PATH` — re-running proves nothing about
  an environment-dependent red. `cost-block-selftest.sh:40` mirrors `pipeline-cost-block.sh`'s
  state resolution but anchors it on `$HERE` where the script anchors on `$PWD`; with no git repo
  above an install cache the mirror falls to `cd ""`, which is a silent no-op on bash ≤ 5.2 and an
  error on bash ≥ 5.3, so the fixture and the script land in different state dirs on exactly the
  bash versions both CI lanes run. Reproduced by running the staged suite under `/bin/bash` 3.2 —
  CI's first failure line verbatim — and green under 5.3 on the same tree. Both stay listed rather
  than fixed: this spec's Out of scope defers `cost-block-selftest.sh` by name, and `preflight-selftest.sh`
  is D-6's class-B bucket, whose fix is a third copy of a ladder the lockstep manifest has already
  declined to pin. #421 owns both.)*

- **AC-8** — A follow-up issue is filed and linked from the closing comment, covering exactly what
  #419 defers: each remaining row of `install-topology-known-red.tsv`, D-10's undiagnosed
  `audit-selftest.sh`, and D-4's shipped-suite SKIP policy.

- **AC-9** — Mutation accounting is reconciled in this diff: `tools/mutation-baseline.tsv` drops
  any `plan-lint.sh` survivor that the hermetic fixture kills, or states — from a measurement, not
  an assumption — that none is killed. `tools/install-topology-selftest.sh` needs **no** accounting
  row: the guard universe rule excludes `*-selftest.sh` by name (`tools/mutation-sweep.sh:22-25`),
  so it is not in the universe and cannot be unaccounted, and that is verified by running the
  sweep's accounting rather than asserted.

  *(Amended before milestone 5: `mutation-sweep.sh` has no single-guard mode, and this branch
  touches no in-universe guard, so `--mode pr` sweeps nothing. The measurement is instead a
  faithful reproduction of the sweep's own rule — operators read out of `mutation-operators.tsv`,
  sites enumerated with the same `grep -nE --`, ordinals indexing the matched-line list — applied
  to `plan-lint.sh` in two detached worktrees and scored by the OLD and NEW suite. That is
  stronger evidence than a single-sided sweep would be, because it shows the delta.)*

- **AC-10** — Docs: `docs/testing.md`'s tier map and `CLAUDE.md`'s "Where a new test goes" table
  each gain a row for the install-topology guard, naming what it guards (a shipped suite still
  passing from a version-keyed install cache). `CLAUDE.md`'s measured `-P 4` sweep timings are
  re-measured on this branch with the guard present, and the note updated to the new pair; if the
  guard does not move them materially, that is stated instead of silently leaving stale numbers.

## Out of scope

- Fixing the reds owned by D-6/D-10 (`check-review-context-sections-selftest.sh`,
  `config-lint-selftest.sh`, `cost-block-selftest.sh`, `preflight-selftest.sh`,
  `audit-selftest.sh`) — they get rows and a follow-up ticket. *(Amended before milestone 5:
  `preflight-selftest.sh` joins the list — it was not known to be red when this was written,
  because the seeding environment hid it. Diagnosing is no longer deferred with them: AC-7's
  `undiagnosed` escape hatch is for a cause nobody has, not for one nobody looked for, and both
  late rows carry a reproduced mechanism.)*
- Implementing D-4's SKIP behavior in the shipped suites it governs; it is deferred with them.
- Any change to `plan-lint.sh` itself. Check 5a behaves correctly; the assertion was wrong.
- Adding a CI job or editing `ci.yml` — D-5's whole point is that the existing glob discovers the
  guard.
