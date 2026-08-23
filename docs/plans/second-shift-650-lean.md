# #650 — build the campaign's instruments; the campaign itself runs outside this PR

Issue: https://github.com/manoldonev/second-shift/issues/650
Criterion (frozen, +revision 5 on an operator ruling): [`second-shift-643-preregistration.md`](second-shift-643-preregistration.md)
Campaign evidence file: [`second-shift-650-campaign.md`](second-shift-650-campaign.md)
Follow-up (the campaign and the arm execution): #652
Audit (phase 1): [`second-shift-643-audit.md`](second-shift-643-audit.md)

## What this slice is, and what it is not

#650 as filed bundles work with three different completion conditions:

1. **instruments** — the per-launch spawn logging AC-2's denominator needs, the mid-run staleness
   re-check `D-12` routed here, and the variant-`c` drive-mode that does not exist yet;
2. **a campaign** — nine lane runs across three drive-modes, on comparable tickets, over days;
3. **an arm execution** — up to and including deleting the scheduler.

(1) is a session. (2) is calendar work that cannot be collected inside one `build-lean` run, and
whose runs must not be *simulated* — a simulated timing is not a timing. (3) cannot begin until
(2) reports, and the criterion's whole purpose is that no arm is chosen before it does.

**This slice delivers (1), plus the committed evidence file the campaign's runs fill in.** (2) and
(3) move to a follow-up, filed before handoff per `AC-8`. The re-scope is `D-4`/`D-5` below and is
the operator's call, not this session's.

**The criterion is frozen.** It is scored exactly as written, and revision 5 (`AC-3`) lands only
because the operator ruled it, in the terms recorded at `D-6` — not because this session found the
result inconvenient. Revisions 1–4 stand unedited; revision 5 is appended, states its direction,
and changes no outcome in this PR, because no arm is selected here under any revision.

## Acceptance Criteria

- **AC-1** — **per-launch spawn evidence.** `orchestrate-lean.sh` stamps every payload transcript
  with a per-launch token, so a re-launch can no longer truncate its predecessor's transcript, and
  the launch a spawn belongs to is recoverable from the state directory alone. A launch that spawns
  nothing is still enumerable. Lands as this branch's **first implementation commit**, with its own
  selftest cases, before any other scope item — until it holds, nothing a campaign run records is
  scorable (`D-1`).
- **AC-2** — **the mid-run staleness re-check is wired.** The gate asks whether the ticket is still
  live at the step-7 handoff (`mark`), not only at `entry`. A build session alive across its
  ticket's close is refused before it hands off, so the review round that close would otherwise
  cost is not spent. Arm-independent: it holds under `run-lean`, under the manual two-terminal
  lane, and under the variant-`c` drive-mode. Selftest cases guard both the refusal and the
  landing-path exemption (`D-9`).
- **AC-3** — **revision 5 of the criterion is appended**, prior text standing, carrying both parts
  the operator's ruling names (the emptiness finding and the redefinition of variant `c`) and the
  required direction note. Appended, never edited in.
- **AC-4** — **variant `c` exists as a time-boxed instrument**: the attended drive-mode. The
  scheduler's entire control flow runs as direct gate calls; there is no `claude -p` transport
  anywhere; the next payload command is printed for an operator to run in an attended session; and
  re-invocation resumes statelessly from the gate's own reads. It is an instrument, not a ship — it
  lands only if it wins, and the arm it belongs to is selected by the campaign, not here. Arm `a`
  is not perturbed: the existing loop is untouched on its own path.
- **AC-5** — **the evidence file the campaign fills in is committed** at
  [`second-shift-650-campaign.md`](second-shift-650-campaign.md), with the row schema, the
  per-run fields AC-2 of #643 requires (wall-clock, session count, **operator-attention minutes**),
  the frozen attribution rubric restated by reference rather than by copy, and every run row empty.
  A skeleton whose columns are decided after the first run is a skeleton that gets fitted to it.
- **AC-6** — *departed, see `D-4`.* The campaign's nine runs are neither run nor simulated in this
  session. They happen across days, outside it, and fill in `AC-5`'s file.
- **AC-7** — *departed, see `D-5`.* No arm is selected and none is executed in this PR under any
  outcome, including the outcome where the instruments make one look obvious.
- **AC-8** — the follow-up carrying `AC-6` and `AC-7` is **filed and linked from this PR before
  handoff** — **#652**. #643's own `AC-7` rule, inherited: a re-scope that does not file its
  remainder is a scope cut, not a split. Filed `needs-spec-work` rather than `ready-for-dev`
  deliberately: its work is nine lane runs over days, which no build session can pick up, and a
  queue label would offer it to one. Re-label at the operator's discretion.
- **AC-9** — `bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` is
  green, and `shellcheck -e SC1091,SC2015,SC2181` is clean over every `*.sh`.
- **AC-10** — `Changelog:` and `Guard-mass:` trailers present. This slice adds guard mass
  (`lean-gate.sh` counts, and so does every `*-selftest.sh` case), so the trailer is due and states
  the reason rather than waving the budget through.
