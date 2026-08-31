# Lean spec — #665: merge-time diff-scoped mutation sweep replaces the nightly wholesale cron

The sweep's cost/signal topology is inverted: the PR lane costs 10–15s and grades almost
nothing (every slow or multi-suite guard defers), while the nightly re-derives ~570 known
verdicts onto a dashboard nobody reads and has been red for nights untriaged. Move the
enforced sweep from clock-driven wholesale to event-driven diff-scope, and land verdicts
where they are consumed: a filed issue, not a cron dashboard.

## Scope

- `.github/workflows/mutation-merge.yml` — NEW. Push-to-`main`, diff-scoped to the merge,
  deferral disabled. Queued (never cancelled) concurrency; report artifact; files an issue
  on red.
- `.github/workflows/file-issue-on-red.yml` — NEW. Reusable (`workflow_call`) file-or-comment
  mechanic, deduplicated on a title key.
- `tools/mutation-sweep.sh` — the `MUTATION_SWEEP_NO_DEFER` knob, and the human-facing
  deferral prose repointed off the deleted nightly.
- `.github/workflows/mutation-sweep.yml` — nightly cron → monthly audit; red files a digest.
- `plugins/dev-pipeline/skills/build-lean/lean-gate.sh`, `plugins/dev-pipeline/tools/preflight.sh`
  — the knob joins the `seam-scrub` LOCKSTEP denylist.
- `tools/mutation-sweep-selftest.sh` — companion coverage for the knob.
- `docs/testing.md`, `.claude/skills/writing-tests/SKILL.md` — the lane topology.

Out of scope: `.github/workflows/nightly-guards.yml`'s triggers (#666/PR #735 owns that
file); the PR lane's deferral decisions (AC-4).

## Acceptance Criteria

- **AC-1**: a push-to-`main` workflow sweeps the merge's diff at full generic+catalog depth
  with deferral off; the deferral bypass is a named env knob under `SEAM_SCRUB_ENV`
  discipline (no ambient leak into other lanes), and the baseline exit contract is unchanged.
- **AC-2**: a red merge-time or monthly-audit run files a deduplicated issue carrying the
  survivor ids and the triggering commit; a green run files nothing.
- **AC-3**: `mutation-sweep.yml`'s nightly schedule is gone; monthly audit schedule +
  dispatch remain; the seed recipe still works via dispatch.
- **AC-4**: the PR-lane job's behavior is byte-identical — no change to which guards it
  defers, nor to the `deferred-to-nightly` report enum.
- **AC-5**: `docs/testing.md`'s "Where it runs" section describes the new topology; the
  CLAUDE.md mutation paragraph's lane references stay accurate; and no surviving in-tree
  comment routes a reader to a lane this change deletes. Historical narrative about past
  nightly runs is left alone — it records when something happened, not where to look now.
- **AC-6**: companion-selftest coverage for the new knob — with the knob on, each of the
  three deferral reasons the PR path applies (slow suite, multi-suite union, fast-guard cap)
  grades its guard instead of emitting `deferred-to-nightly`.
- **AC-7**: `Changelog:` trailer per repo convention.
- **AC-8** (added at build; see Departures): `.claude/skills/writing-tests/SKILL.md`'s
  "Test-the-tests" paragraph names the new lane set. CLAUDE.md's mutation paragraph delegates
  its lane facts there, so AC-5 is unsatisfiable without it — the skill currently asserts
  "**Those two are the only places it runs**", which this change falsifies.
- **AC-9** (added at the round-1 fix; see Departures): every workflow this change adds or
  edits passes CI's `actionlint` step, which runs shellcheck over each `run:` body — not only
  the YAML floor that `scripts/check-workflows-selftest.sh` asserts.

## Departures from the pre-flight ledger

- **D-7** is applied as written and is itself the disclosed departure from AC-4's literal
  "byte-identical": the report enum `deferred-to-nightly` is untouched (three selftest greps
  and `docs/testing.md` consume it), but the human-facing `WARN:` / `::warning::` /
  step-summary / `info` prose that pointed at the deleted nightly is repointed at the
  merge-time sweep. AC-4 above is restated to scope the guarantee to deferral decisions and
  the enum, per AC-4's own parenthetical.
