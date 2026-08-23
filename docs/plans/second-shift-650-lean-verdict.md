# lean review verdict — #650

verdict=approve
run_id: review-650-1
session_id: afeaada0-0582-4ed9-be48-d802c82074d9
rounds: 1
pr: #653
reviewed_head: df2262214e61016ecfd0f178cf65e284ed71e653
reviewed_patch_id: 6a2baf325ab87b2b51bd9339e85f618a5484ba59
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Round 1 — PR #653 (#650): approve

Range read: `4813e0b..df22622` — the whole branch diff (round 1, nothing to inherit).
Panel: six reviewers selected, five returned, one dark. Reviewed from the lane worktree at
`df22622`, verified unmoved against `origin/claude/second-shift-650` immediately before this record.

## Verdict

**approve.** No blockers. Every numbered `AC-n` is satisfied or departed-by-ledger; the two
departures are recorded as `D-4`/`D-5`, operator-attested at launch, and their remainder is filed
and linked as **#652** (OPEN, `needs-spec-work`), which is what `AC-8` requires.

## Per-AC scoring

| AC | score | evidence |
| --- | --- | --- |
| AC-1 per-launch spawn evidence | **satisfied** | `orchestrate-lean.sh:695` keys the transcript on `$LAUNCH_ID` as well as `$SPAWN_N`; ledger at `:460`, rows from `launch_note` (`:288`). First implementation commit is `7e2aa76`, ahead of every other scope item (`D-1`). Cases `(z1)`–`(z5)`, `(z1)` scored on **bytes** so truncation cannot pass it, `(z2)` the anti-vacuity that the two launches address two files. `D-8`'s flat-glob claim verified: `retro-corpus.sh:391` reads `"$dir/$tk"-lean-spawn-*.log` and tests existence only — no positional parse of the ordinal or role — so the stamp is transparent to the shipped reader. |
| AC-2 mid-run staleness re-check | **satisfied** | `require_ticket_still_open` (`lean-gate.sh:2581`) on the `mark` dispatch arm (`:5403`); exit 7 on CLOSED, exit 2 fail-closed on unreadable. Exemption verified at the source, not from prose: `cmd_5` (`:4835`) and `cmd_close_out` (`:4804`) call `cmd_mark` as a function and never traverse the dispatch. `(tl1)`–`(tl4)` green in my own run, `(tl2)` the OPEN anti-vacuity. |
| AC-3 revision 5 appended | **satisfied** | `81` insertions, **`0` deletions** on `second-shift-643-preregistration.md` — appended, prior text standing, mechanically. Both parts present, and the direction note states it favours arm B. `R5-1a` re-derived independently at `4813e0b`: `spawn` is called at `:762`, `:763` (both `--dry-run` preview), `:800` BUILD, `:929` REVIEW — two real sites, both model payloads; and `:173–174` of that same file already records that #590 deleted the close-out spawn. The emptiness finding holds. |
| AC-4 variant `c` as an instrument | **satisfied** | The `--attended` branch (`:894`) returns before the round loop; `attended_handoff` prints and calls `terminal … 9` — there is no `claude -p` on the path. Every predicate is a direct gate call (`staleness_rc`, `resolve_pr`, `inflight_rc`, `verdict_rc`, `closeout_rc`), and the verdict rc is the router with the same taxonomy the loop uses. `(aa1)`–`(aa8)`, and `(aa2)` is the load-bearing half: the same fixture without the flag still spawns. `D-12`'s lost round budget is stated in the header rather than discovered. |
| AC-5 evidence file committed empty | **satisfied** | `docs/plans/second-shift-650-campaign.md`: columns fixed pre-run, all nine rows `—`, rubric by reference only, and the scoring block carries an explicit "do not fill this in before all nine rows exist". |
| AC-6 the nine runs | **departed** (`D-4`) | Not run and not simulated here. Operator-attested at launch; remainder in #652. |
| AC-7 arm execution | **departed** (`D-5`) | No arm selected or executed anywhere in the diff. Confirmed by reading the campaign file's scoring table — every cell `—`. |
| AC-8 the follow-up is filed and linked | **satisfied** | **#652** OPEN, `needs-spec-work`, linked from the PR body's departure table and from the spec header. The label choice is ratified by the operator. |
| AC-9 sweep + shellcheck | **satisfied** | `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh`: **rc=0, no output**. Both touched suites run by me from this checkout: `orchestrate-lean-selftest.sh` all green, `lean-gate-selftest.sh` all green. `prose-blockers-selftest.sh` **56 passed, 0 failed** — the red the build disclosed is discharged by the re-key, not merely described. |
| AC-10 trailers | **satisfied** | `Changelog:` on all nine commits; `Guard-mass:` on the two guard-adding commits; `check-guard-budget.sh origin/main` → `base 50282, HEAD 50543 (delta +261), covered`. See W1 for the stated figure. |
| AC-11 doc AC | **satisfied** | `run-lean/SKILL.md` documents `--attended` and exit `9`, at **59 lines** — inside the 60-line cap. `docs/testing.md` carries the `D-11` declined coupling under *Unanchorable*. Help ranges checked for leakage: `sed -n '2,302p'` ends one line before `set -uo pipefail` in the gate, `2,236p` likewise in the scheduler. |

