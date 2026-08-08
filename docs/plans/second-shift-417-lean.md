# second-shift #417 — the audit hook writes the ledger where no reader looks

Issue: https://github.com/manoldonev/second-shift/issues/417
Pre-flight receipt: `.claude/pipeline-state/417-ledger.md` (D-1 … D-12, OR-1, OR-2) — **binding**.

## Problem

One directory, three resolutions.

| Role | Site | Resolves to |
| --- | --- | --- |
| writer | `plugins/audit-toolkit/hooks/audit-tool-calls.sh:59` | `${CLAUDE_PROJECT_DIR:-$CWD}/.claude/audit` — the **worktree** |
| reader | `plugins/dev-pipeline/skills/run-lean/lean-gate.sh:712` | `$MAIN_ROOT/.claude/audit` — the **main checkout** |
| reader | `plugins/dev-pipeline/skills/run-lean/lean-reconcile.sh:144` | `$MAIN_ROOT/.claude/audit` — the **main checkout** |

`MAIN_ROOT` is `--git-common-dir/..` on both readers, so every lean run — which works in a linked
worktree by contract — writes its ledger where neither reader looks. Two opposite failure modes:

1. **False refusal.** `cmd_entry` fails closed on a missing ledger, so a worktree run with a
   perfectly live hook is refused at the door.
2. **Silent unreconcilability.** A review session that ran in a worktree produces a verdict record
   naming a session `lean-reconcile.sh` can never resolve. It reports *"the verdict record names a
   session the harness has no record of"* — a forgery signal, fired on an honest review. That is
   the worse one: reconcile's value is that a failure means something.

Verified against the current tree — `git -C <linked worktree> rev-parse --git-common-dir` prints the
main checkout's absolute `.git`, while the same command inside the main checkout prints the relative
`.git` (`../.git` from a subdirectory). Any resolution must handle both forms.

## Decisions carried from the receipt

The receipt is binding input and it settles the shape before this spec starts. Transcribed because a
reviewer reads the spec, not the state dir:

- **D-1 — the WRITER moves.** The hook adopts `--git-common-dir/..`; one ledger directory per repo
  family. Shape 2 (reader-side worktree fallback) is **rejected**: it leaves the ledger dying with
  the worktree, which is a data-loss path reconcile cannot tell from forgery.
- **D-2 — `LEAN_AUDIT_DIR` stays a fixture seam,** documented as such. Not an operator override: a
  sanctioned reader-side directory override lowers the attestation ceiling from "forge a second
  session's hook ledger with coherent timestamps" to "write a JSONL file anywhere".
- **D-3 — `/audit` and `/audit-history` move in the same PR.** They ship in audit-toolkit alongside
  the hook, so there is no version skew to sequence.
- **D-4 — ledgers already written under worktrees are ABANDONED, not migrated,** and said out loud
  in the `Changelog:` trailer and audit `SETUP.md`. No reconcile-side worktree probe (Shape 2
  re-entering through the diagnostic door) and no migration tool.
- **D-5 / D-6 — precedence unchanged.** `${CLAUDE_PROJECT_DIR:-$CWD}` stays the starting point; only
  what is *derived from* it changes. When derivation yields no readable directory, fall back to
  exactly today's path.
- **D-7 — `statectl.sh` needs no change.** `ledger_dir()` is already common-dir-anchored.
- **D-10 — prose corrected only where the fix makes it false.**

`D-11`/`D-12` are parked under OR-1/OR-2; both dispositions are *reversible-default-and-flag*, and
both flags are discharged in **Flagged open regions** below.

## Acceptance criteria

**AC-1 — the writer anchors on the main checkout.** `audit-tool-calls.sh` resolves the ledger
directory as `--git-common-dir/..` of `${CLAUDE_PROJECT_DIR:-$CWD}`, handling both the absolute form
git prints inside a linked worktree and the relative form it prints inside the main checkout. A
session whose project dir is a linked worktree writes to the **main checkout's** `.claude/audit/`.

**AC-2 — the fallback is today's path, and the hook never blocks.** When resolution yields no
readable directory — a non-git project dir, an unresolvable or unreadable common dir, no `git` on
PATH — the hook writes to `${CLAUDE_PROJECT_DIR:-$CWD}/.claude/audit` and still exits 0. No new
failure mode for any layout: the fallback *is* the status quo.

