# second-shift — repo conventions

This repo IS the second-shift marketplace. It consumes itself as a smoke test, not as evidence:
what the product should do is measured on consumer repos' committed records.

## The guiding light: no silent decisions

*"Model for intelligence, harness for law, ledger for memory."* In plain words: *"No silent
decisions. Every material decision names who made it — the ticket, a human's answer, the
codebase, an explicit deferral, or the agent under your standing delegation — and a departure from
the record is written down, never buried. Ask, build and review all serve that one
idea; we hold that the asking is the make-or-break step. We develop it against what consumer
records show, never against this repo's own lane."*

**Admission.** A ticket enters the lane only with (a) a row id from the operator's consumer
scoreboard that is a blocker or an extra round, or (b) a failure of documented shipped behavior
reproduced in a consumer run or from a consumer clone's `origin/main`. A red seen only in this
repo's dogfood lane or the selftests is fixed by hand or not filed.

**Only the operator queues or launches the lane in this repo.** A session never applies
`ready-for-dev` (intake slices use the no-queue-label form) and never runs `run.sh` or
`/dev-pipeline:run` on a ticket the operator has not queued; on the scheduler's exit 3 it stops.
It writes the admission evidence into the ticket body and stops.

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

**The verb goes on the PR title.** Merges are squash-merges, so `derive-release.sh` reads the PR
title as the commit subject: a verb that sits only on a branch commit is lost, and a verbless
title derives a patch. A `BREAKING CHANGE:` line in the body still derives a major.

## A session-launch fix lands in the scheduler

When a spawned session cannot run as launched (a prompt it cannot answer, a missing grant, a wrong
flag), the fix lands in `plugins/dev-pipeline/skills/run/run.sh`, with a `run-selftest.sh` case
that fails without it — never only in a wrapper or a one-off launch.

## Verification

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
```

**The third line takes minutes; a foreground `Bash` call is reaped at 2 minutes** whatever its
`timeout`. Run it as `nohup <cmd> > <log> 2>&1` under `run_in_background` (a bare `&` is reaped
too).

The recipe runs cold, excludes `tools/install-topology-selftest.sh` (run it directly when your
change is about how plugins are installed), and a killed sweep leaves `mktemp` litter that can red
the next run. The runner, the exclusion, the pass cache, concurrency and the scrub recipe:
[`docs/testing.md`](docs/testing.md#how-the-sweep-runs).

Every checked-in script is **exercised by some selftest**; CI discovers suites by glob, so a new
selftest needs no registration. CI is model-free by design (no API-billed calls).

The rule is coverage, not naming. Several scripts are covered under a differently-named suite —
`claim-issue.sh` by `claim-selftest.sh`, `check-frozen-files.sh` and `check-configversion-migration-doc.sh` by
`derive-release-selftest.sh`. Do not "fix" those by adding a same-named suite.

Genuine exceptions, one kind:

- **By design, no independent contract:** `plugins/review-toolkit/workflows/runtime-shim-lib.mjs`
  (the meta-strip + injected-fake mechanics, named so it does **not** match the discovery glob —
  `runtime-shim-selftest.mjs` drives it on every run), `_effective-registry.sh`,
  `install-gh-bot.sh`, and the eval runners.

### Adding or changing a test

The tier map (where a new guard goes), the scenario-first rule, the no-prose-presence-guards and
no-mirror-harnesses rules and the mjs-seam grep exception live in the `writing-tests` skill — it loads when you touch a test. Full contract:
[`docs/testing.md`](docs/testing.md).

**One thing in there binds ordinary PRs, not just test authorship:** a behavior change to
`run.sh` lands with a `run-selftest.sh` case that fails without it.

Testing: [`docs/testing.md`](docs/testing.md) — the tier map, the runtime shim, and the operator-run adversarial recipe.

Release process: [`docs/releasing.md`](docs/releasing.md) — the checklist of record.

Consumer evaluation: [`docs/consumer-eval.md`](docs/consumer-eval.md) — releases record no replay; evaluation is the operator's read of consumer runs' records and verdicts, plus the pinned-base recipe a one-off replay uses.

Enforcement principles: [`docs/pipeline-manifesto.md`](docs/pipeline-manifesto.md) — P1–P10, the trust boundary, and the T0 note. A judgment aid, not a gate.
