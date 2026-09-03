# C2-a — ablation arm `R-4`: lines 115–116 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 115–116 deleted** —
unit `R-4`, rule 4, approve on the diff, not the spec's promises; an unmet `AC-n` is a blocker. Registered reach: **in-reach**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/R-4.txt)" \
  | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
      -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
      -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT -u CLAUDE_EFFORT -u CLAUDE_PID \
      -u RUN_ID -u LEAN_RUN_MODEL -u LEAN_ATTEND_MODE \
      claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob" \
        --output-format stream-json --verbose
```

The prompt is the ablated SKILL text, then
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
| r1 | `0` | 428645 B, 419 lines, sha256 `2256eb349b2c5538…` | exit 0 — `COMPLETE` | 1 | 22 Bash,  6 Grep,  7 Read | **0** |
| r2 | `0` | 367879 B, 289 lines, sha256 `c2c0f2ddd1dd51dd…` | exit 0 — `COMPLETE` | 1 | 7 Bash,  13 Grep,  4 Read | **0** |
| r3 | `0` | 456105 B, 423 lines, sha256 `72f3b60512a0242b…` | exit 0 — `COMPLETE` | 1 | 21 Bash,  11 Grep,  12 Read | **0** |
| r4 | `0` | 439411 B, 419 lines, sha256 `29744deee6bf8e3e…` | exit 0 — `COMPLETE` | 1 | 33 Bash,  10 Grep,  6 Read | **0** |
| r5 | `0` | 417644 B, 436 lines, sha256 `59decbd6ce7f1ba9…` | exit 0 — `COMPLETE` | 1 | 19 Bash,  19 Grep,  3 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:46:22Z → 2026-09-03T18:55:28Z. stderr empty.

I could not execute anything in this environment (running repo scripts is blocked here), so everything below is static verification — I re-implemented the enumerator's recipe with the same `grep`/`sed` shapes to check its output against the register by hand. The counts I reproduce (132 `envfail`, 51 `terminal`, 34 `note_violation`, 63 `fail_milestone`, 10 fixture sites) agree with the guard's own `305` and with the selftest's `g1c`/`g14` constants, so I'm confident the recipe I reasoned about is the one that runs.

The design is sound and the guard's internals hold up: the `FILENAME`-not-`FNR == NR` two-file read is correct and `g22` pins it; the distinct-bucket set is counted as it is built rather than re-split; the corpus-existence check is correctly hoisted out of the `$(enumerate)` subshell; the batched awk pass is a genuine improvement and the per-row `grep` only fires on a zero-hit row. AC-2, AC-4, AC-5, AC-6, AC-7 and AC-9 are satisfied as written. My objections are to the **completeness claim** the artifact makes, not to its machinery.

## Nits

1. `scripts/check-gate-buckets.sh:181-185` — the comment says "Pure bash on purpose: this runs once per register row, and a subprocess per row is what the batching below exists to remove," but `$(corpus_prims "$rfile")` is a command substitution, which forks a subshell on every row. The function body is fork-free; the call is not.
2. `scripts/check-gate-buckets.sh:195-200` — AC-5 direction 1 already fires for any non-`gates-process` row with a yield cell other than `-`, so direction 2 can only ever fire alongside it. One register mistake is counted as two violations. Harmless, but the exit code is a count.
3. `scripts/check-gate-buckets.sh:107` — the definition-exclusion regex requires `name()`; a POSIX-style `name () {` (space before the parens) both escapes the exclusion *and* matches the site regex, so a reformatted helper definition would be enumerated as a call site. Not present in the corpus today.
4. `scripts/check-gate-buckets.sh:50` — `*) ROOT="$1"` swallows unknown flags, so `--verbse` becomes a repo root and reports "corpus file is missing" rather than a usage error. Fails closed, reads confusingly.
5. `scripts/check-gate-buckets.sh:165-167` — if the third `mktemp` fails, `envfail` fires before the `trap` is installed and the first two temp files leak.
6. `docs/pipeline-manifesto.md:145` points readers at the register as the statement of "which gate is which", but the register's largest single value, `not-a-gate`, appears nowhere in the manifesto. A reader following the link finds a fourth value the prose never introduced.
7. Two rows with the same key, same bucket and overlapping anchors are silently accepted — AC-1's "exactly one disposition" is enforced as one *bucket*, not one *row*. Defensible, but AC-4's "one row per enumerated site" is not actually checked in that direction.

## Warnings

1. **`exit "$violations"` aliases modulo 256** (`scripts/check-gate-buckets.sh:300`) against a 305-site denominator. The doctor convention is `check-fail-open-shapes.sh`'s precedent, but that guard's denominator is ~26, so it can never reach 256; this one can. A register that rotted into exactly 256 violations exits 0 and CI reads green. Unlikely, but it is a fail-open in a guard whose header argues at length against failing open, and the fix is one line.
2. **The blanket `envfail ` anchors are write-once coverage.** Four rows carry the bare anchor `envfail ` and dispose of 132 sites as `not-a-gate`. OR-1 sanctions this and AC-4's printed count is the stated mitigation — but that count is printed on the *green* path, into a CI log nobody opens when the step passes. Any future `envfail` added to those files is auto-classified with no signal at all. The `terminal` rows are keyed by slug and therefore fail closed on a new slug; the `envfail` rows are the opposite, and the asymmetry isn't noted.
3. **`lean-gate.sh:4412` is dispositioned `not-a-gate` by the blanket row, and it is at least arguable.** The site refuses `verdict` when `CLAUDE_CODE_SESSION_ID` is unset "so its authorship cannot be separated from the build's," and the function header at `:4404-4406` frames it as failing closed on unverifiable authorship — the `gates-llm` rationale verbatim. The counter-reading (an unset env var is an environment fact, exit 2 means nothing was evaluated) is also fair, which is exactly why a blanket anchor covering 57 sites is the wrong instrument here.

## BLOCKERS

1. **The denominator omits live refusal shapes in three of the five corpus files, and the declared residual describes only a forward-looking risk.** `scripts/check-gate-buckets.sh:57-61` states the residual as "a *newly named* refusal helper in a corpus file is not enumerated until it is added to CORPUS", and AC-8 requires that "a reader can tell an excluded surface from a forgotten one." Three surfaces are already outside the enumeration today and read as forgotten:
   - `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` — roughly two dozen `warn "✗ …"` + `return 1` refusals that no declared primitive reaches (30 such sites, ~6 of them inside `fail_milestone`/`block_milestone`/`ticket_refuse`'s own bodies). Among them: `:4421` ("the build progress file records no session id, so authorship separation is unverifiable. Refusing.") and `:2667`/`:2676` (`entry` refusing to start without a live audit ledger, "without a ledger the run is unverifiable at the merge boundary"). These are P10 self-approval and three-record-reconciliation defenses — the `gates-llm` bucket, the one the manifesto says never yields.
   - `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh:1156-1159` — a bare `echo "… ✗ …" >&2; exit 1`, commented in place as "A refusal, never a waiver," using neither `note_violation` nor `envfail`.
   - `plugins/dev-pipeline/tools/operator-override.sh:109-122` — the attendance predicate (`return 1` with `ATTEND_REASON`), plus the record-validation refusals at `:500-521`. The register's own row for this file concedes it: *"The gate it guards (whether a record may be written at all) is the attendance check, not this primitive."* So the file contributes 23 `not-a-gate` rows and zero classified gates, while the one gate that decides whether any yield may be minted at all is unclassified. That is precisely the vacuous coverage the spec's `lean-evidence.sh` rationale says the corpus was chosen to prevent, reproduced one file over.

   Mechanism: the enumerator is a shape scan over a hand-declared primitive set (`CORPUS`, `:91-97`), and a refusal expressed as `warn`/`echo` + non-zero return matches no declared primitive, so it never enters the denominator and no row is owed for it. Consequence: the guard's green line asserts "305 enumerated refusal site(s) … all bucketed", and `docs/pipeline-manifesto.md:145-146` now directs readers to the register as the authoritative answer to "which gate is which" — but the lane's independence and attendance gates are not in it, and nothing reds when one is added or removed. The `✗` marker is a mechanically scannable shape, so "a shape enumerator cannot close this" is not true of it. Either declare the shape (AC-3's own argument: "a file that refuses through five helpers and is scanned for one is 80% unguarded while reading as covered"), or state the exclusion and its size explicitly in the header and AC-8 so the coverage claim is honest about its scope.

2. **`scripts/check-gate-buckets-selftest.sh:294` and `:302` assert on fixture coordinates that cannot match, so both cases pass unconditionally.** The `orchestrate-lean.sh` fixture (`:66-74`) is: line 1 shebang, line 2 `terminal()` definition, line 3 `envfail() { terminal "$1" 2 "$2"; }`, line 5 the `terminal` call, line 6 the `envfail` call.
   - `g18b` checks `$1 == "$OL::terminal" && $2 == 1` — line 1 is the shebang. The definition it claims to pin is on line 2. The assertion cannot fail for any implementation.
   - `g18d` checks `$1 == "$OL::envfail" && $2 == 3` while its label claims to pin the cross-primitive exclusion ("excluded from the TERMINAL enumeration too — the exclusion is by the file's whole primitive set, not by the primitive being scanned"). Testing that claim requires key `$OL::terminal` at line 3. As keyed it tests the same-name exclusion — which is itself unreachable, because the site regex requires whitespace after the primitive and `envfail(` is followed by `(`, so `envfail`'s own definition line is never an `envfail` site with or without the `defs` filter.

   Mechanism: both awk probes match on a `(key, lineno)` pair that no correct *or* incorrect implementation produces, so neither can red. Consequence: the section headed "what the recipe must NOT enumerate" records coverage of the `defs` exclusion that does not exist, and AC-3's distinctive clause — exclusion by the file's whole declared primitive set — has no case naming it. The underlying behavior is still caught indirectly (narrowing `defs` to the scanned primitive makes fixture line 3 an unclassified `OL::terminal` site, which reds `g1`), so no mutant currently survives; the defect is the false record, in a suite whose immediately preceding commit is "kill the gate-bucket guard's surviving mutants" and which a future maintainer will read as licence to narrow the exclusion. Fix is `$2 == 2` in `g18b` and `k="$OL::terminal"` in `g18d`.

---

## r2

2026-09-03T18:48:34Z → 2026-09-03T18:54:55Z. stderr empty.

I reviewed the guard, the register, the selftest and the CI wiring, and checked the enumeration recipe against the real corpus files.

## What's good

The design holds up: the denominator is the script's own `--list` output rather than a count, both directions of rot red independently, and the AC-1 "exactly one disposition" arm (AMBIG) is a genuinely non-obvious addition that the spec didn't ask for by name. The `FILENAME == ENVIRON[...]` note at `scripts/check-gate-buckets.sh:231` is a real bug avoided — `FNR == NR` would have loaded the sites file's first record as a register row against an empty rows file, and g22 cases it. Anchors flow through files and `ENVIRON`, never `awk -v`, so backslashes survive. `in_set` quotes `"$1"` inside the case pattern, so a glob metacharacter in a yield cell can't match spuriously. AC-10's obligations are paid (all three `Guard-mass:` trailers present, no corpus file edited).

## Warnings

1. **`exit "$violations"` wraps at 256** (`scripts/check-gate-buckets.sh:300`). This copies `check-fail-open-shapes.sh:181`, but that guard enumerates tens of sites while this one enumerates 305. A tree state producing exactly 256 (or 512) violations exits 0 and the CI step at `.github/workflows/ci.yml:162` reads green. The precedent guards were never in range of the wrap; this one is. Consider `exit $(( violations > 250 ? 250 : violations ))` or a plain `exit 1` above a cap.

2. **AC-5 "direction 2" is fully subsumed by direction 1** (`scripts/check-gate-buckets.sh:198`). `GATE_VOCAB` never contains `-`, so any row caught by the `in_set "$ryield" "$GATE_VOCAB"` arm was already caught by `"$ryield" != "-"` at line 195. Both fire, so such a row counts as two violations. g7/g8 read as two independent directions in the selftest, but only one predicate can ever be load-bearing. Defensible as defence-in-depth if direction 1 is later relaxed — worth saying so in the comment rather than letting the suite imply two arms.

3. **Unknown flags become the repo root** (`scripts/check-gate-buckets.sh:80`). `check-gate-buckets.sh --lst` sets `ROOT=--lst` and exits 2 with "corpus file is missing", which is a misleading answer to a typo. `tools/check-sweep-bound.sh:69` is the better in-repo precedent (`die "unknown argument: $1"`).

## Nits

- `IFS="$TAB" read` collapses runs of tabs (tab is IFS-whitespace), so the guard cannot actually distinguish a 5-field row with an empty middle cell from a 4-field row — both land in the same "malformed row" arm. g12b's comment ("the field count is not the check, the field CONTENT is") describes a distinction the code doesn't make. The direction is safe; the comment overstates.
- `docs/plans/second-shift-636-lean.md` OR-1 says "5 rows over 132 sites"; `scripts/gate-buckets.tsv:36` says "132 sites, 6 rows". Six is right (`orchestrate-lean.sh` splits `envfail` into `env-` and `usage-`). The spec doc is stale against the register it specifies.
- The four class-level `envfail` rows each say "132 near-identical rows would add no classification" — 132 is the repo-wide total, not that file's count, so the sentence reads as a per-file claim that is false in each of the four.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator's command-position prefix omits shell keywords, so refusals written after `then`/`else`/`elif`/`do` never enter the denominator.**

   *Mechanism.* The recipe is `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`. A command that starts after a reserved word has neither `^` nor one of `;&|(){}` immediately before it, so it does not match. The header's own self-exclusion list (`scripts/check-gate-buckets.sh:52-54`) states the intended rule as "The primitive must sit at the start of a command", and a primitive after `else` *is* at the start of a command — the implementation contradicts the rule it declares, and the gap is not among the stated exclusions.

   *It is live in the tree.* `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is `      else envfail "unexpected argument: $1"`. That line contains no `;`, `&`, `|`, `(`, `)`, `{` or `}`, and does not begin with `envfail` after leading whitespace, so it is not enumerated. Its sibling at line 416 (`-*)  envfail "unknown option: $1" ;;`) is enumerated only because a `)` precedes it. The true site count is at least 306, not the 305 the feature commit and the guard's verdict line both report.

   *Consequence.* Today this costs nothing semantically — the escaped site is a `not-a-gate` usage error that the class row would have absorbed anyway. Going forward it is silent and unbounded: a gate added as `else fail_milestone 3 "…"`, `then ticket_refuse "…"` or `else note_violation "…"` is never enumerated, never reds as UNCLASSIFIED, and `check-gate-buckets.sh` prints "all bucketed" while an unclassified refusal sits in the lane. That is exactly the failure mode AC-2 and the "denominator as artifact" design exist to prevent, and it is not covered by the residual AC-8 records (which is scoped to *newly named primitives*, not new syntactic positions of already-declared ones).

   *Fix.* Widen the alternation to accept keyword positions, e.g. `(^|[;&|(){}]|[[:space:]](then|else|elif|do))[[:space:]]*${p}[[:space:]]`, restate the exclusion in the header, and add a negative/positive pair to the `negatives` fixture in `scripts/check-gate-buckets-selftest.sh` (it already has the right shape to extend at g18a-d). The existing `lean-gate.sh::envfail` row's anchor is `envfail ` with a trailing space, so it will cover the newly enumerated site and the register stays green without an edit.

---

## r3

2026-09-03T18:49:06Z → 2026-09-03T18:57:56Z. stderr empty.

I reviewed this against the tree (Bash was mostly unavailable, so this is static verification plus targeted searches — I could not execute the guard or its selftest).

The design is sound and the register's per-row `why` reasoning is genuinely good — I spot-checked the `gates-process` / `spec-open-region` row against `lean-gate.sh:3444-3451` and it describes `check_pause_and_ask` accurately. The `gates-signal` bucket is well-argued and the manifesto edit (AC-9) is correctly scoped to the principle. CI placement (AC-7) is right: the step lands in the always-on guard job beside `check-lockstep-pairs.sh` and `capability-parity-check.sh`, not `pr-gates`. `check-fail-open-shapes.sh` should stay green with no new row — every `| grep -q` in the new selftest is a `printf` producer, which its `VAR_PRODUCER` arm already excludes.

My blockers are all one theme: the enumeration is narrower than the completeness claim built on top of it.

## Warnings

1. **The ambiguity arm compares buckets only, not dispositions.** `scripts/check-gate-buckets.sh:247` builds the distinct set from `rb[i]` alone. Two `gates-process` rows covering the same site with different yield cells (`spec-open-region` vs `unwired — …`) agree on bucket and pass silently, so AC-1's "exactly one disposition" is enforced on half the disposition. Today each corpus file has at most one `gates-process` row, so nothing is affected.

2. **AC-5's "direction 2" can never fire on its own.** `check-gate-buckets.sh:198` is a strict subset of the check at `:195` — an `OVERRIDE_GATES` value is never the literal `-`, so any row tripping the second also trips the first. It's a message refinement, not an independent arm. `(g8)` passes because both messages land in the captured output; the selftest's framing of "both directions cased" reads stronger than what is actually independently guarded.

3. **The enumerator emits raw source text into a TSV without escaping.** `enumerate()` pastes the matched line into field 3; `awk -F"$TAB"` then truncates `$3` at the first embedded tab, so a tab-indented refusal line would match no anchor and red as a spurious `UNCLASSIFIED`. It fails closed, and none of the five corpus files contains a tab today — but the failure is a false accusation rather than a real one, which is the kind of red that gets baselined.

## Nits

- `check-gate-buckets.sh:297` uses BRE alternation `'^[[:space:]]*\(#\|$\)'`. Every sibling in the repo writes this as `grep -vE '^[[:space:]]*(#|$)'`; this is the only BRE-alternation grep among the guards.
- Unknown flags fall through `*) ROOT="$1"` — `check-gate-buckets.sh --lst` is read as a repo root and reports "corpus file is missing" rather than a usage error. Mildly ironic in a script that classifies usage errors.
- The `EXIT` trap at `:167` is installed after all three `mktemp` calls, so a failure on the second or third leaks the first.
- `in_set()` matches via `case`, so cell values are glob patterns. A key or yield cell containing `*`/`[` matches more than it should. Every path fails closed today.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the command-position regex omits shell keywords, contradicting the recipe the header declares.** The header (`:44-47`) states the rule as "the primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`", but `then`, `else`, `elif` and `do` are also command-start positions and are not in the class. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` — `else envfail "unexpected argument: $1"` — is a live call to a *declared* primitive that the enumerator cannot see, so it is absent from the denominator that `--list` defines as authoritative. Today the missed site is a usage error, so nothing is misclassified; the consequence is forward-looking and exactly the invariant the slice exists to establish: a future refusal written as `else fail_milestone 1 "…"` or `then ticket_refuse "…"` — ordinary shell, in a file already in `CORPUS`, using a primitive already declared — joins the lane unclassified with the guard green and no row owed. This is a hole in the enumeration, not a stated self-exclusion, so AC-8's "a reader can tell an excluded surface from a forgotten one" does not hold for it either.

2. **`scripts/check-gate-buckets.sh:93-97` — refusals that do not route through a named primitive are invisible to the enumerator, and several of them are real gates that are unclassified today.** `CORPUS` scans only for named helpers, so any refusal written as a bare `exit N` is structurally unreachable. In the corpus as it stands:
   - `lean-gate.sh:5373` — `require_entry_attested`'s refusal ("this run has no entry attestation … a run with no ledger is unreconcilable at the merge boundary (#416)"). This is a first-class lane gate; `review-lean`'s own checklist step 4 treats it as hand-back-worthy.
   - `lean-gate.sh:2591` (`exit 7`) and `:2594` (`exit 2`) — `require_ticket_still_open`'s "THE TICKET CLOSED UNDER THIS RUN" and its fail-closed unreadable-tracker arm, the same subject matter the register classifies under `ticket_refuse` when it happens to be routed through that helper.
   - `lean-gate.sh:5333` (`exit 9`), `check-lean-chain.sh:568` (failed comment fetch), `:879` (the boundary's violation verdict), plus usage refusals at `check-lean-chain.sh:189`, `lean-evidence.sh:160` and `operator-override.sh:540`.

   Three consequences. First, the completeness claim is false *now*, not prospectively: gates that are already in the lane carry no bucket and nothing reds. Second, the header's residual statement (`:56-60`) names "a *newly named* refusal helper" as the one thing a shape enumerator cannot close — but these are neither new nor named, so AC-8's requirement that an excluded surface be distinguishable from a forgotten one is unsatisfied, and the plan's Out-of-scope list does not exclude them either. Third, `scripts/gate-buckets.tsv` states a specific falsehood: the `operator-override.sh::envfail` row asserts "`envfail` is its single refusal primitive and covers both halves — a malformed invocation and an unusable environment — at exit 2", which `operator-override.sh:540` (`usage >&2; exit 2`) contradicts. Relatedly, the reasoning that makes the five `envfail` class rows `not-a-gate` — "the exit-2 contract is what makes every site in it true" — is itself falsified by `lean-gate.sh:5373`, an exit-2 refusal that is unambiguously a gate.

---

## r4

2026-09-03T18:56:37Z → 2026-09-03T19:04:57Z. stderr empty.

Confirmed. Writing up the review.

---

## Summary

This is a well-constructed slice. The design — an enumerator whose `--list` output *is* the denominator, checked against a register that must cover it exactly — is the right posture, it copies an established in-repo precedent (`check-fail-open-shapes.sh`), and the four independent red arms (unclassified / anchor drift / outlived row / disagreeing rows) are each cased in the selftest. I verified the load-bearing classification claims against the tree rather than taking the `why` cells at their word:

- All three `gates-process` rows are correct and their anchors are unique. `lean-gate.sh::fail_milestone` / `fail_milestone 1 "$reason"` is `check_pause_and_ask` (`lean-gate.sh:3451`), and its claimed `spec-open-region` yield really is wired at `lean-gate.sh:3064`. `terminal preflight-rejected-resumable 3` is genuinely wired to `intake-unqueued` at `orchestrate-lean.sh:547`, and the resumable arm really does exit before the `preflight-rejected 2` line (`orchestrate-lean.sh:630-634`), so that row's `why` is honest.
- No duplicate `(key, anchor)` pairs; 156 rows (20 llm / 121 signal / 3 process / 12 not-a-gate) reconcile with the commit message's counts.
- AC-10's obligations hold: the new script introduces no `| grep -q` fail-open shape needing a `fail-open-sites.tsv` row (the selftest's `printf … | grep -q` uses are already excluded by `VAR_PRODUCER`), no corpus file is edited, and all three commits carry `Guard-mass:` trailers.
- AC-7 is satisfied — the step lands in `lint-and-selftests` alongside `check-lockstep-pairs.sh` and `check-eval-model-identity.sh`, not `pr-gates`.

One defect in the enumerator falsifies the guard's central claim, and it is live in the tree today.

## Warnings

**W1 — two of the four "negative direction" assertions (g18b, g18d) cannot fail.**
`check-gate-buckets-selftest.sh:~330`. In the `$OL` fixture, `terminal()` is defined on **line 2** and `envfail()` on line 3, but g18b asserts there is no `$OL::terminal` site at **line 1** (the shebang) — trivially true regardless of the definition exclusion. g18d is worse: its message says "envfail()'s one-line definition is excluded from the **TERMINAL** enumeration too", which is AC-3's subtlest requirement (exclusion by the file's *whole* primitive set), but the assertion uses `k="$OL::envfail"`. Since `envfail(` has no trailing space, an `$OL::envfail` site at line 3 can never be enumerated in the first place. To test what it claims, `k` must be `$OL::terminal`. The invariant is not actually uncovered — mutating `defs` to only exclude the scanned primitive would make `orchestrate-lean.sh:336` enumerate as `OL::terminal` and turn g0/g1 red — but the block that the header calls out as load-bearing ("an enumerator that reds on those gets an exclusion baselined into it within a week") is two-for-four vacuous, and a reader auditing coverage would be misled.

**W2 — refusals that use no primitive at all are outside the denominator and outside the stated residual.**
`lean-evidence.sh:160` and `check-lean-chain.sh:189` are usage refusals written as `echo …; exit 2` with no helper, and `check-lean-chain.sh:879` is a bare `exit 1`. The header's stated residual covers only "a NEWLY NAMED refusal *helper* … is not enumerated until it is added to CORPUS", which does not describe these. They would all classify `not-a-gate` today, so nothing is misfiled — but AC-8's test is "a reader can tell an excluded surface from a forgotten one", and these are currently indistinguishable from forgotten.

**W3 — `exit "$violations"` truncates mod 256 over a 305-site denominator.**
`check-gate-buckets.sh:300`. This is the repo's doctor convention and `check-fail-open-shapes.sh` does the same, but that guard's denominator is small; this one enumerates 305 sites, so exactly 256 violations is a reachable state that exits 0 and reads as a clean pass. Cheap fix: `exit $(( violations > 250 ? 250 : violations ))`, or clamp to 1.

## Nits

- `--list` is documented as "Checks nothing" (`check-gate-buckets.sh:67`), but the corpus-presence loop at `:121-124` runs before the `LIST_ONLY` branch, so `--list` still `envfail`s on a missing corpus file. The behavior is right; the doc line overstates.
- `*) ROOT="$1"; shift ;;` silently accepts several positional arguments, last one winning. Inherited from the precedent, but a stray argument becomes a silently wrong repo root.
- The awk pass splits site text on `-F"$TAB"`, so a corpus line containing a literal tab would truncate `$3` and could produce a spurious `ANCHOR DRIFT`. No corpus line does today; worth a word in the comment at `:230`.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator drops refusal sites in keyword command position, and one exists in the tree today.**

   The recipe is `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`. It admits a primitive only at line start or after `;&|(){}`. A command that begins after a shell *keyword* — `else`, `then`, `do`, `elif` — matches neither arm, because the character preceding the whitespace run is a letter.

   `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is exactly that shape:

   ```
         else envfail "unexpected argument: $1"
   ```

   I confirmed it is dropped: `grep -nE "(^|[;&|(){}])[[:space:]]*envfail[[:space:]]" lean-gate.sh | grep -c "^420:"` returns `0`. A sweep of all five corpus files for keyword-preceded calls finds this as the only live instance (the two other hits are prose in comments).

   The consequence is not the misclassification of line 420 — as an `envfail` it would land in the `not-a-gate` class row and change no disposition. The consequence is that the guard's stated invariant is false. The header asserts "`--list` prints the enumeration, that output IS the denominator by definition", and AC-8 requires that every self-exclusion be recorded so "a reader can tell an excluded surface from a forgotten one." This exclusion is neither recorded nor intentional: the header's third bullet describes the command-position rule as being about **argument** position, citing `launch_note terminal "…"` as the case it exists to exclude. Nothing tells a reader that `else fail_milestone 1 "…"` or `then ticket_refuse "…"` would be invisible. Because the register is checked *against* this enumeration, such a site produces no `UNCLASSIFIED` red, no drift, and no coverage-count anomaly — it simply does not exist as far as the guard is concerned, which is precisely the silent-coverage-rot failure mode #636 was filed against.

   The fixture in `check-gate-buckets-selftest.sh` contains no keyword-position call, so no assertion pins this either way.

   Fix: extend the leading context to admit keywords, e.g. `(^|[;&|(){}]|[[:space:]](then|else|elif|do))[[:space:]]*${p}[[:space:]]`, add a fixture line in `new_fixture` carrying `else envfail "…"` plus a positive assertion that it *is* enumerated, and re-anchor `lean-gate.sh::envfail`'s coverage count. If instead the keyword form is judged genuinely out of scope, then it must be stated as a fourth self-exclusion in the header per AC-8 — but note that leaves a live gate-shaped hole that no arm of the guard can ever report.

---

## r5

2026-09-03T18:56:39Z → 2026-09-03T19:06:04Z. stderr empty.

## Verification note

Command execution was blocked in this session beyond `git`/`sed`/`grep`, so I could not run `check-gate-buckets.sh`, its selftest, or `check-fail-open-shapes.sh`. Everything below is static analysis against the tree at the PR head; I have not confirmed the guard is green on the real register, only that nothing I read predicts it is red.

## AC scoring against `docs/plans/second-shift-636-lean.md`

| AC | Score |
| --- | --- |
| AC-1 closed enum + `not-a-gate` why | satisfied (`check-gate-buckets.sh:189`, `:208`) |
| AC-2 three independent reds + `--list` | satisfied as *checks*; the denominator they check against is incomplete — see blocker 1 |
| AC-3 every primitive per file, exclusions stated | **unsatisfied** — the primitives are all named, but one exclusion is unstated (blocker 1) |
| AC-4 one row per site, count printed | satisfied (`:288-292`) |
| AC-5 register-internal safety arm | satisfied (`:195-200`), though direction 2 is subsumed by direction 1 — see warnings |
| AC-6 yield-cell form | satisfied (`:202-206`) |
| AC-7 always-on guard job, not `pr-gates` | satisfied — verified in `.github/workflows/ci.yml`, same job as `check-lockstep-pairs.sh` / `capability-parity-check.sh` |
| AC-8 residuals + self-exclusions legible | **unsatisfied** (blocker 1) |
| AC-9 manifesto gains `gates-signal` + pointer | satisfied; no lockstep twin of the bucket list exists (checked all 10 files mentioning `gates-llm`) |
| AC-10 obligations | satisfied on inspection — `Changelog:`/`Guard-mass:` trailers on all three commits, no corpus file edited, no new `producer \| grep -q` shape in either new script (the selftest's are `printf … \| grep -q`, which `check-fail-open-shapes.sh` excludes as VAR_PRODUCER), no new `lean-gate.sh` call site |

## Nits

1. `scripts/check-gate-buckets.sh:234` cites “(g21) is the case” for the `FNR == NR` hazard; the case that covers it is **(g22)**. (g21) is the empty-denominator case. The commit message gets this right; the code comment does not.
2. `scripts/check-gate-buckets-selftest.sh:16` — the header calls the negative direction “(g17)”, but the negative cases are `g18a`–`g18d`; `g17` is the missing-register case. The case ids also run out of order in the file (`g22` is defined above `g17`).
3. `docs/plans/second-shift-636-lean.md` D-2 says the `path::name` key is adopted from `docs/prose-blocker-triage.tsv` “unchanged”. There `name` is an enforcer/arm name (`scripts/check-lean-chain.sh::verdict-record`, row `pb-94ee597a`); here it is a shell function name. Same syntax, different namespace — worth a word, since a reader now sees two `check-lean-chain.sh::…` keys that do not mean the same kind of thing.
4. `check-gate-buckets.sh:198` can never fire without `:195` also firing (any `$ryield` in `GATE_VOCAB` is by definition not `-`), so an AC-5 direction-2 violation is always reported twice and counted twice toward the exit code.
5. `exit "$violations"` (`:300`) collides with the header's `2 = environment refusal` at exactly two violations, and wraps mod 256. Both are the repo's existing doctor convention (`check-fail-open-shapes.sh:181`, `stack-generality-lint.sh:100`), but this is the first guard with a ~305-site ceiling, so the wrap is reachable here in a way it is not there.

## Warnings

1. **The `envfail` blanket rows make the headline promise conditional.** Four of the six `envfail` rows anchor on the bare string `envfail ` (`gate-buckets.tsv` rows for `lean-gate.sh`, `lean-evidence.sh`, `operator-override.sh`, `check-lean-chain.sh`). Any future `envfail` call in those files is absorbed as `not-a-gate` without reding — including one that is genuinely a gate. `orchestrate-lean.sh` is the counter-example done right: its slug-prefixed anchors (`envfail env-`, `envfail usage-`) *would* red on a new prefix. OR-1 records this as a taken default and AC-4's printed count is the stated mitigation, but that mitigation is 156 lines of coverage output in a green CI log — nobody reads it. Consider slug- or message-prefix anchors for the other four, matching the `orchestrate-lean.sh` treatment.

2. **The “one-cell edit” claim is stronger than the enforcement.** `check-gate-buckets-selftest.sh:12-16` and the guard header both frame AC-5 as what stops “a future edit wiring a red test lane to an operator waiver”. What the guard actually refuses is a yield cell on a non-`gates-process` row. Rewriting the lane-red row (`fail_milestone 3 "$key failed (rc=$rc)"…`) from `gates-signal` to `gates-process` with yield `unwired — <reason>` passes every arm — and that is also a one-cell edit. No mechanical test can decide bucket *correctness*, which is fine; the prose should say so rather than claim the arm closes the hole.

3. **(g0) couples the selftest sweep to production register drift.** `check-gate-buckets-selftest.sh:117-124` runs the guard against the real repo. The `ci.yml` step already does that, and the comment above the `capability-parity` step states the opposite convention explicitly (“the paired selftest is glob-discovered but only proves the guard works, never runs it against the real register”). The consequence is that adding an unregistered refusal site to `lean-gate.sh` reds `check-gate-buckets-selftest.sh` in the sweep as well as the guard step, attributing a register-drift failure to a test suite. Deliberate or not, it diverges from a convention this repo wrote down.

4. **`(g18c)` is masked.** It asserts the position rule keeps `launch_note terminal "…"` out of the enumeration, but that line (`OL` fixture line 2) also starts with `terminal()`, so the definition exclusion removes it independently. Weakening the position anchor would leave (g18c) green. It is caught by (g1) via a different fixture line, but not by the case that names it.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the command-position recipe misses a refusal call preceded by a shell keyword, and one such site is live in the tree today.** The enumeration regex is `(^|[;&|(){}])[[:space:]]*${p}[[:space:]]`: the primitive must follow line-start or one of `; & | ( ) { }`. A call after `then`, `else`, `do` or `elif` matches none of those. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` — `else envfail "unexpected argument: $1"` — is a live refusal site that `--list` does not emit, so it is not in the denominator and no row disposes of it. Two consequences. First, the merged state contradicts the CI step's own name and the commit subject: a lean-lane refusal site exists that declares no yield bucket, and the guard is silent. Second, and worse, the hole generalizes to shapes that *do* matter — a future `then fail_milestone 3 "…"` or `else ticket_refuse "…"` is invisible to the enumerator, so it never reds as UNCLASSIFIED, which is precisely the rot the denominator-as-artifact design exists to prevent (`:28-34`). AC-8 requires that “a reader can tell an excluded surface from a forgotten one”; this exclusion is not in the header's list, and the header's framing (`:52-54`, “non-command positions… the primitive must sit at the start of a command”) actively asserts the opposite — `else envfail "…"` *is* the start of a command. Fix by extending the alternation (`then|else|elif|do|!` in addition to the punctuation), or by matching on a word boundary and leaning on the existing comment/definition/argument exclusions, and re-run `--list` to pick up the newly enumerated site. Either way the register needs the resulting count re-checked, and the header's exclusion list should say what the final rule is.

2. **`scripts/check-gate-buckets-selftest.sh:327` — (g18b) asserts a condition that can never be false, and (g18d) at `:333` does not test the mechanism its message names.** (g18b) searches `--list` output for a record with key `orchestrate-lean.sh::terminal` at **line 1**. Line 1 of the `OL` fixture is the shebang (`:77`); `terminal()`'s definition is line 2 (`:78`). The assertion passes unconditionally — it would pass with the definition exclusion deleted outright, and it would pass with the enumerator returning nothing at all. It therefore reports coverage of “a helper's definition line is not a site” that it does not have. (g18d) at `:333` compounds this: its message claims to pin the whole-primitive-set exclusion (“the exclusion is by the file's whole primitive set, not by the primitive being scanned”), but it queries key `OL::envfail` at line 3 — which is `envfail`'s *own* definition, i.e. the trivial same-primitive case. The only line in the fixture where the whole-set rule is load-bearing is `OL::terminal` at line 3 (`envfail() { terminal "$1" 2 "$2"; }`, `:79`), and no named assertion covers it. The mutant is still killed — reducing `defs` to the scanned primitive alone makes that line an unclassified `OL::terminal` site and (g1) reds — so the risk here is misleading coverage rather than an unguarded mutation, but in a suite whose stated invariant is that every disagreement reds *independently*, two of the four negative-direction cases not testing what they announce has to be fixed before it is baselined in. Fix: point (g18b) at line 2 with a key that the position rule does not already exclude, and re-key (g18d) to `$OL::terminal` at line 3.