**AC-3 — `audit-history.sh` resolves identically.** Its sweep is anchored on the same directory the
writer targets, so a worktree-run `/audit-history` reports the repo family's sessions rather than
nothing. The resolution is one block, held byte-identical across the two shell sites by a
`verbatim` row in `scripts/lockstep-manifest.tsv` — the copies are separate because the hook must
stay dependency-free, and prose is the only other thing that would hold them together.

**AC-4 — `/audit`'s ledger-location step resolves identically,** and its user-facing paths name the
resolved directory rather than a bare `.claude/audit`. Same for `QUERIES.md`'s two path-bearing
recipes and `audit-history.sh`'s own onboarding messages: D-10's rule is "correct it where the fix
makes it false", and a recipe that silently returns nothing in a worktree is false.

**AC-5 — `audit-selftest.sh` covers the new resolution against a throwaway repo.** Cases for:
(a) project dir = linked worktree → ledger lands under the **main checkout**;
(b) non-git project dir → falls back to that dir, hook still exits 0;
(c) no `CLAUDE_PROJECT_DIR` → the payload's `cwd` takes the identical resolution.
The suite must stop writing its smoke ledgers into the real checkout: post-fix, a suite run from a
sandbox worktree would write into the operator's live `.claude/audit/` and then look for the rows
somewhere else — so its fixture becomes a `mktemp` git repo it owns.

**AC-6 — the false refusal is pinned.** `lean-gate-selftest.sh` gains a case where the **real** hook
writes a ledger from a linked worktree and `cmd_entry`, run from that worktree, exits 0. It drives
both parties, so it fails if either side of the agreement moves alone.

**AC-7 — the second reader is pinned on its DEFAULT path.** Every existing `lean-reconcile-selftest.sh`
case sets `LEAN_AUDIT_DIR`, so the shipped resolution is exercised by nothing. One case drops the
seam: the review session's ledger is written by the **real** hook from a linked worktree, and
reconcile's own `$MAIN_ROOT/.claude/audit` finds it.

**AC-8 — the location contract is stated where it was false.** Audit `SETUP.md` states the
main-checkout anchoring **and** D-4's abandonment of per-worktree ledgers already on disk;
`lean-reconcile.sh`'s env block marks `LEAN_AUDIT_DIR` fixture-only (D-2). The `Changelog:` trailer
states the abandonment too. No prose-presence guard is added for any of it — the contract is pinned
by AC-5 … AC-7's fixtures, per CLAUDE.md.

**AC-9 — the mutation registry is re-keyed in this diff.** `audit-tool-calls.sh` and
`audit-history.sh` both carry generic-ordinal rows in `tools/mutation-baseline.tsv`; editing a guard
re-keys its ordinals, so the affected rows are re-baselined here rather than left to red a later
diff. Verified by a diff-scoped `tools/mutation-sweep.sh` run over the two guards.

## Out of scope

- `statectl.sh`'s `ledger_dir()` (D-7 — already correct).
- A migration or probe for ledgers already written under worktrees (D-4).
- Promoting `LEAN_AUDIT_DIR` to an operator override (D-2).
- #416 — the entry gate's precondition being unenforced at the merge boundary. Adjacent and filed
  separately; this ticket makes `entry` *correct*, not *enforced*.
- `lean-gate.sh`'s own relative-common-dir anchor (it joins a cwd-relative answer onto `REPO_ROOT`,
  which is wrong from a subdirectory). Real, pre-existing, and not what this ticket is about — see
  **Flagged open regions**.

## Flagged open regions

**OR-1 — common-dir resolution in layouts nothing here exercises** (submodules, `.git`-file
worktrees, bare checkouts). Taking the receipt's stated default: the D-6 ladder, where anything that
does not resolve to a readable directory falls back to today's path.

An earlier draft justified the flag as "the fallback *is* the status quo, so such a layout is no
worse off than before this PR." **That is false for two of the three, and the correction is kept
here rather than dropped, because the wrong version is the reason the flag looked cheap.** Two of
them *resolve* — to a new place, not to the fallback:

| Layout | `--git-common-dir` answers | Where the ledger lands |
| --- | --- | --- |
| submodule | `<super>/.git/modules/<name>` | inside git's private directory |
| bare checkout | `.` | the parent of the bare repo, outside any repository |
| `.git`-file worktree | the main checkout's `.git` | the main checkout — the case this PR covers |

