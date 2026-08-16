# lean review verdict — #531

verdict=approve
run_id: review-531-1
session_id: 91f5cba1-dd4a-4831-a282-ff54612bdc59
rounds: 1
pr: #548
reviewed_head: 0cf72473a5b559a1ef613df00c5197d6cec19a05
reviewed_patch_id: e3542a40e450c785611755d863031aa086356343
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review verdict — #531 / PR #548, round 1

Range read: `14d5a00..HEAD` (full branch diff — `bash G delta 531` reported FULL: nothing
verifiable to inherit). 7 files, +1555/-200.

Panel: security, performance, maintainability, complexity, scope-completeness (test-coverage
went dark — see Coverage gap). Findings below are the synthesized set after triage; the
scope-completeness FAIL is recorded and dismissed as a blocker with the reasoning stated.

## Verdict: approve

No blocker. Every `AC-1`…`AC-15` is satisfied against the committed spec. Three warnings and
two suggestions, none of which changes what the code does on any path the lane takes.

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `lean-gate.sh` `append_teardown` / `obligations_report` | The teardown report's "standing outcome" goes stale when an outcome KIND recurs. `append_teardown` is idempotent per outcome kind across the whole record, and `obligations_report` takes the LAST `\| teardown \|` row — so `removed → kept → removed` (a re-entered lane whose second teardown was blocked and whose third succeeded) reports `kept`. CONFIRMED by probe in an isolated worktree at this head: driving the three appends through library mode leaves two rows and the report reads `teardown: kept (…)` after the successful third. Diagnostic only — echoed in the scheduler's close-out failure message, gates nothing, and AC-9 is satisfied either way. `(td5)` accepts `removed` OR `kept`, so it cannot catch this. |
| 2 | Warning | `orchestrate-lean.sh` `spawn`, the unopenable-transcript arm | AC-3's second sentence — "A capture that cannot be opened is reported and does not stop the run" — has no case. The behavior is there (the arm says so and falls back to `/dev/null`), but nothing pins it, so an edit that made it fatal passes the whole suite. `(y1)`/`(y2)` only drive the happy path. One case with an unwritable `LOG_DIR` closes it. |
| 3 | Warning | scope completeness, `#531` body | The trap-based push named in #531's Scope is deferred only in the PR's own artifacts. Not a blocker — see below — but the ticket is where a future reader looks, and it still reads as an open ask. |
| 4 | Suggestion | `orchestrate-lean.sh` terminal slugs | Four slugs are reused across distinct call sites: `closeout-progress-unreadable` ×4, `progress-unreadable` ×2, `infra-unreadable` ×2, `usage-max-rounds` ×2. Each pair/quad is one condition class with one remedy, so AC-1's "no two DISTINCT terminal conditions share a slug" holds on its own wording. The four close-out sites are the ones worth splitting eventually: they span two token spaces and both sides of the spawn, so a log router cannot tell "could not read before spawning" from "could not read after". |
| 5 | Suggestion | `run-lean/SKILL.md` | "You author nothing and the scheduler writes nothing" now sits beside a scheduler that creates `<stateDir>/` and writes per-spawn transcripts. The bullet's own enumeration (tracker comment, label swap, commit, record) stays true and `orchestrate-lean.sh`'s header carries the artifact-vs-transcript carve-out explicitly, so this is a note, not drift. SKILL.md is at its 60-line cap, so a fix has real cost. |

### Why finding 3 is not a blocker

#531's Scope bullet reads: "Mechanize it as a gate call, not as `build-lean/SKILL.md` prose …
A trap-based push on BUILD's exit paths **would additionally cover** the killed-mid-phase
case." The imperative half is implemented (`inflight` + the two call sites). The trailing
clause is the only subjunctive sentence in the Scope section.

Three facts decide it:

* **The deferral predates the code.** `## Out of scope` is in `e03dcfc`, the branch's FIRST
  commit, and `docs/plans/second-shift-531-lean.md` was never touched again
  (`git log 14d5a00..HEAD -- <spec>` shows one commit). This is not a spec amended after the
  fact to match the diff — the one shape review-lean calls a blocker outright.
