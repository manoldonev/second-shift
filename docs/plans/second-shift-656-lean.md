# #656 — long verification commands die at the foreground cap before anyone backgrounds them

Operator-directed, 2026-08-24, from the #647 arm-b campaign run's observed friction: a build
session started the (long) lean-gate selftest as a foreground call, lost it to the harness cap, and
only then re-ran it backgrounded.

## Problem, restated in one line

The recipe a build session is told to run takes minutes, the surface that tells it to run it says
nothing about how, and the default — a foreground `Bash` call — is the one shape that cannot
finish.

## What this slice is

**Routing prose, in the surface a build session already loads.** No gate, no script, no new
mechanism: the pattern that works exists and is measured, and what is missing is a reader of
`## Verification` being told about it before they run the command underneath it.

Two sites, split by role rather than duplicated:

- **`CLAUDE.md`, `## Verification`** — the operative rule, immediately under the recipe fence. It is
  loaded automatically in every session in this repo, which is what makes it the surface AC-1 names.
- **`docs/testing.md`, `## How the sweep runs`** — the killed-attempt runbook the rule routes to:
  the mechanism, what `tools/reap-lean-fixtures.sh` already clears on the sweep's way in, the
  read-only enumeration for what it does not, and the check to make before deleting anything.

Neither site restates the other. The repo's own rule is that two copies of one contract are held
together by a `LOCKSTEP-BEGIN` anchor; the way to owe no anchor is to write no second copy, so the
rule points at the runbook rather than inlining it.

The `CLAUDE.md` half also resolves a cross-reference that is currently dangling:
`tools/reap-lean-fixtures.sh`'s header cites "CLAUDE.md's killed-sweep note" for the `mktemp -t`
vs no-template `TMPDIR` distinction, and no such note exists. The rule carries it, so the pointer
lands somewhere.

## What is deliberately NOT in scope

- **`lean-gate.sh 3` is not a candidate for backgrounding.** Milestone 3 runs the sweep inline,
  bounded by `tools/selftest-suite-timings.tsv` to fit the turn, precisely so a session cannot
  detach it and end the turn on top of it. The prose says so, so that "background long calls" is not
  read as a licence to unpick that.
- **No consumer-repo surface.** The ticket scopes to this repo's own `CLAUDE.md` / `docs/testing.md`.
- **No claim that a fixed defect is live.** The killed-attempt litter's one known victim —
  `check-emit-deadline-selftest.sh`'s live-scan refusal case — was structurally isolated by nesting
  its fixture root one level below its `mktemp` dir, and that isolation is asserted by its own
  neighboring case rather than assumed. The runbook is written against the mechanism, not against
  that case.

## Acceptance Criteria

- **AC-1** (oracle) — `CLAUDE.md`'s `## Verification` section carries the rule, naming all three of:
  the **2-minute foreground reap** (and that the `timeout` parameter does not lift it), the
  **background shape that survives** and is collected in the same turn, and the **scrub obligation**
  when a foreground attempt was already killed. It sits with the recipe, not behind a link.
- **AC-2** (oracle) — `docs/testing.md` carries the killed-attempt runbook: why `TMPDIR` cannot
  isolate the litter, what the sweep's own `tools/reap-lean-fixtures.sh` pass already clears before
  a reader touches anything by hand, a **read-only** enumeration command for what it does not reach,
  and the check to make before removing anything. The command is verified to run on the lane machine,
  and the prose says what a match with no plugin marker means.
- **AC-3** (critic) — **no new gate and no new script.** `bash scripts/check-guard-budget.sh
  origin/main` reports guard/test shell mass unchanged, so the branch owes no `Guard-mass:` trailer.
- **AC-4** (critic) — every measurement either carries a runnable derivation or the date it was
  measured, and no sentence asserts a currently-fixed defect as live. Specifically: the runbook does
  not name the emit-deadline live-scan case as a thing that still reds.
- **AC-5** (critic) — a `Changelog:` trailer on the branch (`none` if nothing consumer-visible).
- **AC-6** (oracle) — `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude
  tools/install-topology-selftest.sh` green at the branch head.

## Do not touch

`plugins/*/.claude-plugin/plugin.json` `version`, `CHANGELOG.md`,
`.claude-plugin/marketplace.json` `metadata.version` — release artifacts, derived at release time.

## Decision Ledger

No pre-flight `656-ledger.md` exists, so this table is the run's own. Every row is grounded in the
ticket text, in this tree, or in a measurement this run states the date of.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | AC-1 says "CLAUDE.md and/or `docs/testing.md`" — one site or two? | Two, split by role: the rule in `CLAUDE.md` (auto-loaded, so it is what "a build session actually loads" means), the runbook in `docs/testing.md`. Split rather than duplicated — `CLAUDE.md`'s own rule sends two copies of one contract to a `LOCKSTEP-BEGIN` anchor, and writing no second copy is how this owes no anchor. | codebase-derived |
| D-2 | What exactly is "the background pattern"? | `nohup <cmd> > <log> 2>&1` under the harness's `run_in_background`. A **bare** backgrounded command is not the pattern: it has been reaped at 2m on this repo's own lanes (#492 round 3, #583, #590), while the `nohup … > log` shape carried a ~6-minute 75-suite full sweep to a `summary:` line on the #661 lane, 2026-08-25. The prose states both, because "just background it" is the advice that has already failed here. | codebase-derived |
| D-3 | Does `timeout: 600000` deserve a mention? | Yes, as a refusal — it is the first thing a reader reaches for, and it does not work: a call requesting 600000ms was still SIGKILLed at exactly 2m 0s. Re-measured first-hand on this lane before the prose was written. | codebase-derived |
| D-4 | Does the guidance apply to `bash G 3`? | No, and the prose says so. Milestone 3 is inline **by design** since the slow-suite table replaced the detached-runner protocol; a reader who backgrounds it and ends the turn reproduces the failure class that design removed. An exception named is cheaper than a contradiction discovered. | codebase-derived |
| D-5 | The scrub's known victim was `check-emit-deadline-selftest.sh` case B6. Name it? | No. B6 stages its root at `<mktemp>/iso` rather than `<mktemp>`, which puts a concurrent suite's fixture outside its resolution glob, and its neighboring case stages a decoy at the collide depth to assert exactly that. Naming it would write a fixed defect into the docs as a live one. The runbook is written against the mechanism, and says the tell is a red the diff cannot explain. | codebase-derived |
| D-6 | Is the enumeration command safe to publish? | Yes — it is `ls -d`, read-only, and it is paired with a `stat`-before-delete caution because the same shared directory holds a concurrent lane's live fixtures. Verified on the lane machine: `TMPDIR=/tmp/x mktemp -u -d` still returns a `/var/folders/…/T/` path, and the enumeration returns a real match (a vendor's, with no plugin marker beside it — the harmless case the prose names). | codebase-derived |
| D-7 | Guard mass and the `Guard-mass:` trailer | The diff is markdown only. `check-guard-budget.sh` measures `.sh` files matching its guard predicate, so the delta is zero and no trailer is owed. AC-3 asserts it rather than assuming it. | codebase-derived |
| D-8 | The scrub is partly automated already — does the runbook say so? | Yes, first. `run-selftests.sh` invokes `tools/reap-lean-fixtures.sh` over `$TMPDIR` before discovery, and it is ownership-checked (pid + process start time stamped into a `mktemp -t` template, "could not tell" resolving toward keeping). A runbook that sent a reader hand-deleting from a shared directory without saying that would be advising a riskier action than the tooling already takes safely. The ticket's own words are "routing prose to the pattern that already exists"; this is that pattern. | codebase-derived |
