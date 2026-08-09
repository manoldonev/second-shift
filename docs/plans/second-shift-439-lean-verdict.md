# lean review verdict — #439

verdict=needs-work
run_id: review-439-1
session_id: 4ffdc180-cc8c-42ca-9795-626796b060b2
rounds: 1
pr: #452
reviewed_head: f691cbe3a43c519ed8dcb40d15474243a442bbeb
reviewed_patch_id: 3ddd85214a65956bfe8ab49600117a587608f82b
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Review summary

Round 1, `review-439-1`, chain root — the whole branch diff (`b55e701..f691cbe`, 7 files,
537 insertions). Panel: security, performance, maintainability, complexity, test-coverage,
scope-completeness. None dark; all six returned `approve` with no findings above the
confidence threshold.

The change is well-built and the hard part is right. I verified the load-bearing claim
independently rather than taking the goldens on trust: prettier 3.7.4 produces **exactly**
the four golden tables, and leaves all four unchanged under a second `--write` — so the
write-site padder really is byte-equal to the formatter it is imitating, and AC-1's
"measured against prettier 3.7.4" holds.

One blocker, and it is in the case that was supposed to establish that fact. `(fp5)`, the
live-prettier oracle AC-8 requires, **fails on every machine where a prettier resolves** —
the exact inverse of the "SKIP, never a failure" posture the AC and D-10 both specify. CI
cannot see it (no node in the lane), so it lands on whoever runs the sweep locally, which is
this repo's stated verification recipe.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | `lean-gate-selftest.sh` (fp5) | The live-prettier oracle is fed the padder's *input*, which has no delimiter row. Prettier does not parse that as a table and rewrites nothing, so the `cmp` against the padded golden always mismatches. The case cannot pass. |
| 2 | Warning | `lean-gate-selftest.sh` | The suite is not hermetic against an ambient prettier — the same class of leak AC-10 just closed for `RUN_ID`. Every `verdict`-writing case now spawns a real node process. |
| 3 | Suggestion | `lean-gate.sh` `cmd_4` | AC-7's milestone-4 half ships unguarded; `(fp11)` pins only the milestone-3 message. |
| 4 | Suggestion | `lean-gate.sh` `md_table_prettier` | A literal `|` in an author-written `route`/`state` cell splits a column. Sits beside the declared OR-2 (display width) flank and is not covered by it. |

### 1 — Blocker: `(fp5)` fails wherever a formatter resolves

Reproduced by running the branch's own suite with prettier 3.7.4 on `PATH`:

```
PASS: (fp1) column widths come from the widest body cell
PASS: (fp2) a header cell wider than every value sets the column width
PASS: (fp3) a single-row manifest table matches prettier byte for byte
PASS: (fp4) columns narrower than three characters pad to the 3-dash minimum
FAIL: (fp5) .../bin/prettier disagrees with the golden form: 1,3c1,2
PASS: (fp6) … (fp7) … (fp8) … (fp9) … (fp10) … (fp11)
[lean-gate-selftest] 1 FAILURE(S)
```

Root cause. `FP_IN` is the **padder's** input contract, and the padder's contract is that the
delimiter row is *not* supplied (`md_table_prettier`'s own header comment says so, because the
dash count is a function of the widths it computes). Markdown requires that delimiter row for
a table to exist at all, so prettier reads `FP_IN` as an ordinary paragraph and leaves it
verbatim — confirmed directly, `prettier --write` reports `(unchanged)` on all four inputs.
`cmp` then compares an unpadded paragraph against a padded table.

Two consequences, and the second is the one that matters:

- The case is a guaranteed red, not an opportunistic skip. AC-8 says "reported **SKIP**, never
  a failure"; D-10 says "runs opportunistically and is SKIPPED, not failed". As written it
  passes only by never running. On a machine with a global prettier — common — the whole-tree
  sweep in `CLAUDE.md` reds, and so does `install-topology-selftest.sh`, which re-runs every
  shipped suite.
- Nothing executable binds the goldens. The four `(fp1)`–`(fp4)` goldens are a claim about
  another program's output; `(fp5)` is the only thing that was supposed to check it, and it has
  never once done so. A future prettier table-format change would be caught by nobody.

The goldens themselves are correct — I checked, so the fix is confined to the oracle:

```
$ printf '| a | bb |\n| --- | --- |\n| c | d |\n' > t.md && prettier --write t.md
| a   | bb  |
| --- | --- |
| c   | d   |          # byte-identical to (fp4)'s FP_WANT
```

and `prettier --write` on each of the four `FP_WANT` tables reports `(unchanged)` — they are
fixed points of prettier 3.7.4.

Remedy: give prettier a real table. Splice an unpadded delimiter row (`| --- | ... |`, one per
column) between the header and the body rows of `FP_IN` before writing `fp-live.md`, then `cmp`
against `FP_WANT` as now. That is a true re-derivation: prettier is then doing the padding, and
the goldens are what it must produce.

While fixing it, please also make it cover **the goldens** rather than one of them. `FP_IN`
and `FP_WANT` are reassigned in place through `(fp1)`–`(fp4)`, so `(fp5)` re-derives whichever
pair happened to be last — fp4's, the narrowest and least interesting. The 64-char digest case
`(fp3)` is the one the shipped shape actually depends on, and it is the one currently unchecked
against a live formatter. Holding the four pairs in a small loop makes the AC's plural true.

