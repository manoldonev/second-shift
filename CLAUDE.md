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
feat(dev-pipeline): the quality pass now reverts on red

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

## A bench finding about how sessions are launched is fixed in the scheduler

When the lane bench (`tools/lane-bench*.sh`) finds that a spawned session cannot run as launched
(a prompt it cannot answer, a missing grant, a wrong flag), the fix lands in
`plugins/dev-pipeline/skills/run/orchestrate.sh`. A `LANE_ARM_*` knob in the bench wrapper may
carry it for a cell, but never as the only fix: the bench fixed `EnterWorktree` that way
in #818, and the scheduler shipped without the fix until real runs stopped as `blocked`.

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
```

**That third line takes minutes, and a foreground agent call cannot finish it.** The harness reaps
a foreground `Bash` call at **2 minutes**, and the `timeout` parameter does not lift the cap — a
call requesting 600000ms was still SIGKILLed at exactly 2m 0s (re-measured 2026-08-25, and the same
2m 0s on every lane that has tried it). The shape that survives is `nohup <cmd> > <log> 2>&1` under
the harness's `run_in_background`: it stays harness-tracked, so it is collected in the same turn
rather than abandoned at turn end. A *bare* backgrounded command is not that shape and has been
reaped at 2 minutes too — do not budget on it. This covers the sweep above, any single slow suite
run on its own, and `tools/mutation-sweep.sh`. **`milestone-gate.sh 3` is the exception**: it runs the
sweep inline, bounded by `tools/selftest-suite-timings.tsv` to fit the turn, which is what a session
detaching it and ending the turn would undo.

**The killed-sweep note.** A foreground attempt that was already killed skipped its suites'
`trap … EXIT`, and whatever those suites had under `mktemp` stays on disk with nothing to remove
it. The two big fixture-producing selftests, `milestone-gate-selftest.sh` and
`orchestrate-selftest.sh`, joined the explicit-template form `mktemp -d
"${TMPDIR:-/tmp}/…"` in #780 — so **a private `TMPDIR` relocates their scratch** — but most of the
tree has not: `mktemp -d -t <name>`, plain `mktemp -t`, and bare `mktemp -d` (which *is* `-t tmp`
— same TMPDIR-ignoring behavior, not a safe third option) are all still in wide use, including the two
largest scratch trees in the repo (`tools/mutation-sweep.sh`,
`tools/install-topology-selftest.sh`), so a private `TMPDIR` does not isolate those.
[`docs/testing.md`](docs/testing.md#when-a-run-is-killed-mid-sweep) has the reproducible caller
count and the scrub recipe — a hardcoded number here would only go stale. Nothing reaps a killed
run's leftovers automatically; scrub before re-running — a red the diff cannot explain is that
litter more often than it is your branch.

**`tools/run-selftests.sh` is the sweep — here, in both CI selftest jobs, and in this repo's own
dogfood milestone-gate milestone-3 `test` lane** (the gitignored `.claude/second-shift.config.json`,
at a wider `--jobs 10` but the same runner — not a hand-rolled `find | xargs` pipeline).
`SKIP_STRESS=1` is yours to set or omit — the runner never sets it, which is what keeps the
mutation baseline's environment check meaningful.

**The `--exclude` is why this recipe is ~3 minutes instead of ~10.**
`tools/install-topology-selftest.sh` re-runs every *shipped* suite from a staged install cache, so
its cost is the whole suite set a second time. It no longer runs on the PR lane either — both CI
selftest jobs pass the same exclusion, and `.github/workflows/install-topology.yml` decides when
it runs. Run it directly, `bash
tools/install-topology-selftest.sh`, when your change is about how plugins are installed or laid
out and you want the answer before pushing.

**The recipe above runs COLD, and that is deliberate.** CI additionally passes `--cache-dir`, which
lets a suite with a row in `tools/selftest-cache-inputs.tsv` be skipped when the content of every
declared input is unchanged. The runner participates only where a store is named — that flag, or
the `LANE_SELFTEST_CACHE_DIR` the milestone gate exports into its own milestone-3 lane (#563) — and the
recipe above names neither, so what you run locally is still a full sweep. See
[`docs/testing.md`](docs/testing.md) for the contract, and add a row there only when you can
enumerate a suite's inputs exactly.

**Concurrency is load-bearing, not incidental.** The suites are independent — each allocates its
own `mktemp` state dir — so running four at a time is behavior-preserving, and on the current
64-suite tree it is the difference between a **13:12** sweep and a **5:22** one (measured). A
failing suite still fails the sweep.

Every checked-in script is **exercised by some selftest**; CI discovers suites by glob, so a new
selftest needs no registration. CI is model-free by design (no API-billed calls).

The rule is coverage, not naming. Several scripts are covered under a differently-named suite —
`claim-issue.sh` by `claim-selftest.sh`, `pipeline-cost-block.sh` by `cost-block-selftest.sh`,
`check-frozen-files.sh` and `check-configversion-migration-doc.sh` by
`derive-release-selftest.sh`. Do not "fix" those by adding a same-named suite.

Genuine exceptions, one kind:

- **By design, no independent contract:** `plugins/dev-pipeline/workflows/runtime-shim-lib.mjs`
  (the meta-strip + injected-fake mechanics, named so it does **not** match the discovery glob —
  `runtime-shim-selftest.mjs` drives it on every run), `_effective-registry.sh`,
  `install-gh-bot.sh`, and the eval runners.

**This register is authoritative; `tools/mutation-exclusions.tsv` defers to it.** The mutation
sweep needs the same "no kill criterion exists" facts in machine-readable form, so two of its
exclusion rows restate entries from the list above — and each cites this register as its origin
rather than asserting an independent rationale. Dropping an entry here obliges dropping its row
there. Rows in that file with no counterpart here (local operator tooling, the sweep's own
recursion guard) are the sweep's alone.

### Adding or changing a test

The tier map (where a new guard goes), the scenario-first rule, the no-prose-presence-guards and
no-mirror-harnesses rules, the mjs-seam grep exception, and the mutation-sweep obligations live in
the `writing-tests` skill — it loads when you touch a test. Full contract:
[`docs/testing.md`](docs/testing.md).

**Two things in there bind ordinary PRs, not just test authorship:** editing a guard's CODE
re-anchors its `tools/mutation-catalog.tsv` rows, and a new gate contract must extend the liveness
scenario. Read the skill before either.

Testing: [`docs/testing.md`](docs/testing.md) — the tier map, the runtime shim, and the operator-run adversarial recipe.

Release process: [`docs/releasing.md`](docs/releasing.md) — the checklist of record.

Release eval: [`docs/consumer-eval.md`](docs/consumer-eval.md) — the consumer-shaped replay every release records, its four metrics and their exact sources.

Enforcement principles: [`docs/pipeline-manifesto.md`](docs/pipeline-manifesto.md) — P1–P10, the trust boundary, and the T0 note. A judgment aid, not a gate.
