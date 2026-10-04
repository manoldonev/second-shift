# Live render — wiring a consumer render harness

`design.liveRender` names two repo-owned commands. `/dev-pipeline:run` uses them for a **route
smoke** after every build: for each screen the ticket's record declares, it renders the route and
asserts one value the design says must be on it — and, when the smoke command takes `{textScale}`,
that no text overflows or is clipped at 1× and at 2× text size. The build and review sessions use the same render
command to look at what they built and compare it with the design frame. Nothing in the lane diffs
pixels; the fidelity judgment is the review session's.

Without `design.provider`, nothing arms. With it, every ticket's record must say which screens it
renders (or that it renders none) — see [Arming](#arming-per-ticket) below.

## Config

```jsonc
"design": {
  "provider": "figma",
  "liveRender": {
    "command": "yarn render:verify --route {route} --state {state} --out {out}",  // required
    "smokeCommand": "yarn render:smoke --route {route} --must-show {mustShow} --text-scale {textScale}",   // required once a record declares frames; {textScale} optional
    "readyProbe": "http://localhost:3000/system/status"                            // optional pre-check URL
  }
}
```

Both commands run in the ticket's worktree, never the main checkout.

## The command contracts

Your scripts own **boot, auth, screenshot and the assertion**. The scheduler owns the row list,
the substitution, the PNG hashes and the outcome.

`command` — render one state of one route:

- **`{route}`** — the app-relative leaf below your feature mount path (e.g. `prospects`,
  `prospects/new`). The harness owns any shell/org/tenant prefix; operator-specific segments come
  from the operator's env, never from second-shift config.
- **`{state}`** — optional. The state named by the record's `RS-n` row (e.g. `filters expanded`).
  Your harness maps the name to whatever it takes to reach that view.
- **`{out}`** — an absolute PNG path. Emit exactly one non-empty screenshot there.

`smokeCommand` — assert one route shows one thing, and fits it at enlarged text:

- **`{route}`** — as above.
- **`{mustShow}`** — the row's `must-show` cell: a data-test id or a copy string taken from the
  frame. Exit non-zero unless the route renders and shows it.
- **`{textScale}`** — optional, a unitless multiplier: `1`, then `2` (WCAG 1.4.4's 200% resize-text
  bar). When the template takes it, the scheduler runs the command twice per row, once at each
  scale, and **at each scale** the command must exit non-zero unless the must-show value is
  satisfied **and** no text overflows or is clipped.
  - **Scale the text only**, e.g. the root font-size × `textScale`; the viewport and px-sized boxes
    stay put. Not page zoom or `deviceScaleFactor`: those scale fixed-px boxes along with the
    text, so a fixed-px box that clips enlarged text never shows.
  - **Overflow or clipping** is an element whose `scrollWidth`/`scrollHeight` exceeds its client
    box. Whether an intentional `text-overflow: ellipsis` is whitelisted is your harness's call.
  - Without `{textScale}` the smoke runs once per row as before, and each run prints
    `scaled smoke: not configured (smokeCommand takes no {textScale})` once, in its output and in
    the PR's run block. That note is never a red.
  - A harness that takes `{textScale}` and ignores it runs green; second-shift cannot see that.
    The catch is your detector's.

Both:

- **Placeholders appear UNQUOTED** in the template, `{textScale}` included. The scheduler shell-quotes each substituted
  value itself — a state is human prose with spaces — so `--state {state}` is correct and
  `--state "{state}"` delivers a literally-quoted argument. Values reach the harness verbatim,
  query strings and punctuation included.
- **Exit code** — non-zero on any failure, with a one-line actionable message (e.g. `API not
  reachable on :3000 — start the backend dev server`). The smoke log is what the next build
  session reads as its findings.

**`readyProbe`** — your harness's external prerequisite, typically a backend health endpoint. When
set, the scheduler curls it (up to three tries) before rendering; a 2xx or 3xx is ready. Not ready
ends the run as `env-not-ready` — start the service and re-launch with `--resume` — instead of
spending a red attempt on an environment the branch cannot fix.

## What the smoke does

After a build round's checks are green, for each `RS-n` row in the record's design section (read
from the record's first commit on the branch, never the head):

1. renders the row through `command` and requires exit 0 and a non-empty PNG at `{out}`;
2. hashes the PNG — two declared states that render byte-identical images are red, because that is
   a harness ignoring `{state}` and shooting the same view twice;
3. requires a `must-show` value on the row, then runs `smokeCommand` with it — at text scale `1`
   and at `2` when the template takes `{textScale}`. Both scales run even when `1` is red, and a
   red names the row, the scale and the substituted command
   (`RS-1 at text scale 2: smoke failed: <command>`), so the build session can re-run it.

The render in steps 1–2 stays one default-scale render per row: `{textScale}` is substituted only
in `smokeCommand` and reaches `command` literally. The scaled smoke doubles the smoke invocations
per row (2N harness boots for the reference harness below), and like every lane command it has no
wall-clock bound.

Any red spends one attempt on the checks-red counter (`run.checksRedMax`, default 3), never a build
round; the smoke log goes to the next build session. A record that declares frames on a repo with
no `command` or `smokeCommand` configured ends the run as `env-smoke-unconfigured`.

**Rendering must be deterministic enough for step 2.** Pin what varies between runs: animations
and transitions, live timestamps and relative-time strings, randomly seeded fixture data, font
loading, scrollbar and viewport differences, and text size (a smoke at `{textScale}` 2 must not
leak its scale into the next render). When two states legitimately look identical, merge or
re-scope the rows at intake.

## Arming, per ticket

Config `design.provider` must be set, and the ticket's intake record must carry a
`## Design frames` section (`## Design` is read the same way) in one of two forms — one row per
screen and state, written at intake by `/intake-toolkit:plan-interview`:

```markdown
## Design frames

| RS | route | state | frame | must-show |
| --- | --- | --- | --- | --- |
| RS-1 | /imports | empty | 815:2201 | Nothing imported yet |
| RS-2 | /imports | loaded | 815:2240 | data-test=import-row |
```

…or the explicit disarm, `Design: none — <reason>`. Neither form on a provider repo, and the run
refuses before it claims (`env-design-undeclared`). The full row schema is in the
`interviewing-baseline` skill ("Design frames").

## What the sessions do with it

- **Build.** On a ticket with frames, the build prompt names the `figma-faithful` sequence: read
  every frame id first, write the token and component plan, have a subagent critique the plan
  against the frames, then render every screen with `command`, open the PNG, compare it with its
  frame and fix what differs.
- **Review.** The review session renders every screen at the PR head with `command` and compares
  it with its frame. If it cannot render, it cannot approve: it posts `verdict: needs-work` with a
  line `reason: render-unavailable`, and the scheduler stops the run as `env-not-ready` without
  spending a round.

## Reference harness shape (Playwright, MIFE-in-shell)

A worked example: a Vite MIFE mounted in a platform admin shell, backed by a sibling BE.

- **Playwright config** with two projects: a `setup` project (auth) and a `render` project
  (`dependencies: ['setup']`, consumes the storage state). `webServer` boots the FE dev server
  with the local-API env override; the BE is probed, not booted (its lifecycle belongs to the
  operator — a sibling-relative path breaks inside worktrees).
- **Hybrid auth** — the setup project refreshes a Playwright `storageState` file via the real
  signin flow (through the FE dev proxy, using an API `request.newContext()` — no browser page)
  **when credentials are present in env** (`E2E_USERNAME`/`E2E_PASSWORD`); otherwise it consumes
  an existing, manually exported state file as-is. State lives at a gitignored path.
- **Render spec** — `goto` the composed URL, deterministic wait (network idle + fonts + an
  optional selector), `page.screenshot({ path: out, fullPage: true })`.
- **Smoke spec** — the same `goto` and wait, then assert the `must-show` value: a `data-test=`
  prefix selects by test id, anything else by visible text. With `{textScale}`, set the root
  font-size to its multiple before the wait, then fail on any text element whose
  `scrollWidth`/`scrollHeight` exceeds its client box.
- **CLI wrappers** — parse the flags, set env, spawn `playwright test` with the matching config,
  propagate the exit code. Wire them as the package scripts the two config commands name.

## Worktree traps (both bite silently — design for them)

1. **Never reuse a foreign dev server.** Runs execute in the ticket's worktree; if the operator's
   own dev server already holds the port, `reuseExistingServer: true` would screenshot the **main
   checkout's** code and pass. Default reuse **off** (fail loud on port collision via
   `strictPort`) and gate interactive reuse behind an explicit env opt-in.
2. **Gitignored state does not exist in fresh worktrees.** Accept an absolute-path env override
   for the auth-state file (e.g. `E2E_AUTH_STATE`) so a worktree run can point at the operator's
   maintained state — or set the credential env vars and let the setup project mint a fresh one.

Before the first armed run, have the harness's dependencies up and confirm both commands run green
by hand once from a worktree.
