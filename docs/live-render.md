# Live-render verify — wiring a consumer render harness

`design.liveRender` names one repo-owned render command that `/dev-pipeline:build-lean`'s
milestone 3 runs: after the design engine implements a screen, the gate runs your command, reads
the emitted PNG, and semantically compares it against the cached design frame (placement,
sizing/fill, truncation, default state — not a pixel diff). Without the key an armed ticket reds;
without a provider, nothing arms. See [Lean-lane wiring](#lean-lane-wiring) below.

**One blocking posture.** A failure on this key reds the lean gate. A consumer whose harness
was written against an older, tolerant posture is now on the strict one.
The advisory smoke-capture it was contrasted with, `stageParams.visualCapture`, was retired in
the same change (it had no reader left).

## Config

```jsonc
"design": {
  "provider": "figma",
  "liveRender": {
    "command": "yarn render:verify --route {route} --state {state} --out {out}",  // required
    "cwd": "fe",                                                  // topology repo id; default: the fe repo
    "readyProbe": "http://localhost:3000/system/status"           // optional pre-check URL
  }
}
```

## The command contract

Your script owns **boot, auth, and screenshot**. The gate owns route derivation and comparison.

- **`{route}`** — the app-relative leaf below your feature mount path (e.g. `prospects`,
  `prospects/new`). The harness owns any shell/org/tenant prefix (`/admin/{orgSlug}/offers/…`) —
  operator-specific segments come from the operator's env, never from second-shift config.
- **`{state}`** — *lean lane only, optional.* The render state named by the spec's `| RS-n |` row
  (e.g. `filters expanded`). Your harness maps the name to whatever it takes to reach that view
  and screenshots it. Declare `{state}` in the command whenever any ticket declares a state other
  than `default`; the lean gate refuses the mismatch rather than shooting the default view twice.
  The staged lane never substitutes it.
- **`{out}`** — an absolute PNG path. Emit exactly one screenshot there; the gate treats a missing
  or zero-byte file as failure.
- **Placeholders appear UNQUOTED** in the command. The lean gate shell-quotes each substituted
  value itself — a state name is human prose and contains spaces — so `--state {state}` is correct
  and `--state "{state}"` nests the quoting and delivers a literally-quoted argument. Values are
  substituted literally: a route carrying a query string (`?tab=new&sort=asc`) and a state
  carrying punctuation both reach the harness verbatim.
- **Exit code** — nonzero on any failure, with a one-line actionable message on stderr/stdout
  (e.g. `API not reachable on :3000 — start the backend dev server in the sibling repo`). That tail
  becomes the operator-facing reason on a milestone-3 red, and the degraded-condition detail in
  the PR body.
- **Failure is blocking.** A failure reds milestone 3 on the run's shared 3-attempt fix budget,
  and the 4th red hard-stops.  Make the message good enough that the operator can fix the prerequisite and re-run — here
  it costs an attempt.
- **`readyProbe`** — declare your harness's external prerequisite (typically a sibling BE health
  endpoint) so the gate fails fast with the probe URL instead of waiting out a render timeout.
  Under the blocking lean posture this is what keeps an environmental red cheap: pay a probe, not
  a timeout, for the same attempt.

## Reference harness shape (Playwright, MIFE-in-shell)

A worked example: a Vite MIFE mounted in a platform admin shell, backed by a sibling BE.

- **Playwright config** with two projects: a `setup` project (auth) and a `render` project
  (`dependencies: ['setup']`, consumes the storage state). `webServer` boots the FE dev server
  with the local-API env override; the BE is probed, not booted (its lifecycle belongs to the
  operator/pipeline — a sibling-relative path breaks inside worktrees).
- **Hybrid auth** — the setup project refreshes a Playwright `storageState` file via the real
  signin flow (through the FE dev proxy, using an API `request.newContext()` — no browser page)
  **when credentials are present in env** (`E2E_USERNAME`/`E2E_PASSWORD`); otherwise it consumes
  an existing, manually exported state file as-is. State lives at a gitignored path.
- **Render spec** — `goto` the composed URL, deterministic wait (network idle + fonts + an
  optional selector), `page.screenshot({ path: out, fullPage: true })`.
- **CLI wrapper** — parses `--route`/`--out`, sets env, spawns `playwright test` with the render
  config, propagates the exit code. Wire it as the `render:verify` package script the config
  command names.

## Worktree traps (both bite silently — design for them)

1. **Never reuse a foreign dev server.** Pipeline runs execute in the ticket's worktree; if the
   operator's own dev server already holds the port, `reuseExistingServer: true` would screenshot
   the **main checkout's** code and pass. Default reuse **off** (fail loud on port collision via
   `strictPort`) and gate interactive reuse behind an explicit env opt-in.
2. **Gitignored state does not exist in fresh worktrees.** Accept an absolute-path env override
   for the auth-state file (e.g. `E2E_AUTH_STATE`) so a worktree run can point at the operator's
   maintained state — or set the credential env vars and let the setup project mint a fresh one.

## Lean-lane wiring

`/dev-pipeline:build-lean` reads `design.liveRender` directly. The `extraLanes` workaround this
section used to describe is **superseded** — an opaque lane retained no screenshot, named no
state, and bound nothing to a review, which is exactly how a *passing* render came to verify a
screen's default collapsed state.