* **It is the binding pre-flight ledger's decision (D-3), not the build session's.** The spec's
  preamble names the ledger as binding and says where it and the ticket disagree the ledger
  wins. The committed lean spec is this lane's definition of done.
* **The rationale is mechanical, not convenience.** SIGKILL is untrappable; under `claude -p`
  no build-session process survives to carry a trap; the only remaining host is `spawn()`,
  which would make the scheduler a source-control writer against its own standing header rule.
  Implementing it as literally asked would violate a lane invariant.

So the ask is not deferred for cost — it is not implementable at the boundary the ticket names.
A round spent here could produce no code, only an issue-body edit. Recorded as a warning
instead: say so in milestone 5's closing comment on #531, which the close-out already writes.

## AC scoring — 15/15 satisfied

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | Every run-ending exit routes through `terminal()`; 41 distinct slugs over 53 sites, no literal `exit <n>` left outside the helper and `--help`. Exit codes 0/1/2/4/5/6/7 unchanged (header block re-read). `(x1)` pins six conditions → six distinct slugs, one line each. Slug reuse is same-condition only — see finding 4. |
| AC-2 | satisfied | `now_iso()` matches the gate's format; `say` stamps every control line; `envfail` folded onto `terminal` → `say` → stdout. `(y3)` asserts over EVERY control line, not a sample. |
| AC-3 | satisfied | `2>&1 \| tee -a "$log" >&2` with `rc=${PIPESTATUS[0]}`; per-spawn file `<issue>-lean-spawn-<n>-<role>.log` under the config-resolved state dir (same `$MAIN_ROOT/$STATE_DIR` shape the gate uses — no drift on an absolute override). `(y1)`/`(y2)` pin the three-way split. Advisory arm present but untested — finding 2. |
| AC-4 | satisfied | `worktree_inflight()` extracted; `worktree_destroy` calls it and keeps on both non-zero answers, so teardown's decisions and wording are unchanged. `cmd_inflight` is outside `require_entry_attested`'s set and never calls `ensure_progress_file`. 0/8/1 as specified. `(if1)`–`(if7)`, `(if2)` for the read-only posture. |
| AC-5 | satisfied | Called after a BUILD spawn only when `$PR` is non-empty, and after the close-out; both fail-closed on a non-8 non-zero. `worktree_inflight`/`cmd_inflight` are reachable only from `worktree_destroy` and the subcommand dispatch — verified by grep, so nothing in `all` or milestone 5 is gated on it. `(t1)`–`(t4)`; `(t4)` is the ordering guard that protects #527's continuation. |
| AC-6 | satisfied | `verdict_rc` runs before the REVIEW spawn; `rc=0` logs `terminal-vocabulary: review-skipped-approved`, spawns nothing, falls into the close-out. `(u1)` + `(u2)` non-vacuity. Classes 4/6/3 now hard-stop one spawn earlier, which the header states and which is strictly cheaper. |
| AC-7 | satisfied | `MAX_CLOSEOUT_CONTINUATIONS=1`, hard-coded, no flag; predicate is the general `progress_token` delta reused verbatim; advanced-nothing is the immediate terminal. `(w1)`/`(w2)`/`(w4)`, each on a distinct slug. |
| AC-8 | satisfied | `append_obligation` writes `\| milestone-n \| obligation \| <name> \| <met\|unmet>`; `fail_obligation` records-then-fails at every milestone-5 red that names one. Aggregate withheld until both hold. `(ob3)` measures the token UNMOVED across a partial close-out — the verb assertion driven on real rows, not on spelling. `(ob6)` idempotence. |
| AC-9 | satisfied | `append_teardown` in its own `\| teardown \|` namespace, guarded on the file so it never mints a record; `cmd_teardown` returns 0 on all three outcomes. `(td1)`/`(td3)`/`(td4)`, `(td2)` for token invisibility. Staleness of the derived report is finding 1, not an AC failure. |
| AC-10 | satisfied | `progress --obligations` prints the two obligations, the aggregate alongside its parts, and teardown as its own line; the scheduler echoes via `closeout_report` and reads nothing. `(w3)` asserts on the passed-through lines. |
| AC-11 | satisfied | `(lean-closeout)` drives the real scheduler, the real gate and a real `git worktree` with a real origin through BUILD → REVIEW → a close-out that discharges one of two obligations → continuation → terminal write. Paired `(lean-closeout-nv)` arm varies the FIXTURE, spends the one continuation, stops under `closeout-continuations-spent`, reaches no terminal write. The fixtures now push, which is what makes the in-flight read mean anything. |
| AC-12 | satisfied | `(t1)`/`(t2)` exits-0-with-work-in-flight and its fail-closed direction; `(t4)` the ordering; `(u1)`/`(u2)` the approved-head skip and non-vacuity; `(x1)` the vocabulary asserted per terminal via `slug_of`, not by grepping source. |
| AC-13 | satisfied | `(if1)`–`(if7)` both firing arms, the unreadable direction and the read-only posture; `(ob1)`/`(ob3)` partial satisfaction with the token unmoved; `(td1)`/`(td3)`/`(td4)` the three teardown outcomes. |
| AC-14 | satisfied | `mutation-baseline.tsv` correctly untouched — I re-derived the site lists at base and head for both edited guards: `lean-gate.sh::cmp-eq::1` (a prose site), `::default::1`/`::default::2`, and `orchestrate-lean.sh::default::1` all still point at the same lines, every new site landing past the baselined ordinals. `mutation-catalog.tsv` re-anchors `lean-gate-teardown-pushed-direction` for D-3's extraction (one site, two callers, killed at both) and adds `lean-orchestrate-terminal-code` to replace the `fail-open` reach the routing deleted (16 sites → 1). |
| AC-15 | satisfied | Both header blocks document the new subcommand + exit 8 and the terminal-slug contract. Help ranges re-pinned and both verified against the file: `orchestrate-lean.sh` `2,216p` ends one line before `set -uo pipefail` at 217; `lean-gate.sh` `2,291p` ends one line before `set -uo pipefail` at 292. |

