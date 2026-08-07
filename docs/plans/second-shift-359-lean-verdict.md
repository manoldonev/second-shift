# lean review verdict — #359

verdict=approve
run_id: review-359-2
session_id: e2778348-6cbc-47a7-884b-c0593333c0de
rounds: 2
pr: #430
reviewed_head: 0f02a2e247312d06f976d19cd59cfc5b2be19246
reviewed_patch_id: 3818c4fc81ae77ce9c2dcf94e9c0050e914ccf07
inherited_patch_id: a59198db47818ca0377ce843245d125d8cdc9228
inherited_from_verdict: 726188ec732c9c088655b35087d3edeed1465f17
fidelity: not-applicable
model: unknown

## Round 2 — `approve`

Range read: `726188e..HEAD` (the round-2 delta; `delta` reported the round-1 record's patch
`a59198db4781` as inheritable). 8 files, +108/−19. Round 1's findings were read first, from the
committed record, before reading the delta. Panel: security, performance, maintainability,
complexity, test-coverage, scope-completeness — all six returned, none dark, zero findings at or
above the confidence threshold.

Both round-1 findings are fixed, and each fix is pinned by an assertion that dies under a
targeted mutation. The blocker's fix is the stronger of the two: it did not just add the scopes,
it made the assertion block-scoped, which is what stops the same bug recurring behind a
commented-out line.

### Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| 1 | Resolved (was round-1 Blocker) | `plugins/second-shift/templates/consumer/second-shift-ci.yml:30-33` | The `permissions:` block now grants `contents: read` + `issues: read` + `pull-requests: read`, matching this repo's `pr-gates` job for the same `GET /repos/{o}/{r}/issues/{n}/comments` read. The misleading "never widen this job's permissions" comment is replaced by one that separates read from write and names each scope's arm. Verified non-decorative by five hand probes, each mutation confirmed landed by `cmp`: dropping `contents`/`issues`/`pull-requests` from the block kills **only** that scope's own pin (P1/P2/P3); adding `id-token: write` kills **only** the no-write pin (P4); and moving the two reads out of the block into a comment above it kills both scope pins (P5) — which a whole-file `grep` would have survived, so the `awk` block extraction is load-bearing rather than stylistic. |
| 2 | Resolved (was round-1 Warning) | `plugins/dev-pipeline/skills/run-lean/lean-evidence.sh:462-467` | `arm_freshness` now suppresses its restatement only when the verdict arm actually ran, guarded on the dispatch list itself (`case ",$ARMS," in *,verdict,*`) — the same predicate `run_arms` dispatches on, so the two cannot drift. A `needs-work` record counts **1** violation on a combined run and still counts 1 under `--arms freshness` alone. `(h)` pins the count (it previously only printed it); `(h2)` is new and covers the lone-arm half. Probed with the two opposite flips of that one line: `*,verdict,*` → `*,zzzzzz,*` kills only `(h)`; `*,verdict,*` → `*)` kills only `(h2)`. Neither is killed by both, so the pair is provably not one assertion written twice. Confirmed independently that this cannot move any verdict in `scripts/check-lean-chain.sh`: its only `delegate freshness` call (line 646) sits in the `elif` branch reached exclusively when `verdict_value == approve`, so the suppressed path is unreachable from the host gate. |
| 3 | Note | `plugins/second-shift/templates/consumer/second-shift-ci-check-selftest.sh:195-197` | The sibling loop one line above the new block — `check "yml: step env carries $v" "$(grep -q "$v:" "$YML" ...)"` — is still a whole-file grep, the exact weakness the new scope pins were rewritten to avoid. It is satisfied by any occurrence of `PR_BODY:` etc. anywhere in the file, a comment included. Pre-existing (it arrived with the payload commit, not this delta) and not required to be stronger by any AC, so recording rather than asking for a change; the six env names happen not to appear comment-side today. Worth folding in whenever that block is next touched. |
| 4 | Note (environment) | — | **CI has not run on the round-2 head.** `check-runs` for `0f02a2e` is `total_count: 0` and the branch has exactly one Actions run, against `726188e`, ~35 min after the head commit. So the merge boundary has produced no verdict on the tree being approved here — neither red nor green — and in particular the macOS **bash 3.2** lane has not exercised the new assertions. Nothing in the diff causes this; it is the same dispatch behavior round 1 recorded. Covered locally instead: both changed suites were run under `/bin/bash` 3.2.57 explicitly, `rc=0` each. The last CI run that did complete (`726188e`) was red for exactly one reason, `verdict=needs-work`, with `lint-and-selftests` and `selftests (macos, bash 3.2)` both green. Operator eye before merge. |

