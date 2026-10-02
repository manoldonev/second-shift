# CodeRLM in Claude Code: how it works and how to set it up

CodeRLM is a tree-sitter code index. Instead of grepping and reading whole files, Claude asks it IDE-style questions: where is `X` defined, who calls it, show me the body of `Y`. It comes in two parts:

- **A server** (`coderlm-server`, Rust). It indexes one repo and answers over HTTP on `127.0.0.1:<port>`.
- **The `coderlm` Claude Code plugin** (marketplace `jaredStewart/coderlm`). It is a thin client: four hooks, one skill (`/coderlm`), one subagent (`coderlm-subcall`) and a Python CLI.

The plugin never starts a server. If no server answers on the port it checks, nothing happens.

## How the plugin wires itself into a session

Once enabled, the plugin is active in every repo you open. Its `hooks/hooks.json` does four things:

| Hook | What it does |
| --- | --- |
| `SessionStart` | Runs `scripts/session-init.sh`: checks `http://127.0.0.1:${CODERLM_PORT:-3000}/api/v1/health`. If that answers, it symlinks the CLI to `.claude/coderlm_state/coderlm_cli.py` and runs `init --port <port>`, which writes `.claude/coderlm_state/session.json`. Always exits 0. |
| `UserPromptSubmit` | Echoes "invoke Skill(coderlm) for code in supported languages… always include code extracts" into **every prompt**. |
| `SubagentStart` | Adds the same instruction as `additionalContext` to **every subagent**. |
| `Stop` | Runs `scripts/session-stop.sh`: saves annotations and deletes the server-side session, if `session.json` exists. |

The prompt hook is the whole "when to use coderlm" mechanism. No repo file tells Claude to use it.

After `init`, every CLI command (`search`, `impl`, `callers`, `tests`, `grep`, `peek`, `symbols`, `structure`, `batch`, `exec`) reads the server address from `session.json`. The skill tells Claude to run `python3 .claude/coderlm_state/coderlm_cli.py <command>`.

## One-time setup per repo (macOS)

The setup that works is one server per repo, each on its own fixed port, kept alive by `launchd`.

### 1. Install the plugin and build the server

Enable the plugin with `/plugin` (marketplace `jaredStewart/coderlm`). Then build the server once. This needs a Rust toolchain:

```sh
cd ~/.claude/plugins/marketplaces/coderlm/server && cargo build --release
```

### 2. Run a server per repo under launchd

Pick an unused port per repo (for example 7400, 7401, …) and check it is free with `lsof -nP -iTCP:<PORT> -sTCP:LISTEN`. Then write `~/Library/LaunchAgents/com.coderlm.<repo>.plist`. launchd does not expand `~`, so use absolute paths:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.coderlm.REPO</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/USER/.claude/plugins/marketplaces/coderlm/server/target/release/coderlm-server</string>
    <string>serve</string>
    <string>/Users/USER/work/REPO</string>
    <string>-p</string>
    <string>PORT</string>
  </array>
  <key>WorkingDirectory</key><string>/Users/USER/work/REPO</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>/Users/USER/Library/Logs/coderlm/REPO.out.log</string>
  <key>StandardErrorPath</key><string>/Users/USER/Library/Logs/coderlm/REPO.err.log</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
</dict>
</plist>
```

```sh
mkdir -p ~/Library/Logs/coderlm
launchctl load -w ~/Library/LaunchAgents/com.coderlm.REPO.plist
curl -sf http://127.0.0.1:PORT/api/v1/health    # expect {"status":"ok",...}
```

### 3. Point the plugin at the right port

The plugin and CLI default to port 3000, so a per-repo port needs one of these:

- **Port shim (in use today).** Replace the symlink at `.claude/coderlm_state/coderlm_cli.py` with a small wrapper. It adds `--port PORT` to any `init` call that lacks one, then `exec`s the real CLI from the plugin cache, globbing `~/.claude/plugins/cache/coderlm/coderlm/*/skills/coderlm/scripts/coderlm_cli.py` so it survives plugin upgrades. A user-level `SessionStart` hook (`~/.claude/hooks/restore-coderlm-shim.sh`, registered in `~/.claude/settings.json`) maps each known repo path to its port. It rewrites the wrapper whenever the wrapper is missing or has been replaced by a symlink.
- **`CODERLM_PORT` (simpler, untested).** `session-init.sh` reads `CODERLM_PORT` and passes it to `init` as `--port`, and every later command takes its port from `session.json`. So setting `CODERLM_PORT=PORT` for the repo should be enough, for example in the repo's `.claude/settings.local.json` under `"env"`. This depends on hooks inheriting that env, which has not been verified. A manual `init` with no `--port` would still go to 3000.

### 4. Re-index after branch moves (optional)

Add untracked `.git/hooks/post-checkout` and `post-merge` hooks that re-run `python3 .claude/coderlm_state/coderlm_cli.py init --port PORT` in the background. In `post-checkout`, only do it when `$3 = 1`, meaning a branch checkout. A spawn-the-server-if-down branch is a useful backup for when launchd is unloaded.

## Pitfalls

- **Anything on port 3000 breaks the default path.** The plugin's health check is `curl -s` without `-f`, so *any* HTTP answer passes, including a Node dev server's HTML page. `init` then parses that HTML as JSON and the session starts with a `JSONDecodeError` traceback. Fix: give the repo a port (step 3), or keep 3000 free.
- **A repo without a server is half set up.** The state directory and symlink get created, but there is no index or session. The prompt hook still tells Claude to use coderlm every turn.
- **The instruction goes everywhere.** It is added to every prompt and every subagent in every repo. Sessions launched with `--setting-sources user,...`, such as scripted or pipeline sessions, inherit it too.
- **Ignore the state directory.** Add `.claude/coderlm_state/` to each repo's `.gitignore`. It is created inside the repo and is easy to sweep into a commit.
- **Logs grow without limit** under `~/Library/Logs/coderlm/`.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `[coderlm] Server not running on port …` | `launchctl list \| grep coderlm`; `curl -sf http://127.0.0.1:PORT/api/v1/health`; `tail ~/Library/Logs/coderlm/REPO.err.log` |
| `JSONDecodeError` at session start | Something that isn't coderlm is answering on the checked port: `lsof -nP -iTCP:3000 -sTCP:LISTEN` |
| `Connection refused` from the skill | The wrapper was overwritten by a symlink and `init` went to 3000. Restart the session so the self-heal hook rewrites it, or run `init --port PORT` |
| Stale results after switching branches | Re-run `init --port PORT`, or install the git hooks from step 4 |
| Restart a server | `launchctl kickstart -k gui/$UID/com.coderlm.REPO` |

## Opting out

- **For one repo:** unload and delete its plist, delete `.claude/coderlm_state/` and its git hooks, and remove its entry from the shim hook.
- **Everywhere:** disable `coderlm@coderlm` with `/plugin`. That also stops the prompt and subagent injection.
