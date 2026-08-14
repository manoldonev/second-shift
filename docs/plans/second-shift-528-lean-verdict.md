# lean review verdict — #528

verdict=needs-work
run_id: review-528-1
session_id: 86bd7274-879b-4e60-86cd-941991810f6b
rounds: 1
pr: #540
reviewed_head: 0899d16c398851446d53183838d3e17b81cdc450
reviewed_patch_id: 0e7aa587092a758b3f06e498749ccc3e831c8f75
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 1 — PR #540 (#528), `review-528-1`

Range read: full branch diff `e583994..0899d16` (root round — `delta` printed FULL, nothing to
inherit). Panel: security, performance, maintainability, complexity, test-coverage,
unit-test-mutation, scope-completeness — 7 selected, 7 returned, none dark.

**Verdict: needs-work.** Four blockers: AC-1's safety interlock is breakable and unguarded (B1), the
mutation lane is red (B2), AC-2's heal half is guarded by two cases that cannot fail for the defect
they name (B3), and the `append_satisfied` rewrite falsifies a soundness argument the scheduler's
continuation predicate rests on (B4). The `append_satisfied` code itself and AC-3 are genuinely
tested — kill-probed below.

---

## Blockers

### B1 — the ownership interlock's writer and reader are different expressions, so AC-1's "never delete a live lane's fixture" does not hold portably

AC-1 (ticket, verbatim): *"Reaping is age-and-ownership guarded so it can **never** delete a live
concurrent lane's fixture."*

The stamp is written one way and read back another:

| | expression | trailing newline |
| --- | --- | --- |
| **writer** — `lean-gate-selftest.sh:59`, `orchestrate-lean-selftest.sh:48` | `raw="$(ps -o lstart= -p "$$" 2>/dev/null \| tr -cs 'A-Za-z0-9' '_')"` | `tr` sees it → becomes a trailing `_` |
| **reader** — `reap-lean-fixtures.sh:97-100` | `raw="$(ps -o lstart= -p "$pid" 2>/dev/null)"` then `printf '%s' "$raw" \| tr -cs …` | command substitution strips it *before* `tr` |

The two agree **only if `ps` emits at least one trailing blank before the newline**. macOS BSD `ps`
does — measured, two of them:

```
$ ps -o lstart= -p $$ | od -c
0000000  F r i   A u g   1 4   1 4 : 1 6 : 1 9   2 0 2 6       \n
                                                        ^^^^^^^
```

Nothing in the repo tests, documents, or enforces that property, and the failure is silent
destruction rather than a red test. Measured fire/no-fire pair, both arms running the branch's own
`_own_stamp` and the branch's own `reap-lean-fixtures.sh`, with **only `ps` swapped** (same raw
string fed to both sides):

```
ARM A — this machine's BSD ps
  fixture : leangate.97025.Fri_Aug_14_14_19_47_2026_.XXXXXX.Ab3xY9zQ1p   (owner pid LIVE)
  [reap-lean-fixtures] keep (live owner pid 97025)
  RESULT  : fixture SURVIVED

ARM B — a ps whose lstart column carries no trailing blank (procps renders lstart as a
         fixed "%24.24s" ctime slice), identical shipped code on both sides
  fixture : leangate.97025.Thu_Aug_7_09_12_33_2025_.XXXXXX.Ab3xY9zQ1p    (owner pid LIVE)
  [reap-lean-fixtures] removed: … (age=51023988s)
  RESULT  : fixture DESTROYED
```

Removal in ARM B is ownership talking, not age — the code keeps an owned fixture regardless of age,
and the emitted line is `removed:`, not `keep (live owner …)`.

**It is guarded by nothing.** Replacing the writer's whole stamp with a constant leaves every suite
that could plausibly notice green:

```
producer stamp -> "MUTANT_STAMP" in BOTH templates
  tools/reap-lean-fixtures-selftest.sh                    rc=0   PASS
  plugins/…/run-lean/orchestrate-lean-selftest.sh         rc=0   all green (77 cases)
```

The one case that reaches the real path — `reap-lean-fixtures-selftest.sh:200-214`, *"with no stub,
a genuinely live pid is read from the real process table and kept"* — re-derives the **reader's**
form at `:202` to build its fixture name, so it compares the reader against itself and cannot see
the disagreement. That is the hand-maintained copy of production logic `CLAUDE.md`'s *No mirror
harnesses* rule names; and four copies of one sanitization in two forms
(`lean-gate-selftest.sh:59`, `orchestrate-lean-selftest.sh:48`, `reap-lean-fixtures.sh:100`,
`reap-lean-fixtures-selftest.sh:202`) with no row in `scripts/lockstep-manifest.tsv` is exactly the
tier map's *"two copies of one contract staying identical → a lockstep row"*.