Neither of those two loses data and neither blocks a session, so the disposition is unchanged; what
changes is the claim. Reversal is still cheap — one branch in `audit_ledger_dir()`. **Flagged: untested against
those layouts, and the first two write somewhere new rather than somewhere old.**

**OR-2 — latency of one added `git rev-parse` per tool call.** Taking the receipt's stated default:
the direct form, resolved per invocation, no cache. Reversal is cheap because the resolution is pure
and its result is a stable per-repo string, so a memo can be added later without moving the
contract.

The draft called this marginal on the grounds that the hook already spawns `jq` six times per call,
and flagged it **unmeasured**. It has since been measured (macOS, 150 invocations × 3 rounds, base
hook vs head hook): **43–61 → 60–78 ms/call, i.e. +16–17 ms, ≈ +37%**, of which
`git rev-parse --git-common-dir` is ≈20 ms and the `cd`+`pwd` subshell ≈1 ms. One `git` costs about
a third of the whole pre-existing hook — a bigger share than "marginal" implied. The disposition
still stands (the hook is not on a latency-sensitive path and the memo remains available), but the
number is now on the record instead of an intuition.

**Deviation from the receipt's enumeration, applying its own rule.** D-10 names two prose sites
(`SETUP.md`, the `LEAN_AUDIT_DIR` line) as examples of "corrected where the fix makes it false".
`QUERIES.md`'s two path-bearing recipes, `audit-history.sh`'s onboarding heredocs and the audit
settings template's path comment fall under the same rule and are corrected too. This applies the
stated rule; it does not decide anything the receipt left open.

## Verification

Per CLAUDE.md, plus this repo's own additions:

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
bash scripts/check-lockstep-pairs.sh
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env -u CLAUDE_CODE_SESSION_ID bash {}
```

The sweep runs **without** `SKIP_STRESS` (the ubuntu lane is the only one that exercises the stress
legs, `audit-selftest.sh`'s among them) and **with** `env -u CLAUDE_CODE_SESSION_ID` (a session id
leaking into a fixture clears refusals that fire in CI).

### Mutation re-baseline (AC-9)

`bash tools/mutation-sweep.sh --mode pr --base origin/main` — 3 guards, 27 mutants, 94s. Every row
below was then re-derived by hand (apply the operator's own `sed` at the named line, run
`audit-selftest.sh`, read the failure count) rather than inferred from survivor-id equality: the
sweep is **advisory** off CI, so its kill verdicts are not by themselves comparable to a committed
baseline.

| Row | Verdict | Action |
| --- | --- | --- |
| `audit-tool-calls.sh::default::1` | survives — a **prose** site (the rationale block names `${CLAUDE_PROJECT_DIR:-$CWD}` literally), unkillable by construction | **added** |
| `audit-tool-calls.sh::default::2` | killed — the real code site, displaced to ordinal 2 and still inside the k=2 window | no row |
| `audit-history.sh::cmp-eq::1` | killed — ordinal unmoved; the new `/audit-history`-from-a-worktree case now asserts a non-zero session count | **removed** |
| `audit-history.sh::cmp-z::1`, `::cmp-z::2` | killed — ordinals 1-2 are now the resolution's own guards; the sites these rows were authored for moved to 3-4 | **removed** |
| `audit-history.sh::logic::2` | killed — same displacement | **removed** |
| `audit-history.sh::fail-open::1`, `::detector::1`, `::detector::2`, `audit-tool-calls.sh::logic::2` | survive, ordinals unmoved | kept |
| `audit-history.sh::fail-open::2` | the sweep scored it KILLED via the **killer process bound** (101 processes) — an artifact of the 20-way stress fan-out, not a kill: applied by hand it survives | kept |
| `lean-reconcile.sh` (6 rows) | survivor set is byte-identical to the baseline; the header edit added no operator site | untouched |

Honest limit on the removals — it applies to **three of the four**, not all of them, and the table
above is the authority on which. `cmp-z::1`, `cmp-z::2` and `logic::2` are killed because the k=2
budget window moved onto the new resolution's guards, **not** because the regressions those rows
described became caught: their sites sit at ordinals 3-6 and are no longer swept at all. `cmp-eq::1`
is the opposite case — its ordinal did not move, it is still swept, and it is killed by genuinely
new coverage (the `/audit-history`-from-a-worktree case asserting a non-zero session count).
Sweeping all four into the budget explanation would **under**-claim this PR's coverage.
