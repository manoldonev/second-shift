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

Every checked-in script pairs with a `*-selftest.sh`; CI discovers them by glob, so a new
selftest needs no registration. CI is model-free by design (no API-billed calls).

Release process: [`docs/releasing.md`](docs/releasing.md) — the checklist of record.