**Arming is per ticket, and takes two things at once.** Config `design.provider` must be set, AND
the committed lean spec must carry a `## Design` section. A provider with no section reds
milestone 1; a section in a repo with no provider arms nothing. The section takes one of two
forms:

```markdown
## Design

Handoff: https://<your provider>/file/abc123

| RS-n | route | state (what must be visible) | AC refs |
| --- | --- | --- | --- |
| RS-1 | prospects | default | AC-2 |
| RS-2 | prospects | filters expanded | AC-3 |
```

…or the explicit disarm, `Design: none — <reason>`, which is a conscious per-ticket decision and
is **state-locked**: once a run has armed, switching to the disarm reds at milestones 1 and 3.

**What the gate does when armed — first, the translation plan.** Before the harness is called
once, milestone 3 asserts a committed **translation plan** at `<plansDir>/<key>-lean-plan.md` —
the artifact `design-toolkit:figma-faithful` step 7 writes. It must carry a `planned_from:` header
(the gate stamps it with the branch's plan patch identity and reds until the stamp is committed),
a table declaring a **`why this component`** column, and a table declaring a **`dimensions`**
column, with every cell of both filled and no row shorter than its header. The ordering is the
point: a wrong token row should red before anything is rendered, because one table cell is the
cheapest place to fix it.

Its reds are split across the two budgets on #642's criterion. Absence, a missing `planned_from:`
line and a stale stamp are **absent**-budget reds naming the checklist's own next step, so they
cost no fix attempt; a table that is present and malformed is a fix attempt, because the plan was
written and what was written is wrong. That split is what keeps an armed run from spending two of
its three milestone-3 attempts reaching its first screenshot.

What the plan buys is that an omission reads as an **empty cell** rather than an absent thought.
Nothing here checks that a recorded component is the right one or a recorded dimension is the
design's — `design-toolkit:figma-faithful-plan-reviewer`, which the implementing session dispatches
at step 7, asks those as questions the plan must answer. It is deliberately **not** re-asserted at
the merge boundary: the boundary re-asserts the verdict chain, and `fidelity: pass` binds to the
render receipt, not to the plan.

**Then the render.** Milestone 3, last — after `extraLanes` — renders every declared row through
your command, asserts exit 0 and a non-empty PNG per row, and writes a hash manifest at
`<plansDir>/<key>-lean-renders.md`. PNG bytes never enter history: they
land under `.claude/lean-renders/<key>/`, which the gate asserts is git-ignored before it renders.
Milestone 4 then refuses any verdict that does not score `fidelity: pass`, or whose manifest was
rendered from different code.

**The receipt is written in Prettier's table form**, cell-padded at the write site, so a repo
whose format gate covers `<plansDir>` does not go red on the artifact its own milestone told it
to commit. The gate computes that padding itself and never reaches the network for a formatter.
Two caveats: the receipt's header block (`rendered_from:` / `issue:` / `spec:`) is plain prose, so
a `proseWrap: "always"` config still fails `--check` on it; and padding is computed by character
count, so a wide-glyph `route` or `state` cell would mis-pad. The spec and any intent-gap record
are yours to format — the gate formats only what it authors.

**Prerequisites are the operator's, and they are worth doing before the run.** Under the blocking
posture an unreachable dev server or a stale auth state costs a milestone-3 attempt. Before
starting an armed run: have the harness's dependencies up (declare the health endpoint as
`readyProbe`), have the auth state reachable from a fresh worktree (see the Worktree traps
section above), and confirm the harness runs green by hand once from the ticket's worktree.

**Rendering must be byte-deterministic.** Two declared states that produce byte-identical
screenshots red — that is the detector for a harness that ignores `{state}` and shoots the same
view twice. When a collision is legitimate the remedy is merging or re-scoping the rows, never
suppressing the check. Sources of nondeterminism worth pinning in the harness: animations and
transitions (disable them), live timestamps and relative-time strings, randomly seeded fixture
data, font loading, and scrollbar/viewport differences.

**Comparison is still not the gate's.** Nothing here diffs a screenshot against a design frame.
The gate owns the state matrix, the paths, the hashes and the manifest; the fidelity judgment is
scored by the `/dev-pipeline:review-lean` session, design-sighted, from a checkout of the reviewed
head, and recorded as `fidelity:` in the verdict record.

**What the gate does own about that judgment is its SHAPE, not its truth.** An armed
`--fidelity pass` is refused at the writer unless the review summary carries a
`## Design fidelity evidence` table: six named columns
(`RS-n | frame node | property | design | rendered | verdict`), every cell populated, one or more
rows for each declared `RS-n` and none for a state the spec does not declare, and a `verdict` cell
reading `match` or `deviation (<AC-n|D-n>)` citing a criterion the spec actually carries. The
grammar is published to its producer in `review-lean/SKILL.md` step 5b.

That is **tamper-evidence, not fidelity.** It converts a one-word header nobody could falsify into
a record a human can read and contradict, and raises the cost of a rubber stamp from typing a word
to fabricating node references, paired numbers, and a citation that resolves in a patch-bound
spec. It verifies nothing against the design — the pixel-diff gate is still deferred, and a
reviewer can still cite a real but irrelevant criterion. The refusal sits at the **writer** rather
than at milestone 4 so a malformed table costs an edit instead of a round, and there is
deliberately **no milestone-4 backstop**: a verdict record carries no schema version, so a legacy
evidence-free `pass` is byte-indistinguishable from one whose section was stripped after the fact,
and every record written before this shipped keeps passing unchanged.