Fidelity: **not-applicable** — the spec has no `## Design` section, so step 5b is not armed.

## What I verified rather than accepted

Three claims the PR asks a reviewer to push on, checked against the code and not against either
the build's or the operator's account of it:

1. **`D-10`'s correction to the ticket body.** The issue said "`lean-gate.sh:2502` … nothing calls
   it". At `4813e0b` that refusal **is** reached: `staleness_ticket_arm` returns 7 at `:2502`, via
   `cmd_staleness`, from `probe_ticket` (`orchestrate-lean.sh:500`) and from `staleness_rc` in the
   loop body (`:780`). The corrected statement — nothing asks *after `entry`* whether the ticket is
   still open — is the accurate one. The build corrected a factual claim about code against the
   code; that is not scope license, and it read the defect correctly.
2. **The bash-3.2 fix is real and correct.** Reproduced on `/bin/bash` 3.2.57: `printf "%s " "${a[@]}"`
   on an empty array under `set -u` dies with `a[@]: unbound variable`, while the shipped form
   `${ORIG_ARGV[@]+"${ORIG_ARGV[@]}"}` survives and round-trips a populated array. This is a defect
   no sweep on a bash-5 host could have surfaced, and it was found and fixed before CI.
3. **`(tl4)` is falsifiable.** It is scored on a refusal's *absence*, which is the weak shape — but
   the disclosed probe (widen the arm to `mark|5|close-out`) reds it while `(tl1)` still passes, and
   `(tl2)`/`(tl3)` bound the other two states. The exemption is guarded, not merely asserted.

## Findings

### Warnings (not blocking)

**W1 — commit `2144162`'s `Guard-mass:` trailer states a figure that is wrong, and mis-states its
own scope.** It reads "+49 lines across `lean-gate.sh` and its selftest"; `git show --numstat`
gives `50` on the selftest and `57/-3` on the gate — so it counts one of the two files it names,
and undercounts the branch by roughly 5x (+261 measured). **Not a blocker, for a checkable reason
rather than a lenient one**: `check-guard-budget.sh` measures both sides itself and, at `:83`,
only greps for the trailer's *presence* — its header says outright it "does not parse or validate
the stated delta/reason". So no gate is fed the wrong number, and the corrected +261 is in the PR
body, which becomes the squash commit message. Amending the landed trailer would require rewriting
the branch and re-stamping this record; that trade is not worth it. Disclosed by the build rather
than found here, which is the right disposition for a defect it could not cleanly fix.