Blast radius is the harm the tool exists to prevent, and it is worse than the status quo: before
this PR nothing deleted live fixtures at all. `tools/run-selftests.sh` invokes the reaper on every
real sweep including the ubuntu `lint-and-selftests` lane (the file is committed `100755`, so the
`[[ -x ]]` guard fires), and CLAUDE.md records live sweeps at 5:22–13:12 — routinely past the 600s
owned floor.

One more instance of the same root cause: ownership has no *unknown* state. Every failure to
establish it — a dead pid, an unreadable one, `ps` absent, the writer's own `${raw:-0}` fallback at
`lean-gate-selftest.sh:60` — resolves to `owned=0`, i.e. **delete**. For a genuinely dead pid that
is right; for "could not tell" it is the unsafe direction.

Confidence split, stated honestly: that the two expressions differ and that a non-padding `ps`
destroys a live fixture is **measured** here. That GNU/procps specifically is the non-padding case
is **inferred** from its fixed-width `lstart` rendering — no Linux was reachable from this session
to execute it. The finding does not rest on that inference: the agreement is untested and
OS-dependent either way, and the fix (one expression, used on both sides, pinned by a lockstep row
or a writer→reader round-trip case) is cheap and OS-independent.

### B2 — `mutation-sweep-pr` is red: the PR-scoped sweep exceeded its 15-minute budget

`mutation-sweep-pr` **failed** — `The action 'mutation sweep (PR-scoped)' has timed out after 15
minutes` (run 31795284556, job 94750916495). It reached `pool: 2 worker(s), 50 mutant(s) to score,
0 served from cache` and never emitted a result set.

This is not mutant volume. Same 2-worker pool, same dominant guard (`lean-gate.sh`) paired to the
same suite (`lean-gate-selftest.sh`), three recent green runs:

| PR / branch | mutants | wall to results | outcome |
| --- | ---: | --- | --- |
| #538 / `…-532` | **66** | ~11 min | pass |
| #535 / `…-511` | 27 | ~11 min | pass |
| #534 / `…-515` | 22 | ~6 min | pass |
| **#540 / `…-528`** | **50** | **>15 min** | **timeout** |

66 mutants finished three runs ago; 50 did not. So per-mutant cost is what moved — and it is **not**
the clean-run cost of the added cases, which I measured as small (`lean-gate-selftest.sh`, same
worktree, CPU time rather than wall because a co-running session distorts wall: main
`42.35u + 59.91s = 102.3s`, branch head `44.86u + 64.67s = 109.5s` — about +7%). +7% over 50
mutants does not turn an 11-minute
66-mutant sweep into a 15-minute timeout.

