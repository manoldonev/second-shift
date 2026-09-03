# C2-a — ablation CONTROL: the full pinned `review-lean`

The control arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897`, **all 127 lines, unablated**.
Registered n=3. Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/control.txt)" \
  | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
      -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
      -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT -u CLAUDE_EFFORT -u CLAUDE_PID \
      -u RUN_ID -u LEAN_RUN_MODEL -u LEAN_ATTEND_MODE \
      claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob" \
        --output-format stream-json --verbose
```

The prompt is the full unablated SKILL text, then
[`prompt-template.txt`](prompt-template.txt) verbatim, then the pinned diff
`dfd68a47..cfba1022` — the assembly §C registers.

Three additions to the registered `env -u` list, recorded rather than folded in: `RUN_ID`,
`LEAN_RUN_MODEL` and `LEAN_ATTEND_MODE` are unset by the runner, and were **also absent from the
launching environment** — these runs were launched detached (`start_new_session`) from an
interactive session that scrubbed them, not from inside a lean build session. That reproduces
arm 2a's realised condition. Nothing else about the invocation differs from the registered form.

## Apparatus

| run | rc | capture | `classify-capture.sh` | `result` events | tool calls | tool inputs naming `review-lean` |
| --- | --- | --- | --- | --- | --- | --- |
| r1 | `0` | 501417 B, 484 lines, sha256 `21a56fadf8bf1979…` | exit 0 — `COMPLETE` | 1 | 36 Bash,  8 Grep,  4 Read | **0** |
| r2 | `0` | 292885 B, 300 lines, sha256 `db2769f27ab82d88…` | exit 0 — `COMPLETE` | 1 | 10 Bash,  10 Grep,  4 Read | **0** |
| r3 | `0` | 417526 B, 401 lines, sha256 `525b92bbdd4f2d0f…` | exit 0 — `COMPLETE` | 1 | 29 Bash,  1 Grep,  7 Read,  1 Write | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## Apparatus failure: the discarded first batch

An earlier control batch was launched from inside the lean BUILD session and was killed when
that session ended its turn — the runs were its children. The three captures are **not scored**,
and — like every scored run's raw capture above — they are **not committed**: they stay in the
run's machine-local scratch (`/private/tmp/c2b-748/out-killed-infra-20260903/`), which no reader
of this repo can resolve. What is preserved here is the measurement, hashed so the reading can be
repudiated on a machine that still has them:

| capture | bytes | sha256 | `result` events | `classify-capture.sh` |
| --- | --- | --- | --- | --- |
| `control-r1.stream.json` | 412047 | `a94bc25aa33dbaa8…` | 0 | exit 2 — **TRUNCATED** |
| `control-r2.stream.json` | 426267 | `c30e6e428a92f64d…` | 0 | exit 2 — **TRUNCATED** |
| `control-r3.stream.json` | 498614 | `a29839f5c46011ab…` | 0 | exit 2 — **TRUNCATED** |

Each stops mid-conversation with no terminal `result` event, and every mtime is the second the
parent session exited. Recorded because a truncated capture read at face value is a clean
negative, which is the failure `classify-capture.sh` exists to make impossible. The lane gap
that produced it is tracked separately.

---

## r1

2026-09-03T18:29:51Z → 2026-09-03T18:39:43Z. stderr empty.

## Summary

The slice does what it says: a shape enumerator over five files, a 156-row register over 305 sites, four independent red arms, and a selftest that cases each one plus the real tree (g0). CI wiring is in the always-on guard job as AC-7 requires, the `Guard-mass:` trailers are present on all three commits, no corpus file is edited, and the new script introduces no `producer | grep -q` shape, so the AC-10 obligations check out. The batched awk pass is correct on the details that matter — `FILENAME` rather than `FNR == NR`, the distinct-bucket set counted as it is built, `ENVIRON` rather than `awk -v` for the backslash-bearing anchors.

AC scoring: AC-1, AC-2, AC-4, AC-5, AC-6, AC-7, AC-9, AC-10 satisfied. AC-3 satisfied on the letter (every *primitive* per file is named). **AC-8 unsatisfied** — see the blocker: the header claims to state every self-exclusion, and one is unstated and live.

