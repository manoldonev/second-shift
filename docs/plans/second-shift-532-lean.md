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

15 sites. Three convert; the rest are dispositioned with a reason:

| Site | Disposition |
| --- | --- |
| `detect.sh:38` (`claude mcp list`) | **converted** — a failed read misdetects the tracker at onboarding |
| `pipeline-doctor.sh:192` (`gh pr list --help`) | **converted** — a failed probe fabricates "old gh" |
| `pipeline-doctor.sh:509` (`claude mcp list`) | **converted** — its own comment already says to treat this as "unknown"; the code did not |
| `ci.yml:54`, `pr-revision/SKILL.md:175`, `statectl.sh:708`, `retro-corpus.sh:269`, `scope-shadows.sh:87` | **safe** — each fails *closed*, or its wrong branch dies loudly one line later |
| four selftest-internal sites, two `2-worktree.md` sites | **out-of-scope** — as the ticket scopes them (`#348` deletes the latter) |
| two sites inside a quoted pattern / a comment | **not-a-site** — the recipe's own textual false positives, recorded rather than silently filtered |

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
  dispositioned. It also scans for the two session-authored shapes that were never in a file —
  `$(… || echo <literal>)` and `$(… 2>/dev/null || true)` feeding a decision — since only a shape
  guard could ever have caught them.
- **AC-5** Tests. `checked-call-selftest.sh` drives the three outcomes against the real
  production text. `check-fail-open-shapes-selftest.sh` covers the guard: clean tree, an
  unclassified new site, anchor drift, and each forbidden shape. `tools/mutation-catalog.tsv`
  gains rows for the new guard, since a guard nothing kills is not coverage; generic survivor
  ordinals re-keyed by editing `detect.sh`, `pipeline-doctor.sh` and `lean-gate.sh` are
  re-baselined in this diff.

## Out of scope

The three claimed instances the ticket records as **not repo code** stay out: two were
session-authored one-liners and one is already fixed and guarded. AC-4's shape legs are the only
thing that could bind them, and they bind them by class, not by site.

`#533` touches `check_pause_and_ask` too. This lands first; whichever lands second rebases.
