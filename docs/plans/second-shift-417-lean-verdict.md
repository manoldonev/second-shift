# lean review verdict — #417

verdict=needs-work
run_id: review-417-2
session_id: c6d9f518-2be9-4635-997e-351bc1f5aa2b
rounds: 2
pr: #420
reviewed_head: be37163b4f03111d0390a14fcf9addcdf2ff5973
reviewed_patch_id: fb21f1e0d879c0a8134da4f606a38b41a10f172e
inherited_patch_id: 1a28fff42ca2c6fcc6f4e882368692cd2e929983
inherited_from_verdict: c5d23730fe60a3cbf17203edb983a6906c89672b
fidelity: not-applicable
model: unknown

## Round 2 — needs-work

Range read: `c5d2373..HEAD` (delta since the tree round 1 covered, inheriting patch `1a28fff42ca2`),
**read wider** to the branch's whole contribution at the merged head (`origin/main...HEAD`, patch
`fb21f1e0d879`). Reviewed from the lean worktree at the PR head. Design section unarmed, so fidelity
scores `not-applicable`.

**Why a round was spent rather than the round-1 approve re-stamped.** A `main` merge landed on top of
the round-1 record today (`be37163`, "Merge main into lean/second-shift-417"), and it was **not** a
clean replay: `git merge-tree c5d2373 3b9c810` reproduces content conflicts in `lean-reconcile.sh` and
`lean-reconcile-selftest.sh`, and the branch's own patch identity moved `1a28fff4…` → `fb21f1e0…`.
The #392 re-stamp remedy is only available when the patch is unchanged; it is not, so round 1 is void
by the gate's own stated rule ("still moves on any real change — including a conflict resolution").

**The conflict resolution itself is correct.** Diffing the branch's contribution before vs after
(`a2b158f...c5d2373` vs `3b9c810...be37163`) leaves exactly three substantive deltas, all of them the
right rebase of a line-sensitive edit:

| Delta | Assessment |
| --- | --- |
| `lean-reconcile-selftest.sh`: the new case renamed **(Q) → (R)** | correct — main's #416 arm took `(Q)`; `(R)` is unique in the file, and main's `(Q)` re-establishes its whole fixture (`write_progress_unattested`/`write_verdict`/`write_ledger`×2/`commit_verdict`), so `(R)`'s mutations do not reach it |
| `lean-reconcile.sh`: `sed -n '2,83p'` → `'2,87p'` | correct — main's header grew 4 lines (77→81); line 87 is `# Exit 0 = reconciled…`, line 88 is `set -uo pipefail`. `--help` prints 86 lines and stops before the code; case `(O)` asserts both directions and is green |
| `lean-gate-selftest.sh` `(d5)`: hunk offset 180 → 213 | offsets only |

`tools/mutation-baseline.tsv` and `scripts/lockstep-manifest.tsv` merged additively — the branch's
rows are byte-identical and land at unchanged offsets. Every audit-toolkit file (the fix itself) is
**byte-identical** to the tree round 1 reviewed, so AC-1…AC-5 and AC-8 inherit that round's coverage
on unchanged content.

### The blocker

**B1 — the merged tree is red: `tools/install-topology-selftest.sh` fails on the two suites this PR
extends, and neither is in `tools/install-topology-known-red.tsv`.**

That guard did not exist at the branch point — it arrived with the merge. It stages `plugins/` at
version-keyed paths (`<cache>/<plugin>/<version>/…`) outside any git repo and re-runs every shipped
suite, and its own header names this exact failure class as one of the two it was built for
("design-sync-selftest.mjs assumed sibling plugins stay adjacent under `plugins/`").

Both new cases reach across plugins with a monorepo-only hop:

```
HOOK="$HERE/../../../audit-toolkit/hooks/audit-tool-calls.sh"
  lean-gate-selftest.sh:227   (d5)
  lean-reconcile-selftest.sh:641   (R)
```

In the repo that is `plugins/audit-toolkit/hooks/…` ✓. In the install cache `$HERE` is
`<cache>/dev-pipeline/4.0.0/skills/run-lean`, so it resolves to
`<cache>/dev-pipeline/audit-toolkit/hooks/…` — while the hook actually stages at
`<cache>/audit-toolkit/2.1.0/hooks/…`. Both cases then take their `[ ! -x "$HOOK" ]` branch.

Reproduced twice, independently:

```
[install-topology] summary: 55 ran, 49 passed, 4 known-red, 0 skipped, 0 stale row(s), 2 red
  RED:   plugins/dev-pipeline/skills/run-lean/lean-gate-selftest.sh — rc=1
  RED:   plugins/dev-pipeline/skills/run-lean/lean-reconcile-selftest.sh — rc=1
```

and, staging the two plugins by hand and running each suite from the staged path:

```
FAIL: (d5) audit hook not found at …/dev-pipeline/4.0.0/skills/run-lean/../../../audit-toolkit/hooks/audit-tool-calls.sh
FAIL: (R)  audit hook not found at …/dev-pipeline/4.0.0/skills/run-lean/../../../audit-toolkit/hooks/audit-tool-calls.sh
```

Per the known-red file's own contract — "a suite NOT listed here that fails or times out is a red
build" — this reds `lint-and-selftests` and `selftests (macos, bash 3.2)`, both of which discover
suites by the `*-selftest.sh` glob. On this machine main scores 51 pass / 4 known-red / 0 red; the
branch converts two passes into two reds.

