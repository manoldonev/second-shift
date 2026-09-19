# second-shift — repo conventions

This repo IS the second-shift marketplace. It consumes itself as a smoke test, not as evidence:
what the product should do is measured on consumer repos' committed records.

## The guiding light: no silent decisions

*"Model for intelligence, harness for law, ledger for memory."* In plain words: *"No silent
decisions. Every material decision in a ticket has a named owner — the ticket, a human's answer,
the codebase, or an explicit deferral — and a departure the agent discloses still needs a human's
signature before it merges: telling is not deciding. Ask, build and review all serve that one
idea; we hold that the asking is the make-or-break step, and we have dated the test that could
prove it wrong. We develop it against what consumer records show, never against this repo's own
lane."*

**Admission.** A ticket enters the lane only with (a) a row id from the operator's consumer
scoreboard that is a blocker or an extra round, or (b) a failure of documented shipped behavior
reproduced in a consumer run or from a consumer clone's `origin/main`. A red seen only in this
repo's dogfood lane, the lane bench or the selftests is fixed by hand or not filed.

**Only the operator queues or launches the lane in this repo.** A session never applies
`ready-for-dev` (intake slices use the no-queue-label form), never records an unintaken-gate
operator override, never runs `orchestrate.sh`, and never invokes `/dev-pipeline:build` or the
gate's `entry` / `claim` on a ticket the operator has not queued; on the scheduler's exit 3 it
stops. It writes the admission evidence into the ticket body and stops. A new file under
`tools/` or `scripts/` merges only if the same PR deletes a larger one.

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

The admission rule above decides whether a bench finding is worked at all. When one is, and the
lane bench (`tools/lane-bench*.sh`) found that a spawned session cannot run as launched (a prompt
it cannot answer, a missing grant, a wrong flag), the fix lands in
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
run on its own. **`milestone-gate.sh 3` is the exception**: it runs the
sweep inline, bounded by `tools/selftest-suite-timings.tsv` to fit the turn, which is what a session
detaching it and ending the turn would undo.

**The killed-sweep note.** A foreground attempt that was already killed skipped its suites'
`trap … EXIT`, and whatever those suites had under `mktemp` stays on disk with nothing to remove
it. The two big fixture-producing selftests, `milestone-gate-selftest.sh` and
`orchestrate-selftest.sh`, joined the explicit-template form `mktemp -d
"${TMPDIR:-/tmp}/…"` in #780 — so **a private `TMPDIR` relocates their scratch** — but most of the
tree has not: `mktemp -d -t <name>`, plain `mktemp -t`, and bare `mktemp -d` (which *is* `-t tmp`
— same TMPDIR-ignoring behavior, not a safe third option) are all still in wide use, including the
largest scratch tree in the repo (`tools/install-topology-selftest.sh`), so a private `TMPDIR`
does not isolate those.
[`docs/testing.md`](docs/testing.md#when-a-run-is-killed-mid-sweep) has the reproducible caller
count and the scrub recipe — a hardcoded number here would only go stale. Nothing reaps a killed
run's leftovers automatically; scrub before re-running — a red the diff cannot explain is that
litter more often than it is your branch.

**`tools/run-selftests.sh` is the sweep — here, in both CI selftest jobs, and in this repo's own
dogfood milestone-gate milestone-3 `test` lane** (the gitignored `.claude/second-shift.config.json`,
at a wider `--jobs 10` but the same runner — not a hand-rolled `find | xargs` pipeline).
`SKIP_STRESS=1` is yours to set or omit — the runner never sets it.

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

### Adding or changing a test

The tier map (where a new guard goes), the scenario-first rule, the no-prose-presence-guards and
no-mirror-harnesses rules and the mjs-seam grep exception live in the `writing-tests` skill — it loads when you touch a test. Full contract:
[`docs/testing.md`](docs/testing.md).

**One thing in there binds ordinary PRs, not just test authorship:** a new gate contract must
extend the liveness scenario. Read the skill before adding one.

Testing: [`docs/testing.md`](docs/testing.md) — the tier map, the runtime shim, and the operator-run adversarial recipe.

Release process: [`docs/releasing.md`](docs/releasing.md) — the checklist of record.

Consumer evaluation: [`docs/consumer-eval.md`](docs/consumer-eval.md) — releases record no replay; evaluation is the operator's read of consumer verdict records, plus the pinned-base recipe a one-off replay uses.

Enforcement principles: [`docs/pipeline-manifesto.md`](docs/pipeline-manifesto.md) — P1–P10, the trust boundary, and the T0 note. A judgment aid, not a gate.
