# lean review verdict — #476

verdict=needs-work
run_id: review-476-1
session_id: 3903c806-40a4-4c5a-9ce1-99d30e42aeac
rounds: 1
pr: #480
reviewed_head: 44dd073cc97a8574e04aa338aa16a01f070da8fe
reviewed_patch_id: 204b708a28370e25f684e02f29224f9565c66d33
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 — `review-476-1`. Verdict: **needs-work**. One blocker, found by CI after this round's
approve was written and superseding it.

## This supersedes an approve written earlier in the same round

Round 1 was first recorded as `approve` at head `ce20820`, then re-stamped at the merged head
`a435008` after `origin/main`'s `ci.yml` conflict was resolved. Both were written while **CI had
never dispatched on this branch** — the PR was `DIRTY` from an add/add conflict with `#475`, so
GitHub produced no `pull_request` run at all, and the approve rested entirely on gates executed
locally. The first CI run after the merge failed. That evidence lands inside round 1, on an
unmoved head and an unchanged patch, so it corrects this round rather than opening a new one.

The approve was wrong. The local sweep that backed it ran under Homebrew bash 5.3 and never
applied the PATH shim that defines the `selftests (macos, bash 3.2)` lane, so it could not have
reached the failure. The lane's existence was also missed: `declare -A` was checked against a
`mapfile` precedent in `scripts/check-lockstep-pairs.sh`, which runs in the ubuntu
`lint-and-selftests` job and establishes a bash-4 floor **only there**.

## Blocker

**B-1 — `tools/capability-parity-check.sh` is inert under bash 3.2, and fails OPEN.** The macOS
CI lane symlinks stock `/bin/bash` ahead on `PATH` so `#!/usr/bin/env bash` resolves to 3.2, and
runs the whole selftest set there. Under that interpreter the guard does not merely misbehave —
it reports success on a register it never judged:

```
tools/capability-parity-check.sh: line 59: declare: -A: invalid option   # SEEN_CAPABILITY
tools/capability-parity-check.sh: line 60: declare: -A: invalid option   # COVERED_PATH
tools/capability-parity-check.sh: line 93: claim: unbound variable
rc=0
```

Line 93 is `${SEEN_CAPABILITY[$capability]:-}`. With no associative array to key, bash 3.2
evaluates the subscript **arithmetically**, so the first capability name —
`queue pickup and atomic claim` — is parsed as identifiers, `claim` is unbound, `set -u` kills the
shell mid-loop, and the process exits **0**. Every per-row check after that point is unreachable.

The paired suite catches it exactly as designed — 10 of 17 cases fail in that lane, each with the
same signature (`did NOT red — rc=0`): (c), (d), (e), (f), (g), (h), (h2), (h3), (i), (l). The
seven that "pass" there pass **vacuously**: (a), (b), (e2), (k) and (m) all assert `rc=0` and get
it from a dead shell; (n) exits 2 before any array use; (j) reds only because a header-only
register never enters the loop body. So the lane reports 7 passed, and not one of those seven
observed the guard working.

This is a blocker rather than a warning on two independent counts. The CI lane is red, which is a
blocker outside the AC set. And it defeats AC-2 on its own terms: on the only lane where the guard
is exercised under the interpreter every shipped script claims to support, the `#348` deletion
gate silently passes anything.

**Remedy — verified, four sites.** I built the patched guard in a scratch tree and ran the real
paired suite against it under CI's own PATH shim: **17/17 under stock 3.2**, and the guard green
against the real 36-row register. The two associative arrays become newline-delimited
accumulators:

1. `declare -A SEEN_CAPABILITY=()` / `declare -A COVERED_PATH=()` → `SEEN_CAPABILITY=""` /
   `COVERED_PATH=""`.
2. Duplicate detection reads back with
   `prev_line="$(printf '%s' "$SEEN_CAPABILITY" | awk -F'\t' -v c="$capability" '$2 == c { print $1; exit }')"`
   and appends `"$LINENO_<TAB>$capability\n"`. A TAB is a safe delimiter here precisely because
   the row was already split on TABs, so no cell can contain one — and `awk` field equality is
   exact, so a capability that is a substring of another cannot false-match.
3. Coverage writes append `"$p\n"`.
4. Coverage reads become `printf '%s' "$COVERED_PATH" | grep -qxF -- "$rel"` — `-x` for
   whole-line, `-F` for literal, so a path containing regex metacharacters cannot mis-match.

Worth a sentence in the header saying why the accumulators are not associative arrays: the failure
mode is silent success, not a diagnosable error, so the next person to "simplify" this needs to
know what it costs.

## Acceptance criteria

| AC | Score | Note |
| --- | --- | --- |
| AC-2 | **unsatisfied** | The register half holds — 36 rows, every disposition in enum. The guard half does not: on the bash-3.2 lane the oracle exits 0 without judging anything, so a stage doc no row names does not red there. B-1. |
| AC-5 | **satisfied** | Unchanged from the approve, and independent of B-1 — this is a property of the TSV, not the guard. 36 rows = 4 seeded + 32 proposed (17 `already-covered` / 13 `dropped` / 2 `choreography`), matching the PR body name-for-name; the four seeded rows carry their settled dispositions; all ten stage docs plus the cross-stage section covered. Re-walked all 2060 lines of the stage docs for the behavior-level ratification obligation. |
| AC-6 | **unsatisfied** | The CI step is wired correctly in the right job, and the selftest does prove all three named red paths — under bash 4+. Under the 3.2 lane those same three proofs fail, so the AC's own clauses ("a disposition outside the enum reds; an uncovered `stages/*.md` file reds; a malformed row reds") do not hold on every lane CI runs. Follows B-1 and clears with it. |

Design fidelity: **not-applicable** (unchanged — the spec's `Design: none` disarm is justified;
the repo declares no design provider).

## CI evidence

Run `31399774419` at head `44dd073`, the first run this branch has ever had:

| Job | Result |
| --- | --- |
| `lint-and-selftests` (ubuntu) | success |
| `mutation-sweep-pr` | success |
| `pr-gates` | success |
| `release-pr-gates` | skipped |
| **`selftests (macos, bash 3.2)`** | **failure** — `tools/capability-parity-check-selftest.sh (rc=10)`; sweep summary `72 scored, 70 run, 2 served from cache, 1 failed` |

Both new CI steps are present exactly once and in order after `contract lockstep pairs`, so the
merge resolution itself is sound; `lint-and-selftests` passing is what confirms it.

## Everything else from the approve still stands

W-1 through W-6 and S-7/S-8 are unchanged and remain non-blocking. W-1 is worth re-reading
alongside B-1 — both are the same shape, an assertion in this guard that nothing exercises. The
Strengths section stands too: the suite's quality is why this was caught at all rather than
shipping a guard that passes everything.

One correction to W-1's remedy ordering: fix B-1 first, then re-check W-1's probe under **both**
interpreters, since the trim's behavior is not what changed but the surrounding parse is.