Not a defect in the fix — the writer/reader contract is right and the cases are the correct shape.
It is a topology assumption that was invisible until the merge. Two remedies, and the repo has
precedent for both: **fix** the hop so it resolves in either topology (the TSV notes
`plan-lint-selftest.sh` and `design-sync-selftest.mjs` "were fixed rather than listed"), or **list**
both suites with a stated cause, alongside the two existing rows whose cause is the identical
"fixed hop count that only holds in the monorepo" (`doctor-selftest.sh`, `preflight-selftest.sh`).
A fix is worth more here than a row: the cross-plugin reach is the *point* of these two cases, and a
known-red row retires the very coverage AC-6/AC-7 were written to add, wherever the plugin actually
ships.

### Warnings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| W1 | warning | PR body, Evidence | Names the reconcile fixture as **(Q)**; the merge renamed it **(R)**, and a *different* `(Q)` now exists — main's #416 build-entry attestation arm. The body points at a real case that is not this PR's. Body-only, so its fix is not a commit and costs no round |
| W2 | warning | `audit-selftest.sh:224` | Round-1 warning 3, unfixed and now doubly stale: cites `lean-reconcile-selftest.sh`'s **(N)**; the case is **(R)** |
| W3 | warning | spec OR-1 / AC-2 | Round-1 warning 1, unfixed — "falls back to today's path, so no worse off" is false for submodules (ledger lands in `.git/modules/`) and bare checkouts (outside the repo) |
| W4 | warning | spec OR-2 | Round-1 warning 2, unfixed — the unmeasured latency was measured at ~+37% per tool call |
| W5 | warning | spec, "honest limit on the four removals" | Round-1 warning 4, unfixed — the paragraph contradicts its own table on `cmp-eq::1` |
| W6 | nit | PR title | Round-1 nit 5, unfixed — no conventional prefix |

W3–W6 are round-1 findings the branch has not addressed; no fix commit landed, only the merge. They
stay at round-1's severity — a round that inherits coverage must not re-grade what the prior round
already weighed.

### Per-AC scoring

Scored by the letter, every AC every round. The blocker sits **outside** the AC set: it is a property
of the merged tree, not an unmet criterion.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 writer anchors on the main checkout, both common-dir forms | satisfied | `audit-tool-calls.sh` byte-identical to the reviewed tree; `audit-selftest.sh` green in-repo |
| AC-2 fallback is today's path, hook never blocks | satisfied | unchanged content; see W3 on the AC's trailing generalization |
| AC-3 `audit-history.sh` resolves identically, held by a `verbatim` row | satisfied | `check-lockstep-pairs.sh`: `PASS: audit-ledger-dir (verbatim)`, 18 pairs / 0 failed at the merged head |
| AC-4 `/audit` + `QUERIES.md` + onboarding name the resolved dir | satisfied | files byte-identical to the reviewed tree |
| AC-5 `audit-selftest.sh` covers (a)(b)(c) against a throwaway repo | satisfied | green in-repo **and** under the install topology — it stays inside its own plugin (`$SCRIPT_DIR/../hooks/…`), which is why it is not among B1's two reds |
| AC-6 the false refusal is pinned | satisfied | `(d5)` present and green in the repo; the pin exists. Its suite's install-topology red is B1, a separate property |
| AC-7 the second reader is pinned on its DEFAULT path | satisfied | `(R)` present and green in the repo, still setting no `LEAN_AUDIT_DIR`; survived the rename intact |
| AC-8 the location contract is stated where it was false | satisfied | unchanged content |
| AC-9 the mutation registry is re-keyed in this diff | satisfied | inherited: both guards (`audit-tool-calls.sh`, `audit-history.sh`) are byte-identical to the reviewed tree, so no ordinal moved, and the branch's baseline rows merged additively. Main's `mutation-sweep.sh` change (#433) re-verifies **survivors** only and does not bear on the kept `fail-open::2` row, whose basis was a false KILL |

### Verification performed this round

| Check | Result |
| --- | --- |
| `shellcheck -e SC1091,SC2015,SC2181` over all `*.sh` | clean |
| `jq empty` over all `*.json` | clean |
| `scripts/check-lockstep-pairs.sh` | 18 pairs, 0 failed |
| Full selftest sweep, **no** `SKIP_STRESS`, `env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL`, `-P 4` | **rc=1** — `install-topology-selftest.sh` the only failing suite (B1); every other suite green, `lean-gate-selftest` and `lean-reconcile-selftest` included |
| Merge replay (`git merge-tree c5d2373 3b9c810`) vs the committed merge | conflicts confirmed in two files; resolution reviewed line by line, correct |
| Branch contribution before vs after the merge | three substantive deltas, all correct; audit-toolkit untouched |
| Branch patch identity | `1a28fff4…` → `fb21f1e0…`, so round 1 is void rather than re-stampable |
| Staged-cache reproduction of B1 | both suites fail at the `audit hook not found` branch |

**Not re-run this round, stated rather than implied:** the reviewer panel (round 1 scored 6/6 approve
on audit-toolkit content that is byte-identical here, and the merge interaction is not a thing a
reviewer agent is placed to catch — running the class guard is), and `tools/mutation-sweep.sh`
(AC-9's guards are unchanged; the fix for B1 will move at least one of these two suites, so the sweep
is worth running against that tree rather than this one).

### CI

`pr-gates` fail, `lint-and-selftests` and `selftests (macos, bash 3.2)` pending on run
`31265316163` at the time of writing. The local sweep above is what this round rests on, and it
predicts both selftest lanes red for B1.