**W2 — #650's issue body still presents scope items 2 and 3 as in-scope, with no deferral sentence
and no pointer to #652.** The body was edited by the operator on 2026-08-23 (`updatedAt`
`15:37:11Z` ≠ `createdAt`), so it is not a stale-by-neglect case. The departure is recorded in the
committed spec (`AC-6`/`AC-7`, `D-4`/`D-5`) and in the PR body, and `AC-8` binds *this PR* to file
and link the remainder — which it does — so the lane's definition of done is met and this does not
block. It is recorded because a reader arriving at #650 after the merge sees a ticket whose scope
list is two items larger than what shipped. The remedy is an issue-body edit, which is
human-authority work and the operator's to make.

### Suggestions

**S1 — the printed resume command loses argument quoting.** `attended_handoff` builds it as
`$0 $(printf '%s ' ${ORIG_ARGV[@]+"${ORIG_ARGV[@]}"})`; elements survive as separate words to
`printf`, but an argument containing whitespace would print a line that does not round-trip when
pasted. Unreachable with the current flag set — an issue number, model names, integers — and
nothing is executed from it, so this is display fidelity only. Raised by the security reviewer at
confidence 55 and suppressed there; I agree with the suppression and record it for the campaign,
since a resume line an operator retypes is exactly what arm (c) is being measured on.

### Coverage

**`test-coverage-reviewer` went dark** (died-after-retry; turn-budget, no text emitted on either
attempt). Its domain is not silently green. I read every new assertion directly instead: all three
anti-vacuity pairs are present and correctly oriented (`(z2)`, `(aa2)`, `(tl2)`), `(z1)` is scored
on bytes rather than existence, and each of the build's three disclosed mutation probes falsifies
the case it is paired with. That is my own reading, not a substitute for the reviewer's, and the
merge decision should be read as made without that dimension's independent pass.

**`a11y-reviewer` and the design-fidelity dimension were not routed** — no changed path matches
`stageParams.webComponentGlobs` (unset; resolved default `apps/web/**/*.{tsx,jsx}`). A shell and
docs diff; not a coverage gap.

**The scope gate returned degraded output and I resolved it rather than relayed it.**
`scope-completeness-reviewer` enumerated #650's five scope items correctly but classified none of
them — all five findings read verbatim "Not yet confirmed in diff within budget", which is an
admission of non-completion, not a scope finding. Resolved against the diff and the committed spec,
per item: **scope 1** → `AC-4`, the `--attended` block at `:857–981`; **scope 4** → `AC-1`, the
launch token at `:695` and ledger at `:460`; **scope 5** → `AC-2`, the guard at `lean-gate.sh:2581`
and `:5403`. All three are covered by the diff and I cite the lines above. **Scope 2 and 3** are
`AC-6`/`AC-7`, departed under `D-4`/`D-5` with the remainder filed and linked as #652. The one place
the gate's own standard is genuinely unmet — the *issue body* carrying the deferral — is W2, and it
is recorded as such rather than dismissed.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Degraded (no classification returned) — resolved in-session | 0 usable | — |
| Security | Pass | 0 | 3 suppressed (40–55) |
| Performance | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Complexity | Pass | 0 | 1 suppressed (55) |
| Test Coverage | **Dark (no output)** | — | — |

## Strengths

- **The instrument does not perturb the arm it measures, and that is asserted rather than
  asserted-about.** `(aa2)` runs the same fixture without the flag and requires a spawn. A campaign
  whose variant-(c) implementation quietly changed arm (a) would have produced nine unusable rows.
- **`(z1)` is scored on bytes.** The regression it guards leaves the file in place and empty, so the
  obvious `-f` test passes on the broken tool. Getting that right is the difference between a case
  that catches the defect and one that documents it.
- **Two defects were reported rather than quietly fixed** — the re-keyed prose-blocker disposition
  the gate's slow-suite deferral hid, and the understated guard-mass trailer. The second is against
  the build's own interest to disclose.
- **The emptiness finding was raised as a blocking question and stopped on**, against a frozen
  criterion the session was instructed it could not amend. The revision landed on a ruling, appended
  with zero deletions and a direction note. That is the pre-registration working as designed rather
  than being worked around.
