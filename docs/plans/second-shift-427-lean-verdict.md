# lean review verdict — #427

verdict=needs-work
run_id: review-427-2
session_id: 03b18872-29da-4afa-96b4-2e02dd68d90c
rounds: 2
pr: #469
reviewed_head: a890716b93d490b6c1f27f5718608629eff25ba4
reviewed_patch_id: 122b559e288060c82144a79302f3bae87fe0bb91
inherited_patch_id: f963dd52a8d0d778e721252f6f1b3eebbc2e88aa
inherited_from_verdict: 072e39d82d282049f900cb81070543a5d638039d
fidelity: not-applicable
model: unknown

Round 2 — delta since the round-1 tree (`072e39d..HEAD`). Inherits the coverage of patch
`f963dd52a8d0`. The branch's own round-2 work is `af6906b` + `a890716` + the
`install-topology-known-red.tsv` merge resolution; the rest of that range arrived from main,
so the panel was run over `origin/main...a890716` instead — the whole branch, main's noise
excluded. That is wider than the delta, not narrower.

Panel: security, complexity, test-coverage, unit-test-mutation, scope-completeness returned.
**maintainability went dark** (died-after-retry, turn budget exhausted mid-exploration) — a
coverage gap, not a pass: readability/naming of the round-2 edits was not reviewed this round.
a11y + design-fidelity were not routed: no changed path matched `stageParams.webComponentGlobs`
(unset → `apps/web/**/*.{tsx,jsx}`).

