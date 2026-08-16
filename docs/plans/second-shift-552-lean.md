# second-shift #552 — prose-budget.sh measures shell comment density

`prose-budget.sh` is a committed-baseline growth ratchet for the instruction layer, and it
scans `*.md` only. The lane's three shell guards — `lean-gate.sh`, `orchestrate-lean.sh`,
`tools/run-selftests.sh` — are majority prose and nothing measures them, so growth is
invisible until someone loses patience with the file. This slice makes the metric exist. It
is the definition the two cutting slices (#553, #554) are scored against, so it lands first:
if the cut and the sweep measure differently, the growth report is meaningless.

Extends `plugins/dev-pipeline/skills/run/tools/prose-budget.sh`, reusing its existing
baseline / tolerance / report machinery. No new tool. `context-drift-audit`, named in the
epic #541, does not exist and is not being created.

Pre-flight ledger: `.claude/pipeline-state/552-ledger.md` (binding — 15 rows, OR-1).

## Acceptance Criteria

- **AC-1**: `prose-budget.sh` measures `*.sh` files, recording per file exactly four fields:
  total lines, non-blank lines, comment lines, and the comment-to-non-blank ratio. A comment
  line is **any** line matching `^[[:space:]]*#`, shebang included. The denominator is
  non-blank lines, so the metric is stable under whitespace reflow.

- **AC-2**: The shell scan root set is the existing `prose_roots()` list **plus `tools/`**.
  This is the one place the shell path deliberately diverges from the markdown path:
  `tools/run-selftests.sh` lives under none of `.claude/skills`, `.claude/agents`,
  `plugins/*/skills`, `plugins/*/agents`, so reusing `prose_roots()` unchanged would silently
  omit one of the three files this slice exists to measure. `tools/` is appended only when it
  exists on disk, the same exists-only filter `prose_roots()` already applies — that filter is
  what preserves the n/a-vs-vacuous distinction. `*-fixtures/` trees are excluded, same as the
  markdown path.

- **AC-3**: The scan is **generic**, not a hardcoded list: every `*.sh` under the roots is a
  ratchet candidate, exactly as every `*.md` is today. The three lane guards are the motivating
  files, not the scope.

- **AC-4**: Shell coverage (`n/a` / `vacuous` / `measured`) is computed **independently of
  markdown coverage**. A root holding markdown but zero shell files is `n/a` for the shell
  path, NOT `vacuous`. Concretely, the markdown `n/a` branch may no longer `exit 0` early —
  a repo with `tools/*.sh` and no `skills/`/`agents/` root must still get a measured shell
  path.

- **AC-5**: Shell rows live in their **own baseline file**,
  `<repo>/.claude/prose-budget-shell.baseline.tsv`, not interleaved into the markdown TSV. The
  markdown baseline's format and its check-mode column-2 lookup are left byte-identical.
  Columns are `path / total / nonblank / comments / ratio_tenths`, in AC-1's field order; the
  ratchet ceiling reads column 5. **No shipped stub companion**: absence of the repo-local file
  is the existing "no repo-local baseline — every file reports NEW" path, never a failure.

- **AC-6**: The ratchet FAILS when a file's comment ratio exceeds its baseline by more than the
  tolerance, where the ratio is stored as a **scaled integer in tenths of a percent**
  (`541` = 54.1%) and tolerance is applied **additively in percentage points**, not
  multiplicatively. Both choices exist because this code must run on stock bash 3.2 with
  integer-only `(( ))` arithmetic, and because the AC targets in the successor slices are
  themselves stated in percentage points. The conversion **rounds half up** —
  `(( (comments * 1000 + nonblank / 2) / nonblank ))` — not truncates: `lean-gate.sh` at
  `3e83e46` is 2494/4612, where truncation yields `540` and contradicts this AC's own worked
  example of `541`. Tolerance is `PROSE_SHELL_TOLERANCE_PP`, default `5`.

- **AC-7**: `--report` prints the four AC-1 fields for every measured shell file, and
  `--update-baseline` writes their rows. The definition is validated against the epic's stated
  measurement commit: run over `git show 3e83e46:<file>` the three lane guards report exactly
  54.1%, 59.6% and 45.1%, and that check is shown in the PR body. The committed baseline
  carries the values at this branch's base, which for `lean-gate.sh` is 53.9% — the file grew
  97 lines between `3e83e46` and `54aec70`. No selftest case pins a ratio of a real repo file;
  such a case would red on any later edit to the very files #553 and #554 exist to change.

- **AC-8**: The markdown path is unchanged — every existing `prose-budget-selftest.sh` case
  passes **untouched**, and existing markdown baseline rows keep their current values. The
  `--update-baseline` empty-snapshot refusal and its `PROSE_ALLOW_EMPTY_BASELINE` hatch keep
  their present markdown-keyed condition.

- **AC-9**: `prose-budget-selftest.sh` gains shell-path cases: a measured file, a file over
  tolerance, the `n/a` outcome, a genuinely vacuous root (a root containing shell files that
  are all excluded), and the AC-2 `tools/` inclusion.

- **AC-10**: The sweep is read-only and never reds the lean lane. It stays reachable from
  `pipeline-doctor.sh`, whose branch set gains one arm per shell failure state, and it runs in
  `.github/workflows/nightly-guards.yml` as one standalone `ubuntu-latest` job. That nightly
  job MAY go red on a ratchet failure — same posture as the other guards in that file;
  "advisory" scopes the lean lane, not CI.

- **AC-11**: Operator-facing output stays unambiguous across the two paths. The shell path's
  three failure states carry marker literals distinct from their markdown counterparts —
  `FAIL vacuous shell coverage`, `FAIL stale shell baseline`, `FAIL ratio grew` — none a
  substring of `FAIL vacuous coverage` / `FAIL stale baseline` / `FAIL grew`, so no
  `pipeline-doctor.sh` branch can claim another's output. The last line of output remains a
  single combined summary naming both tolerances, because `pipeline-doctor.sh` reads the OK
  message with `tail -1`.

- **AC-12**: Mutation obligations are discharged in the same diff. `tools/mutation-baseline.tsv`
  rows keyed `prose-budget.sh::detector::2` and `prose-budget.sh::logic::1` are re-derived, and
  `tools/mutation-catalog.tsv`'s `prose-budget-stale-gate` row is re-verified — the shell
  staleness block uses distinct variable names (`sh_rows`/`sh_stale`) so that row's literal
  `stale == rows` pattern stays single-site.

## Out of scope

- Cutting any prose. #553 (`lean-gate.sh`) and #554 (the other two) do that, and both are
  blocked on this slice.
- Re-tightening a ceiling when a ratio *falls*. Declared OR-1 in the pre-flight ledger,
  `reversible-default-and-flag`: #553/#554 each re-run `--update-baseline` in their own diff.
- Heredoc awareness. Comment counting is textual by the ticket's Constraints, so a heredoc body
  line beginning with `#` counts as a comment; the approximation is documented in the tool
  rather than special-cased.
- `scripts/` and `tests/`. AC-2 fixes the root set at `prose_roots()` + `tools/`.

## Verification

```
SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
```
plus a diff-scoped `tools/mutation-sweep.sh`. Stock bash 3.2 is a live CI lane: no
`declare -A`, no float arithmetic.

## Design

Design: none — this change renders nothing outside a terminal and two committed TSVs.