- **AC-11** — **doc AC.** `run-lean/SKILL.md` documents the attended drive-mode and its exit code;
  `docs/testing.md` records any coupling this slice considers and declines. Scoped here because
  `AC-4` makes the front door's own documentation stale.

## Decision Ledger

| id | subject | resolution | provenance |
| --- | --- | --- | --- |
| D-1 | sequencing of scope item 4 | Lands FIRST, as its own commit with its own selftest, before any campaign run is timed. Until it holds, a launch's evidence is destroyed by its successor and nothing recorded is scorable. | user-answered |
| D-2 | whether scope item 5 may share this PR | Yes — it is arm-independent, so it does not wait on a selection. | user-answered |
| D-3 | the criterion's mutability | FROZEN at `second-shift-643-preregistration.md` through revision 4; scored exactly as written. This session may not author a revision on its own judgment — the standing instruction is to hand back instead. Superseded ONLY in the narrow way `D-6` records. | user-answered |
| D-4 | scope item 2 — the campaign's nine runs | DEPARTURE — they happen across days and outside this session, and must not be run or simulated here. This PR delivers the instruments and the evidence file they fill in. Moves to the follow-up `AC-8` requires. | user-answered |
| D-5 | scope item 3's second half — arm execution | DEPARTURE — not in this PR under any outcome. The arm is selected only after the nine runs exist. Moves to the same follow-up. | user-answered |
| D-6 | variant `c` is empty as `B4` defines it | Post-#590 `orchestrate-lean.sh` has exactly two spawn sites, `:800` BUILD and `:929` REVIEW, and both are model payloads — so the set of spawn sites a direct gate call can serve is EMPTY and variant `c` as written IS arm `a`. Raised to the operator as a blocking question rather than resolved here. RULING: land it as **revision 5** (`R5-1`), appended, prior text standing, carrying the finding, the redefinition of variant `c` as the attended drive-mode, and a direction note recording that the amendment gives arm B an instrument it otherwise lacks. The ticket title's "three drive-modes" reading is ratified. | user-answered |
| D-7 | the follow-up filing rule | #643's `AC-7` applies to this re-scope too: the remainder is filed and linked before handoff, or the split is a cut. | user-answered |
| D-8 | the launch token's shape — a per-launch directory, or a stamped filename | Stamped filename, plus a launch ledger line. A per-launch directory breaks the corpus's own flat `<issue>-lean-spawn-*.log` discovery — the exact glob whose top-level/recursive disagreement produced revision 3's `R3-4` miscount — and would make the next enumeration harder, not easier. The stamp keeps discovery flat and makes launch grouping a field rather than a path. The ledger line is what makes a launch that spawns NOTHING (a preflight reject) enumerable; without it AC-2's denominator still under-counts, in the direction that favours arm A. | codebase-derived |
| D-9 | where the mid-run re-check goes | On `mark`, and on the direct `mark` subcommand only. `mark` is inside the live spawn, already makes a network call and a write, and sits immediately before the handoff — so it costs the milestone calls' recorded network-free property nothing and saves the review round. NOT on `5`/`close-out`'s re-call of it: that is the landing path, and refusing there would strand approved, reviewed work — #515's `D-4` reasoning, honored rather than re-decided. | codebase-derived |
| D-10 | the issue body's "nothing calls it" | Imprecise as written, and corrected rather than repeated: `lean-gate.sh:2502` IS reached, via `cmd_staleness`, from `probe_ticket` (`orchestrate-lean.sh:500`) and from `staleness_rc` (`:780`) before every BUILD spawn. What nothing calls is a re-check *after* `entry`, from inside a live payload — which is the defect the corrected class-M shape describes, and what `AC-2` wires. | codebase-derived |
| D-11 | a re-check at milestone 3's start, which would save more time | CONSIDERED AND DECLINED. It is where the incident's redundant minutes are actually spent, but `lean-gate.sh:781` records that milestone calls are network-free and `require_ticket_live` is "one read per run boundary, never per milestone". Buying minutes by breaking a documented property of the calls a session makes dozens of times is the wrong trade, and it is the campaign's job to price those minutes, not this slice's to assume them. Recorded in `docs/testing.md`. | codebase-derived |
| D-12 | the attended drive-mode's round budget | The operator is the bound. `orchestrate-lean.sh`'s `--max-rounds` and `--max-continuations` are in-memory counters, and a stateless single-step driver cannot carry them without inventing a state file. The gate's own `rc=4` still hard-stops. Stated as a limitation of the instrument rather than papered over — it is a spike, and the campaign measures it as one. | codebase-derived |

**Provenance note for `D-1`..`D-7`.** All seven come from the operator's own words in this session
on 2026-08-23: the sequencing-and-boundaries message that opened the run (`D-1`..`D-5`, `D-7`) and
the ruling answering this session's blocking question about variant `c` (`D-6`). They are recorded
here rather than inferred silently, so a reviewer can repudiate them.

## Verification

```
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh
```
