# Live-render verify — wiring a consumer render harness

`design.liveRender` arms the dev-pipeline's **Stage-5 live-render verify gate** (#84): after the
design engine implements a screen, the gate runs your repo-owned render command, reads the emitted
PNG, and semantically compares it against the cached design frame (placement, sizing/fill,
truncation, default state — not a pixel diff). Without the key the gate records
`render-verify-unavailable` (unconfigured) and the strongest fidelity check in the pipeline never
executes.

Not to be confused with `stageParams.visualCapture` — that is Stage-6's **advisory** smoke-capture
(observation only, never gates); `design.liveRender` is the Stage-5 design-fidelity check with an
in-session fix loop behind it.

## Config

```jsonc
"design": {
  "provider": "figma",
  "liveRender": {
    "command": "yarn render:verify --route {route} --out {out}",  // required
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
- **`{out}`** — an absolute PNG path. Emit exactly one screenshot there; the gate treats a missing
  or zero-byte file as failure.
- **Exit code** — nonzero on any failure, with a one-line actionable message on stderr/stdout
  (e.g. `API not reachable on :3000 — start the backend dev server in the sibling repo`). That tail
  becomes the degraded-condition detail in the Stage-5 comment and PR body.
- **Failure is non-blocking** — the gate degrades to `render-verify-unavailable` with your message;
  it never aborts the run. Make the message good enough that the operator can fix the prerequisite
  and re-run.
- **`readyProbe`** — declare your harness's external prerequisite (typically a sibling BE health
  endpoint) so the gate fails fast with the probe URL instead of waiting out a render timeout.

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
