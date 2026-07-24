# second-shift — repo conventions

This repo IS the second-shift marketplace, and it consumes itself as the dogfooding canary.

## Never edit release artifacts in a feature PR

**Versions and the changelog are DERIVED at release time. Do not write them.**

| File | Who writes it |
| --- | --- |
| `plugins/*/.claude-plugin/plugin.json` → `version` | `scripts/derive-release.sh`, on the release PR |
| `CHANGELOG.md` | `scripts/derive-release.sh`, on the release PR |
| `.claude-plugin/marketplace.json` → `metadata.version` | `scripts/derive-release.sh`, on the release PR |

A feature PR that touches any of them is rejected by CI (`scripts/check-frozen-files.sh`).
This applies to **every** contributor, human or agent — including `/dev-pipeline:run`. A
pipeline run must not bump a version or append a changelog entry "to follow repo
convention": that convention was retired in #119, and doing it now turns the PR red.

Other plugin manifest fields (description, etc.) are freely editable — only `version` is
frozen.

## Every `plugins/**` PR needs a `Changelog:` trailer

The release notes are assembled from commit trailers, so changelog intent lives in the
commit body, not in `CHANGELOG.md`:

```
feat(dev-pipeline): stage-6 quality pass now reverts on red

Changelog: the advisory quality pass resets the worktree when its safety-net
  re-verify fails, instead of leaving a half-applied refactor.
  Migration: none.
```

Use `Changelog: none` when nothing is consumer-visible. CI enforces that one of the two is
present (`scripts/check-changelog-trailer.sh`). Trailers are extracted grep-anywhere, so a
trailer in any commit of the branch survives the squash.

## Commit verbs decide the version bump

Bump level is derived from the conventional type — the verb is load-bearing, not cosmetic:

| Commit | Bump |
| --- | --- |
| `BREAKING CHANGE:` footer, or `type!:` | major |
| `feat:` | minor |
| everything else (`fix:`, `docs:`, `test:`, `chore:`, `refactor:`) | patch |

**Use the honest verb.** The "AI-infrastructure changes take `chore(scope):`" rule belongs
to *product* repos where AI tooling is incidental. Here the AI tooling IS the product, so a
new capability is `feat:` — typing it `chore:` silently downgrades a minor release to a
patch.

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

Every checked-in script is **exercised by some selftest**; CI discovers suites by glob, so a new
selftest needs no registration. CI is model-free by design (no API-billed calls).

The rule is coverage, not naming. Several scripts are covered under a differently-named suite —
`claim-issue.sh` by `claim-selftest.sh`, `pipeline-cost-block.sh` by `cost-block-selftest.sh`,
`max-pushed-slice.sh` by `statectl-selftest.sh`'s `(mps)` section, `slice-scope.sh` by
`scenario-liveness-selftest.sh`, `check-frozen-files.sh` and `check-configversion-migration-doc.sh`
by `derive-release-selftest.sh`. Do not "fix" those by adding a same-named suite.

Genuine exceptions, in two kinds:

- **By design, no independent contract:** `plugins/dev-pipeline/skills/run/scenario-lib.sh` (shared
  scenario mechanics, named so it does **not** match the discovery glob — `statectl-selftest.sh`
  and `scenario-liveness-selftest.sh` exercise it on every run), `_effective-registry.sh`,
  `install-gh-bot.sh`, and the eval runners.
- **Genuinely uncovered, and tracked — not exempt:** `scripts/check-plugin-version-bumps.sh` (a
  merge-blocking release gate whose error branches all degrade to PASS) and
  `plugins/intake-toolkit/hooks/exitplan-ledger-gate.sh` (a live enforcing hook that fails open).
  Both are #215 scope. Listing them is a debt register, not a waiver.

A previous version of this section claimed every script pairs with a *same-named* suite. That was
false in both directions, and the false claim is part of how the dark gates above stayed invisible.

### What to write when you add a test

**Scenario-first.** A new per-tool fixture case must name the invariant it guards and why no
scenario in `scenario-liveness-selftest.sh` covers it. The stacked-prs path died with all 42
selftests green because every one of them checked a component against itself.

**No prose-presence guards.** Grepping a literal out of a markdown file asserts only that prose
contains words — it cannot fail for a reason a reader of the diff would not already see. Pin the
contract in `scripts/lockstep-manifest.tsv` instead, which compares the two copies. When a coupling
is real but not byte-anchorable, record it in that manifest as a **DROPPED** entry with the
reasoning, so the decision is visible rather than forgotten.

**No mirror harnesses.** Never test a hand-maintained *copy* of production logic. A copy cannot
fail on a production edit, so it converges on green while the real code drifts away underneath it
— and it reads as coverage the whole time. Two `.mjs` suites did exactly this: they modelled the
pre-#169 StructuredOutput transport for months after production replaced it, and while they were
green `design-sync.mjs`'s gate path was throwing `ReferenceError` on every dispatch. The sanctioned
replacement is `workflows/runtime-shim-selftest.mjs`, which strips the `export const meta` block,
wraps the remainder in `(async (agent, parallel, pipeline, args, log, phase, budget) => { … })`,
and executes the **real** production body with injected fakes. If you are about to re-declare a
production function inside a selftest, use the shim instead.

**The mjs-seam grep exception, narrowed.** It used to read "grep is the only technique available"
for Workflow-runtime `.mjs` files. That is no longer true — the shim executes them. The sanction
now covers only what the shim cannot reach: static/textual properties of a file that is never
executed on the path under test (`tools/intake-readroot-selftest.sh`'s `intake-review.mjs` seam
pins; `null-reviewer-selftest.mjs`'s Case F token + emit-wiring counts, which guard a constant's
*wiring* rather than its behavior). Behavior belongs on the shim. Pre-existing mutation-eval
anchors (`tools/score-review-selftest.sh`) stay grandfathered; this rule binds newly added guards.

**Where a new test goes** (the tier map — full version in [`docs/testing.md`](docs/testing.md)):

| If you are guarding… | Write it as | Lives in |
| --- | --- | --- |
| one script's behavior against fixtures | a per-tool behavioral selftest | `*-selftest.sh` next to the tool |
| two copies of one contract staying identical | a lockstep row | `scripts/lockstep-manifest.tsv` |
| a composed verdict path reaching a terminal write | a scenario | `scenario-liveness-selftest.sh` |
| a production Workflow `.mjs` dispatch ladder | a shim case | `workflows/runtime-shim-selftest.mjs` |
| prose in a markdown file | **nothing** — see above | — |

**A new gate contract extends the liveness scenario** for every verdict path it touches — a gate
nothing composes against is a gate the next `#204` walks straight through.

Testing: [`docs/testing.md`](docs/testing.md) — the tier map, the runtime shim, and the operator-run adversarial recipe.

Release process: [`docs/releasing.md`](docs/releasing.md) — the checklist of record.
