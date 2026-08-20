# second-shift #604 — lockstep pairs are discovered from their markers, not declared twice

**Issue:** [#604](https://github.com/manoldonev/second-shift/issues/604)
**Branch:** `claude/second-shift-604`

## Problem

Every lockstep pair is declared twice — by the `LOCKSTEP-BEGIN <anchor>` markers in the files, and
again by a row in `scripts/lockstep-manifest.tsv`. The second declaration carries all the cost
(729 lines, a merge conflict on every feature PR that appends to it) and adds no information the
first does not already have. It is also provably incomplete: six blocks carry markers that no row
checks, so the apparatus built to prevent false coverage signals emits one.

## Approach

Delete the manifest. `check-lockstep-pairs.sh` discovers `LOCKSTEP-BEGIN` markers by walking the
tree, groups the sites by anchor, and compares every member of a group. A group of size 1 fails —
that is what turns the six orphans red instead of leaving them reading as covered, and it preserves
today's "a missing marker is a FAILURE, not a skip" property from the other direction.

## Findings that amend the issue

Recorded here **before** implementation, because each changes what the ACs must cover. None of them
was visible from the manifest, which is the point of the ticket.

- **F-1 — `docs/plans/**` holds five quoting sites, not three.** The issue names
  `second-shift-394-lean.md`, `second-shift-445-lean.md` and `acme-260.md`. Discovery also finds
  `acme-263.md` (`decomposition-economy`) and `second-shift-427-lean-verdict.md`
  (`cross-plugin-sibling-plugin-root`). The remedy is unchanged — one exclusion covers all five —
  but AC-4's count was low.
- **F-2 — a marker NAME can appear outside a marker.** Three live sites mention the token in prose
  or in code without being markers: `docs/config-schema.md:21` (a backticked reference to
  `LOCKSTEP-BEGIN seam-scrub`, mid-sentence), `scripts/check-lockstep-pairs-selftest.sh:101-102`
  (the token inside a `sed`/`grep` argument), and `scripts/check-lockstep-pairs.sh`'s own header.
  A naive "grep for the token" discovery adds a phantom third member to `seam-scrub` and a phantom
  fourth to `findings-schema`, and both would red a correct tree. Discovery therefore needs a
  marker GRAMMAR, not a substring search — see AC-1.
- **F-3 — the six orphans are all genuinely single-sited; none gains a counterpart.** Each block's
  own prose says so, and the manifest confirms it by never mentioning five of them:
  `pipeline-chain-required-markers` ("now the SOLE carrier … markers are left in place so a future
  row is cheap"), `prettier-local-rungs` ("nothing outside this file holds them now"),
  `provenance-enum` (single-sited by an explicit #517/#562 decision), `lean-chain-artifact-patterns`
  (the manifest DROPS the pair as "deliberately DIFFERENT sets"), `ac-id-rule` (the intake side
  carries a by-name pointer, not a copy), `stage8-secondary-review` (only site is a plan doc).
  So AC-2 resolves all six by the "loses its markers" arm.
- **F-4 — the false coverage signal was load-bearing.** `docs/plans/acme-167.md`,
  `acme-265.md` and `second-shift-393-lean-verdict.md` each reason about "the live `ac-id-rule`
  row" and cite `check-lockstep-pairs.sh` as proving those copies "still match byte-for-byte".
  No such row has ever existed. Three runs planned against coverage that was not there.
- **F-5 — the newest row shipped with no rationale at all.** `tier-alphabet-parse` (#596) sits at
  EOF under the `#527` verify-lane-exit-code note, which is about something else entirely. The
  append-at-EOF shape does not just conflict; it detaches rationale from row.
- **F-6 — a selftest fixture is a discovery site.** Fixture trees built under `mktemp` are outside
  the walk, but a heredoc INSIDE a selftest source that contains a whole-line marker is not. The
  new suite therefore assembles its fixture markers at runtime rather than writing them literally,
  and AC-8 adds a live-corpus case that would catch a future paste.

## Design decisions

- **D-1 — marker grammar (resolves F-2).** A marker is recognised only when it occupies its whole
  line, modulo leading indentation, an optional host comment opener (`#`, `//`, `<!--`) and an
  optional `-->` closer. Every one of the 42 live markers already satisfies this except
  `ac-id-rule`'s BEGIN, which trails a prose sentence — and that anchor is being retired by AC-2
  anyway. Rejected alternative: "a BEGIN counts only if its file also has a matching END", which
  excludes the three phantoms but silently drops a real block whose END was deleted — the exact
  drift the guard exists to catch.
- **D-2 — the relation lives on the BEGIN marker (AC-3).** An optional third token: absent means
  `verbatim`; `superset` and `subset` spell the `subset-of` relation AND its direction at the
  sites it binds. Only one group uses it (`seam-scrub`), so requiring an explicit token on all 42
  markers would be churn without signal. An unrecognised token is a hard failure, never a silent
  fallback to `verbatim`.
- **D-3 — END markers carry the anchor only.** A relation token on an END makes the line fail the
  grammar, which leaves its BEGIN unclosed, which already fails. No extra code.
- **D-4 — the walk is `find`-based, not `git ls-files`.** The suite drives the checker against
  fixture trees that are not git repositories.

## Acceptance criteria

- **AC-1** `check-lockstep-pairs.sh` takes no manifest argument. It discovers `LOCKSTEP-BEGIN`
  sites under a repo root, groups them by anchor, and compares all members of each group.
  A site is recognised only under the D-1 whole-line grammar. `scripts/lockstep-manifest.tsv`
  is deleted, and the CI step no longer names it.
- **AC-2** An anchor with exactly one site fails, naming the file and the anchor. All six orphans
  are resolved in this PR by removing their markers (F-3), each leaving a one-line comment stating
  that the block is single-sited and what would justify re-adding markers — so the tree is green
  on landing.
- **AC-3** The `subset-of` relation survives, encoded in the marker per D-2. A group carrying
  `superset`/`subset` needs exactly one `superset`; every `subset` member's first single-quoted
  `'...|...'` literal must be a subset of it. A group whose members disagree about their relation
  fails, as does an unknown relation token.
- **AC-4** Discovery excludes `docs/plans/**` — five sites across five anchors (F-1). The exclusion
  is a named constant in the script carrying its reason, not an implicit glob.
- **AC-5** The manifest's `DROPPED`/`RETIRED` rationales move to `docs/testing.md` as decision
  history under their own section. They are not deleted: each records why a coupling was
  considered and rejected, and several name the behavioral guard that replaced it.
- **AC-6** Per-anchor rationale moves to the anchor site, adjacent to its `LOCKSTEP-BEGIN` marker,
  where the person editing the block reads it. Every surviving anchor carries one.
- **AC-7** The 31 live files whose comments point at `scripts/lockstep-manifest.tsv` are
  re-pointed. The 88 historical plan docs are left alone.
- **AC-8** `check-lockstep-pairs-selftest.sh` covers discovery, the size-1 failure, the `subset-of`
  path (both polarities), the relation-disagreement failure, the `docs/plans` exclusion, and the
  three F-2 phantom shapes. It builds fixture markers at runtime (F-6) and carries a live-corpus
  case. `tools/mutation-baseline.tsv` and `tools/mutation-catalog.tsv` rows addressing this script
  are re-anchored against the rewritten code.
- **AC-9** CLAUDE.md's tier map row and `docs/testing.md`'s contract row describe the discovery
  model rather than a manifest row.

## Known trades

- **Deleting BOTH markers of a live pair silently drops it**, where today the orphaned row survives
  and reds. It is a visible diff and the blocks stay covered by their own behavioral suites, but
  it is a real loss. Stated in `docs/testing.md` rather than discovered later.
- **A whole-line marker inside a selftest heredoc becomes a real site** (F-6). Mitigated by the
  live-corpus case in AC-8, and stated in the script header.

## Sequencing

PR 601 (#597) adds a `contribution-compare` pair — two markers plus a manifest row — and is open
against the file this PR deletes. If 601 lands first the conflict is delete-vs-modify and resolves
as "keep the delete", with 601's two markers discovered automatically and no row needed. If this
PR lands first, 601 must drop its manifest row on rebase.
