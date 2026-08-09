# second-shift #426 — suites that need a repo-only artifact declare a counted skip from an install

Two shipped suites assert a lockstep against an artifact that lives in this repo and is not
shipped inside any plugin:

| suite | artifact it needs |
| --- | --- |
| `plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh` | `schema/second-shift.config.schema.json` |
| `plugins/review-toolkit/scripts/check-review-context-sections-selftest.sh` | `docs/extension-points.md` |

Both hard-FAIL on the artifact's absence today. In this checkout that is correct. From a
marketplace install the artifact is structurally absent, so the FAIL says nothing about drift —
it only says "you are not in the monorepo". The resolution is a **named, counted SKIP under the
install topology and an unchanged hard FAIL in this repo** — never a silent green.

## Design (bound by the pre-flight ledger, `.claude/pipeline-state/426-ledger.md`)

- **The probe (D-1)** — a tree is the monorepo iff `<root>/.claude-plugin/marketplace.json` is a
  file AND `<root>/plugins/` is a directory, with `<root>` resolved at the up-count each suite
  already uses to reach its artifact (5 for `config-lint-selftest.sh`, 3 for
  `check-review-context-sections-selftest.sh`). Intrinsic by construction: no environment
  variable can satisfy it, so a consumer running the suite directly from their install gets the
  same answer the guard gets. `git rev-parse --show-toplevel` was rejected — it false-positives
  for a consumer who vendors plugins inside their own git repo, which is the exact false
  hard-FAIL this slice removes.
- **Deferred exit (issue body)** — both suites run substantial assertions after their artifact
  block. Record the skipped lockstep, run everything else, and exit `77` at the tail **only if
  no other assertion failed**. A real failure always outranks a skip.
- **The hoist contract (D-3)** — the suite prints one line beginning `SKIP: ` naming the
  artifact it could not reach, then exits 77. The guard hoists the first such line out of the
  captured log before deleting it. An rc of 77 whose log carries no `SKIP: ` line is scored RED.
- **Guard accounting (D-5)** — mirror the absent-node precedent: set `KR_SEEN` so a matching
  known-red row is unevaluated rather than reported stale, call `skip()`, and `continue` before
  `RAN` increments.
- **Lockstep (D-4)** — the two probe copies are restructured so the differing `ROOT=` assignment
  sits above the markers and only the marker test is inside the block, then pinned with a
  `verbatim` row in `scripts/lockstep-manifest.tsv`.
- **AC-5's venue (D-2)** — an in-suite case in each suite fabricates a monorepo-shaped root
  (marker + `plugins/`, artifact absent), copies the suite into it at its required depth, runs
  the copy, and asserts the run is a hard failure. A recursion-guard environment variable stops
  the inner run re-entering that case; it gates a fixture case, never the skip discriminator.
- **Mutation re-baseline (D-6)** — none. `tools/mutation-sweep.sh` filters `-selftest\.sh$` out
  of its target set and all three edited scripts are selftests, so no generic survivor ordinals
  re-key.

Open regions OR-1 (recursion-guard seam name/breadth) and OR-2 (a synthetic cache-source
injection seam in the guard) are `reversible-default-and-flag`; both take their default here.

Design: none — no `design.provider` is configured for this repo.

## Acceptance criteria

- **AC-1** — Run from a version-keyed install cache outside any git repository, both suites exit
  `77` and print a line naming the artifact they could not reach.
- **AC-2** — `tools/install-topology-selftest.sh` reports both as `SKIP:` lines carrying the
  suite's own reason (hoisted from its captured log) and counts them in `SKIPPED`. Neither is
  scored as a pass; neither reds the guard; and, mirroring the existing absent-node skip,
  neither counts in `RAN`.
- **AC-3** — Run from a version-keyed install cache, every assertion in both suites that does
  **not** depend on the absent artifact still executes. A suite that fails one of those
  assertions exits non-zero and is scored red, not skipped.
- **AC-4** — Run from this checkout with the artifact present, both suites behave exactly as
  they do today: the lockstep executes and its result is unchanged.
- **AC-5** — Run from a tree the probe accepts as the monorepo but with the artifact **deleted**,
  both suites still hard-FAIL. The skip path must be unreachable in the monorepo, and a test case
  proves it.
- **AC-6** — The two corresponding rows are removed from `tools/install-topology-known-red.tsv`.

## Scope

Edited:

- `plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh`
- `plugins/review-toolkit/scripts/check-review-context-sections-selftest.sh`
- `tools/install-topology-selftest.sh`
- `tools/install-topology-known-red.tsv`
- `scripts/lockstep-manifest.tsv`

Out of scope: the fixed-hop-count known-red rows (`check-emit-deadline-selftest.sh`,
`doctor-selftest.sh`, `preflight-selftest.sh`, `cost-block-selftest.sh`) — a sibling slice of
#421. The `Seeded from the guard's first run` header line in the TSV records the seed, not
current state; it stays as-is.

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh
bash tools/install-topology-selftest.sh   # D-7: the AC-1/AC-2/AC-3 venue; not on the PR lane
```
