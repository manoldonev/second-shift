# second-shift #464 — config-grill's web-surface checks must not fire on a repo that renders nothing

Issue: #464 · lane: run-lean · pre-flight ledger: none

## Problem

`config-grill.sh`'s trigger-2 helper `t2_key` treats every glob key as universal: zero tracked
matches is always a finding. That is right for `T2.formatGlob` — every repo has files to format —
and wrong for the two web-conditional keys, where "this repo renders nothing" is a terminal fact
rather than a config omission.

Grilling this repo's own config (343 `.md`, 144 `.sh`, 91 `.json`, 38 `.mjs`, zero `.tsx`/`.jsx`/
`.css`) emits two FAILs demanding hand-authored globs for files that do not exist. Every shell,
CLI or library repo onboarded to the marketplace hits the identical pair and writes the identical
waiver prose. A waiver should carry a judgment the tool cannot make, not restate a fact it can
measure.

The evidence to decide it is already in hand at the point of the finding: the tracked-file list
`t2_key` already sweeps.

## Shape

An **applicability probe**: caller-set state alongside `DEFAULT_GLOBS`/`CANDIDATES`, consulted by
`t2_key` only once the configured-or-default globs have scored zero. When the probe is non-empty
and nothing in the tree matches it, the capability the key gates does not exist in this repo, so
the entry goes to `add_noteval` instead of `add_finding`.

`notEvaluated` — not `unadopted` (#462's third severity). `unadopted[]` is for an optional key
sitting at its default that a human should dispose of; it is waivable and carries a proposal. A
repo that renders nothing has no disposition to force and nothing to propose, which is exactly the
`notEvaluated` contract. Routing it to `unadopted[]` would re-impose the waiver-prose tax this
change exists to remove — onboard blocks on `unadopted[]`.

The probe is extension-shaped and deliberately generous — component and stylesheet forms only.
Bare `.ts`/`.js` are excluded on purpose: including them makes the probe never fire for any
TypeScript repo, which defeats it. `.html` is what catches the Angular shape (`.ts` + template),
matching the existing `src/app/**/*.{html,ts}` candidate.

Failure direction is conservative by construction: a stray tracked `.html` means the probe declines
to convert and present behavior stands. Over-firing is the safe error, so the probe only ever
suppresses when confident.

No new matching machinery. The probe reuses `count_glob_matches`, whose slash-free branch already
transliterates `*` as crossing separators — exactly the semantics an extension probe wants.

**Not in scope.** `T2.formatGlob` keeps present behavior. `doctor.sh` is not touched: `notEvaluated`
rendering already exists there and is already pinned. No doc AC is owed — no prose anywhere states
the "zero matches is a finding" rule per key; `docs/extending.md`, `onboard/SKILL.md` and
`doctor.sh`'s 7.9 block all describe the three channels generically and stay true.

## Acceptance Criteria

**AC-1 — the probe converts the two web keys on a repo that renders nothing**
(oracle: `plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh`).

A fixture git work tree with no web-surface file and both keys unset yields `notEvaluated` entries
for `T2.webComponentGlobs` and `T2.visualCaptureTriggerGlobs` — same ids and keys the finding would
have carried — and **no** `findings[]` entry for either. The reason names the probe, so the line is
diagnosable on its own.

The probe set is exactly `tsx`, `jsx`, `vue`, `svelte`, `astro`, `html`, `css`, `scss`, `sass`,
`less`. A tracked `.ts` file alone must NOT hold the probe open (the exclusion is the point, not an
oversight), and a tracked file with any one probe extension must.

**AC-2 — the regression guard: a real web surface still fires** (oracle:
`config-grill-selftest.sh`). Both arms, because they are different branches of `t2_key`:

- **a candidate matches** — the existing `t2-web-default` case (`src/App.tsx`, `src/Button.tsx`)
  keeps firing with its proposal naming `src/**/*.{tsx,jsx}` and its count, and the hand-set-value
  case on the same tree keeps firing. A configured value that matches nothing is the same defect as
  an absent one, and the probe must not silence it.
- **no candidate matches** — a tree carrying a web-surface file that neither the resolved default
  nor any shipped candidate matches still yields the finding for both keys, including the "no
  candidate from the shipped list matched" proposal and the comma-joined four-literal
  `visualCapture.triggerGlobs` default. This is the branch the probe sits next to, so it is the one
  that can be silenced by accident.

The existing cases that lose their meaning under the probe are **re-pointed, not deleted**: the
`t2-no-alt` tree (`docs/guide.md` only) becomes AC-1's fixture, and the no-candidate assertions move
to a tree that carries a web-surface file in a location no candidate reaches. The hand-set
`visualCapture.triggerGlobs` case moves onto a tree that has a web surface.

**AC-3 — `T2.formatGlob` is unchanged, and the probe does not leak into it** (oracle:
`config-grill-selftest.sh`). Its existing cases pass untouched, including the slash-free-glob case
and the hand-set-value case. The leak guard is explicit: on the `t2-format-go` tree (`main.go`,
`pkg/server.go` — zero web-surface files), `T2.formatGlob` must still **fire** in the same call
where both web keys land in `notEvaluated`. A probe left set from the preceding call would convert
`formatGlob` too, and only a fixture with no web surface can catch it.

**AC-4 — doctor's rendering is unchanged** (oracle:
`plugins/second-shift/skills/doctor/tools/doctor-selftest.sh`). The `grill-noteval` scenario still
asserts a rendered `not evaluated [T2.webComponentGlobs]` line at rc 0, re-anchored if its fixture's
classification moves. It should not move: the doctor fixture root is not a git work tree, and the
`TRACKED_OK` early return precedes the probe.

## Verification

```bash
bash plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh
bash plugins/second-shift/skills/doctor/tools/doctor-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh
```

Mutation register: `config-grill.sh` carries no `tools/mutation-baseline.tsv` rows (#462 reported
zero survivors on it), so there are no generic ordinals to re-key and no
`tools/mutation-catalog.tsv` row to re-anchor.