## Warnings

1. **`docs/prose-blocker-triage.tsv:40` already settled this gate's bucket, differently.** That row records the all-dark rule's enforcer `scripts/check-lean-chain.sh::verdict-record` as *"settled KEEP / gates-llm by the parent epic. Its bucket is pre-settled"*. The new register disposes of the same enforcement point — `lean-evidence.sh::note_violation "no committed verdict record (a file named *-$KEY$LEAN_VERDICT_SUFFIX)"` — as `gates-signal`, with no note reconciling the two. Both buckets never yield, so nothing is made waivable; but this is the slice whose entire deliverable is "which gate is which", and it silently overrides a disposition another register calls pre-settled. A Decision Ledger row (the shape D-6 uses for the ticket's stale counts) would close it.

2. **`scripts/gate-buckets.tsv`, the `terminal preflight-rejected 2` row's `why` is wrong about the mechanism.** It asserts *"The one probe whose premise is an absent human exits at the resumable code above before this line."* Per `orchestrate-lean.sh:630`, the resumable exit is claimed only when `r1 -eq 3` **and** the other three probes are clean — the code comment there says so explicitly. An unintaken ticket plus any second probe failure falls through to `:634`. The `gates-signal` disposition survives that (such a run is not resumable by paying off intake), but AC-1 requires the `why` to name the mechanism that makes the disposition true, and this one names a mechanism that does not hold in the combined case.

3. **`.github/workflows/ci.yml:162` overstates what this step discharges.** *"#610 D-9 left prose-blockers.sh's coverage unwired … this is it."* D-9's deferral is about SKILL.md prose constructs censused against `docs/prose-blocker-triage.tsv`; `tools/prose-blockers.sh check` is still not wired anywhere in `.github/workflows/`. This guard censuses shell refusal sites against a different register. The claim reads as though prose-blocker coverage is now guarded.

4. **`scripts/check-gate-buckets.sh:300` — `exit "$violations"` over a 305-site denominator can wrap.** A wholesale register break (e.g. a primitive renamed in a corpus file: every row drifts *and* every site goes unclassified) produces hundreds of violations; exactly 256 exits 0 and CI goes green. The doctor convention is inherited from `check-fail-open-shapes.sh`, whose denominator is an order of magnitude smaller, which is why I raise it here and not there. A `[ "$violations" -gt 255 ] && exit 255` tail would cost one line.

5. **AC-5 "direction 2" (`:198`) cannot fire without `:195` firing.** `:195` already reds any non-`gates-process` row whose yield cell is not `-`, and no `OVERRIDE_GATES` value is `-`. So the second arm contributes a better message, not additional detection. g8 does kill a mutant that deletes it (the message string is unique), but the script header and the selftest's banner present the two as independent directions of the safety arm, and only one of them is load-bearing.

6. **The `lean-gate.sh::envfail` row's `why` overstates its class.** *"Nothing here refuses a claim about the CODE"* — `lean-gate.sh:3422` and `:3450` refuse precisely because a milestone-1 check *about the spec* could not complete. The `not-a-gate` disposition still follows the file's own exit-2 contract (`:3445-3449` says rc 2 is an environment error, never a fix attempt), so I would not change the bucket; the sentence is what is too strong, over a row covering 57 sites.

## Nits

1. `while IFS="$TAB" read -r …` (`:169`) — tab is an IFS *whitespace* character, so runs of tabs collapse and an empty interior cell shifts every later field left. g12b's fixture row is therefore caught because the field count drops to four, not because "the field count is not the check, the field CONTENT is" as its assertion text claims. No fail-open results (every empty-cell shape still lands on an empty `rwhy`), but the case does not test what it says it tests.

2. The malformed-row check is one-directional: a row with six or more tab-separated fields is accepted and the surplus is absorbed into `rwhy`.

3. `corpus_prims()` returns 0 on not-found and prints nothing, leaning on `in_set` against an empty set to produce the "no such corpus pair" red. It works; a distinct rc would say what happened.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator's command-position class omits shell reserved words, so it under-counts the denominator today, and the omission is undeclared.**

   *Mechanism.* The recipe is `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`. A refusal primitive invoked at the start of a command that follows `then`, `else`, `elif`, `do` or `!` on the *same line* is preceded by none of `^ ; & | ( ) { }`, so it never matches. The header's self-exclusion list declares only three exclusions — comment lines, helper definition lines, and non-command (argument) positions — and describes the class as *"the primitive must sit at the start of a command"*, which is exactly what these sites do.

   *This is live, not hypothetical.* `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is `else envfail "unexpected argument: $1"` — a real call site, not a comment and not a definition. Confirmed by counting: `lean-gate.sh` has 59 non-comment lines mentioning `envfail` and the enumerator matches 57; the two misses are the definition at `:379` (correctly excluded) and `:420` (silently dropped). So the guard's verdict line reports 305 sites where the corpus has at least 306, and `--list` — which the script and the register both declare *is* the denominator by definition — is short by one.

   *Consequence.* The invariant the slice exists to establish does not hold. A future refusal written as `else fail_milestone 3 "…"` or `then ticket_refuse "…"` is not enumerated, so no row is owed for it, so it lands unclassified with CI green and the register still printing "all bucketed" — the precise silent-rot failure mode the denominator-as-artifact design is built against, and the one #636 was filed to close. The current instance is benign (an `envfail`, which the class row would have dispositioned `not-a-gate` anyway), which is what makes it easy to miss and worth fixing before this becomes the reference implementation for the epic's remaining registers.

   *Fix.* Extend the prefix alternation to cover the reserved-word case — e.g. `(^|[;&|(){}]|\b(then|else|elif|do)\b)[[:space:]]*` — re-run `--list`, add the row that appears for `lean-gate.sh:420` (the existing `envfail ` class anchor already covers it, so this should only move the printed count), and add a negative/positive case to `check-gate-buckets-selftest.sh`'s g18 block pinning the shape. If instead the shape is deliberately out of scope, AC-8 requires it named in the header's residual list alongside the newly-named-primitive residual — but with a live instance in the corpus, declaring it seems worse than catching it.

---

## r2

2026-09-03T18:29:53Z → 2026-09-03T18:36:23Z. stderr empty.

I reviewed this against the tree, tracing the enumerator's recipe by hand against the five corpus files (I could not execute the guard in this session — permissions — so verification is static plus targeted searches).

## What's good

The core design is sound and the paired selftest is unusually strong. `--list` as the denominator, the register as the numerator, and four independent reds (UNCL / ANCHOR DRIFT / outlived row / AMBIG) is the right shape, and `g22` in particular catches a real class of bug (`FNR == NR` loading the sites file as rows when the register is empty) that most reviewers would never have thought to case. The `gates-signal` bucket is well-argued: forcing a red verify lane into `gates-process` really would make it waivable, and the register-internal safety arm (`g7`/`g8`) is the right place for that check rather than code proximity. AC-7's placement in `lint-and-selftests` rather than `pr-gates` is correct — the guard reads five files off the tree and needs none of `pr-gates`' env block. AC-9 is satisfied and the manifesto is the only prose site carrying the enum (I checked: no lockstep twin is owed). Commit trailers (`Guard-mass:`, `Changelog:`) are present on all three commits, and `tools/run-selftests.sh` discovers `scripts/*-selftest.sh` repo-wide, so the new suite is swept.

## Warnings

**W1 — `exit "$violations"` overloads the code the header reserves for environment refusal.** `scripts/check-gate-buckets.sh:300` returns the violation count, and the header (line ~72) declares `2 = environment refusal`. A run with exactly two violations exits 2, which the script's own vocabulary reads as "nothing was evaluated." The selftest is safe (`g15`/`g16` also grep the message), and CI only reads non-zero, so nothing is broken today — but the two meanings share a code. Separately, `exit 256` wraps to 0; the corpus has 305 sites, so a register that lost exactly 256 dispositions would exit green. `check-fail-open-shapes.sh:181` has the same wrap, so this is a house convention, but that script doesn't also claim 2.

**W2 — the "132" in four `why` cells is a repo-wide total presented as a per-file one.** `scripts/gate-buckets.tsv` repeats "so 132 near-identical rows would add no classification" verbatim in the `lean-evidence.sh::envfail`, `lean-gate.sh::envfail`, `operator-override.sh::envfail` and `check-lean-chain.sh::envfail` rows. The file header states 132 is the total across all six `envfail` rows. Read in a row keyed to one file, it asserts that file has 132 `envfail` sites. The `why` column's job is to name the mechanism that makes the disposition true, and a reader auditing OR-1's default will check that number against the wrong denominator.

**W3 — a temp file leaks if the second or third `mktemp` fails.** `COVERED_ROWS`, `SITES_F` and `PASS_OUT` are all created before the `trap ... EXIT` is installed, so an `envfail` from the second or third `mktemp` leaves the earlier ones behind. Cosmetic, but this guard runs in a job that also runs the whole selftest sweep.

**W4 — a row with *more* than five fields is not detected.** The malformed-row arm tests each of the five reads for emptiness; a sixth tab-separated field folds silently into `rwhy` via `read`'s remainder semantics. `g12`/`g12b` cover the too-few and empty-cell directions only.

## Nits

- Two `lean-evidence.sh::note_violation` rows have anchors where one is a strict prefix of the other (`…'verdict=${VERDICT_VALUE:-<none>}', n` and `…', not 'verdict=approve' — freshness is`). Both are `gates-signal`, so the AMBIG arm stays quiet and the shorter row simply reports a count of 2. Benign as written — and it *would* red as AMBIG if either bucket were changed — but the shorter anchor buys nothing over the longer one and could be tightened.
- D-2 says the `path::name` key is `docs/prose-blocker-triage.tsv`'s "adopted unchanged." That register's `name` half is a gate *concept* (`check-lean-chain.sh::verdict-record`), not a shell primitive. Same syntax, different referent; worth a word so a future reader doesn't try to reconcile the two key spaces.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the command-position regex misses shell reserved-word positions, and there is a live corpus site it already fails to enumerate.** The recipe is `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`: a primitive is only a site at line start or after one of `; | & ( ) { }`. But `else`, `then`, `do` and `elif` are also command positions in shell, and none of them is in that class. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is `else envfail "unexpected argument: $1"` — a real, live `envfail` call site, not a comment and not a definition line, that `--list` does not emit. It is therefore absent from the 305-site denominator, and no row in `scripts/gate-buckets.tsv` disposes of it. (I searched all five corpus files for `(then|else|do|elif)\s+<primitive>\s`; line 420 is the only code hit today — the other matches are comments.)

   The consequence is not this site's own bucket (the `lean-gate.sh::envfail` class row would have called it `not-a-gate` anyway). It is that the guard's central claim is false: the header asserts "`--list` prints the enumeration, that output IS the denominator by definition," AC-2 requires the guard to red on "an enumerated site no row claims," and AC-8 requires that "a reader can tell an excluded surface from a forgotten one." The header does state the class literally, but frames it as excluding "non-command positions" — and `else envfail` *is* a command position, so the stated rationale does not cover the exclusion it actually performs. A reader auditing completeness would conclude line 420 is enumerated. Concretely: add `else fail_milestone 3 "$msg"` or `then ticket_refuse "…"` to `lean-gate.sh` tomorrow and it lands unclassified with CI green — which is exactly the regression #636 was filed to make impossible. The fix is to widen the class to include the reserved words (e.g. an alternation `(^|[;&|(){}]|\b(then|else|elif|do)\b)`), add a negative case to `check-gate-buckets-selftest.sh`'s `g18` group asserting `else <primitive>` *is* enumerated, and add the resulting row(s) to the register.

---

## r3

2026-09-03T18:29:55Z → 2026-09-03T18:38:39Z. stderr empty.

I reviewed the guard, the register, the selftest, and the corpus files it enumerates. I could not execute the guard in this session (bash invocation is gated), so the enumerator's behaviour was verified by replaying its exact `grep` recipe against each corpus file.

## Acceptance criteria

| AC | Score | Note |
| --- | --- | --- |
| AC-1 | unsatisfied | mechanically enforced, but the `operator-override.sh::envfail` row's `why` is false for the sites it covers (blocker 1) |
| AC-2 | satisfied | g2/g3/g4/g5 red independently; `--list` checks nothing (g14) |
| AC-3 | unsatisfied | every *primitive* is named, but a real command position is silently dropped (blocker 2) |
| AC-4 | satisfied | per-row covered-site count printed; zero-hit reds, split drift vs. outlived |
| AC-5 | satisfied | both directions cased; `OVERRIDE_GATES` read from `operator-override.sh:182` at run time |
| AC-6 | satisfied | `spec-open-region` wiring verified live at `lean-gate.sh:3064`; `unwired — <reason>` form accepted |
| AC-7 | satisfied | `.github/workflows/ci.yml:162` sits in the same always-on job as `check-lockstep-pairs.sh` / `check-eval-model-identity.sh`, not `pr-gates` |
| AC-8 | unsatisfied | the exclusion in blocker 2 is unstated, and the header asserts the opposite |
| AC-9 | satisfied | `gates-signal` added, register pointer added, no enforcement restated |
| AC-10 | satisfied | no corpus file edited; `check-fail-open-shapes.sh` needs no new row (every new `| grep -q` is a `printf` producer, which `VAR_PRODUCER` excludes); `Guard-mass:` trailer present on 16ae844a |

## Warnings

1. **`exit "$violations"` wraps at 256** (`scripts/check-gate-buckets.sh:300`). The precedent `check-fail-open-shapes.sh` uses the same doctor convention over ~26 sites, where the collision is unreachable. Here the denominator is 305 sites against 156 rows, so a register edit that leaves exactly 256 violations exits 0 and CI reads it as clean. Low probability, but it is a fail-open in a guard, which is a shape this repo guards elsewhere. `exit $(( violations > 0 ? 1 : 0 ))`, or clamp, would close it.

2. **`check-lean-chain.sh:457` is buckets-as-environment by the same class-row looseness.** `envfail "the evidence payload returned no applicability verdict — refusing to guess"` is a fail-closed-on-unknown; every comparable site in the register (`build-inflight-unreadable`, `staleness-unreadable`, `infra-unreadable`, the `ticket_refuse` unreadable-tracker arms) is dispositioned `gates-signal`. The `scripts/check-lean-chain.sh::envfail` class row calls it "environment refusal". Milder than blocker 1 — the site genuinely cannot be evaluated — but it shows the same cost of one anchor per class.

3. **AC-5's two directions are not independent** (`check-gate-buckets.sh:195` and `:198`). Direction 2 can only fire when direction 1 has already fired, since any `$ryield` in `GATE_VOCAB` is by definition not `-`. One register edit therefore produces two violations. The selftest passes only because g7 and g8 match on message text, not on count.

4. **Comment cross-references are off.** `check-gate-buckets.sh:234` says the all-comment-register hazard is "(g21) is the case"; that case is g22, and g21 is the empty-corpus case. The selftest header says "THE NEGATIVE DIRECTION (g17)", but the negative-direction cases are g18a–g18d and g17 is the missing-register case. In a file whose whole argument is that the case list is the contract, the labels have to resolve.

5. **The spec and the register disagree on OR-1's arithmetic.** `docs/plans/second-shift-636-lean.md` OR-1 says "one row per class per file — 5 rows over 132 sites"; `scripts/gate-buckets.tsv:35` says "132 sites, 6 rows" (`orchestrate-lean.sh` splits into `env-` and `usage-`). The register is right; the spec's Open Regions row is stale.

## Nits

- `check-gate-buckets.sh:80` — an unknown flag (`--lst`) falls through `*)` and is silently taken as the repo root, which then fails as "corpus file is missing" rather than as a usage error. The precedent has the same shape, so this is consistency, not regression.
- `check-gate-buckets.sh:161-167` — the `trap` is installed after all three `mktemp`s, so a failure of the second or third leaks the earlier ones.
- `check-gate-buckets-selftest.sh` — g13 captures `rc` and never asserts on it; g22 is defined between g16 and g17, out of numeric order.

## BLOCKERS

1. **`scripts/gate-buckets.tsv:220` — the lane's attendance defenses are registered as `not-a-gate`.** The single `plugins/dev-pipeline/tools/operator-override.sh::envfail` row uses the anchor `envfail ` and therefore disposes of all 24 `envfail` sites in that file, including `cmd_attend`'s `headless) envfail "this process tree is marked headless … Attendance cannot be minted here"` (`operator-override.sh:141`), `resolve_attendance || envfail "refusing to record an override from a headless session … a headless run has no operator to quote"` (`operator-override.sh:298`), and `envfail "LEAN_ATTEND_MODE='…' is not a value this reads … attendance is never self-asserted"` (`operator-override.sh:110`). These are the anti-self-assertion defenses that the entire yield mechanism rests on — the manifesto's `gates-llm` shape, where what is missing is independence rather than attendance. The row's `why` asserts the opposite in as many words: "The gate it guards (whether a record may be written at all) is the attendance check, not this primitive." That is contradicted by `:298`, where `envfail` *is* the attendance check's refusal. Consequence: the one artifact whose purpose is to state which gate is which records the yield mechanism's root defenses as "not a gate / environment refusal"; AC-1's closed `why` enum passes only because the guard checks the class row's opening phrase and never the sites it covers; and because the disposition is class-wide, a later relaxation of `:141` or `:298` lands with the register still green and still calling them not-gates. At minimum `:110`, `:141` and `:298` need their own rows outside the class anchor.

2. **`scripts/check-gate-buckets.sh:109` — the enumerator drops command positions that follow a shell reserved word.** The site regex is `(^|[;&|(){}])[[:space:]]*${p}[[:space:]]`, so a call written as `then …`, `else …`, `do …` or `elif …` on the same line matches no alternative and never enters the denominator. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` — `else envfail "unexpected argument: $1"` — is exactly that shape and is absent from `--list` today (replaying the recipe over all five corpus files yields this as the only live call site missed; `orchestrate-lean.sh:333` and `lean-gate.sh:3987` are the intended argument-position and comment negatives). Two consequences. The header at `:37-39` states the rule as "The primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`", which is false: `else envfail` *is* the start of a command, so AC-8's "a reader can tell an excluded surface from a forgotten one" does not hold. And forward, a refusal added as `else fail_milestone …` or `then ticket_refuse …` joins the lane unclassified with the guard staying green — the precise failure mode #636 was filed against. Fix is to admit the reserved words into the leading alternation (or to declare the exclusion in the header and in AC-8's residual list).

3. **`scripts/check-gate-buckets-selftest.sh:327` and `:333` — the two negative-direction cases assert nothing that can fail.** In the `$OL` fixture (`:88-96`) line 1 is the shebang, line 2 is `terminal() { launch_note terminal "$1 rc=$2"; exit "$2"; }`, line 3 is `envfail() { terminal "$1" 2 "$2"; }`. g18b (`:327`) asserts there is no `$OL::terminal` site at **line 1** — the shebang, which contains no `terminal` under any variant of the recipe. g18d (`:333`) asserts there is no `$OL::envfail` site at **line 3**, but the site regex requires the primitive to be followed by whitespace and line 3 has `envfail(`, so that key can never be emitted there either; the invariant g18d's own `ok` text names — "the exclusion is by the file's whole primitive set, not by the primitive being scanned" — requires asserting no **`$OL::terminal`** site at line 3, which is the one key the narrow per-primitive exclusion would let through. Both cases print `ok` unconditionally. (g18c at `:330` is weaker than it reads for the same reason: the fixture's only `launch_note terminal` sits on a definition line, so the def-exclusion alone satisfies it and the argument-position rule is never exercised.) The underlying behaviours are incidentally covered by g0 and g1/g1c, so the guard is not unguarded — but three assertions in the section the file introduces as "THE NEGATIVE DIRECTION … pins what the recipe must NOT enumerate" report passes for properties they do not test, which is the failure this suite exists to make impossible.

