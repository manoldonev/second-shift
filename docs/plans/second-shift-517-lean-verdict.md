# lean review verdict — #517

verdict=needs-work
run_id: review-517-1
session_id: 1c4bb8a1-f31e-409c-83bb-8e8d58bbd988
rounds: 1
pr: #592
reviewed_head: 5bdc0f6cdcd6efb5c991de5ded2123cbf11375b0
reviewed_patch_id: 422191818c1bcff2c3206e9c85a9e74601f7b8c7
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Verdict: needs-work — 2 blockers

Round 1, full branch range `d287848..5bdc0f6` (root round, nothing to inherit).

The mechanism itself is good work. `--reconcile` does what the spec says, the parse handles
both receipt arities on provenance rather than on `Kind`, mode isolation is genuinely
byte-identical against `origin/main`'s copy, and the composed scenario leg carries a real
non-vacuity arm. Nine of eleven ACs are satisfied against the code, verified by execution
rather than by reading. Two blockers: one is CI-red at the reviewed head, the other is an
unsatisfied AC that this repo's own configuration makes invisible.

---

## Blockers

### B-1 — `lint-and-selftests` is RED at the reviewed head; the ubuntu selftest lane never ran

`plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh:542`

CI run [32191296654](https://github.com/manoldonev/second-shift/actions/runs/32191296654) is on
`headSha 5bdc0f6` — exactly the patch this record names — and `lint-and-selftests` fails:

```
In ./plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh line 542:
rc_receipt() { # rc_receipt <resolution-for-D-3>
^-- SC2120 (warning): rc_receipt references arguments, but none are ever passed.

In ./plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh line 557:
rc_receipt > "$TMP/rc-receipt.md"
^-- SC2119 (info): Use rc_receipt "$@" if function's $1 should mean script's $1.
##[error]Process completed with exit code 123.
```

`rc_receipt` takes `${1:-Both call sites}` but is only ever called with no argument. Its sibling
`rc_plan` has the same `${1:-…}` shape and *is* called with an argument, which is why only one of
the two fires.

**Why the PR body says "shellcheck clean repo-wide" and is not lying.** This is the known
local-vs-CI version skew. CI installs shellcheck **0.9.0**; the local brew is **0.11.0**, which
does not raise SC2120 here. I confirmed both directions: the repo's own recipe
(`shellcheck -e SC1091,SC2015,SC2181`) over that file returns rc=0 on 0.11.0, while the CI log
shows 0.9.0 raising it on the same bytes. The verification claim was made honestly against the
wrong checker.

**Second-order consequence, and the reason this is a blocker rather than a nit.** Shellcheck is
the **first** step of `lint-and-selftests`, so the job died at 54s and the ubuntu `jq` validation
and selftest sweep in that lane **never executed at this head**. The only CI selftest evidence on
`5bdc0f6` is the macos bash-3.2 job. The PR's "69 scored, 69 run, 0 failed" is a local result.

Remedy: give `rc_receipt` a parameter at its call site, drop the unused `${1:-…}`, or add a
`# shellcheck disable=SC2120` with the reason. Whichever — re-run CI, because that lane has not
yet reported on this diff.

### B-2 — AC-8 unsatisfied: the reconciliation note is clobbered whenever the design lane is armed or disarmed

`plugins/dev-pipeline/skills/build-lean/lean-gate.sh:3034` vs `:3059-3060`

AC-8 requires that "milestone 1's pass line discloses the reconciliation through `cmd_1`'s
existing `note` variable". The reconciliation **appends**:

```bash
0) note="$note, ${rec_out#ledger-lint: reconcile: }" ;;      # :3034
```

but the `design_state` block that runs immediately after **assigns**:

```bash
      note=", design lane disarmed for this ticket" ;;        # :3059
    armed)    note=", design lane ARMED" ;;                    # :3060
```

So on any run where `design_state` returns `armed` or `disarmed`, the reconciliation disclosure is
silently discarded. Reproduced against the real gate, one fixture tree, three configs, only the
config and the spec's `## Design` section varying:

```
no design provider   → ✓ milestone-1: … (1 AC-n reference(s)), 1 bound, 1 carried, 0 departure(s)
provider + disarmed  → ✓ milestone-1: … (1 AC-n reference(s)), design lane disarmed for this ticket
provider + armed     → ✓ milestone-1: … (2 AC-n reference(s)), design lane ARMED
```

The counts are gone in rows 2 and 3.

**Why every green thing missed it.** This repo configures no `design.provider`, so `design_state`
returns `unarmed`, the `case` matches no arm, and `note` survives. That is true of the dogfood run
quoted in the PR body *and* of `lean-gate-selftest.sh`'s fixture config, which carries no `design`
key — so `(a11)`, the case that owns the AC-8 claim, cannot fail on this. It is not a
hypothetical configuration: it is the state of a consumer repo that has a design provider
configured and a pre-flight receipt on the ticket, and both are ordinary supported states.

This matters beyond cosmetics for the same reason `(a11)`'s own comment argues — the disclosure is
what distinguishes "reconciled 8 rows" from "silently bound nothing". Losing it on exactly the
runs that also have a design lane is the shape a silently-inert check hides behind.

**Remedy, proven.** Two characters, in an isolated worktree off `5bdc0f6`:

```bash
      note="$note, design lane disarmed for this ticket" ;;
    armed)    note="$note, design lane ARMED" ;;
```

```
provider + disarmed  → … 1 bound, 1 carried, 0 departure(s), design lane disarmed for this ticket
provider + armed     → … 1 bound, 1 carried, 0 departure(s), design lane ARMED
```

The remedy is also safe: with it applied, the whole of `lean-gate-selftest.sh` is **all green**
(`SUITE_RC=0`), so nothing in the existing suite depends on the clobber.

Please also extend the guard, or the next edit re-introduces it: `(a11)` proves AC-8 only on the
no-provider path. A case driving the same assertion under a config with `design.provider` set is
what would have caught this.

---

## Warnings

- **W-1 — the AC-8 guard cannot fail on the defect it names.** Folded into B-2's remedy above;
  called out separately because it is the reusable lesson: `lean-gate-selftest.sh`'s single `CFG`
  has no `design` key, so every case in the file scores the `unarmed` branch of `cmd_1`. Any
  future contract that composes with `note`, or with `design_state`, inherits the same blind spot.

- **W-2 — coverage gap: `maintainability-reviewer` went dark.** Died after its automatic retry
  (`turn-budget: agent emitted no text on either attempt`). Its domain — readability and ease of
  future modification, over a ~700-line diff that is mostly new bash — was not reviewed this
  round. The other five reviewers returned; this round is not void, but merge readiness is
  assessed without that dimension.

- **W-3 — `pr-gates` red is expected, and is not B-1.** It fails on
  `no committed verdict record (a file named *-517-lean-verdict.md)`, which is precisely what this
  record supplies. Noted so the two reds are not conflated when CI is re-read: `lint-and-selftests`
  is the one that needs a code change.

---

## Findings raised and dismissed

- **Scope narrowing to `user-answered`/`user-delegated`** (scope-completeness, confidence 88).
  Issue #517's prose states the predicate as "every `D-n` id"; the implementation binds only intent
  rows. Not a finding: the issue's own Notes section supplies the rationale, receipt row **D-1** is
  `user-answered` and resolves it explicitly, the spec discloses it in three places, and
  `SKILL.md:22` states the narrowed obligation so instruction and gate agree. This is the
  operator's resolved intent, not a reading the build role picked — exactly the class of decision
  the mechanism under review exists to make visible, and it is visible.

- **AC-11's promised `tools/mutation-baseline.tsv` re-key is absent from the diff**
  (scope-completeness, confidence 82). Checked independently and the baseline is **correct as-is**.
  The dispatched sweep [32188942819](https://github.com/manoldonev/second-shift/actions/runs/32188942819)
  ran at `a651fbb`, and both guards were genuinely swept per their shard logs:
  `ledger-lint.sh applied=11 killed=6 survived=5`, `lean-gate.sh applied=28 killed=25 survived=3`.
  The `survived=5` against only **4** committed generic rows resolves to the fifth being
  `catalog::ledger-lint-empty-decision` (`tools/mutation-baseline.tsv:22`) — catalog mutants are
  keyed `catalog::<id>`, not `path::operator::ordinal`, and are swept in the same line. All five
  are baselined; a baseline-absent survivor is the one thing that reds the lane
  (`tools/mutation-sweep.sh:1879`), so the green enforcing run is the proof. `lean-gate.sh`'s 3
  survivors likewise match its 3 rows exactly, meaning every one of its ~15 catalog mutants was
  killed. The head commit `5bdc0f6` touches only `lean-gate-selftest.sh`, which adds kill-set
  assertions and enumerates no new sites, so it cannot introduce a survivor the `a651fbb` sweep
  did not see.

---

## Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 | satisfied | `--reconcile <receipt> <plan>` present. Binds via `INTENT_PROVENANCE` (`ledger-lint.sh:149`, single-sited), **not** the `Kind` cell. Both arities parse: `ledger_rows` requires ≥5 `|`-fields and reads Provenance as the 4th column, so the 4-column pre-Kind receipt binds — driven by `(ll-rc10)` and re-run by hand. |
| AC-2 | satisfied | Dropped bound row → rc=1 naming `D-3 (user-delegated)`. Verified directly and by `(a9)` (which also asserts exactly one attempt line). |
| AC-3 | satisfied | Verified all three arms by hand: differing text → rc=1; `100/min` vs `100/MIN` → rc=1 (case-sensitive, per OR-1); `\|    100/min    \|` → rc=0 (whitespace-normalized). |
| AC-4 | satisfied | `DEPARTURE` with no alphanumeric reason → rc=1; `DEPARTURE — <reason>` → rc=0 and counts as a departure, not a carry. Confirmed the departure row still passes #562's provenance lint clean (`ledger-lint: OK`), which AC-4 explicitly requires. `(ll-rc7)` covers the `DEPARTURES were made` prose case. |
| AC-5 | satisfied | Spec stating `No material decisions — all choices codebase-derived.` against a receipt with one bound row → rc=1, landing on the per-row missing arm as the code comments predict. |
| AC-6 | satisfied | The strongest check available and it holds: extracted `origin/main`'s `ledger-lint.sh` and diffed rc+stdout+stderr against the branch copy for plain mode and `--receipt` mode, on the very spec/receipt pair `--reconcile` refuses. **Byte-identical both modes.** Zero-bound receipt → `0 bound, 0 carried, 0 departure(s)`, rc=0. `--receipt` + `--reconcile` → rc=2; `--reconcile` with no value → rc=2. |
| AC-7 | satisfied | Block sits above the `LEAN_GATE_OBSERVE` guard. rc mapping confirmed: 0 passes, 1 → `fail_milestone 1` (attempt line present), anything else → `envfail` with no attempt line. Absent receipt inert `(a12)`; unreadable receipt → rc=2 under **both** a normal and an observe call `(a13)` — and the observe call is the arm that attributes the refusal to this reader rather than to #533's `check_pause_and_ask`. |
| **AC-8** | **unsatisfied** | See **B-2**. The pass line discloses the reconciliation only when `design_state` returns `unarmed`; `armed` and `disarmed` overwrite `note` and drop the counts. Reproduced against the real gate. |
| AC-9 | satisfied | `SKILL.md:22` states the carry-forward obligation naming the provenance pair, the `D-n`/Resolution match, and the `DEPARTURE — <reason>` escape. File is **47** lines against the 60-line cap. No intake-side skill amended, as the AC requires. |
| AC-10 | satisfied | Header documents the mode. `sed -n '2,98p'` verified exact: line 98 is `# Exit: 0 clean, 1 violations …`, line 99 is `set -euo pipefail` — help prints 97 lines and stops immediately before the code. `(ll-rc13)`-adjacent case pins it. |
| AC-11 | satisfied | All four tiers present and non-vacuous: `(ll-rc1)`–`(ll-rc13)` per-tool (suite green, 61 passed / 0 failed); `(a9)`–`(a14)` on the gate; the composed `(lean-receipt)` leg, which reaches the refusal through `all` **and** carries a real non-vacuity arm (restore the dropped-row spec, remove the receipt, same call passes). Mutation baseline correct as committed — see the dismissed finding above. The B-1 shellcheck red lives in a file this AC added but is a lint defect, not a coverage gap, so it is scored as a blocker outside the AC set. |

**Design fidelity:** `not-applicable` — no `design.provider` is configured in this repo, the
committed spec carries no `## Design` section, and `design_state` returns `unarmed`. Nothing to
score. (Note the irony that this same condition is what hides B-2.)

## Panel

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (2 suppressed <80) |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Test Coverage | Pass | 0 |
| Scope Completeness | Pass (nits) | 2, both dismissed above with evidence |
| Maintainability | **Dark (no output)** | — (died after retry) |

Both blockers are the round's own work; the panel found neither.