Fidelity: `not-applicable` — the spec arms no `## Design` section and the repo configures no
design provider.

## Coverage gap

`review-toolkit:test-coverage-reviewer` went **dark** (`died-after-retry`: turn-budget, no text
on either attempt). Its domain was not covered by the panel. I read the three selftest diffs
myself in its place and scored AC-11/12/13 against them; findings 1 and 2 are what that read
produced. Merge readiness below is stated on that basis, not on a panel that covered every
dimension.

## Panel verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Fail | 1 (dismissed as blocker, kept as warning) | 88 |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | **Dark (no output)** | — | — |

## Strengths

* **The ordering fix is the finding the ticket did not contain.** #531's Scope reads "after
  every BUILD spawn"; that placement hard-stops the exact spawn #527 taught the loop to
  continue from, because a build session holds unpushed commits for most of its life. Gating on
  a PR existing keeps both behaviors AND makes the unreadable arm a genuine environment error.
  `(t4)` pins it with an in-flight answer that would stop the run if consulted.
* **The `fail-open` reach lost to the refactor was noticed and replaced.** Routing thirteen
  `exit 1` sites through one helper takes the generic operator's only sites away — nothing reds,
  because non-application is data. A catalog row replaces it, probe-verified rather than
  asserted.
* **The composed leg is genuinely composed and genuinely non-vacuous.** Real scheduler, real
  gate, real worktree with a real origin, and a paired arm that varies the fixture rather than
  the code. `(ob3)` is the same discipline gate-side: the verb contract measured as an unmoved
  token, not asserted about spelling.
* **The fixtures were made to push.** Two legs went red for what looked like a fixture problem
  and the honest fix was both halves — push in the fixtures AND move the check.
