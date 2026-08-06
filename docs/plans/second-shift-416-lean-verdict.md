# lean review verdict — #416

verdict=needs-work
run_id: review-416-1
session_id: b1fea4be-385c-4317-9b2b-679b7c56e37d
rounds: 1
pr: #422
reviewed_head: a072882090233983608359dc847795a8920c53cb
reviewed_patch_id: 479246a9ee21e922172224cc1f940f9a98393ece
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1, full branch diff (`a2b158f..HEAD`, 14 files, +601/-25) — `bash G delta 416` printed the
FULL range with nothing to inherit. Panel: security, performance, maintainability, complexity,
test-coverage, scope-completeness (all six returned; all six `approve`, one nit at confidence 70).
Every blocker below is my own cross-cutting finding, reproduced locally, not a panel relay.

Design fidelity: **not-applicable** — the spec declares no `## Design` section and this repo
configures no `design.provider`, so step 5b does not arm.

## Verdict: needs-work — 3 blockers

### B1 — `cmd_entry`'s new `ensure_progress_file` freezes `run_id: unset` into the progress header, reverting #322 and false-reding `lean-reconcile.sh` arm (1)

`cmd_entry` now calls `ensure_progress_file` before appending the AC-1 row. `ensure_progress_file`
writes the header — including `run_id: $RESOLVED_RUN_ID` — **only at creation**, and nothing in
`lean-gate.sh` ever rewrites it (`run_id:` is emitted at `lean-gate.sh:627` for the header, and at
`:828`/`:1999` for unrelated records).

`run-lean/SKILL.md` step 1 is `bash G entry <issue>`; the instruction to export `RUN_ID` lives in
**step 2**. An operator following the checklist in order therefore runs `entry` with no `RUN_ID`
in the environment, and the header freezes at `unset` for the life of the run.

Reproduced end to end on a scratch fixture:

```
### STEP 1: `bash G entry 99` exactly as SKILL.md step 1 orders it — NO RUN_ID exported
    [lean-gate] ✓ entry: audit ledger live (1 lines).
    [lean-gate]   entry attestation recorded in .../prog.md.
### header after step 1:
    run_id: unset
### STEP 2: operator exports RUN_ID and continues
### header after the real RUN_ID was exported:
    run_id: unset
```

This is exactly the defect closed by **#322** — `CHANGELOG.md:543`: *"run-lean's `entry` step no
longer creates the progress file — milestone 1 does, after `claim` has cached RUN_ID, so the
header's run_id field no longer freezes at 'unset' on a normal run."* Adding
`ensure_progress_file` back into `cmd_entry` undoes that fix.

The consequence is not cosmetic. `lean-reconcile.sh` arm (1) compares the bot claim comment's
`run_id` against the progress file's (`lean-reconcile.sh:280-285`):

```
  elif [ "$RUN_CLAIM" = "$RUN_PROGRESS" ]; then
    ok "build run_id consistent across the claim comment and the progress file ($RUN_CLAIM)"
  else
    bad "build run_id mismatch — claim='$RUN_CLAIM' progress='$RUN_PROGRESS'. These must be one run."
```

With the header at `unset` and the claim comment carrying the real id, that arm reds — a hard
`do NOT merge` on an honest github run, produced by the same diff that adds a new arm to the same
script.

**The branch's own fixtures paper over it.** `attest_at`'s signature is
`attest_at <tree> <config> <progress-file> <issue> [run-id]` with `RUN_ID="${5:-}"`, and its
comment says a case *"whose header must carry a particular run id passes it here rather than
letting the header stamp `unset`"*. The jira claim case at `lean-gate-selftest.sh:1409` passes
`jira-run-1` for precisely that reason. The suite absorbed the symptom as a fixture parameter
instead of surfacing it as a production regression.

Not triggered on this PR's own build run (`416-lean-progress.md` reads `run_id: lean-416-a`)
because that session exported `RUN_ID` before `entry` — which is why the suite stayed green and
why nothing here is evidence the trap is absent.

Before this diff, running `entry` without `RUN_ID` was harmless; `entry` created nothing. The diff
converts benign ordering latitude into a run-poisoning trap on a step it simultaneously makes
mandatory-first. #322 chose the structural fix (`entry` does not create the file) over a doc fix;
whichever route this takes, moving the export instruction into step 1 alone leaves the trap armed
for anyone who forgets.

