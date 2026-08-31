# second-shift #666 — install-topology moves off the nightly cron onto event triggers

`nightly-guards.yml` runs the install-topology class guard on a 02:41 UTC cron. Its own docs
already accept within-a-day detection, and a clock is the least relevant trigger for a
packaging guard: its answer only moves when packaging/layout changes or a release is cut. Move
it to a new `.github/workflows/install-topology.yml`, triggered by a packaging-path push to
`main`, the release PR, and `workflow_dispatch`; file a deduplicated issue on red instead of
leaving it to rot on a cron dashboard nobody here reads. `nightly-guards.yml` keeps its other two
jobs (`wholesale-selftests` — which owns the `check-sweep-bound.sh` leg — and `prose-budget`) on
the cron unchanged; neither is install-topology's guard and neither moves when packaging changes.

## Acceptance Criteria

- **AC-1** The schedule trigger is gone from the install-topology guard, and it runs on
  packaging-path pushes to `main`, the release PR, and dispatch:
  - `test -f .github/workflows/install-topology.yml`
  - `! grep -q '^\s*schedule:' .github/workflows/install-topology.yml`
  - `grep -qE '^\s*push:' .github/workflows/install-topology.yml && grep -qE '^\s*pull_request:' .github/workflows/install-topology.yml && grep -qE '^\s*workflow_dispatch:' .github/workflows/install-topology.yml`
  - `! grep -qE '^\s*(install-topology|install-topology-bash32):' .github/workflows/nightly-guards.yml`
    (both jobs left that file entirely — no job of either name remains there)
  - `git -C . show HEAD:.github/workflows/install-topology.yml | ruby -ryaml -e 'YAML.unsafe_load(STDIN.read) rescue YAML.load(STDIN.read)'` parses (workflow-level `check-workflows-selftest.sh` covers this on every run)
- **AC-2** A red run files a deduplicated issue; a green run files nothing:
  - a `file-issue-on-red` job (or equivalent) gated on `contains(needs.*.result, 'failure')` (or
    an equivalent failure condition over both guard jobs) exists in
    `.github/workflows/install-topology.yml`
  - that job's issue-filing step searches for an already-open issue (`gh issue list --search`)
    before calling `gh issue create` — `grep -c 'gh issue list' .github/workflows/install-topology.yml`
    and `grep -c 'gh issue create' .github/workflows/install-topology.yml` are each ≥ 1, and the
    `list` call precedes the `create` call in the file
  - the created issue's body names the triggering commit (`github.sha` / `$SHA`) and the failing
    lane(s)/suite(s) — `grep -c 'SHA' .github/workflows/install-topology.yml` ≥ 1 in that job
- **AC-3** The path filter is derived from what the guard actually stages, each family commented:
  - the `push.paths` list under `.github/workflows/install-topology.yml` contains exactly the
    three families `plugins/*/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`,
    `tools/install-topology-selftest.sh` — `awk '/^  push:$/{f=1;next} /^  pull_request:$/{f=0} f' .github/workflows/install-topology.yml | grep -c "\.claude-plugin/plugin\.json\|marketplace\.json\|install-topology-selftest\.sh"` → 3
  - the file's header comment names why each family is in scope (a `PATH FILTER` block, one
    line per family) — `grep -c 'PATH FILTER' .github/workflows/install-topology.yml` ≥ 1
- **AC-4** Docs referencing the nightly cadence are updated to the event-triggered contract:
  - `! grep -n 'guard runs nightly' CLAUDE.md docs/testing.md`
  - `grep -q 'install-topology.yml' CLAUDE.md` and `grep -q 'install-topology.yml' docs/testing.md`
  - neither file's install-topology passage still says "nightly cron" / "within a day" as the
    live trigger contract (historical/incident prose referring to the guard's past behavior is
    fine; the *current* contract description is not)
- **AC-5** `Changelog:` trailer per repo convention.

## Scope boundary

- `wholesale-selftests` and `prose-budget` are untouched — they stay in `nightly-guards.yml` on
  the existing cron. Neither is the guard this ticket is about, and #666 is explicit that an
  independent leg (`check-sweep-bound.sh`, owned by `wholesale-selftests`) keeps running wherever
  it runs today.
- No change to `tools/install-topology-selftest.sh`'s own behavior, timeout, or concurrency —
  only when/how it is invoked.
- Prose-only accuracy fixes to comments that described the guard as "nightly" in the present
  tense (`ci.yml`, `tools/install-topology-detail-selftest.sh`) ride along; they are not a
  separate AC because they are consequences of AC-4's contract change, not new scope.

## Adversarial pass (from the issue)

| Botch | Closed by |
| --- | --- |
| Keep the cron alongside the new triggers ("belt and braces") | AC-1's `! grep schedule:` |
| File one issue per push (spam) instead of deduping | AC-2's list-before-create requirement |
| Filter on all of `plugins/**` (defeats moving off cron — same frequency as every merge) | AC-3's exact three-family count |
| Silently drop `wholesale-selftests`/`prose-budget`'s cron while editing the shared file | Scope boundary + `nightly-guards.yml` still has a `schedule:` key (implied by AC-1 only asserting the two named jobs left, not the whole file) |
| Leave stale "runs nightly" prose in CLAUDE.md/docs/testing.md | AC-4 |

Changelog: `install-topology` moves from a nightly cron to push (packaging paths) / release-PR /
workflow_dispatch triggers, and a red run now files a deduplicated GitHub issue instead of only
showing on the Actions dashboard. Migration: none — CI-only.
