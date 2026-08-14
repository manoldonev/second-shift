# #532 — a dead call is indistinguishable from a negative result

`producer | grep -q P` has two outcomes where the world has three. When the producer dies,
`grep` sees an empty stream and reports *no match*; under `pipefail` a dead producer makes the
pipeline non-zero, which reads as *no match* again. Either way the caller learns "no", and "no"
is a lie — the honest answer is "unknown".

The same defect wears a second costume: `out="$(cmd)" || { warn; return 0; }`, where `return 0`
means **clear**. `check_pause_and_ask` in `lean-gate.sh` is the live instance: a network blip
reads as "no unresolved pause-and-ask region" and milestone 1 passes.

## Approach

Three-outcome return codes, everywhere. `0` = yes, `1` = a genuine no, **`2` = the producer
failed and the answer is unknown**. That vocabulary is the shared contract — a function carries
it for the pipeline sites, and `check_pause_and_ask` adopts the same numbers for the capture
site, so one rule ("2 means you may not treat this as a negative") covers both shapes.

**`checked_match` is a lockstep block, not a sourced library, at the second-shift plugin's copy.**
The two call sites that need it live in *different plugins*, and a cross-plugin path resolved by
hop count is the trap #469 was filed for. So the canonical text lives in
`plugins/dev-pipeline/skills/run/tools/checked-call.sh` (sourced by its same-directory consumer,
the `_effective-registry.sh` precedent), and `detect.sh` carries a byte-identical copy pinned by
a `verbatim` row in `scripts/lockstep-manifest.tsv`. That is the tier map's own answer for two
copies of one contract, and it is why the selftest can drive the real production text rather
than a mirror.

**The enumeration is the artifact, and a bare count cannot be it.** Three prior measurements of
"the sites" disagreed (17/18/26) purely on scoping. So the guard *carries* the recipe
(`check-fail-open-shapes.sh --list` prints it), its output is the denominator by definition, and
every row of that denominator must be dispositioned in `scripts/fail-open-sites.tsv`. An
unclassified site reds; a row whose anchor no longer matches reds as drift. Neither the recipe
nor the classification can rot silently, because each is the other's check.

**The classification is anchored on text, never on line numbers.** A `file:line` key would red on
every unrelated edit above it, and a guard that cries wolf gets baselined away.

### What the denominator says today

Three sites convert; the rest are dispositioned with a reason. The counts below describe this
diff, not the contract — the contract is that `--list` and the table agree exactly.

| Site | Disposition |
| --- | --- |
| `detect.sh` (`claude mcp list`) | **converted** — a failed read misdetects the tracker at onboarding |
| `pipeline-doctor.sh` (`gh pr list --help`) | **converted** — a failed probe fabricates "old gh" |
| `pipeline-doctor.sh` (`claude mcp list`) | **converted** — its own comment already says to treat this as "unknown"; the code did not |
| `ci.yml`, `pr-revision/SKILL.md`, `statectl.sh`, `retro-corpus.sh`, `scope-shadows.sh` | **safe** — each fails *closed*, or its wrong branch dies loudly one line later |
| four selftest-internal sites, two `2-worktree.md` sites, the two lines case (c10) runs on purpose | **out-of-scope** — as the ticket scopes them (`#348` deletes the `2-worktree.md` pair) |
| four sites inside a quoted pattern, a comment, or a header paragraph | **not-a-site** — the recipe's own textual false positives, recorded rather than silently filtered |

Two whole file classes are out of the scan, both for one reason — they are never executed, so a
shape in them is quoted shell rather than a call site: `docs/plans/` (the run-artifact archive)
and every `*.tsv`. The second matters more than it looks: `tools/mutation-catalog.tsv` is a
corpus of deliberately broken shell, and a catalog row whose job is to describe reintroducing a
banned shape would otherwise red the guard for saying so.

### A correction to the ticket's premise

The ticket states that `check_pause_and_ask`'s two `gh` arms make milestone 1 **pass** on a
network blip. They do not. Each arm prints a reason, the caller treats any non-empty reason as a
refusal, and `lean-gate-selftest.sh`'s (n16) already depended on that. What they could not do is
refuse for the right *reason*: an unreadable tracker was charged to the fix budget, so three
blips hard-stopped the run at `rc=4` with a rescue path no edit could clear. That is what AC-2
fixes. The genuine fail-open in that function is the third arm the ticket does not mention — the
`--issue-file` `jq`, whose discarded stderr and empty result enumerate no regions and return
clear.