Round 1's finding 3 (the unkilled defensive guard at `scripts/check-lean-chain.sh:369`) was
declared as left-as-recorded and is unchanged; it stays a note, not a re-raised finding.

**Spec amendments are tightening, not retrofitting.** This delta edits AC-1, AC-2, AC-8 and the
Architecture's exit-code paragraph. Every edit **adds** a requirement and removes none — AC-2
gains the whole `permissions:` clause, AC-1 gains the one-fact-one-violation clause, AC-8 gains
the read-scopes clause — and the diff then meets each. That is the opposite of the banned
"spec amended after the fact to match the diff": the bar moved up in response to the review, and
a future round now checks something round 1 had to find by hand.

Suppressed below the confidence threshold (both from the panel, ≤60): the two added read scopes
marginally widening what a compromised pinned-ref script could read on a private consumer repo
(dominated by the pre-existing `contents: read`, required by the arm, read-only, documented); and
the no-write-scope pin covering only the workflow-level block, so a future **job-level**
`permissions:` would evade it (accurate, and the template has no job-level block today).

### AC scoring — `docs/plans/second-shift-359-lean.md`

Every AC scored against the whole spec, not only the delta; inherited scores carry round 1's
evidence plus this round's clean full-suite run.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 payload selftest | **satisfied** | The nine enumerated assertions are unchanged and green; the amendment's new clause is met by `(h)` + `(h2)`, killed by opposite flips of one line with disjoint killers (P6/P7 above). 37/37 green (36 at round 1, +1 for `(h2)`), hermetic. |
| AC-2 template selftest | **satisfied** | The clause that round 1 could only score "by its letter" is now armed: `PERMS="$(awk '/^permissions:/{f=1;next} f&&/^[^ ]/{f=0} f' "$YML")"` then `grep -q "^  $p\$"` per scope, plus the no-write pin. Four assertions, four disjoint killers (P1–P4), and P5 proves block-scoping is what makes them real. The retired `yml: job permissions are contents: read` file-wide check is strictly subsumed. 49/49 green. |
| AC-3 delegation | **satisfied** | Untouched by the delta; `check-lean-chain-selftest.sh` green in the full sweep. Re-verified that the one behavioral change in the payload cannot reach this gate (finding 2). |
| AC-4 writer | **satisfied** | Untouched; `lean-gate-selftest.sh` green (92s, rc=0). Confirmed live: PR #430 carries a bot-authored (`user.type: Bot`) marker with `run_id: lean-359-a`, a session id, and `stage: lean-pr-marker`. |
| AC-5 config resolution | **satisfied** | Untouched; green. |
| AC-6 jira degrade | **satisfied** | Untouched; green. |
| AC-7 mutation baseline | **satisfied** | Verified independently and **uncached**, because the delta edits `lean-evidence.sh` mid-file and a re-key would be invisible to a cached run: `mutation-sweep.sh --mode pr --base origin/main` with `MUTATION_SWEEP_CACHE=0` — 49 verdicts, 0 from cache, 413s, advisory/local. Observed survivor set is **exactly** the committed baseline on all four guards, 16 ids, **zero unbaselined**: `lean-evidence` `{cmp-eq::1, cmp-eq::2, default::1}`, `lean-gate` `{cmp-eq::1, default::1, default::2}`, `ci-check` `{cmp-eq::1, cmp-z::1, logic::2, default::1}` + `catalog::ci-check-lint-path`, `check-lean-chain` `{cmp-eq::1, cmp-eq::2, cmp-z::1, default::1, default::2}`. So the new `case` block re-keyed no ordinal, and no baseline row needed re-anchoring. |
| AC-8 doc | **satisfied** | `SECOND-SHIFT.md` gains the hand-maintainer's paragraph naming all three scopes, the replaces-wholesale rule and the read-only boundary; `.github/workflows/ci.yml` gains the reciprocal pointer; `SKILL.md` step 7 unchanged; `lockstep-manifest.tsv` keeps the marker-shape row and adds the token-scopes DROPPED entry. `check-lockstep-pairs.sh` 19/19. |
| AC-9 critic | **satisfied** | All **seven** commits carry a `Changelog:` trailer (checked per-commit, not only `check-changelog-trailer.sh origin/main`, which is grep-anywhere); the new commit's trailer names the consumer-visible change and its manual migration. No consumer identity anywhere in the branch — fixtures are `acme-*`; a scan for org/product names and company ticket keys over both the delta and the full branch returns nothing. |