Everything else in the suite stayed green with a real prettier resolvable, including
`(fp8)`/`(fp9)`/`(fp10)` — the fake-formatter fixtures are properly hermetic. `(fp5)` is the
only case affected.

### 2 — Warning: the suite is not hermetic against an ambient prettier

`(fp8)`–`(fp10)` install a fake formatter at the rung the resolver probes, deliberately. Every
*other* case that writes a verdict record now picks up whatever prettier the host happens to
have, because `lean_format_verdict_record` fires on the real `cmd_verdict` path. Measured once:
the suite completes inside two minutes with no formatter and needed over six with one — a real
process spawn per verdict-writing case, and this suite writes many. `install-topology-selftest.sh`
re-runs every shipped suite and is already the sweep's long pole.

This is the shape of the leak AC-10 just closed one file over: an ambient environment fact
changing what a suite exercises. Not a blocker — nothing is wrong with the *result*, and the
formatting behavior is exactly what AC-4 asks for — but the suite would be better off pinning
its own resolution (a scratch `node_modules` root, or an explicit skip) than inheriting the
host's. Round-1 warning, recorded so it is not lost.

### 3 — Suggestion: AC-7's milestone-4 half is unguarded

`(fp11)` greps the milestone-3 refusal for both notices. The two milestone-4 messages took the
same class of edit — the spec/intent-gap formatting obligation — and have no equivalent case.
Cheap to add beside `(fp11)`; the AC is satisfied either way, since both messages do carry the
text.

### 4 — Suggestion: a literal `|` in a manifest cell splits a column

`md_table_prettier` splits on `|` with no escape handling, and `render_manifest_rows` reads the
result positionally. `RS-n`, the png path and the digest are gate-derived, but `route` and
`state` come from author-written RS rows in the spec, so a `|` in either is reachable by an
author. The result is a mis-padded table *and* a receipt whose png/sha columns have shifted —
slightly worse than OR-2's declared failure mode (one red format check, never a mis-read
artifact), so it is not covered by that flank. Very low likelihood; noting it rather than
asking for escaping.

## Acceptance criteria

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — manifest emitted in Prettier's exact form | satisfied | `md_table_prettier` computes `max(3, widest cell incl. header)`, one space each side, matching dashes. Verified against a live prettier 3.7.4 two ways: it canonicalizes an unpadded table to exactly these bytes, and leaves all four goldens unchanged. |
| AC-2 — padding computed at the write site | satisfied | Pure `awk` over rows the gate already holds; no formatter, no new dependency. `(fp6)` shows the milestone-3 re-derive converges on the padded form. |
| AC-3 — no reader changes, legacy manifests parse | satisfied | `render_manifest_rows` untouched; `(fp7)` parses a padded and a space-collapsed legacy manifest to identical rows. |
| AC-4 — verdict record formatted by a local formatter | satisfied | `lean_resolve_prettier`: worktree rung, then main checkout, no `npx`. Both `MAIN_ROOT` resolutions (gate and `verifyctl.sh`) are `dirname(git-common-dir)`, so the lockstep row is semantically as well as textually true. `(fp8)`. |
| AC-5 — formatting never damages the header | satisfied | Pre-format bytes staged; all ten emitted keys re-read via `header_key`, plus the `verdict=` line; any change or non-zero exit restores and warns once. `LEAN_VERDICT_HEADER_KEYS` matches `cmd_verdict`'s emission set exactly, key for key. `(fp9)`. |
| AC-6 — absent formatter is a consumer fact | satisfied | One warn line, `return 0`, no milestone failure. `(fp10)`, and observed live: this repo resolves no prettier and the gate skipped cleanly. |
| AC-7 — both commit instructions name the obligation | satisfied | Milestone-3 refusal carries the obligation *and* the "voids an in-flight verdict" cost; both milestone-4 messages carry the obligation. `(fp11)` guards the first only — see finding 3. |
| AC-8 — Prettier-exact claim bound by fixtures, CI takes no node dependency | **unsatisfied** | Goldens, library mode and the fake-formatter cases all ship, and CI takes no node dependency. But the live-prettier case neither re-derives the goldens nor skips: it **fails** wherever a formatter resolves. Finding 1. |
| AC-9 — two docs brought current | satisfied | `docs/live-render.md` records the pre-padded receipt, the no-network posture and both OR flanks; `docs/testing.md` documents library mode and the positional-parameter caveat. |
| AC-10 — suite hermetic against an exported `RUN_ID` | satisfied | `unset RUN_ID` at the top beside the `LEAN_RUN_MODEL` guard. Suite green both without `RUN_ID` and with `RUN_ID=review-439-1` exported. |

## CI

`lint-and-selftests` and `selftests (macos, bash 3.2)` green; `release-pr-gates` skipped.
`pr-gates` red on the **missing verdict record only** — the expected pre-review state, and the
only `✗` in the job log. No CI blocker outside the AC set.

Note that CI being green is not evidence against finding 1: the lane has no node, so `(fp5)`
skips there by construction. The failure is only reachable from a developer machine.

## Verdict

`needs-work` — one blocker (finding 1). Everything else on the branch is sound and the
padding work is verified correct against the real formatter; the fix is confined to `(fp5)`.
