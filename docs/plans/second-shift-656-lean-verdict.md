# lean review verdict — #656

verdict=needs-work
run_id: review-656-3
session_id: 220fcbf9-ebb8-4101-8e22-d891f04ae4b0
rounds: 3
pr: #681
reviewed_head: 721c8f9b5907134591b15d5fee719d7f50cda96e
reviewed_patch_id: 4a5d6ea102c11c18dc27aabfaa181b5c4b5b980f
inherited_patch_id: e759b3e53257da5db37674405cb525dc92cceae0
inherited_from_verdict: 581ffd467877283f537e2fcaa39b82f019e76e03
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 3, delta range `581ffd46..HEAD`, inheriting patch `e759b3e53257` (round 2). Four files:
`CLAUDE.md`, `docs/testing.md`, `docs/plans/second-shift-656-lean.md`, `tools/reap-lean-fixtures.sh`.
Rounds 1 and 2 findings were read first.

**All three round-2 blockers are fixed, and each fix was re-measured here rather than read.**
R2/B-1 (the blanket "no `mktemp` form honors `TMPDIR`") is now a two-family split, and all five
lines of the enlarged derivation block reproduce verbatim on this machine. R2/B-2 (*unset* vs
*default* `TMPDIR`) is now correct, dated, and carries its own two-line derivation, which also
reproduces. R2/B-3 (`reap-lean-fixtures.sh`'s header citing the note that refutes it) landed as
AC-7 with the header rewritten — the scope expansion was written into the spec and the ledger
(D-10/D-11) rather than made silently, which is the right shape.

**Verdict: needs-work.** The central claim is now true. The paragraph that argues why it *matters*
is not: the one worked example it names is mischaracterized, and the count beside it puts two files
on the wrong side of the very split this PR exists to draw. Same class as rounds 1 and 2 — a
sentence reaching past the measurement under it — at reduced magnitude, and both blockers are
answerable by rewriting two sentences against the numbers below.

## Blockers

**B-1 — `run-selftests.sh`'s `BASE` is neither "the parent of every suite's scratch" nor "the
single largest thing a killed run strands". Measured live during a sweep: it is a SIBLING of the
stamped fixture dirs, and 3–23× smaller than them.**

`docs/testing.md`:

> The explicit template is not a curiosity: `grep …` finds **14** files using it, among them the
> sweep runner's own state dir — **the parent of every suite's scratch**, and **the single largest
> thing a killed run strands** (`tools/run-selftests.sh`)

*Not the parent.* The runner never puts a suite's state dir under `BASE`. `TMPDIR` is named on
exactly two lines of the file (`:241` reaper `--dir`, `:394` `BASE`), and the worker branch
(`:127-170`) runs `( cd "$W_ROOT" && env -u … bash "$W_SUITE" ) > "$W_OUT/$W_IDX.log"` — the suite
inherits the ambient `TMPDIR` untouched and writes only `<idx>.log/.rc/.secs` into `RESULTS`. So
`BASE` = `$TMPDIR/run-selftests.XXXXXX` and a stamped fixture = `$TMPDIR/leangate.XXXXX` are
**siblings in the same directory**. The runner's own header says so (`:16`, "the suites are
independent, each allocating its own `mktemp` state dir"), and so does `CLAUDE.md` forty lines
below this PR's own hunk.

*Not the largest.* Measured 2026-08-25 on this lane, sampling `du -sk` every 8s through a live cold
`SKIP_STRESS=1 … --full --exclude tools/install-topology-selftest.sh` at `721c8f9b`:

```
sample   BASE(KB)   leangate.*(KB)   orchestrate-lean-selftest.*(KB)
 4          112          616               1776
 6          216         1148               4168
 9          352         1636               8016      <- stamped peak, 23x BASE
27          820         2696                  0       (both stamped suites had finished
end        1036            0                  0        and run their own trap … EXIT)
```

At **every** sample where a stamped dir existed at all, the stamped total exceeded `BASE` — 3.4× at
the narrowest, 23× at the widest — and that is the window a kill actually lands in. `BASE` only
becomes the biggest surviving thing after the two suites the reaper exists for have already cleaned
up after themselves, which is the case where nothing was killed. The historical figure in
`reap-lean-fixtures.sh`'s own header — 107 `leangate.*` and 73 `orchestrate-lean-selftest.*` orphans
on one machine — is the same story at rest.

Why this blocks rather than nits: it is the mirror of round 2's blocker. A reader is now told the
biggest thing a killed sweep leaves behind is the one thing a private `TMPDIR` relocates, i.e. that
the remedy buys most of the volume; measured, it buys the smaller sibling and leaves the two
families the reaper exists for exactly where they were. The sentence also contradicts its own
paragraph four lines later ("does **not** move the stamped fixture families") — if `BASE` were the
parent of every suite's scratch, moving `BASE` would move them.

Remedy: say what `BASE` is — the runner's own bookkeeping and per-suite captured output, a sibling
of the fixture dirs, not their parent — and drop the size superlative or replace it with the
sampled numbers above.

**B-2 — "14 files using it" is 12; two of the matched files use the OPPOSITE form. `CLAUDE.md`'s
derived "thirteen other callers" inherits the error.**

`grep -rl 'TMPDIR:-/tmp}/' --include='*.sh' .` does return 14 files at `721c8f9b` — the command
reproduces. But it is a `-l` file match, and two of the 14 match on a **comment**, not a call:

| File | Line | What it is | What that file's temp dirs ACTUALLY use |
| --- | --- | --- | --- |
| `tools/mutation-sweep.sh` | `:1359` | comment describing a mutant of the shape | `mktemp -d -t mutation-sweep-work.XXXXXX` (`:1261`), `-t mutation-sweep-sandbox` (`:1326`), `-t mutation-sweep-report` (`:828`), `-t mutation-sweep-line` (`:1809`) — **all `-t`** |
| `plugins/intake-toolkit/hooks/exitplan-ledger-gate-selftest.sh` | `:121` | comment about the hook's tier-1 scratch | `mktemp -d -t exitplan-ledger-gate-selftest.XXXXXX` (`:42`) — **`-t`** |

So 12 files carry a real explicit-template call, and `CLAUDE.md`'s "the sweep runner's own `BASE`,
and **thirteen other callers**" should be eleven. Verified by reading all 18 matched lines: 16 are
calls, 2 are comments. Note that 13 is not reachable on *either* basis — 11 other files, or 15
other call sites (`exitplan-ledger-gate.sh` and `check-gate-buckets.sh` carry three each). It is
`14 − 1`, i.e. a `grep -l` file count minus the runner, with the matched lines never read.

Why this blocks rather than nits: the two miscounted files are not random. `tools/mutation-sweep.sh`
is named by `CLAUDE.md` in this very section as a long call to background, its `-t` work/sandbox
dirs are stranded by exactly the kill this runbook is about, and `reap-lean-fixtures.sh` reaps only
the `leangate.*` / `orchestrate-lean-selftest.*` prefixes (`:133`) — so its litter is residue that
a private `TMPDIR` does **not** move. The doc's own enumeration command therefore hands a reader
`mutation-sweep.sh` under the heading "files using the honored form", which is the wrong side of
the split. A count derived from `grep -l` without reading the matched lines is the same defect the
`#567` intake recorded (41 of 142 baseline rows were comment sites).

**Where the number came from, said plainly: the round-2 review record.** Its B-1 wrote
"`grep -rln 'mktemp[^|]*\"${TMPDIR:-/tmp}'` finds **14** guard scripts using this form", and its
commit body wrote "13 other guards use the same form". Replayed here, that pattern returns the
**identical** 14-file set as the doc's (`comm -3` between the two sets is empty), comment sites and
all. So this round is correcting a number the review role itself put into circulation — the build
adopted a reviewer's count rather than inventing one. It is still a blocker because the PR is what
ships the claim and the prose is what a reader acts on, but the fix is a re-derivation both sides owed, not a lapse this round is charging
to the build alone.

Remedy: either count call sites (`grep -rn 'mktemp[^#]*"${TMPDIR:-/tmp}/'` and read them) and say
12/eleven, or keep 14 and say "14 files mention it, 12 call it". `CLAUDE.md`'s number moves with it.

## Per-AC scoring

| AC | verdict | basis |
| --- | --- | --- |
| AC-1 | satisfied | All three required elements sit under the recipe fence, not behind a link: the 2-minute foreground reap and that `timeout` does not lift it; `nohup <cmd> > <log> 2>&1` under `run_in_background` as the shape that survives and is collected in the same turn, with a bare backgrounded command explicitly excluded; and the scrub obligation, correctly routed to the runbook anchor. The cap paragraph is unchanged in this delta and is inherited from round 2, which measured it first-hand. The killed-sweep note in this delta carries B-2's count. |
| AC-2 | **unsatisfied** | Five of its six elements hold and were re-run here: the reaper-clears mechanism is now correct and dated (round 2's B-2 discharged); the enumeration is read-only and returns `/var/folders/…/T/gitkraken/gitlens/agents` — a real match, no `.claude-plugin/plugin.json` beside it, the harmless case the prose names; the `stat`-before-delete check is present. The first element — *why `TMPDIR` cannot isolate the litter* — is where B-1 lands: the form split is right, but the worked example carrying it is false in both halves and contradicts the sentence four lines below it. |
| AC-3 | satisfied | `bash scripts/check-guard-budget.sh origin/main` re-run at `721c8f9b` after the `reap-lean-fixtures.sh` header edit: base 51793, HEAD 51793, **delta 0**. No new gate, no new script. No `Guard-mass:` trailer owed. |
| AC-4 | **unsatisfied** | "the single largest thing a killed run strands" is a size claim carrying neither a derivation nor a date, and it is false when measured (B-1). "14 files using it" carries a runnable derivation that reproduces, but the derivation does not support the characterization (B-2). The second half of AC-4 **is** met: no sentence asserts a currently-fixed defect as live, and the emit-deadline live-scan case is still described by mechanism without being named as still redding. |
| AC-5 | satisfied | `Changelog: none` on all six branch commits. `check-changelog-trailer.sh origin/main`: no `plugins/**` change, trailer not required. |
| AC-6 | satisfied | Re-run cold and locally at the reviewed head via the shape this PR documents. `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` → `summary: 75 scored, 75 run, 0 served from cache, 0 failed`, byte-identical to the PR body's claim. CI at `721c8f9b`: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr` pass. |
| AC-7 | satisfied | `tools/reap-lean-fixtures.sh`'s header no longer contradicts the note it cites. It now states where `-t` resolves (`_CS_DARWIN_USER_TEMP_DIR`, not `TMPDIR`) and why its own default reaches them — verified against `DIR="${TMPDIR:-/tmp}"` at `:69`, `--dir` at `:79`, and the three-line launchd derivation, all of which reproduce here. Header comment only; guard mass still 0 (AC-3). |

## Warnings

**W-1 — the header's citation is one hop short of what it promises.** `reap-lean-fixtures.sh:9`
says "see CLAUDE.md's killed-sweep note **for the derivation**"; that note explicitly does not carry
one ("measured 2026-08-25; the derivation is in the runbook") and forwards to
`docs/testing.md#when-a-run-is-killed-mid-sweep`. Not a contradiction — AC-7 is met — but the
header would land its reader one hop sooner by naming the runbook anchor directly. Note the header
is also `--help` output (`reap-lean-fixtures-selftest.sh` asserts that), so it is read by operators,
not only by editors.

## Also verified (no findings)

- The full five-line derivation block in `docs/testing.md` reproduces **exactly** on this machine,
  including the two lines added this round: `TMPDIR="$PRIV" bash -c 'mktemp -u -d
  "${TMPDIR:-/tmp}/x.XXXXXX"'` → `$PRIV/x.…`, and `env -u TMPDIR …` → `/tmp/x.…`. The `-p` control
  moves and the two `-t`-family lines do not, so the negatives are a result, not a harness artifact.
- The reaper-reach block reproduces: `env -u TMPDIR … "${TMPDIR:-/tmp}"` → `/tmp` while
  `env -u TMPDIR mktemp -u -d -t stamp` → `/var/folders/…/T/…`, and the inherited value is that same
  confstr directory. `tools/reap-lean-fixtures-selftest.sh` independently asserts the `/tmp`
  fallback, so the corrected sentence is guarded as well as true.
- "the two stamped prefixes" is exact: `reap-lean-fixtures.sh:133` iterates `leangate.*` and
  `orchestrate-lean-selftest.*` and nothing else.
- `check-lockstep-pairs.sh`: 29 anchors, 0 failed. The split-by-role decision (D-1) still owes no
  anchor — the two sites do not restate each other.
- `check-frozen-files.sh origin/main`: clean, no release-owned file touched.
- **The spec amendment is legitimate.** AC-7 and the scope paragraph were added in the same commit
  as the fix, but they *raise* the bar in response to a review blocker rather than lowering it to
  match the diff, and D-10/D-11 record the reasoning. This is not the "amended after the fact to
  match the diff" case.
- `pr-gates` red at `721c8f9b` verified from its own log, not assumed: both arms name only
  `verdict=needs-work` in `docs/plans/second-shift-656-lean-verdict.md` (`lean-evidence` 1 artifact,
  `lean-chain` 2). No other gate fails.

## Deviation to record

The reviewer panel was not fanned out this round, as in rounds 1 and 2: this session runs under a
standing operator instruction not to dispatch subagents or workflows unasked, which is in tension
with review-lean step 5 naming `review-lead` as the implementation. The review is first-hand — the
delta was read in full and every factual claim in it was executed. Both blockers were found by
measurement (a live `du -sk` sampler through a real sweep, and reading all 18 lines behind a `-l`
count), which is the mode that has now carried all three rounds of this ticket.
