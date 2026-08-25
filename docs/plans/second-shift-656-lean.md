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
lands somewhere — and, since the note it lands on refutes the clause citing it, that header's own
false premise is corrected here too (AC-7). A comment edit on a file no guard predicate matches; it
is the third file this branch touches, and the only one outside the two named above.

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
- **AC-7** (critic) — `tools/reap-lean-fixtures.sh`'s header no longer contradicts the note it
  cites: it describes where its `-t` fixtures actually resolve and why its `${TMPDIR:-/tmp}`
  default reaches them. Header comment only — the file matches no arm of
  `check-guard-budget.sh`'s predicate, so AC-3 stays green.

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
| D-6 | Is the enumeration command safe to publish? | Yes — it is `ls -d`, read-only, and it is paired with a `stat`-before-delete caution because the same shared directory holds a concurrent lane's live fixtures. Verified on the lane machine 2026-08-25, and the enumeration returns a real match (a vendor's, with no plugin marker beside it — the harmless case the prose names). The `TMPDIR` half of this row originally cited `TMPDIR=/tmp/x mktemp -u -d`, which is **vacuous** — `/tmp/x` does not exist, so the `/var/folders/…` answer cannot distinguish "ignored `TMPDIR`" from "fell back because the directory was missing". D-9 replaces it with the form that can. | codebase-derived |
| D-7 | Guard mass and the `Guard-mass:` trailer | The diff is markdown only. `check-guard-budget.sh` measures `.sh` files matching its guard predicate, so the delta is zero and no trailer is owed. AC-3 asserts it rather than assuming it. | codebase-derived |
| D-8 | The scrub is partly automated already — does the runbook say so? | Yes, first. `run-selftests.sh` invokes `tools/reap-lean-fixtures.sh` over `$TMPDIR` before discovery, and it is ownership-checked (pid + process start time stamped into a `mktemp -t` template, "could not tell" resolving toward keeping). A runbook that sent a reader hand-deleting from a shared directory without saying that would be advising a riskier action than the tooling already takes safely. The ticket's own words are "routing prose to the pattern that already exists"; this is that pattern. | codebase-derived |
| D-9 | Round 1 blocker: does the killed-sweep note's "the `-t` form does honor `TMPDIR`" survive measurement? | **No — it is false, and the note now says the opposite.** With `TMPDIR` set to a directory that EXISTS, `mktemp -u -d`, `-u -d -t stamp` and `-u -t stamp` all resolve under `_CS_DARWIN_USER_TEMP_DIR`; the `-p <dir>` control resolves where it is told, so the negative results are a result and not a harness artifact. `mktemp(1)` gives the mechanism: `-t` resolves against that confstr and reaches `TMPDIR` only as a fallback when it is unavailable, and a bare `mktemp -d` *is* `-t tmp` — so there is no second behavior for the parenthetical to be about. The runbook carries the `-u` derivation, and names the vacuous form so it is not repeated. The conclusion drawn from it in round 2 was too wide — see D-10. | codebase-derived |
| D-10 | Round 2 blocker: does "no `mktemp` form puts that litter where `TMPDIR` points" hold? | **No — it is true of the two forms measured and false of the one that was not.** D-9's three spellings (`-u -d`, `-u -d -t stamp`, `-u -t stamp`) are one behavior, since `mktemp(1)` makes bare `-d` an alias for `-t tmp`; the untested fourth is the **explicit template** `mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX"`, where the shell expands the path before `mktemp` runs, so `TMPDIR` is honored unconditionally — and falls back to `/tmp`, not to the confstr dir, when unset. `grep -rl 'TMPDIR:-/tmp}/' --include='*.sh' .` finds 14 files mentioning it, 12 of which call it (D-12), including `run-selftests.sh`'s own `BASE` — a sibling of the stamped fixture dirs, cleaned by the `trap … EXIT` a killed sweep skips. Both surfaces are rescoped to the two families rather than to "any form", and the derivation block now enumerates the FORMS, not spellings of one. Measured 2026-08-25. | codebase-derived |
| D-11 | Round 2 blocker: `reap-lean-fixtures.sh`'s header cites the note it now contradicts — in scope? | Yes, and it is why AC-7 exists. Round 1 spared it as a file the PR did not touch, on the reasoning that the two surfaces agreed; round 2 inverted the cited authority, so the contradiction became this branch's. The header's own claim ("BSD `mktemp -t` DOES honor TMPDIR, unlike its no-template form") is false in both halves by this PR's measurement, and it heads the live guard the runbook routes readers to. `check-guard-budget.sh`'s predicate is `*-selftest.sh` / `check-*.sh` / `*-lint.sh` / `*/skills/*/lean-gate.sh` plus `run-selftests.sh`, `mutation-sweep.sh`, `gate-ablation.sh`; `reap-lean-fixtures.sh` matches none, so a header edit moves zero guard mass and AC-3 is no argument against it. | codebase-derived |
| D-12 | Round 3 blocker: is `run-selftests.sh`'s `BASE` the parent of every suite's scratch, and is 14 the number of files calling the explicit-template form? | **Neither.** The worker branch (`tools/run-selftests.sh:127-170`) runs each suite from the repo root with `TMPDIR` inherited untouched and captures only its `log`/`rc`/`secs` under `BASE`, so a suite's own `mktemp` dir is a SIBLING of `BASE`, not a child — which is also why moving `TMPDIR` cannot move the stamped families, as the same paragraph already said four lines below. The size superlative beside it ("the single largest thing a killed run strands") is dropped rather than re-derived: nothing measured it, and the paragraph's point — that the honored form is widely used — does not rest on it. The count is 14 files *mentioning* the form and **12** *calling* it at 16 sites: `tools/mutation-sweep.sh:1359` and `plugins/intake-toolkit/hooks/exitplan-ledger-gate-selftest.sh:121` match on a comment while both allocate with `-t`, i.e. on the ignored side of this very split. The 14 originated in the round-2 review record's own B-1 and was adopted here rather than derived; re-derived 2026-08-25 by reading all 18 matched lines. D-10 inherited both errors and is corrected in place. | codebase-derived |
| D-13 | Round 3 warning: the reap header cites CLAUDE.md's note "for the derivation", and that note forwards one hop further. | Fixed in the same header — the file is already in scope under AC-7 and this is a citation target, not a new claim: the comment now names `docs/testing.md#when-a-run-is-killed-mid-sweep` directly. Same line count, so `--help` (`sed -n '2,55p'`) still stops before `set -uo pipefail` and `reap-lean-fixtures-selftest.sh`'s header case is unaffected. Guard mass unmoved for the reason D-11 gives. | codebase-derived |