The cost is on the *mutant* path, and it is **wall-clock sleep, not compute** — measured. `(rc1)`
and `(rc3)` each wait for two background gate processes to reach `LEAN_GATE_TEST_STALL_DIR`,
bounded at `100 × sleep 0.1` = 10s; `_lean_gate_test_stall` in `lean-gate.sh` carries its own 10s
ceiling. A mutant that stops a writer from reaching `append_satisfied` leaves the second `ready.*`
file uncreated, so the coordinator spins its whole ceiling. Running the suite under one
representative mutant (`append_satisfied`'s absence test flipped `0` → `1`):

```
                       wall        user + sys
clean branch head      2m28.3s     44.86 + 64.67 = 109.5s
under one mutant       2m40.6s     45.57 + 66.87 = 112.4s
delta                  +12.3s      +2.9s
  FAIL: (rc1) expected both writers to reach the stall (got 0/2) …
```

`got 0/2` is the ceiling being spun in full. +12s of wall per mutant × 50 mutants ÷ 2 workers ≈
**+5 min** on top of a ~9-minute base — which lands exactly on the 15-minute cliff, and a mutant
that also perturbs the heal path pays another ~10s.

The +2.9s CPU is why this did not show up locally: the added time is `sleep`, so a wider local pool
overlaps it away while CI's 2-worker pool serializes it. The PR body's *"mutation sweep 0 survivors
across all three swept guards"* is a local (macOS, wider pool) result; CI's table is the authority
here and CI never produced one.

Either way the lane is red and is the lane's to close, not the diff's to argue around — a shorter
ceiling, an early bail once a writer exits, or skipping the racing cases under the sweep are all
the build's call.

### B3 — `(rc3)` and `(rc4)` cannot fail for the `heal_progress_run_id` defect they name

The ticket's Tests section mandates *"assert exactly one satisfied row **and no `.heal`
collision**"*, and the spec's Tests section claims `(rc3)`/`(rc4)` deliver it. They do not. Reverting
`heal_progress_run_id` to the exact pre-#528 shape the ticket calls *worse* — `local
tmp="$PROGRESS_FILE.heal"`, the fixed sibling two concurrent heals collide on — leaves the **whole
suite green**:

```
M3: heal reverted to the fixed .heal sibling
  rc=0   suite verdict: [lean-gate-selftest] all green
  (rc3) passed  <- mutant SURVIVED
  (rc4) passed  <- mutant SURVIVED
```

Both are vacuous, for two different reasons, each confirmed:

- **`(rc3)`** asserts one `run_id: p-race-heal` and zero `run_id: unset`. Both racing heals run the
  same `awk` over the same header and resolve the same id (`lean-gate.sh:889-892`), so their output
  is **byte-identical**. Colliding on one filename still yields one correctly-healed header —
  there is nothing for the assertion to observe. The collision is real; its effect is not.
- **`(rc4)`** asserts no leftover matching `-name 'rheal-progress.md.heal.*'`. The pre-fix temp is
  named `rheal-progress.md.heal` — no dot, no suffix — so it **cannot match that glob**, measured:

  ```
  $ find /tmp/rc4glob -maxdepth 1 -name 'rheal-progress.md.heal.*'   # file: rheal-progress.md.heal
  0
  ```

  The pattern was written against the *post*-fix name shape, so the case is structurally incapable
  of reddening for the code it replaced. (It is also moot: the pre-fix `mv` removes the temp on the
  success path anyway.)

Contrast the sibling half, which is genuinely live: reverting `append_satisfied` to read-then-append
**does** red `(rc1)`. So the technique works — it just was not made to bite on the heal seam. The
production change to `heal_progress_run_id` is correct; what is missing is any case that would
notice if it were reverted, which is the coverage this ticket exists to add.

### B4 — the diff falsifies `progress_token`'s in-tree soundness argument and leaves it standing

`lean-gate.sh:1480-1483`, **untouched by this diff**, is the written justification for the
scheduler's continuation predicate:

> *"WHY A COUNT IS A SOUND TOKEN. These rows are append-only: `append_attempt` and
> `append_satisfied` **only ever add**, and **the single rewriter in this file**
> (`heal_progress_run_id`) has an exact-string compare bounded to the header. So the selected count
> **cannot go up and back down** within a spawn and read as unchanged."*

Both clauses are false at head. `append_satisfied` (`:983-992`) is now `cat` the whole file → append
→ `mv`, i.e. a full-file rewrite, and it is a second rewriter. The consequence the comment declares
impossible is the residual risk the spec itself accepts: a rewrite built from a fresh-at-write-time
read can drop a row a concurrent `append_attempt`/`append_absent`/`append_started`/
`append_concluded` wrote in the gap. Dropping an `attempt` row makes the counted set go **down** —
the movement the comment says cannot occur — and `orchestrate-lean.sh:490` compares that token
byte-for-byte across two reads to decide whether the BUILD phase advanced.

The spec's stated mitigation does not cover it. *"Self-correcting — the next `bash G all`
re-evaluates and re-records what was lost"* holds for `satisfied`/`absent`, which a re-evaluation
regenerates. It does not hold for `attempt`: `append_attempt` fires only on a fresh milestone
failure (`:1141`), so a lost row is never replayed and the #494 fix budget is silently un-charged by
one. That is the permissive direction on the counter the epic named as this exact seam.

The window is the narrow one the spec already documents, so this is not a new hazard class — but an
accepted risk is only accepted if the acceptance is accurate, and here the acceptance rests on a
mitigation that does not apply and leaves a contradicting invariant in the same file. The fix is
small: correct `:1480-1483` and re-argue the acceptance for the `attempt`-row case (or exclude
`attempt` rows from the rewrite by appending rather than rebuilding).

---

## Warnings

- **W1 — `MIN_AGE_OWNED`/`MIN_AGE_LEGACY` (600/86400) are never exercised.** Every fixtured case in
  `reap-lean-fixtures-selftest.sh` passes explicit `--min-age-*-secs`; the one flag-less case is a
  `--dry-run` against the real `/tmp` asserting only the scan root. The sole production call site
  (`run-selftests.sh:192`) passes **no** overrides, so these two constants are exactly what gates
  real deletions. `86400 → 0` would pass the whole suite.
- **W2 — the trap-before-`mktemp` reorder was not mirrored.** `lean-gate-selftest.sh` moves
  `trap cleanup EXIT` above its `mktemp` with a comment saying this closes AC-1's second window;
  `orchestrate-lean-selftest.sh:48-50` keeps `WORK="$(mktemp …)"` then `trap`, leaving the same
  one-line window open in the sibling the same PR is otherwise treating identically.
- **W3 — the new `run-selftests.sh` call site is unexercised.** Every case in
  `run-selftests-selftest.sh` drives a synthetic `--root` whose `tools/` (built by `write_tsv` at
  `:319`) only ever contains `selftest-cache-inputs.tsv`, so the `[[ -x … ]]` guard takes its false
  branch in all of them. Nothing proves the guard fires when the tool *is* present, nor that a
  non-zero reaper exit is genuinely swallowed.

## Suggestions

- The header's *"`<prefix>.<pid>.<stamp>.<random>` — 4 dot-fields"* (`reap-lean-fixtures.sh:121`) is
  wrong on BSD: `mktemp -d -t` treats the whole argument as a prefix and appends its own suffix,
  yielding **5** fields (`leangate.12345.<stamp>.XXXXXX.Hm1uZwFg4A` — measured). `-ge 4` is
  tolerant, so this is doc-only, but no fixture uses a >4-field name.
- `rc5`/`rc6` capture `2>&1`, so they cannot distinguish the announcement being on stderr from it
  being on stdout — the stream choice is the load-bearing part of the AC-3 design comment.
- `orchestrate-lean.sh:350` captures `staleness` with `2>&1` into a human-facing preflight message,
  which now carries a `[lean-gate] config: …` line. Display-only, so cosmetic — worth a glance.
- `file_mtime` (`reap-lean-fixtures.sh:77-83`) is a second hand-maintained copy of
  `pipeline-cost-block.sh`'s BSD/GNU pair, as its own comment says, with no
  `scripts/lockstep-manifest.tsv` row either. This one is *correct* — it validates the digits rather
  than the exit status, which is what makes the pair portable — but it is the same duplication
  pattern that B1 turned into a live defect one function up.
- The zero-edit conclusion for `mutation-baseline.tsv`/`mutation-catalog.tsv` is correct (the
  `default` ordinals 1–2 stay the Seams-block prose entries and `K_BUDGET=2` leaves the window
  unmoved) but is recorded nowhere, so the next reader re-derives it.

## Verified

- Kill probes against the pre-#528 code, scored by case id: `append_satisfied` reverted to
  read-then-append → **(rc1) FAILS** (mutant killed); the config announcement removed → **(rc5) and
  (rc6) FAIL** (mutant killed). The heal arm is B3.
- bash 3.2 clean: the reaper and its suite both run green under stock `/bin/bash 3.2.57`, and all
  four changed shell files pass `bash -n` under it.
- `shellcheck -e SC1091,SC2015,SC2181` clean on all six changed shell files (0.11.0 local;
  CI 0.9.0 lane green).
- `lint-and-selftests` (ubuntu) and `selftests (macos, bash 3.2)` both pass.
- Scope-completeness gate: **PASS** — all three ACs present in the diff.

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| **AC-1** — orphans reaped, age-and-ownership guarded, never deletes a live lane's fixture | **unsatisfied** | The reaping half works (dry run against this machine's 289 real orphans behaves as specified). The safety half does not: B1 destroys a live-owned fixture with the branch's own code, and no suite guards the writer↔reader agreement. |
| **AC-2** — `append_satisfied` + `heal_progress_run_id` atomic, no blocking waiter | **unsatisfied** | The **code** is right on both seams — unique temp + atomic rename, `append_satisfied` re-verifying absence against the copy it commits, no lock and no waiter. The ticket's Tests clause is not: it mandates a "no `.heal` collision" assertion, and B3 shows `(rc3)`/`(rc4)` cannot fail for the pre-fix heal. The `append_satisfied` half is fully satisfied and kill-probed. |
| **AC-3** — resolved config path announced | **satisfied** | `lean-gate.sh:377`, via `warn` (defined `:253`), skipped on `progress`. Kill-probed: removal fails `(rc5)` and `(rc6)`. `(rc7)` pins the `progress` exemption. |
