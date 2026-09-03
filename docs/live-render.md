# Live-render verify — wiring a consumer render harness

`design.liveRender` names one repo-owned render command that `/dev-pipeline:build-lean`'s
milestone 3 runs: after the design engine implements a screen, the gate runs your command, takes
the emitted PNG, and hashes it into the render receipt bound to the reviewed patch. **The gate
holds no design frame and diffs no pixels.** It does compare one thing — the sizes the translation
plan transcribed against the sizes your harness measured in the DOM ([Measured
sizes](#measured-sizes-the-rectsjson-sibling) below). Everything else about the comparison
(placement, sizing/fill, truncation, default state) is the design-sighted
`/dev-pipeline:review-lean` session's, scored as `fidelity:` in the verdict record — and it stays
that way, by decision: see
[Why there is no pixel-diff gate](#why-there-is-no-pixel-diff-gate-and-none-is-coming) below.
Without the key an armed ticket reds; without a provider, nothing arms. See
[Lean-lane wiring](#lean-lane-wiring) below.

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
    "cwd": "fe",                                                  // topology repo id that OWNS the harness; unset = this one
    "readyProbe": "http://localhost:3000/system/status",          // optional pre-check URL
    "tolerancePx": 2                                              // optional; default 2
  }
}
```

`cwd` names which repo of the topology owns the harness, and on a multi-repo topology that is also
**which repo the design lane arms**: `design.provider` is configured once for the pair, so a repo
that is not the named owner unarms and is asked for neither a `## Design` section nor a
design-disarm override. Leave `cwd` unset when the repo you run in owns the harness. A value naming
no `topology.repos` key is a milestone-1 error rather than a silent unarm — otherwise a typo would
retire the design axis with nothing said.

`/second-shift:doctor` applies the same ownership rule when `liveRender` is missing altogether —
the case where there is no `cwd` to read. It asks whether the root it was run in has any tracked
rendering surface at all, and where there is none it reports the check as not-evaluated rather than
demanding a render harness from a repo with nothing to render. So on a pair, `design.provider` in
the shared config no longer produces a doctor FAIL at the backend root. Run doctor from the repo
that owns the surface to grill the harness itself.

## The command contract

Your script owns **boot, auth, and screenshot**. The gate owns route derivation, the state
matrix, the PNG hashes and the manifest — **never comparison**, which is the review session's
([why](#why-there-is-no-pixel-diff-gate-and-none-is-coming)).

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
- **`{out}.rects.json`** — a second artifact, written beside the screenshot at exactly that path
  (`…/RS-1.png` ⇒ `…/RS-1.png.rects.json`). A JSON **object keyed by the translation plan's node
  names** — the first column of its sized-node table — whose values carry the node's rendered
  `width` and `height` in **CSS pixels**:

  ```json
  { "Filter panel": { "width": 320, "height": 604 }, "Results grid": { "height": 412 } }
  ```

  Resolving a node name to a DOM element is **yours**: you own the DOM, and the gate owns only the
  arithmetic. Emit the object for every declared state, `{}` included — "the file is missing" and
  "this state has nothing to report" are different claims, and only the second is an answer.
  A node you cannot resolve is **omitted from the object**, and the gate then reds that node:
  silence is not a pass, so a node you cannot measure comes out of the plan or gets resolved in
  the harness. An axis you cannot measure is omitted the same way, and reds the same way if the
  plan states a number for it.

  **CSS pixels, not device pixels.** A harness screenshotting at `deviceScaleFactor: 2` and
  reporting device pixels renders a correct implementation at a uniform 2.0 and takes a hard
  `scale` red — that is a harness bug, and the gate deliberately does not tolerate an integer
  factor to paper over it.
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

**The disarm alone is not enough on a provider repo (#709).** A build session writing `Design:
none — <reason>` on its own is the opt-out this mechanism exists to forbid, so the gate additionally
requires a gate-visible `design-disarm` operator override before it accepts the disarm — an
attended operator, present before the run, records one:

```
bash <path-to>/operator-override.sh record --gate design-disarm --scope design-disarm \
  --issue <n> --decision '<what the operator decided, one line>' --answer '<their answer, verbatim>'
```

With no record, milestone 1 reds naming that exact command. With a valid record, the ticket is
`disarmed` and the committed verdict carries `fidelity: not-applicable (override: <ref>)`, where
`<ref>` is `<issue>#<n>` — the record's own block ordinal. The merge boundary resolves that ref
against the committed record independently of config, which it cannot read on a consumer.

**What the gate does when armed — first, the translation plan.** Before the harness is called
once, milestone 3 asserts a committed **translation plan** at `<plansDir>/<key>-lean-plan.md` —
the artifact `design-toolkit:figma-faithful` step 7 writes. It must carry a `planned_from:` header
(the gate stamps it with the branch's plan patch identity and reds until the stamp is committed),
a table declaring a **`why this component`** column, and a table declaring a **`dimensions`**
column — which since #711 also declares **`node`**, **`RS`** and **`px`** beside it: the key your
harness reports that node under, which declared render state it is measured in, and its design
size as `<w>×<h>` with an integer or `-` per axis (`348×32`, `-×32`). Every cell of both tables is
filled and no row is shorter than its header. `dimensions` stays prose — it carries the per-axis
fixed/hug/fill and overflow reading `figma-faithful` step 3b takes, which a bare `348×32` cannot. The ordering is the
point: a wrong token row should red before anything is rendered, because one table cell is the
cheapest place to fix it.

Its reds are split across the two budgets on #642's criterion. Absence, a missing `planned_from:`
line and a stale stamp are **absent**-budget reds naming the checklist's own next step, so they
cost no fix attempt; a table that is present and malformed is a fix attempt, because the plan was
written and what was written is wrong. That split is what keeps an armed run from spending two of
its three milestone-3 attempts reaching its first screenshot.

What the plan buys is that an omission reads as an **empty cell** rather than an absent thought.
Nothing in the shape check tells you a recorded component is the right one or a recorded dimension
is the design's — `design-toolkit:figma-faithful-plan-reviewer` asks those as questions the plan
must answer.

**And on an armed lean run that dispatch is mandatory, not advisory.** The gate cannot run an
agent, so it takes the verdict record's shape: the build session dispatches the reviewer on the
committed plan and writes its output with `lean-gate.sh plan-review <issue> --verdict
<pass|fix-and-go|block> --summary-file <findings> --model <m>`, which stamps `reviewed_plan_from`
from the checkout. Milestone 3 then refuses — **before any render command runs** — when the record
at `<plansDir>/<key>-lean-plan-review.md` is missing, when its `reviewed_plan_from` no longer
matches the branch's plan binding, or when its verdict is `block`, quoting the first finding.
`pass` and `fix-and-go` proceed; committing the record never stales it, because that path is
excluded from the binding exactly as the plan is. A family with no plan-reviewer agent
(`claude-design` has none today) is unreviewed at this stage and the gate says so rather than
demanding an artifact nobody can produce.

None of it is re-asserted at the merge boundary: the boundary re-asserts the verdict chain, and
`fidelity: pass` binds to the render receipt, not to the plan.

**Then the render.** Milestone 3, last — after `extraLanes` — renders every declared row through
your command, asserts exit 0 and a non-empty PNG per row, compares the measured sizes (below), and
writes a hash manifest at `<plansDir>/<key>-lean-renders.md` carrying two rows per state: the
screenshot, and the `RS-n.rects` sibling. PNG bytes never enter history: they
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

### Measured sizes: the `.rects.json` sibling

**One number the gate does read.** For each declared state it joins the plan's `px` cells to your
`.rects.json` entries by node name, and the comparison is **scale-adaptive rather than absolute** —
a browser viewport and a design frame differ as a matter of course, and pinning a viewport would
put a second contract on every consumer harness. Per state, over the axes the plan states a number
for, it takes `r = rendered / design` and `k = median(r)`, then raises two separately named reds,
both in pixels against `tolerancePx`:

- **`shape`** — `abs(design × k − rendered) > tolerancePx`: this node is out of proportion with the
  rest of the state. It survives any uniform viewport difference, which is what makes it the
  interesting one.
- **`scale`** — `abs(design × k − design) > tolerancePx`: `k` itself is not explained by tolerance,
  so the whole state renders at `k`. Named **once** per state, because "everything is 2.2×" is one
  fact, not one fact per node.

A state with one stated axis degenerates to plain absolute comparison, since the median absorbs
everything: `33` against a design `32` passes at the default tolerance and reds at `tolerancePx: 0`.

Every mismatch across every state is reported **together**, not the first one — a mismatch is on
the fix budget, and revealing them one per attempt would hard-stop a run at attempt 4 having never
shown the shape of the problem. The two budgets split on what the worktree can fix: a `shape` or
`scale` mismatch, an unparseable `px` cell, a plan node your file does not carry, and an axis the
plan states and your file omits are **fix attempts**; a missing or malformed `.rects.json` is an
**absent**-budget red, because the harness owns it and no branch edit reaches it.

What this does **not** buy: its ground truth is the Figma value *as the build agent transcribed
it*, so it catches plan→code drift and stays blind to design→plan drift. That is
`figma-faithful-plan-reviewer`'s question, asked before any of this runs.

**The rest of the comparison is still not the gate's.** Nothing here diffs a screenshot against a
design frame. The gate owns the state matrix, the paths, the hashes, the manifest and those two
size reds; the fidelity judgment is scored by the `/dev-pipeline:review-lean` session,
design-sighted, from a checkout of the reviewed head, and recorded as `fidelity:` in the verdict
record.

**The provider's fidelity reviewer is mandatory on an armed spec (#708).** It used to be routed by
model judgment over `stageParams.webComponentGlobs`, and a miss left a one-line note in the round
summary while the round proceeded — so an armed ticket could be approved with the design dimension
never reviewed, and nothing in the record said so. `review-lead` now spawns it unconditionally on
an armed spec, and a round that lost it to a dark reviewer is **voided** rather than recorded
(`review-lean` step 5c). The record's `panel:` key is the attestation: the reviewer agent types the
round actually returned a result from, qualified and comma-separated. Milestone 4 and
`check-lean-chain.sh` evidence arm 8 both require it to name the provider's reviewer.

WHICH reviewer is derived from the **handoff link's host**, never from `design.provider`: the first
recognised URL in the `## Design` section naming `figma.com` (or a subdomain) means
`design-toolkit:figma-faithful-reviewer`; `claude.ai` under `/design` means
`design-toolkit:design-faithful-reviewer`. The reason is the same one arming has: the merge
boundary reads a CI checkout where `design.provider` is gitignored and invisible. A handoff host
neither side can classify is refused at milestone 1, where the remedy is a spec edit, and a host
that disagrees with the configured provider is refused there too — the gate is the only reader that
sees both. Like the evidence table below, this is **tamper-evidence**: the panel is agent-written,
and what it buys is that a silently unrun design dimension has to be actively misstated rather than
achieved by an omission.

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
spec. It verifies nothing against the design: a reviewer can still cite a real but irrelevant
criterion. The refusal sits at the **writer** rather than at milestone 4 so a malformed table
costs an edit instead of a round, and there is
deliberately **no milestone-4 backstop**: a verdict record carries no schema version, so a legacy
evidence-free `pass` is byte-indistinguishable from one whose section was stripped after the fact,
and every record written before this shipped keeps passing unchanged.

## Why there is no pixel-diff gate, and none is coming

The rendered-vs-design comparison was a standing deferral in four documents. #695 **retired** it
rather than building it, and this is the settled posture — not an interim one.

A pixel differ would compare a Figma frame export against a browser screenshot: different
rasterizer, DPR, font stack and viewport. Its tolerance model is therefore either loose enough to
catch nothing or tight enough to red on the next machine, with nothing in the repo to tell the two
settings apart — and the dependency would land on every consumer's render harness, in a contract
whose whole shape is that the harness owns boot/auth/screenshot and the lane owns nothing that
needs installing.

The narrower alternative — asserting **measured properties** against the translation plan — was
never refuted, and it **shipped** in #711 as [Measured
sizes](#measured-sizes-the-rectsjson-sibling) above: the plan's `px` column against the harness's
`.rects.json`, scale-adaptive, on a stated tolerance. It cost exactly what this section priced it
at — a second emitted artifact per state, breaking for any consumer already armed — and it buys
exactly what this section said it would, no more: plan→code drift, blind to design→plan drift.
None of that makes a pixel differ cheaper, and none of the rest of the judgment moved.

So fidelity on this lane is **attested, and the attestation is auditable** — that is the whole
claim. The evidence table above is what makes contradicting a rubber stamp possible, and it is
what a reader should read instead of waiting for a gate.
