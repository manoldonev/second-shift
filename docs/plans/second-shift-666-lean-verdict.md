# lean review verdict — #666

verdict=needs-work
run_id: review-666-1
session_id: 9628d05a-9a5e-46d7-aa04-44edcbd2275d
rounds: 1
pr: #735
reviewed_head: ac59ff5c92d1943e979b28f37345c24d8b0eaf0b
reviewed_patch_id: 6ad651796fc56a6d2834e8d83626a0a0ed738b17
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 read the full branch range `1d714d4..ac59ff5` (7 files, +285/-94) — `lean-gate delta`
reported FULL: no prior round to inherit from.

Verdict: **needs-work** — 3 blockers, all in the "the artifact says something the code does not
do" class. The mechanics of the move are sound; what fails is that three separate sentences
this PR ships assert a trigger contract the workflow does not implement.

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | All five oracles run at `ac59ff5`: the file exists; no `schedule:`; `push:`/`pull_request:`/`workflow_dispatch:` all present; neither `install-topology:` nor `install-topology-bash32:` remains in `nightly-guards.yml`; the file parses under `ruby -ryaml`. `nightly-guards.yml` still carries its `schedule:`/`cron: '41 2 * * *'` (L30/33) with `wholesale-selftests` and `prose-budget` intact — the scope boundary holds. `scripts/check-workflows-selftest.sh` globs `.github/workflows/*.yml`, so the new file needs no registration. |
| AC-2 | **satisfied** | `file-issue-on-red` exists, `needs` both guard jobs, gated `always() && contains(needs.*.result, 'failure')` — a skipped pair yields `skipped`, not `failure`, so a non-release PR files nothing. `gh issue list` (L122) precedes `gh issue create` (L152). The body names `${SHA:0:12}` (L138) and the failing lane(s). I additionally probed the `set -euo pipefail` + `[[ … ]] && FAILING+=(…)` shape at L129-130 that the security reviewer flagged at confidence 55: it does **not** abort when only one lane failed — measured rc=0 under both bash 3.2 and bash 5. Not a defect. |
| AC-3 | **unsatisfied** | First bullet passes: the `push.paths` awk count is exactly 3, and `grep -c 'PATH FILTER'` is 1. Second bullet fails — see **Blocker 1**. |
| AC-4 | **unsatisfied** | Both greps pass (`guard runs nightly` gone; `install-topology.yml` present in both files). The third, judgment bullet fails on two independent counts — see **Blockers 2 and 3**. |
| AC-5 | **satisfied** | `ac59ff5`'s body carries a `Changelog:` trailer. |

## Blockers

### 1. AC-3 — the `PATH FILTER` rationale for `marketplace.json` is false