### B2 — the new `doctor.sh` FAIL cannot see `.claude/settings.json`, so AC-5's condition does not hold for the file onboard writes

AC-5 by its letter: *"`doctor.sh`'s opt-out scan FAILs (`bad`, exit-code-affecting) when
`audit-toolkit` is disabled **and** `dev-pipeline` is enabled."* The condition is unqualified by
file. The scan loop it lands in (`doctor.sh:283`) iterates `"$LOCAL_SETTINGS" "$USER_SETTINGS"`
only — `$SETTINGS` (`.claude/settings.json`) is read for the new `DP_ENABLED` predicate but never
for the opt-out itself.

Proven pair, same fixture, only the file moved:

```
# audit-toolkit:false in .claude/settings.local.json
[doctor] FAIL  audit-toolkit disabled in settings.local.json while dev-pipeline is enabled — ...
[doctor] summary: 1 failed check(s)

# audit-toolkit:false in .claude/settings.json  (dev-pipeline:true in the same file)
[doctor] OK    audit-toolkit @ 2.0.0 installed
[doctor] summary: 0 failed check(s)
```

Silent — not even the pre-existing `warn`. And `.claude/settings.json` is the file onboard writes
the bundle into, so it is the *primary* place a hand edit lands.

The diff disagrees with itself here: `lean-gate.sh`'s new `audit_toolkit_opted_out()` reads
`.claude/settings.json` **and** `settings.local.json` across both roots. One half of the PR treats
that file as a legitimate home for the flag; the other half cannot see it.

Three shipped statements assert the behavior that does not hold:

- `plugins/second-shift/skills/onboard/SKILL.md` — *"a later hand edit flipping it to `false` …
  `/second-shift:doctor` FAILs on the combination rather than warning"*, immediately followed by
  *"If the existing file already carries that `false`…"* — squarely about `.claude/settings.json`.
- `docs/onboarding.md` — *"`/second-shift:doctor` FAILs on the pairing rather than warning"*,
  unqualified.
- The `Changelog:` trailer on `8e9a7af`, which ships as a release bullet:
  *"`/second-shift:doctor` now FAILs (not warns) when `audit-toolkit` is disabled while
  `dev-pipeline` is enabled."*

Either extend the scan to `$SETTINGS` or narrow all three statements — but a doc telling an
operator that doctor catches a misconfiguration doctor cannot see is the trust-without-observability
shape #416 exists to close. Mitigating, and why this is second rather than first: the lane itself
is still protected — `entry`'s ledger predicate fails closed regardless of where the flag lives,
with the specific `audit-toolkit` wording.

### B3 — the new arm makes three arm-count statements false, in the class the immediately preceding commit fixed

`lean-reconcile.sh`'s header enumeration grew from **6 items to 7** (`# ---- (N)` markers 5 → 6).
Three prose sites that count or enumerate those arms are unchanged:

| site | text | why it is now false |
| --- | --- | --- |
| `lean-reconcile.sh:123` | "Checks (1b) and (2)-(6) read git, the progress file, …" | byte-identical to the base; the new arm is adapter-insensitive, so the range extends by one |
| `tracker/README.md:55` | "six arms" · "**five of six.** … (1b) and (2)–(6) run unchanged" | total rose by one, and so did the jira-surviving count |
| `tracker/README.md:61` | "keeps five of its six arms" | same |

Because AC-4 makes the arm run *"under both tracker adapters"* — and the diff's own comment says
**"ADAPTER-INSENSITIVE … it runs in full under jira"** — both the numerator and the denominator
move. Whichever numbering those sites key to, neither number is right any more.

