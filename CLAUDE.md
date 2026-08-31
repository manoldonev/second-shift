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
This applies to **every** contributor, human or agent — including `/dev-pipeline:run-lean`. A
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
run on its own, and `tools/mutation-sweep.sh`. **`lean-gate.sh 3` is the exception**: it runs the
sweep inline, bounded by `tools/selftest-suite-timings.tsv` to fit the turn, which is what a session
detaching it and ending the turn would undo.

**The killed-sweep note.** A foreground attempt that was already killed skipped its suites'
`trap … EXIT`, and **a private `TMPDIR` relocates the scratch and not the fixtures.** The
stamped fixture families allocate with `mktemp -d -t <name>`, and on macOS that path resolves
against `_CS_DARWIN_USER_TEMP_DIR` — a bare `mktemp -d` *is* `-t tmp`, so there is no second
behavior to fall back on. Those land in one directory shared with every other lane on the machine
whatever `TMPDIR` says. The explicit-template form `mktemp -d "${TMPDIR:-/tmp}/…"` — the sweep
runner's own `BASE`, and eleven other scripts — *is* honored, because the shell expands the path
before `mktemp` runs (measured 2026-08-25; the derivation is in the runbook). The sweep reaps the
stamped families itself on its way in; for the rest,
[scrub before re-running](docs/testing.md#when-a-run-is-killed-mid-sweep) — a red the diff cannot
explain is that litter more often than it is your branch.

**`tools/run-selftests.sh` is the sweep — here, in both CI selftest jobs, and in this repo's own
dogfood lean-gate milestone-3 `test` lane** (the gitignored `.claude/second-shift.config.json`,
at a wider `--jobs 10` but the same runner — not a hand-rolled `find | xargs` pipeline). It
discovers every `*-selftest.sh`, runs `SELFTEST_JOBS` (default 4) of them at a time, and replays
each suite's output as one contiguous `::group::`-framed block in a deterministic order that does
not move with completion timing. It exits non-zero naming every failing suite, and it reds rather
than reporting a fast green when its discovered count and its run count disagree, when an
`--exclude` matches no discovered suite, or when a worker dies without writing a verdict.
`SKIP_STRESS=1` is yours to set or omit — the runner never sets it, which is what keeps the
mutation baseline's environment check meaningful.

**The `--exclude` is why this recipe is ~3 minutes instead of ~10.**
`tools/install-topology-selftest.sh` re-runs every *shipped* suite from a staged install cache, so
its cost is the whole suite set a second time. It no longer runs on the PR lane either — both CI
selftest jobs pass the same exclusion, and the guard runs in
`.github/workflows/install-topology.yml` on push to `main` when the diff touches packaging paths
(plugin manifests, the guard script itself), on the release PR, and via
`workflow_dispatch` (#666 retired the nightly cron — a clock was the least relevant trigger for a
guard whose answer only moves on those paths). Run it directly, `bash
tools/install-topology-selftest.sh`, when your change is about how plugins are installed or laid
out and you want the answer before pushing.

**The recipe above runs COLD, and that is deliberate.** CI additionally passes `--cache-dir`, which
lets a suite with a row in `tools/selftest-cache-inputs.tsv` be skipped when the content of every
declared input is unchanged. The runner participates only where a store is named — that flag, or
the `LEAN_SELFTEST_CACHE_DIR` the lean gate exports into its own milestone-3 lane (#563) — and the
recipe above names neither, so what you run locally is still a full sweep. See
[`docs/testing.md`](docs/testing.md) for the contract, and add a row there only when you can
enumerate a suite's inputs exactly.

**Concurrency is load-bearing, not incidental.** The suites are independent — each allocates its
own `mktemp` state dir — so running four at a time is behavior-preserving, and on the current
64-suite tree it is the difference between a **13:12** sweep and a **5:22** one (measured). A
failing suite still fails the sweep.

The cost is heavily skewed, and one suite now sets the floor: `tools/install-topology-selftest.sh`
re-runs every *shipped* suite from a staged install cache, and takes **roughly 7 minutes on its
own** — three runs of one unchanged tree measured 319s, 438s and 584s, so treat the range, not a
point value, as the number (a run at the slow end is not a regression). It already parallelizes
internally (`INSTALL_TOPOLOGY_JOBS`, default 4), so it is the long pole rather than something an
outer `SELFTEST_JOBS=4` can shorten — the 5:22 above is essentially that one suite, and moves with
it. Everything else is roughly 8 minutes serial and folds into its shadow. See
[`docs/testing.md`](docs/testing.md) for what it buys, and for the trade accepted in moving it off
the PR lane: a manifest-version or guard-script change is caught at the next push to `main`, but a
shipped suite's own content is caught only at the next release PR or via `workflow_dispatch` — the
push filter is deliberately too narrow to catch that class, so it doesn't fire once per merge.

`SELFTEST_JOBS=1` gives you a serial sweep with the same verdict, if you want one while debugging;
prefer running the single suite alone instead. Output stays framed per suite either way, so
lowering it is not what makes the log readable.

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

Enforcement principles: [`docs/pipeline-manifesto.md`](docs/pipeline-manifesto.md) — P1–P10, the trust boundary, and the T0 note. A judgment aid, not a gate.