**On the token-scopes DROPPED entry.** Recording a byte-anchorable pair as DROPPED normally
reads as an anchoring dodge, so I checked it rather than took it: the entry says outright that
the two blocks *do* collapse to the same string and rests on "not one contract" instead, which
has precedent in this manifest (the artifact-name-suffix entry above it drops on "the two sets
are deliberately DIFFERENT"). The argument holds — a `verbatim` row binds in the wrong direction,
turning a scope the *host* later needs into one every consumer is forced to grant, which is the
escalation the template's own comment refuses. The replacement is asymmetric and matches where
the signal is: the template has none in this repo, so it gets four assertions; the host executes
that read on every PR, so an assertion there would restate what CI already proves. The residual
— a future payload arm needing a new scope is not *mechanically* forced into the template, since
the three pins are a lower bound — is exactly what the revisit clause and the new `ci.yml`
pointer are for, and both sit at the sites a future editor touches.

### Design fidelity

`not-applicable`. The spec's `## Design` section carries the explicit `Design: none — this is
shell/CI plumbing with no rendered surface` disarm, and the repo's committed config declares no
`design.provider` (`.design` is null), so the disarm is justified and steps (i)–(iii) do not
apply. Unchanged from round 1.

### Verification I ran (from this checkout of the PR head)

- Full sweep, **no `SKIP_STRESS`**, with `CLAUDE_CODE_SESSION_ID` / `RUN_ID` / `GH_BOT` unset:
  **64/64 green**, per-suite exit codes captured individually rather than read off a summary line.
- Both changed suites re-run under the system **bash 3.2.57**, standing in for the CI lane that
  has not run: `rc=0` each.
- **7 hand-probed mutations, 7 killed, no two assertions sharing a killer** — each probe `cmp`-ed
  against the original so an unchanged file scores PROBE INVALID rather than SURVIVED, and the
  tree verified clean afterwards.
- `shellcheck -e SC1091,SC2015,SC2181` clean on all three changed shell files.
- `check-lockstep-pairs.sh` 19/19, `check-changelog-trailer.sh` rc=0 (plus the per-commit check),
  `check-frozen-files.sh origin/main` clean with the expected `.github/workflows/**` advisory.
- Uncached diff-scoped mutation sweep, 49 verdicts (AC-7 row above).

### Strengths

- The blocker's fix is not just the two scopes. It changes what the assertion *can* fail on —
  block-extracted rather than file-wide — and P5 is the probe that proves it, dying on a mutation
  a `grep`-the-file version would have shrugged off. That is the difference between closing this
  bug and closing this bug's class.
- The freshness suppression is guarded on the dispatch list itself rather than on a hand-copied
  arm name, so "did the verdict arm run" is answered by the same expression that decides whether
  it runs. The two opposite flips with disjoint killers are the right proof for a single line
  carrying two assertions.
- The DROPPED entry argues its own weakest point — that the pair *is* anchorable — instead of
  hiding behind "no anchor exists", and replaces the row with a decision procedure a future editor
  can actually execute, mirrored into `ci.yml` where they will be standing.
- The commit message states the manual migration for consumers who already have the workflow
  emitted, which the changelog trailer alone would not have conveyed.