The README understates jira coverage for exactly the new arm, and jira is the tracker of the two
runs that motivated #416. `git log` on that file: `a2b158f` *"tracker README's lean-lane branch-site
counts are stale for both scripts (#414)"* — the branch's own base commit — and `a74af10`
*"tracker README counts the lean lane's operations correctly (#407)"* before it. Two of the last
three commits touching this file corrected these same sentences.

No AC covers it: AC-12's list of doc sites is closed and does not include the tracker README, and
`lean-reconcile.sh:123` is a different comment block from the "header enumeration" AC-12 names. So
AC-12 is satisfied by its letter and this lands here or nowhere. CLAUDE.md's rule — *"a change that
makes docs stale needs an explicit doc `AC-n`"* — points at the gap in the AC set, not at the prose.

## Warnings

**W1 — `delta`'s exit 2 conflates "the build never attested" with "this checkout does not share the
build's `MAIN_ROOT`".** `PROGRESS_FILE` resolves to `$MAIN_ROOT/.claude/pipeline-state/…`
(`lean-gate.sh:302`) and that path is gitignored (`.gitignore:7`), so it never travels with the
branch. `review-lean` step 3 says *"any checkout of that branch works"*; from a clone that is not a
worktree of the build host, `delta` now exits 2 on a perfectly attested run, and the new step-4
text tells the reviewer *"this means the BUILD run never recorded its entry attestation: stop and
hand it back"* — with a remedy the build side cannot apply, since `entry` there is idempotent and
reports the row already present. AC-3 models only the unattested cause. Not a blocker: every
review in this repo's topology runs from the sibling worktree that shares `MAIN_ROOT`, which step 3
names as "the usual place", and AC-3 delivers exactly what it specifies. Worth a diagnostic that
distinguishes the two causes, or a step-4 sentence that admits the second.

**W2 — the PR title carries no conventional-commit type, so this `feat:` ships as a patch.**
`derive-release.sh:147` tests `^feat(\([^)]*\))?:` against each commit's **subject**, and a squash
subject is the PR title — here *"the lean entry gate's ledger precondition is unenforced"*. The
`BREAKING CHANGE:` path reads the body (`:145`), but `feat` does not. Pre-existing and repo-wide
(verified previously on #383, which carried a `feat(dev-pipeline):` commit under a plain-English
title and released as a patch), and dispositioned warning-class on the #404 record — restated only
because this is a new-capability PR where the downgrade actually bites. Retitling is the one-line
remedy, but it collides with the lean lane's issue-title convention, so it is the author's call,
not a review amendment.

**W3 — `(ea7)` asserts a missing string, not an exit code.** `if ! printf '%s' "$out" | grep -qF
'no entry attestation'` passes for any `verdict` failure whose message differs. The comment says
*"Anything other than 2 proves the precondition let it through"* — but rc is never read. Pinning
`rc != 2` alongside would make the exemption case fail for the right reason.

**W4 — settings-precedence logic now exists twice** (maintainability-reviewer, confidence 70).
`doctor.sh`'s `dp_true`/`dp_false`/`DP_ENABLED` block and `lean-gate.sh`'s `audit_toolkit_opted_out()`
independently re-implement "scan the settings files for an `enabledPlugins` key with
local-overrides-main precedence", in the same PR, with different shapes. Both are correct for their
own need; the divergence in *which files* each reads is B2. A third consumer would be the point to
extract a helper.

## Acceptance criteria

| AC | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | `cmd_entry` appends one row carrying `ledger=`/`lines=`/`session=`, guarded by `entry_row_present`; shape pinned in the primitives comment block at `:610`. `(ea1)`/`(ea2)`. |
| AC-2 | satisfied | `audit_toolkit_opted_out()` picks the wording; the ledger predicate still decides. `(ea8)`/`(ea9)`/`(ea10)` — including the direction proving the settings read never became a second authority. |
| AC-3 | satisfied | `require_entry_attested` at the dispatch, before the `case`; exit 2, remedy string, no `attempt` line; `entry` and `verdict` exempt. `(ea3)`/`(ea5)`/`(ea6)`/`(ea7)`. |
| AC-4 | satisfied | Arm (6) at `lean-reconcile.sh:462`, presence-only, no adapter branch. |
| AC-5 | **unsatisfied** | See **B2**: the scan loop never reads `.claude/settings.json`, so the AC's stated condition does not hold for the file onboard writes. Proven pair above. |
| AC-6 | satisfied | Onboard step 2 states the lane requirement; step 6 states the hand-edit risk. The false doctor clause inside it is carried under B2 rather than scored here — the AC's letter is the lane-breaking claim, and that is true. |
| AC-7 | satisfied | `(ea1)`–`(ea4)`: row, idempotency, refusal + remedy + exit 2 + zero attempts, and the D-13 milestone-4 backstop paired red/green. |
| AC-8 | satisfied | Every lean leg acquires its row by calling the gate (`lean_seed_progress` → `lean_gate entry`); `(lean-entry)` composes the refusal at `all` **and** a single milestone with the fix budget untouched; `LEAN_SID`/`EL_SID`/`LEAN_DSID` pin the session id so the ambient one cannot leak. |
| AC-9 | satisfied | `(Q)`'s pair reds without the row and greens with it, everything else held at the consistent-run state. |
| AC-10 | satisfied | `opt-out` re-keyed to exit 1 + "while dev-pipeline is enabled"; new `opt-out-lane-off` pins the surviving `warn`. |
| AC-11 | satisfied | All four catalog mutants independently re-applied with `sed -E` (the sweep's own flavor) against a pristine copy and their paired suites run: `lean-gate-entry-row` **killed** (143 failures), `lean-gate-entry-precondition` **killed** (rc 4), `lean-reconcile-entry-arm` **killed** (rc 1), `doctor-audit-toolkit-lane` **killed** (rc 1). No baseline re-key owed — see the note below. |
| AC-12 | satisfied by its letter | The three named sites are accurate: `run-lean/SKILL.md` step 1, `lean-gate.sh`'s usage header + exit-code table (`2` now names the precondition), `lean-reconcile.sh`'s header enumeration (item 7). The `Changelog:` trailer states the no-grandfather-window rollout. B3 sits outside this AC's closed list. |

## Verification I ran

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh`: **rc 0**.
- `jq empty` over every `*.json`: **rc 0**.
- Full selftest sweep, all **63** suites, `-P 4`, **without** `SKIP_STRESS` and with
  `env -u CLAUDE_CODE_SESSION_ID`: **rc 0**, no `FAIL:` line. (`xargs` propagates non-zero under
  `-P`, so rc 0 is the whole-sweep claim.)
- `check-frozen-files.sh a2b158f`: clean. `check-changelog-trailer.sh a2b158f`: OK.
- `prose-budget.sh`: **19 FAILs on the branch, 19 at the base**, and both files this PR touches
  were already failing at `a2b158f` (`run-lean/SKILL.md` 972→1010 against a 575 baseline;
  `onboard/SKILL.md` 3187→3318 against 2740). The PR body's claim reproduces.
- **Mutation-ordinal re-key**: diffed the first `k=2` matching lines of all six
  `tools/mutation-operators.tsv` regexes across the three edited guards, base vs branch. Fifteen of
  eighteen are byte-identical. The three apparent moves are all the *same construct* with edited
  content — `cmp-z` ordinal 1 on `lean-gate.sh` and `lean-reconcile.sh` is the
  `-h|--help) sed -n '2,Np'` line whose range legitimately grew (`2,128p`→`2,132p`,
  `2,77p`→`2,81p`). Neither guard carries a `cmp-z` baseline row, so nothing is owed. The PR body's
  "UNMOVED for all six operators on all three guards" holds under the site-identity reading, which
  is the correct one.
- **CI could not be read**: `gh pr checks 422` reports *"no checks reported on the
  'lean/second-shift-416' branch"* — zero check runs were ever created, matching the
  account-level GitHub Actions runner outage seen on this repo today. Everything above is local
  evidence only; no lane on this PR has been observed green in CI.

## Strengths

- The `attest_at` helper drives the **real** `entry` rather than echoing the row, across all six
  fixture trees. That is the difference between a guard and a decoration, and it is what makes
  B1's fixture accommodation visible in the diff at all.
- `(ea10)` tests the direction that matters most for AC-2 — a live ledger passing *despite*
  `audit-toolkit: false` in settings — which is the exact way a "check the plugin instead"
  implementation would have gone wrong and false-red every honest run.
- `(Q)` and `(lean-entry)` are both true pairs: everything else is held at the fully-consistent
  state so the row is the only variable. `(lean-entry)` additionally asserts the fix budget is
  untouched, which is the half of AC-3 a rc-only check would miss.
- Placing the precondition at the dispatch rather than inside each `cmd_*` closes every
  start-at-milestone-N path in one site, including `all`'s cheap pre-pass — and the
  `lean-gate-entry-precondition` catalog row models precisely the narrowing that would reopen them.
- The rejected shapes (D-2, D-3, D-5) are recorded in the spec with their reasons, so the
  independence from #417 is auditable rather than asserted.