`.github/workflows/install-topology.yml:25-32` states each family is listed "because
install-topology-selftest.sh itself reads it to build the staged cache", and for
`.claude-plugin/marketplace.json` specifically that it "declares the shipped plugin set the
guard iterates (plugins/*/.claude-plugin/)".

The guard never reads that file:

```
$ grep -c marketplace tools/install-topology-selftest.sh
0
```

It iterates the glob directly — `for plugin_dir in "$REPO"/plugins/*/` at
`tools/install-topology-selftest.sh:158` — and reads only `plugin.json`'s `.version` from each.
The other two families' rationales are true; this one is not.

AC-3 asks for a comment that "names why each family is in scope". A rationale that is wrong is
worse than an absent one: it is the sentence a future reader consults before widening or
narrowing the filter, and it would send them to the wrong file. Restate it for what is true
(it is the consumer-facing install manifest and it carries the release-time version), or drop
the family.

### 2. AC-4 — both docs claim the push trigger catches a *suite* regression; it cannot

`CLAUDE.md:129` — "a packaging or suite regression is caught at the next push/release that
touches those paths, not at PR time."
`docs/testing.md:685` — "a packaging or suite regression is now caught at the next push or
release that touches those paths, rather than at PR time."

The push filter matches three paths. **No suite path is among them.** The guard stages whole
plugin directories (`cp -R "$plugin_dir." …`, L166) and builds its worklist with
`find "$CACHE" \( -name '*-selftest.sh' -o -name '*-selftest.mjs' \)` (L195) — 56 shipped
suites, all under `plugins/**`. A change to any of them moves the guard's answer and matches
none of the three families.

This is not hypothetical: **every defect this guard has ever caught lives outside the filter.**
The two in its own header (a suite borrowing the repo's git toplevel; `design-sync-selftest.mjs`
assuming adjacent siblings) and #664's `pipeline-doctor-selftest.sh` sibling-resolution defect
are all `plugins/**` files.

Measured over the last 40 first-parent merges to `main` (2026-08-23 → 2026-08-31):

| | count |
| --- | --- |
| merges touching `plugins/**` — the guard's staged surface | **23** |
| merges touching the three filtered families | **4** — and **3 of those 4 are release merges** |

So the push arm's only non-release firing in 40 merges was `f9eeb28`, which touched the guard
script itself. The real load-bearing trigger is the release PR. Between the `v12.1.0` release
(08-26 10:39) and `v12.2.0` (08-30 16:33) — a **4.25-day gap** — **12 merges changed the
guard's staged surface** with zero triggers. The retired cron ran 4 times in that same window.

The pre-change sentence ("caught **within a day**") was true. Its replacement is false in the
push half. The accurate statement is "caught on the next release PR, or by
`workflow_dispatch`", and the honest trade is that the ≤1-day window widens to the release
cadence — empirically ~4 days here.

Worth flagging for whoever fixes this, though it is not itself a blocker: routing the guard's
only reliable trigger onto the release PR puts the repo's longest job on the release critical
path, which inverts the "a standing measurement belongs off the critical path" argument the
same doc paragraph makes. Either widening the filter or restating the contract resolves the
blocker; the two choices differ on this.

### 3. AC-4 — `docs/testing.md` still states the retired cadence as the live contract

`docs/testing.md:158`, untouched by this diff:

> `install-topology-selftest.sh` itself runs in its own nightly jobs (`install-topology`,
> `install-topology-bash32`), never alongside a sweep.

Present tense, describing where the guard runs today, and naming the two jobs this very diff
deletes from `nightly-guards.yml`. It sits in the `--exclude` callers section — a current-state
inventory, not incident prose, so AC-4's historical carve-out does not reach it.

Two secondary sites, weaker because they sit inside the #664 incident narrative, but both
stated as standing present-tense facts rather than dated history:

- `docs/testing.md:604-605` — "Since #620 the guard is nightly-only; the PR lane excludes it."
- `docs/testing.md:622` — "a nightly-only guard is a detection tier, not a PR gate."

`tools/install-topology-detail-selftest.sh:10-11` shows the pattern that works and was applied
in this diff — "install-topology ran nightly at the time (#666 later moved it to event
triggers)". Applying it in one file and not the other is what leaves these three.

## Recorded, not blocking

- **`pr-gates` red at `ac59ff5`** — the lean-chain check, which reds until a verdict record
  exists on the branch. Expected pre-approval state, not a finding.
- **CI at `ac59ff5`**: `lint-and-selftests` **success** (4m41s), `mutation-sweep-pr`
  **success**, `release-pr-gates` skipped, `selftests (macos, bash 3.2)` still in progress when
  this record was written. `install-topology` and `install-topology-bash32` correctly report
  `skipping` on this non-release PR — the new `if:` guard behaving as designed, observed live.
- **Design fidelity**: `not-applicable` — the spec carries no `## Design` section, so step 5b
  does not arm.
- The `release/next` + head-repo check at L64-65 and L81-82 matches `ci.yml:249` and `ci.yml:365`
  verbatim; `release-pr.yml:92` confirms that is the real release head branch. The fork-PR
  hardening is correct.
- Panel: security / performance / maintainability / complexity / test-coverage all returned
  **approve, zero findings**. Scope-completeness returned two blockers, which converge with
  Blockers 1 and 3 above; its `set -e` concern (suppressed, conf 55) I falsified by measurement.

## Strengths

- The `if:` gate on both guard jobs is the right shape: `pull_request` cannot be path-filtered by
  head branch in `on:`, so job-level routing is the only way to express "the release PR and
  nothing else", and it reuses the repo's existing head-repo-pinned idiom rather than inventing
  one. Verified live — both jobs skipped on this PR.
- `file-issue-on-red` degrades honestly. `gh run view --log-failed` cannot read an in-progress
  run's logs, and the code says so and falls back to a run link rather than filing an issue with
  an empty body.
- Dedup by title substring with the stated reason (a label must pre-exist or
  `gh issue create --label` errors outright) is the correct call and the comment records why.
- `tools/install-topology-detail-selftest.sh`'s prose was correctly re-dated rather than
  rewritten, preserving the incident record.