- **D-17** is widened: the ledger's shape is one slow-suite case; AC-6 covers all three
  deferral reasons, because D-2 makes the knob responsible for all three and a single-arm
  case leaves the other two arms ungraded. A fourth sub-case pins the knob OFF by default, so
  a mutant that made the bypass unconditional cannot pass by satisfying the other three.
- **D-16 / AC-5** widened by one site: `ci.yml`'s `mutation-sweep-pr` header said guards
  "defer to the nightly wholesale sweep", which after this change routes a reader to a lane
  that no longer runs at that cadence. It is a comment, so AC-4's behavior guarantee is
  untouched. `tools/mutation-baseline.tsv`'s eight "confirm at the first nightly" row
  comments are left alone per OR-3 — they date a seeded row, they do not route.
- **OR-2** resolved on its stated default: PR #735 (#666) is OPEN at build time, so this PR
  authors `file-issue-on-red.yml` and calls it from its own two workflows; rewiring
  `install-topology.yml` is left to a follow-up rather than editing a file not on `main`.
- **OR-1**, **OR-3** left on their stated defaults.
- **AC-9 added after round 1.** The original set bound what the workflows *say* and nothing
  bound whether they *lint*. `scripts/check-workflows-selftest.sh` is a YAML parser: it
  discovered both new files and passed them while four `run:`-body lines were failing CI's
  `actionlint` on SC2016 (markdown backticks inside single-quoted shell). The resulting
  blocker was therefore outside the AC set entirely — the gap this AC closes. Graded with the
  same pinned `actionlint` 1.7.7 CI runs.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Shape of the shared file-on-red mechanic (#666 asks the second lander to reuse, not duplicate) | A reusable workflow `.github/workflows/file-issue-on-red.yml` (`workflow_call`, inputs: dedup title key, body, commit, run id), called by the new merge-time workflow and by `install-topology.yml`. No new `*.sh`, so it incurs no paired-selftest or mutation-universe obligation under CLAUDE.md's coverage rule | user-answered |
| D-2 | Which of the three PR-mode deferral reasons the new knob disables | All three — slow suite, multi-suite killer union, and the hard `PR_FAST_GUARD_CAP=6` (`tools/mutation-sweep.sh:1080-1087`). All three protect the PR lane's time bound, which merge time does not have; the multi-suite defer runs the FULL union when it runs, the same criterion that produced the baseline, so disabling it manufactures no false reds | user-answered |
| D-3 | A repeat red while a filed issue is still open | Comment on the open issue with the new commit + survivor ids, instead of skipping. The mechanic is shared, so `install-topology`'s second red gains the same behavior (today it is dropped) | user-answered |
| D-4 | Infra reds (`pool disagreement`, `unrunnable pair`, `catalog anchor drift`, `unaccounted guard`, `baseline-missing`, sandbox failure) vs survivor reds | Two separate title keys — `mutation sweep red` for survivors, `mutation sweep infra red` for harness faults — so neither suppresses the other under the dedup rule, and each triages to the route `docs/testing.md` already prescribes | user-answered |
| D-5 | Dedup namespace for the monthly wholesale audit's digest | A third title key, `mutation wholesale audit red`. Same suppression argument as D-4: the digest is drift/baseline hygiene over the whole universe, not a coverage gap in one merge | user-answered |
| D-6 | Concurrency shape for the merge-time workflow | `concurrency: {group: mutation-merge, cancel-in-progress: false}` — queue, never cancel. Every merge is graded on its own diff. Coalescing (the issue's literal wording) would drop a cancelled merge's guards with no lane left to catch them; its saving is ~0 because runs are async and `mutation-sweep.yml` already records that minutes are free on a public repo | user-answered |
| D-7 | The `deferred-to-nightly` status token and the WARN that points at the deleted nightly (AC-4 says the PR lane stays byte-identical) | Keep `deferred-to-nightly` as the report-TSV enum value — three selftest greps and `docs/testing.md:1593` consume it. Repoint only the human-facing WARN / `::warning::` / step-summary prose at the merge-time sweep. AC-4's "byte-identical" is read as scoping deferral decisions, per its own parenthetical; the prose edit is a knowing, disclosed departure from the literal wording | user-answered |
| D-8 | Labels on an auto-filed red | `bug` only. Deliberately NOT `ready-for-dev` or `in-progress`: those are `dup-scan.sh`'s corpus and the run-lean eligible set, and an auto-filed red has had no intake, so it must not read as queue-ready | user-answered |
| D-9 | Diff base for the merge-time sweep | `--mode pr --base "$GITHUB_EVENT_BEFORE"`. The sweep scopes via `git diff --name-only "$BASE"...HEAD` (`tools/mutation-sweep.sh:797`); on linear `main` history the three-dot merge-base equals two-dot, so `github.event.before` is exact for a squash merge. Requires `fetch-depth: 0`, as both existing sweep jobs already use | codebase-derived |
| D-10 | Push path filter on the merge-time trigger | None. The guard universe is a rule over every tracked non-selftest `*.sh` outside `*/evals/*` and `tests/hooks-smoke/` (`tools/mutation-sweep.sh` header), so a path filter would have to approximate it; the sweep already self-scopes and exits green immediately on a diff touching no in-universe guard (`mutation-sweep.sh:1013`). This deliberately diverges from #666's narrow filter, whose guard reads only two path families | codebase-derived |
| D-11 | Mode and sharding for the merge-time run | `--mode pr`, unsharded, one job. Sharding is `--mode full` only (`tools/mutation-sweep.sh:11-13`) | codebase-derived |
| D-12 | Shape of the monthly wholesale audit | `mutation-sweep.yml` keeps its 10-shard matrix + merge job and its `workflow_dispatch` (seed included, which stays dispatch-gated); only the `cron` line changes from nightly to monthly. AC-3 | codebase-derived |
| D-13 | Time bounds on the merge-time job | Step 60 / job 75 minutes — the issue's own ~30-45 min worst case (a lean-gate merge with deferral off), against the nightly's step-45 / job-60 idiom and the step-vs-job rationale documented in `mutation-sweep.yml` | codebase-derived |
| D-14 | Where the knob's no-ambient-leak discipline is enforced (AC-1) | Append the knob to the `seam-scrub` LOCKSTEP list in BOTH `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` (subset) and `plugins/dev-pipeline/tools/preflight.sh` (superset), so `env -u` strips it from every lane child. The leak path is live: this repo's dogfood milestone-3 `test` lane runs `run-selftests.sh`, which discovers `mutation-sweep-selftest.sh`, whose sub-invocations would inherit an exported knob | user-answered |
| D-15 | Evidence published by the merge-time run | Upload the `--report` TSV as an artifact with `if-no-files-found: error`, matching `mutation-sweep.yml`'s idiom and its reasoning about streamed reports | codebase-derived |
| D-16 | Doc surfaces AC-5 binds | `docs/testing.md:1389` "Where it runs" restated as three surfaces (PR diff-scoped, merge-time full-depth, monthly audit); the `A green PR does not mean a green nightly` block at 1591 repointed; CLAUDE.md's mutation paragraph lane references updated | codebase-derived |
| D-17 | Shape of AC-6's companion coverage | A scenario-first case in `tools/mutation-sweep-selftest.sh`: with the knob on, a slow-suite-paired guard is GRADED where the PR path emits `deferred-to-nightly`. Scoped non-exporting in the suite, per the `SLOW_THRESHOLD_S` precedent at `mutation-sweep.sh:160-169` | codebase-derived |
| D-18 | Whether #665 authors the reusable workflow or consumes one #735 already merged | parked under OR-2 | deferred |
| D-19 | The merge-time job's real wall clock with deferral off | parked under OR-1 | deferred |
| D-20 | The `mutation-baseline.tsv` row comments reading "confirm at the first nightly" | parked under OR-3 | deferred |
