# C2-a — the built-in `/code-review` on PR #654

The arm-2a challenger session for sample **C2-a**, run 2026-09-03 against the pinned clone. Registered at [`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §B; scored against the frozen C2 rule at [`docs/skill-ablation-pre-registration.md`](../../../skill-ablation-pre-registration.md):146-161. Everything below the rule is this session's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2-a-654
printf '%s' '/code-review max pr-654' | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE \
  -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID \
  -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT \
  -u CLAUDE_EFFORT -u CLAUDE_PID \
  claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob,Bash" \
    --output-format stream-json --verbose
```

Byte-identical to the registered form. `RUN_ID`, `LEAN_RUN_MODEL` and `LEAN_ATTEND_MODE` were additionally absent from the launching environment, so no lane variable leaked into the challenger; the registered `env -u` list itself is unchanged.

## Apparatus

| fact | value |
| --- | --- |
| pinned base (`main`) | `dfd68a47402acb9f77530e3e086dd42760749709` |
| pinned head (`pr-654`) | `cfba10220fced059a2fd3032b58d7075ffd538f4` |
| pre-run assertion | both `git rev-parse` tests passed; clone tree clean |
| `plugins/` in the working tree | present (spec D-1) |
| exit code | `0` |
| stderr | empty |
| wall clock | 2026-09-03T10:34:37Z → 2026-09-03T11:00:04Z |
| capture | 4,313,652 bytes, 1,766 lines, sha256 `256d8d7ff091c9e9…` |
| `tools/classify-capture.sh` | exit 0 — [classify-capture] COMPLETE — /private/tmp/c2-a-654.stream.json ran to completion successfully (subtype=success, is_error=false). |
| parent `tool_use` | `Bash` 4 |
| subagent `tool_use` | `Bash` 345, `Grep` 2, `Read` 26 |
| `result` events | 2 |
| tool calls touching `review-lean` | 1 |

Only an exit-0 capture is scored (§B *A capture must be proven complete before it is scored*); this one classified `COMPLETE`, so its findings were read out of it.

---

## Assistant text — `result` event 1 of 2

Agent results never came back through the harness, so I completed all angles and verification myself — every finding below is confirmed by execution, not inspection. Repo root: `/private/tmp/c2-a-654`.

```json
[
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 300,
    "summary": "`exit \"$violations\"` truncates mod 256, so a violation count that is a multiple of 256 makes a fully-broken register exit 0 and CI green.",
    "failure_scenario": "PROVEN. Drift 89 register anchors (`f[2] += 'ZZZdrift'`) in scripts/gate-buckets.tsv — each yields 1 UNCLASSIFIED site + 1 ANCHOR DRIFT row. The guard prints 256 `[gate-buckets] ✗` lines and `exit 256` -> rc **0**. ci.yml's `run: bash scripts/check-gate-buckets.sh` passes. Measured ladder: 88 rows -> 254 violations/rc 254; **89 rows -> 256 violations/rc 0**; 90 -> 258/rc 2. rc 2 is a second collision: line 69 defines exit 2 as \"environment refusal\". With a 305-site denominator and up to 2 violations per site, 256 and 512 are both inside range. Fix: `exit $(( violations > 255 ? 1 : violations ))` or a fixed non-zero code."
  },
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 241,
    "summary": "A row's anchor is an unconstrained substring with no minimum specificity and no expected-count check, so a brand-new unclassified refusal site is silently absorbed and never reds.",
    "failure_scenario": "PROVEN twice. (a) Inserting `[ -n \"$BRAND_NEW\" ] || envfail \"a brand new refusal nobody classified\"` into lean-gate.sh leaves the guard GREEN: `✓ 306 enumerated refusal site(s) ... all bucketed`, because the blanket row `lean-gate.sh::envfail  not-a-gate  «envfail »` (gate-buckets.tsv:75) claims it. 132 of 305 live sites (43%) are already covered by 6 such rows. (b) Worse: rewriting the register to 13 rows whose anchor is a single space `\" \"` still prints `✓ 305 enumerated refusal site(s) across 5 file(s), all bucketed by 13 register row(s)` and exits 0. `index($3, ra[i])` accepts any non-empty anchor, and the AMBIG arm at line 250 only fires when buckets DISAGREE, so one blanket row per (file, primitive) pair satisfies the whole contract. This contradicts the guard's stated purpose (header lines 8-10) and the new manifesto claim at docs/pipeline-manifesto.md:145 that \"an unclassified one fails CI\". The printed count at line 288 is a display, not a gate — nothing compares it to a declared expectation."
  },
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 109,
    "summary": "The command-position class `(^|[;&|(){}])` omits shell keywords, so a refusal invoked after `then`/`else`/`do`/`elif` on the same line is missing from the denominator.",
    "failure_scenario": "PROVEN. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is `      else envfail \"unexpected argument: $1\"` — a live refusal site. `bash scripts/check-gate-buckets.sh --list | awk -F'\\t' '$1 ~ /lean-gate.sh::envfail/ && $2==420'` returns nothing, yet the guard reports `✓ 305 enumerated refusal site(s) ... all bucketed`. Header lines 28-31 assert `--list`'s output IS the denominator by definition, so an invisible site is an unfalsifiable completeness claim. A full cross-scan of all 5 corpus files against the enumeration found this as the only live miss today, but the class is open: any future `then fail_milestone …` / `do note_violation …` is equally invisible. Fix: add `!` and word-boundary keyword handling, e.g. `(^|[;&|(){}]|\\b(then|else|elif|do)[[:space:]])`."
  },
  {
    "file": "scripts/check-gate-buckets-selftest.sh",
    "line": 333,
    "summary": "Case (g18d) checks the wrong enumeration key, so it passes unconditionally and AC-3's \"exclusion by the file's WHOLE primitive set\" behavior has no test at all.",
    "failure_scenario": "PROVEN by mutant. g18d claims to guard that `envfail() { terminal \"$1\" 2 \"$2\"; }` (fixture $OL line 3) is not enumerated as a **terminal** site. It asserts `-v k=\"$OL::envfail\" '$1 == k && $2 == 3'` — but line 3 is never enumerated under the `envfail` key in ANY version, since envfail's own definition is excluded by its own name. I narrowed `defs` (line 107) to only the primitive being scanned — the exact mutation AC-3 and the header at lines 48-51 exist to forbid — and confirmed `--list` then emits `orchestrate-lean.sh::terminal\\t3\\tenvfail() { terminal \"$1\" 2 \"$2\"; }`, while **g18d still reports `ok`**. The assertion should read `-v k=\"$OL::terminal\"`. As written it duplicates g18b's coverage under a key that can never match."
  },
  {
    "file": "scripts/check-gate-buckets-selftest.sh",
    "line": 26,
    "summary": "The new selftest runs 13-18s but the PR adds no row to `tools/selftest-suite-timings.tsv`, whose threshold is 9s — the repo's own sweep already warns about it.",
    "failure_scenario": "PROVEN by the repo's tooling. `bash tools/mutation-sweep.sh --mode pr --base main` emits: `WARN: slow-list drift: scripts/check-gate-buckets-selftest.sh measured 13s (>= 5s) but tools/selftest-suite-timings.tsv does not record it at or above that bar, so its guard is still swept in the PR lane. Add or update the row by ordinary PR.` Local wall clock: 18.48s / 15.65s (bash 5) on an M-series Mac; ubuntu runners are slower. Consequences named by the consumers themselves: (1) `tools/mutation-sweep.sh:1083` `is_slow()` returns false, so every mutant of this guard runs a 13s killer in the PR lane; (2) `tools/run-selftests.sh` (9s threshold) does not defer it; (3) `tools/check-sweep-bound.sh` ratchets the un-deferred serial sum at `baseline-seconds 106` + `allowance-percent 20` = 127s, and an untabled 13s suite takes it to ~119s — 62% of the remaining headroom — which is verbatim the failure that file's header exists for: \"A new or grown suite that stays untabled walks the un-deferred sum back toward the reap; past it, milestone 3 is not slow but UNPASSABLE.\" The table lists suites down to 5s, so 13s plainly belongs there."
  },
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 185,
    "summary": "`$(corpus_prims \"$rfile\")` forks a subshell per register row — 156 forks and 222ms — which is exactly the \"subprocess per row\" the comment two lines above claims was removed.",
    "failure_scenario": "The comment at lines 181-184 reads \"Pure bash on purpose: this runs once per register row, and a subprocess per row is what the batching below exists to remove.\" But `$(...)` is command substitution: bash forks for every one. Measured: 156 substitutions of an identical `corpus_prims` = **222 ms**, against a full-guard runtime of 843 ms — 26% of the guard, and 44% of everything after enumeration. The perf commit cfba1022 claims to have eliminated \"~460 spawns\" (156 rows + 305 sites); 156 of them are still there, in the loop the comment points at. Cheaper and fork-free: build one `PAIRS=\"$f::$p …\"` string before the loop from CORPUS and call the existing `in_set \"$rfile::$rprim\" \"$PAIRS\"`."
  },
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 220,
    "summary": "The perf commit's justifying comment is factually wrong: the paired selftest is still 2.6-3.7x over the mutation sweep's 5s bar it claims to have cleared.",
    "failure_scenario": "The comment states \"at 3.5s the paired selftest crossed the mutation sweep's 5s slow bar, which is what decides whether the PR lane grades this guard at all.\" Measured: the selftest at `cfba1022~1` was 20.72s; at HEAD it is 15.65-18.48s locally and 13s under the sweep's own timing. The bar times the SELFTEST, not the guard (1.1s), so the batching moved 20.7s -> ~16s and never approached 5s. The stated consequence is also inverted: because the suite has no timings row, `is_slow()` is false and the PR lane grades the guard anyway. Either correct the comment or record the row (finding above)."
  },
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 126,
    "summary": "`SITES=\"$(enumerate)\"` discards every grep's exit status, so an existing-but-unreadable corpus file yields a silently partial denominator — the exact fail-open the header at 117-120 claims to have closed.",
    "failure_scenario": "The precheck at lines 121-124 only tests `[[ -f \"$ROOT/$_cf\" ]]`. A corpus file that exists but is not readable (mode 000, a restrictive umask in a container, a stale ACL) passes that test; `grep` then exits 2 to stderr and `enumerate()`'s pipeline status is thrown away by the command substitution. `SITES` silently loses that file's sites and the run continues against a partial denominator. `grep`'s exit 1 (\"no matches\", normal) and exit 2 (\"could not read\") are indistinguishable here. The header at 117-120 asserts this class is handled: \"leaving SITES holding a partial denominator and the run continuing against it, which is failing open in the very act of checking.\" Fix: check readability (`[[ -r ]]`) in the precheck, and/or test `grep`'s status explicitly (>1 is an error)."
  },
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 108,
    "summary": "`enumerate()` spawns 4 processes per (file, primitive) pair and re-reads each corpus file once per primitive — 44 spawns over 9,217 lines, 338ms.",
    "failure_scenario": "For each of the 11 CORPUS pairs the loop runs `grep -nE | grep -vE | grep -vE | sed -E`. `lean-gate.sh` (5,420 lines) is read 5 times, `check-lean-chain.sh` (880) 3 times, `lean-evidence.sh`/`orchestrate-lean.sh` twice each — 9,217 lines read as ~24,000 line-reads across 44 processes. Measured `--list` = 338 ms of the guard's 843 ms. One `awk` per file, handling all its primitives in a single pass (the same technique the rows-vs-sites comparison was just refactored to use at line 235), is 5 spawns and 5 reads."
  },
  {
    "file": "scripts/gate-buckets.tsv",
    "line": 67,
    "summary": "Row 67's anchor is a strict prefix of row 68's, so one enumerated site carries two dispositions and nothing reds — an unsanctioned third exception to the register's stated granularity rule.",
    "failure_scenario": "`note_violation \"verdict record '$VERDICT' reads 'verdict=${VERDICT_VALUE:-<none>}', n` (line 67) is a byte-prefix of `…, not 'verdict=approve' — freshness is` (line 68), so row 67 matches both sites (`hits=2`, visible in the coverage print). AMBIG at check-gate-buckets.sh:250 only fires when `nb > 1`, i.e. when the buckets DISAGREE; both rows are `gates-signal`, so the double claim is invisible to the guard. The register's own header (lines 38-44) declares \"One row per enumerated site is the default\" with exactly two sanctioned exceptions (the envfail classes and orchestrate-lean's terminal slugs); this is a third, undeclared one. A full prefix scan of all 156 rows found exactly this one instance. Tighten row 67's anchor so each row claims its own site."
  },
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 170,
    "summary": "The row loop and the verdict line's row count disagree about what a comment is: an indented `#` line or a spaces-only line is parsed as a data row and reds with a misleading \"malformed row\" message.",
    "failure_scenario": "`case \"${rkey:-}\" in ''|'#'*) continue ;;` runs with `IFS=\"$TAB\"`, so spaces are not separators and are not stripped. A register line `  # a note` gives `rkey=\"  # a note\"` — neither empty nor `#*` — and falls through to `fail \"$rkey: the key is not a 'path::primitive' enforcer key\"`. A line of only spaces gives `rkey=\"   \"` and reds as `malformed row (need 5 tab-separated fields):    `, naming nothing. Meanwhile the verdict line's own count at :297, `grep -cv '^[[:space:]]*\\(#\\|$\\)'`, skips both — so the two halves of the script disagree about the register's shape. Use the same `^[[:space:]]*(#|$)` test in both places."
  },
  {
    "file": "scripts/gate-buckets.tsv",
    "line": 51,
    "summary": "A 297-character rationale paragraph is duplicated byte-for-byte in four data rows, restating a rule the same file's header already states once.",
    "failure_scenario": "Lines 51, 75, 204 and 207 each end with the identical 297-char block \"Dispositioned as one row for the whole class, which is OR-1's recorded default: the exit-2 contract is what makes every site in it true, so 132 near-identical rows would add no classification and would drown the register. The covered-site count printed above is what keeps that looseness visible.\" OR-1 is already stated once in this file's own header at lines 38-44 and again in check-gate-buckets.sh's header. That is ~1.2 KB of pure restatement and four places to edit when the OR-1 default changes, with nothing keeping them identical (they are TSV cells, so scripts/check-lockstep-pairs.sh cannot anchor them). Each row's `why` should carry only its own first sentence and defer to the header for the shared rationale."
  },
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 208,
    "summary": "AC-1's `not-a-gate` `why` check is an unanchored prefix match, so any string that merely starts with one of the three phrases satisfies it.",
    "failure_scenario": "`[[ \"$rbucket\" == \"not-a-gate\" && ! \"$rwhy\" =~ ^(environment\\ refusal|usage\\ error|success\\ path) ]]` has no trailing boundary. A `why` of `success pathologically unclear, TODO` or `environment refusalz` passes the mechanical check that AC-1 says makes the closed set \"checked mechanically\" (docs/plans/second-shift-636-lean.md:39-41). Add a boundary, e.g. `^(environment refusal|usage error|success path)([[:space:]]|—|,|\\.|$)`."
  },
  {
    "file": "scripts/check-gate-buckets.sh",
    "line": 80,
    "summary": "The argument parser's catch-all silently treats an unknown flag as the repo root and silently keeps only the last of several positional arguments.",
    "failure_scenario": "`*) ROOT=\"$1\"; shift ;;` — `check-gate-buckets.sh --lst` (a typo for `--list`) sets `ROOT=--lst`, then the corpus precheck dies with `[gate-buckets] corpus file is missing: plugins/dev-pipeline/skills/build-lean/lean-gate.sh — the denominator cannot be computed…` and exit 2, which points the operator at the corpus rather than at their typo. Likewise `check-gate-buckets.sh /a /b` silently checks `/b`. The script's own register classifies `unknown argument` refusals across the corpus as a first-class shape (header lines 22-26), but the guard itself has none. Add `-*) envfail \"unknown option: $1\" ;;` and reject a second positional."
  }
]
```

---

## Assistant text — `result` event 2 of 2

All ten agents have now reported. They corroborate my findings and add substantial new material. Spot-checks I ran just now confirm the four load-bearing new claims (awk status, `in_set` duplication, CORPUS gaps, commit scope).

## New findings — not in the report I sent

**Fail-opens**

1. **`check-gate-buckets.sh:235` — the batched awk pass's exit status is never checked.** Confirmed by reading: `... > "$PASS_OUT"` under `set -uo pipefail` with no `set -e`. If awk fails, PASS_OUT is empty, all three consumer loops iterate zero times, `grep -q '^HITS'` fails so the coverage block is skipped too, `violations` stays 0 — green checkmark, rc 0. Agent reproduced with a stub awk exiting 2: `✓ 305 enumerated refusal site(s) ... all bucketed by 0 register row(s)`, rc 0. The perf commit concentrated ~460 individually-observable spawns into one unobserved one. **This is the most severe finding in the whole review.**

2. **`:169` — a register with no trailing newline silently drops its last row.** `read` returns non-zero on a partial final line, so the loop body never runs; line 297's `grep -cv` still counts it. Three agents reproduced independently: an appended AC-5 violation (`gates-llm` row wired to `intake-unqueued`) passes **green** without the newline and reds with 3 violations with it. No selftest covers this.

3. **`:171` — the "malformed row (need 5 tab-separated fields)" check does not check the field count.** TAB is an IFS *whitespace* char, so runs collapse and empty cells vanish. A row with an empty anchor cell is accepted silently (the yield-position cell is promoted to anchor); >5 fields glom into `$rwhy`. Selftest g12b passes only because its particular empty cell happens to leave `rwhy` empty — its stated rationale describes behavior the code doesn't have.

4. **`:143` — `GATE_VOCAB` is never checked for emptiness.** Confirmed by reading: line 140 validates only `YIELD_VOCAB` (gates ∪ scopes). Delete only `OVERRIDE_GATES` and AC-5's direction-2 arm — the one the header calls "the wiring that would make an objective signal operator-waivable" — goes vacuous with no error. g16 deletes both declarations, so it never exercises the asymmetry.

5. **`:93` — CORPUS is an allowlist literal, so the enumerator is fail-open for new *files*.** The cited precedent (`check-fail-open-shapes.sh`) scans the repo and subtracts a deny-list. Two surfaces are **already uncovered** and I verified both: `lean-reconcile.sh:98` defines `envfail() { …; exit 2; }` with 10 call sites in the same directory as two corpus files, and `preflight.sh:103` defines `bad()`, the exact counter shape, feeding `terminal preflight-rejected`.

6. **`:101` — the denominator's unit is a line, not a call.** A second refusal appended to an already-dispositioned line inherits that row's bucket; `--list` count doesn't move; AMBIG can't fire. Reproduced by chaining a `gates-process`-shaped refusal onto a `gates-signal` line — green.

7. **`:107` — `envfail ()` (POSIX spacing) is not self-excluded** but *is* matched, so reformatting a definition enters it into the denominator as a bogus site.

8. **`:241` — a TAB anywhere in a refusal line truncates awk's `$3`.** One agent argues this is a *regression* from `cfba1022`: the pre-refactor loop compared against the full text via `read -r skey sline stext`. Latent (corpus is tab-free today), but it wedges a site into an unfixable red.

**Convention / process**

9. **`in_set()` at `:145` is a byte-identical rename of `override_in_enum()`** — which lives *inside* the `LOCKSTEP-BEGIN override-record-reader verbatim` block in both `operator-override.sh` and `lean-evidence.sh` (I verified both). Renaming makes it invisible to `check-lockstep-pairs.sh`. The comment eight lines above states the exact rule being broken, about the `OVERRIDE_GATES` *data*, then copies the *code* from the same block.

10. **All four commits are scoped `(dev-pipeline)` but the branch touches zero `plugins/` files** (verified: ci.yml, 2 docs, 3 scripts). `derive-release.sh:136-138` skips any commit with no `plugins/**` path, so the `feat:` produces no minor bump and 16ae844a's authored `Changelog:` prose never reaches CHANGELOG.md. The exact-class precedent used `feat(second-shift)`.

11. **The bucket enum is now stated in three places** (manifesto:137, `gate-buckets.tsv:9`, the guard's `case` at :190) with no LOCKSTEP marker and no `docs/testing.md` "Couplings considered and declined" entry — the rule this PR's own D-4 invokes for `OVERRIDE_GATES`.

12. **`check-gate-buckets-selftest.sh:87` hardcodes production's `OVERRIDE_GATES` values**, so no case can distinguish "read at runtime" from "hardcoded" — a mutant that hardcodes the sed's result passes g8 and g16.

13. **`gate-buckets.tsv` is not added to `docs/testing.md`'s "What survives as a register" list**, which already names its sibling `fail-open-sites.tsv`.

14. **The `path::name` key does not actually join with `prose-blocker-triage.tsv`** — the two registers key the same files on disjoint vocabularies (function names vs. logical gate names; zero rows join). And pb-94ee597a records `check-lean-chain.sh::verdict-record` as **gates-llm** where the new register buckets those sites **gates-signal**.

15. **The new ci.yml step is unreachable on its own failure mode.** The selftest sweep step precedes it and its g0 case already runs the guard against the real tree; with default `if: success()`, whenever the register is stale the sweep reds first and the named step never runs.

16. **`tools/gate-ablation-classes.tsv` already enumerates these decision points** under stable `gate_point` ids; 12 of its 33 reason patterns appear verbatim inside gate-buckets anchors, with no cross-check.

17. **Selftest g10 has no negative control** — it's the only case asserting rc 0 against a fixture that's green by construction, so an unfired `sed` still prints `ok`.

18. **Refinement to my duplicated-paragraph finding:** the "132" pasted into all four rows is wrong in every one — they cover 21, 57, 23 and 15 sites. 132 is the corpus-wide total across all six envfail rows.

## Corroborated

Every finding I sent held up, several reproduced independently: the mod-256 exit truncation (4 agents, one measuring the exact 89-anchor ladder), the keyword command-position hole including the live `lean-gate.sh:420` miss (5 agents), blanket anchors covering 132/305 sites, the indented-comment disagreement, the row-67 prefix overlap (one agent added: deleting `lean-evidence.sh:778` leaves it green because the row slides onto :913), the missing timings row, the unanchored `not-a-gate` `why` prefix, and the `corpus_prims` forks.

## Caveats

Runtime numbers disagree across agents — `corpus_prims` measured at 222 / 332 / 408 ms, and the selftest at 8.5–22 s depending on shell and box. The direction is unanimous (both are the dominant costs; the suite is well over both the 5 s and 9 s bars) but don't quote a specific figure. One agent claims the tab-truncation is a regression from `cfba1022`; another calls it latent — both agree it's unreachable today since the corpus is tab-free.