## Acceptance criteria

- **AC-1** `checked_match` exists and returns three distinguishable outcomes — matched (0), a
  genuine no-match (1), and **producer failed** (2) — from one canonical text, with the
  second-shift copy pinned byte-identical by a lockstep manifest row.
- **AC-2** `check_pause_and_ask` distinguishes "read the issue and found nothing" from "could not
  read the issue". An unreadable issue or comment trail is an **environment refusal** (`rc=2`),
  never a clear and never a fix attempt — the read failing is not a fix the build role can make.
  The refusal is raised by the *caller*, because `envfail` inside the `$(…)` this function is
  invoked through would kill only the subshell and leave `reason` empty — i.e. would fail open in
  the act of fixing a fail-open.
- **AC-3** `scripts/check-fail-open-shapes.sh --list` is the committed, reproducible enumeration
  recipe, and its output is the denominator. Every enumerated site is dispositioned in
  `scripts/fail-open-sites.tsv` (`converted` | `safe` | `out-of-scope` | `not-a-site`, each with a
  reason). An unclassified site is a failure; a row whose anchor matches nothing is anchor drift,
  also a failure.
- **AC-4** `scripts/check-fail-open-shapes.sh` prevents reintroduction as code: a new
  command-producer `| grep -q` site anywhere in the tree reds until it is converted or
  dispositioned, and the counting `pgrep -c` / `pgrep -fc` form is banned outright.

  The second leg is the honestly-decidable slice of the session-authored family. `pgrep -fc …
  || echo 0` is what reported "0 competitors" with 33 processes live, and the counting form is
  what invites the fabrication — the repo's one legitimate `pgrep` already uses `pgrep -f … |
  wc -l`. The *general* `$(… || echo <default>)` shape is **not** a leg: measured over this
  tree it matches 51 files, nearly all of them the `$(cond && echo a || echo b)` ternary or a
  `jq … || echo <config default>`, and a guard that reds on those would be switched off inside
  a week. Same posture as `stack-generality-lint.sh`, which guards only the legs a substring
  check can honestly decide.

  Stated plainly, because AC-4's own text overreaches: a repo lint **cannot** catch shell a
  session typed into a tool call — those instances were never in a file for any scanner to
  read. What the guard buys is that the shape is named, enforced wherever it *is* visible, and
  no longer a convention someone has to remember.
- **AC-5** Tests. `checked-call-selftest.sh` drives the three outcomes against the real
  production text, and executes the replaced pipeline beside them so the collapse is pinned by
  a run rather than by a comment. `check-fail-open-shapes-selftest.sh` covers the guard,
  including the real repo tree (which is how it reaches CI at all — there is no `ci.yml`
  registration, only the `*-selftest.sh` glob) — including `--help` and the row-scratch
  `TMPDIR` fallback, two seams no fixture case reaches. `lean-gate-selftest.sh` gains
  (y9)-(y11) and `detect-selftest.sh` a THREE-sided MCP case: dead producer, genuine no, and
  the match. The third is not symmetry — the first two both leave the evidence array empty, so
  without it a `checked_match` whose matcher never matched passes the suite as written.
  `tools/mutation-catalog.tsv` gains rows for both new guards, since a guard nothing kills is
  not coverage; generic survivor ordinals re-keyed by editing `detect.sh`,
  `pipeline-doctor.sh` and `lean-gate.sh` are re-baselined in this diff.

  The generic operators sweep at most **k=2 sites per class**, which makes comment prose that
  quotes an operator literal a coverage hazard and not just noise: in both copies of the idiom
  the first two `detector` sites were comments, so the real matcher sat at ordinal 3, outside
  the window, and its never-match mutant was unreachable rather than merely unkilled. The
  three comments carrying such a literal are reworded so the budget lands on executable code.
  Where prose is left holding a slot (`check-fail-open-shapes.sh`'s two `logic` ordinals), the
  baseline row records what it displaces and why that is the better trade.

## Out of scope

The three claimed instances the ticket records as **not repo code** stay out: two were
session-authored one-liners and one is already fixed and guarded. AC-4's `pgrep` leg binds one
of them by class; nothing in a repo can bind shell that was never committed.

`#533` touches `check_pause_and_ask` too. This lands first; whichever lands second rebases.