Round-1's blocker is genuinely fixed and I reproduced all three legs against a real
12-version cache (a symlink mirror of `~/.claude/plugins/cache/second-shift`, no git repo
above it): `main` → `clean — 0 linted` (the vacuous green); pre-fix `ab1935f` → **16
violations across 38 agents**; this head → resolves `review-toolkit 4.1.0`,
`design-toolkit 2.2.1`, `intake-toolkit 2.3.2` — newest of each — clean over 4 agents, rc=0.
Round-1's warning 2 is closed for real: the two `LOCKSTEP-BEGIN/END
cross-plugin-sibling-plugin-root` blocks are byte-identical (`diff` says so) and
`check-lockstep-pairs.sh` passes 26 pairs / 0 failed with the new row.

The one blocker is the commit that was written to close the mutation obligation. It does not
close it on the lane that scores it.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | `plugins/review-toolkit/scripts/check-emit-deadline-selftest.sh:337` (B11) / AC-5 | `mutation-sweep-pr` is **RED on this exact head** (run 31341958012, headSha `a890716`): `check-emit-deadline.sh::cmp-z::1` returns as a **baseline-absent survivor**, serially re-verified outside the pool. That mutant is the one `a890716` exists to kill, and B11 does not kill it where CI runs. The PR body's "Re-swept: `applied=13 killed=12 survived=1`" is a macOS-only measurement; CI on the same head reports `applied=13 killed=11 survived=2`. |
| 2 | Warning | `docs/plans/second-shift-427-lean.md:125` (OR-3) / ledger D-9 | Both the spec's OR-3 and ledger row D-9 commit to **filing** the follow-ups — Class-C `cost-block-selftest.sh`, and the lexical newest-version sort (`9.0.0` outranks `10.0.0`) now mirrored across five ladder copies. Neither is filed: the newest issues in the tracker are #464/#465, and `gh issue list --search lexical --state all` returns only #421 and #427. The mirroring is done and documented at every site — only the deferral is untracked. |
| 3 | Warning | `.claude/pipeline-state/427-ledger.md:9` (D-3) | The new `verbatim` row is a declared, operator-approved deviation from D-3, recorded in both the spec and the PR body, and it is one of the two remedies round 1's own warning 2 named — so it is not a blocker. But the ledger row itself still reads "No new `scripts/lockstep-manifest.tsv` rows", so the binding input and the diff now disagree in the one place a later reader would check first. Amend D-3 (or add a D-13 superseding it) so the record is self-consistent. |
| 4 | Coverage gap | — | `maintainability-reviewer` dark (died-after-retry). Its domain over `af6906b`/`a890716` — the `plugin_name`/awk block's readability, the parameterized anchor, the B10/B11 fixtures — was not reviewed this round. Not blocking on its own; recorded so the gap is visible. |
| 5 | Nit | `check-emit-deadline.sh:191` | The anchor-WIDENING direction of `^[[:space:]]\{0,2\}"name"` is untested: `sed -n '…p' | head -1` takes the first matching line, and both fixtures write the top-level `"name"` before the nested `author.name`, so relaxing the bound (`\{0,2\}` → `\{0,\}`, or dropping the anchor) leaves B10 and B11 green. The narrowing direction IS caught. Subsumed by blocker 1's remedy — a fixture that discriminates on the VALUE read closes both. |

### Blocker 1 — evidence

The mutant is `cmp-z` ordinal 1, applied verbatim from `tools/mutation-operators.tsv`
(`s/-z /__MUT__/g; s/-n /-z /g; s/__MUT__/-n /g`). `grep -nE -- '-z |-n '` puts ordinal 1 at
line 191, the jq-less name lookup, so the flip is:

```
-    sed -n 's/^[[:space:]]\{0,2\}"name"…/\1/p' "$j" 2>/dev/null | head -1
+    sed -z 's/^[[:space:]]\{0,2\}"name"…/\1/p' "$j" 2>/dev/null | head -1
```

Applied here, on stock BSD sed, B11 **fails** (`24 passed, 1 failed`) — which is what the
build session measured and what the commit message reports. `sed -z` is a GNU extension BSD
sed rejects outright, so `plugin_name` returns empty, every candidate keys on its own path, no
selection happens, and the superseded version's `stale-reviewer` reaches the scan. The mutant
dies for a reason that has nothing to do with reading a name.

On CI's GNU sed it does not die. GNU sed accepts `-z`, and `-z` is **not** `-n`: the flip
silently removes quiet mode, so sed auto-prints, and with NUL-delimited records the whole
manifest is one record whose `^` sits on `{`, so the substitution never fires. `head -1` then
returns `{` for every candidate. That is a CONSTANT — and a constant name is a perfectly good
key, so newest-per-name still selects `2.0.0`, `stale-reviewer` stays out, and B11 passes.

That mechanism is checkable without GNU sed, and I checked it: replacing the jq-less branch
with `head -1 "$j"` — returning the same constant `{` — leaves the suite at
**`25 passed, 0 failed`**, B11's own line included ("the jq-less name lookup selects the newest
version, and ignores a nested `author.name`"). B11 cannot tell a name lookup from a constant.
CI's serial re-verify (`serial re-run agrees: … really does survive its kill set`) is therefore
a real survivor, not a pool artifact, and the site is branch-introduced, so it is not inherited
debt from main's nightly either.

B10 and B11 do both discriminate on the thing they were written for — reverting shape 1 to the
unkeyed pre-fix form fails exactly those two cases and nothing else — so this is not "the cases
are vacuous". It is one axis they do not separate, and it is the axis `cmp-z::1` moves along.

Remedy: make the outcome depend on the VALUE read, not just on some value being read. The
cheapest shape is a fixture where the two version dirs declare DIFFERENT top-level names, so a
correct lookup keeps both (`stale-reviewer` scanned → rc=1) while a constant-returning or
wrong-line lookup collapses them to one — inverting B11's assertion so a broken fallback is
detectable. That closes finding 5's widening direction in the same case. A baseline row is not
available here: `tools/mutation-baseline.tsv` must not absorb a survivor whose paired suite is
supposed to kill it, and CLAUDE.md's own answer for a branch no case can reach is coverage.

## Acceptance criteria

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — selftest passes from a version-keyed install cache (B1/B2/B4/B5 included) | satisfied | `tools/install-topology-selftest.sh` run here: **57 ran, 57 passed, 0 known-red, 2 skipped, 0 stale row(s), 0 red**. Independently: from a real 12-version cache with no git repo above it, the shipped lint is clean over 4 agents where the pre-fix branch reported 16 violations across 38. |
| AC-2 — no-args run from an install lints >0 agents; roots to stderr; stdout unchanged | satisfied | Same real-cache run: 4 agents linted, rc=0, and `2>&1 >/dev/null` shows the `scanning roots:` line is stderr-only. B8 pins the split. |
| AC-3 — `doctor-selftest.sh` passes from that topology and its claims-lint scenarios execute | satisfied | Green in-checkout with `claims-ok` and `claims-expired` both running (not the else-branch), and green under the install-topology guard above. |
| AC-4 — all three call sites resolve in this checkout; ordinary sweep unchanged | satisfied | `check-emit-deadline-selftest.sh` 25/0, `doctor-selftest.sh` all green, `preflight-selftest.sh` 59/0 — all with `env -u CLAUDE_CODE_SESSION_ID`. CI `lint-and-selftests` and `selftests (macos, bash 3.2)` both pass on `a890716`. `shellcheck -e SC1091,SC2015,SC2181` clean on all four changed scripts. |
| AC-5 — mutation obligations discharged in the same diff | **unsatisfied** | `mutation-sweep-pr` is red on this head with a baseline-absent survivor (Blocker 1). The catalog half is fine and independently checked — the `emit-deadline-ceil` sed anchor still matches `check-emit-deadline.sh:320` byte-for-byte, so no re-anchor was owed, and the baseline carries no generic-ordinal rows for this file to re-key. The obligation that is open is the survivor. |
| AC-6 — three rows drained from `install-topology-known-red.tsv` | satisfied | All three gone; the merge conflict was resolved as the union of two independent drains, so neither side's rows returned and only `cost-block-selftest.sh` stays listed. The guard confirms: `0 known-red, 2 skipped, 0 stale row(s)` — the 2 skipped being main's repo-only-artifact pair. |
| AC-7 — `preflight-selftest.sh:38` resolves through the ladder | satisfied | The `assert` makes an empty `RT_TEST_ROOT` a counted failure instead of a silent fall-through to the `claude plugin list` rung, and the suite is 59/0 here. ENVIRONMENT-DEPENDENT by the AC's own terms; what is asserted directly is that the ladder resolves, which is the falsifiable half. |

## Design fidelity

`not-applicable`. The spec's `## Design` section is disarmed (`Design: none — no design.provider is
configured for this repo`). Verified against the repo config: `.design` is absent, and the change is
shell path resolution with no rendered surface. The disarm is justified.

## Dismissed

- **scope-completeness-reviewer, major on the lockstep row** (confidence 88) — it is right that the
  row reverses D-3, and I have kept the record half as warning 3. It is not a blocker: no `AC-n`
  covers lockstep treatment, the deviation is declared in the committed spec and the PR body with
  its reasoning and its approval, and adding this exact row is one of the two remedies round 1's own
  warning 2 offered. A remedy a prior round sanctioned cannot become the next round's blocker.
- **security / complexity / test-coverage** — no findings above threshold. Suppressed items
  (`EMIT_DEADLINE_JQ` as an invoker-owned seam, a hostile local manifest smuggling a tab into the
  awk key, the pre-existing `$ROOTS` word-splitting on paths with spaces, `resolve_sibling_file`'s
  single call site) are either pre-existing forms or already-litigated trade-offs in this diff.
