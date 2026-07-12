# Dev-Pipeline Cost Tracking — Setup

**Opt-in, local, experimental.** The dev-pipeline works fine without this. If you want each PR to carry a cost block in its description, follow the steps below.

The goal: at Stage 9 (after the PR is opened), the pipeline invokes `pipeline-cost-block.sh` in-band. The script reads OTel metrics emitted under the sessions recorded in `pipelineSessions[]`, clamps them to the run's own wall-clock fence (`[startedAt, terminal-stage completedAt]`) so a co-resident sequential run or `/pipeline-retro` sharing the same `session.id` doesn't leak in, buckets the in-fence datapoints per stage, and appends a single cost block to each PR's body (idempotently — re-runs detect the marker and no-op).

Opting in is just steps 1–3 below (collector + telemetry env + bot wrapper) — no per-engineer hook wiring. The skill records the native Claude Code session UUID (`$CLAUDE_CODE_SESSION_ID`) at Stage 2 (and again only on a crash-recovery Stage 8 resume in a fresh session) via `statectl pipeline-session-add`, and Stage 9 reads the resulting `pipelineSessions[]` to attribute cost. That UUID is the same value the OTel exporter tags datapoints with as `session.id`, which is what lets the cost block match them.

## Prerequisites

- **macOS** (tested on Darwin arm64; Linux works with minor tweaks to the date commands in `pipeline-cost-block.sh`).
- **`gh` CLI** installed and authenticated (`gh auth status` should succeed). Used for PR reads.
- **Bot wrapper** — when config `tracker.bot.enabled`, installed by `tools/install-gh-bot.sh` and referenced via the env var named by `tracker.bot.envVar` (default GH_BOT), executable. The script uses it for the `gh pr edit` write call (writes to GitHub go through the bot identity per the dev-pipeline's bot-identity convention). If the wrapper is missing or non-executable, the script records `costBlockApplied: "skipped-no-bot-wrapper"` and exits 0 with an actionable log line — no PR is amended.
- **`jq` ≥ 1.6** (ships with macOS).
- **Native session UUID recorded.** The in-band sub-step relies on `pipelineSessions[]` being populated by the skill at Stage 2 (and on a crash-recovery Stage 8 resume in a fresh session), which reads `$CLAUDE_CODE_SESSION_ID` and records it via `statectl pipeline-session-add` (the subcommand enforces the UUID shape). A run whose Stage 2 never recorded a session id — e.g. `$CLAUDE_CODE_SESSION_ID` was unset — leaves `pipelineSessions[]` empty and skips cost tracking gracefully (`costBlockApplied = "skipped-no-sessions"`).
- **Pipeline state with timestamps + PR URL.** The script reads `stages.{N}.startedAt`/`completedAt` (for stage windows) and `prs.{branch}.url` (to know which PRs to amend) from `.claude/pipeline-state/{issue}.json`. The dev-pipeline writes both at every stage boundary.

## 1. Install the OTel collector

`otelcol-contrib` is **not in Homebrew.** Grab the release tarball:

```bash
VERSION=0.150.1   # pick latest from https://github.com/open-telemetry/opentelemetry-collector-releases/releases
ARCH=darwin_arm64 # or darwin_amd64, linux_amd64, etc.
curl -sLO "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${VERSION}/otelcol-contrib_${VERSION}_${ARCH}.tar.gz"
mkdir -p ~/bin
tar -xzf "otelcol-contrib_${VERSION}_${ARCH}.tar.gz" -C ~/bin otelcol-contrib
rm "otelcol-contrib_${VERSION}_${ARCH}.tar.gz"
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc   # or ~/.bashrc
```

Verify: `otelcol-contrib --version`.

## 2. Start the collector

The repo ships the collector config at `otel-collector-config.yaml` — it listens on `127.0.0.1:4317`, batches every 1s, and appends JSONL to `~/.claude/otel-metrics/metrics.jsonl` (50 MB rotation, 30-day retention).

In a tmux/iTerm pane you keep around:

```bash
mkdir -p ~/.claude/otel-metrics
otelcol-contrib --config="$(pwd)/otel-collector-config.yaml"
```

Verify it's live: `lsof -iTCP:4317 -sTCP:LISTEN` should show the process.

**Stopping it:** `Ctrl+C` in the pane where it's running, or from any terminal:

```bash
pkill -f otelcol-contrib
# or by port:
lsof -ti:4317 | xargs kill
```

(If you set up the optional launchd appendix below, `pkill` alone won't stick — use `launchctl bootout` as shown there.)

Want it always-on instead? See the launchd appendix at the bottom of this file.

## 3. Tell Claude Code to export telemetry

The collector receives OTel data from any process with the right env vars. The recommended per-repo pattern is [direnv](https://direnv.net/) — load vars automatically when you `cd` into the repo.

```bash
brew install direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc   # or bash equivalent, then restart the shell
```

In each repo where you want cost tracking, create `.envrc` at the root (the repo's `.gitignore` already excludes `.envrc`):

```bash
cat > .envrc <<'EOF'
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_METRIC_EXPORT_INTERVAL=2000
EOF
direnv allow
```

From now on, every `claude` session launched from this repo exports telemetry to your local collector.

Don't want direnv? Export the same vars from `~/.zshrc` or wrap `claude` in an alias. The pipeline doesn't care how they get there — only whether they're set when the session starts.

## 4. (No hook wiring step)

In-band cost tracking does not need a Stop hook. Stage 9 of the dev-pipeline skill invokes `pipeline-cost-block.sh` directly as a sub-step, just before marking the stage complete.

## 5. Verify end-to-end

1. Launch the dev-pipeline interactively (`/dev-pipeline <issue>`). The skill at Stage 2 reads `$CLAUDE_CODE_SESSION_ID` (the native session UUID) and records it via `statectl pipeline-session-add`.
2. Tail the collector output: `tail -f ~/.claude/otel-metrics/metrics.jsonl` — you should see JSON lines within a few seconds of the session emitting.
3. When Stage 9 completes (PR opened), the in-band sub-step queries the metrics file for all sessions in `pipelineSessions[]`, renders a per-stage cost block, and amends every PR in `prs`. The state file's `costBlockApplied` flips to `true` on success.

For ad-hoc verification without the full pipeline:

```bash
# Pretend a state file exists; invoke directly.
bash pipeline-cost-block.sh <issue-number>
# Inspect outcome:
jq '.costBlockApplied' .claude/pipeline-state/<issue-number>.json
```

## Troubleshooting

**Cost block doesn't appear in PR.** Check `.claude/pipeline-state/{issue}.json` `costBlockApplied`:

- `"skipped-no-sessions"` — `pipelineSessions[]` is empty. Did Stage 2 run with `$CLAUDE_CODE_SESSION_ID` set? You can backfill manually with the real session UUID (find it as a `session.id` in `~/.claude/otel-metrics/metrics.jsonl`): `bash statectl.sh pipeline-session-add <issue> --session-id <session-uuid> --source interactive`.
- `"skipped-telemetry-off"` — `~/.claude/otel-metrics/metrics.jsonl` is empty or absent. Was the collector running? Is your `.envrc` loaded (`direnv status` should show "Found RC")?
- `"skipped-otel-error"` — the jq query against the metrics file failed. Re-run from a terminal to see stderr, then follow **Manual re-run after an OTel query failure** below.
- `"skipped-zero-datapoints"` — the recorded session UUID returned `$0.00` from the collector. The likely cause: the session was launched WITHOUT the OTEL\_\* env vars exported (your `.envrc` was not loaded when the session started — see step 3 above), so the collector never received datapoints for it. (A malformed, non-UUID session id can no longer reach this state — `statectl pipeline-session-add` rejects it at record time.)
- `"skipped-no-bot-wrapper"` — the configured bot wrapper (config `tracker.bot`) is missing or non-executable. Install / repair the bot wrapper.
- `"skipped-amend-failed"` — `gh pr edit` failed. Check stderr from the most recent Stage 9 run.

The cost log at `.claude/pipeline-state/cost-log.jsonl` has the run's rollup. If it's there but the PR wasn't amended, the bot-identity `gh pr edit` call failed.

### Manual re-run after an OTel query failure

The cost block is a **best-effort, in-band sub-step that always exits 0** — Stage 9 (and the whole pipeline run) is already **complete** when it records `skipped-otel-error`. `costBlockApplied` is informational and is **not** load-bearing for resume, so the pipeline never re-enters on your behalf to retry it. Recovery is a manual, idempotent re-run:

1. **Fix the precondition that made the query fail.** Usually one of:
   - the OTel collector wasn't reachable / wasn't running when the sub-step ran — start it (steps 1–2 above) and confirm `~/.claude/otel-metrics/metrics.jsonl` is non-empty;
   - the `OTEL_*` env vars weren't exported in the shell that launched the run — load your `.envrc` (`direnv allow`) so `OTEL_EXPORTER_OTLP_ENDPOINT` etc. are set;
   - the metrics file is present but malformed — inspect the stderr from the failed run (re-run the command below to reproduce it).
2. **Re-run just the sub-step** (it does not need the pipeline; it reads the state file and the metrics file directly):

   ```bash
   bash pipeline-cost-block.sh <issue-number>
   ```

3. It is **idempotent on the `<!-- pipeline-cost-block -->` marker**: if a prior partial run already amended some PRs, those are detected and skipped; only the un-amended PRs in `prs[]` get the block. A clean re-run flips `costBlockApplied` to `true`. Repeat as needed — re-running after success is a safe no-op.

**Collector won't start.** Port 4317 in use? `lsof -iTCP:4317` to see what's holding it. Kill the old process or change the port in `otel-collector-config.yaml` AND in your `.envrc` `OTEL_EXPORTER_OTLP_ENDPOINT`.

**Wrong cost numbers.** The block is the OTel-reported estimate. The authoritative billing number lives in the Anthropic Console. Expect ±10% drift versus Console (acceptable for v1; reconciliation is deferred).

## Appendix: always-on via launchd (optional)

Only worth it if you run pipelines several times a week. For occasional use the tmux pane is simpler.

```xml
<!-- ~/Library/LaunchAgents/com.yourname.otelcol-contrib.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.yourname.otelcol-contrib</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOU/bin/otelcol-contrib</string>
        <string>--config=<abs-path-to>/otel-collector-config.yaml</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/tmp/otelcol-contrib.log</string>
    <key>StandardErrorPath</key><string>/tmp/otelcol-contrib.err</string>
</dict>
</plist>
```

Load: `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.yourname.otelcol-contrib.plist`
Unload: `launchctl bootout gui/$UID ~/Library/LaunchAgents/com.yourname.otelcol-contrib.plist`
Status: `launchctl list | grep otelcol`

## What gets emitted

For the privacy-curious:

- **Metrics:** cost in USD, token counts (input/output/cacheRead/cacheCreation), per-datapoint attributes including `session.id`, `model`, `query_source` (main/auxiliary/subagent).
- **Labels include PII** — `user.email`, `user.account_id`, `organization.id`. Safe in a local-only file on your own machine; do NOT ship this file anywhere shared.
- **Not emitted:** prompt text (default redacted as `<REDACTED>`), tool call args, tool result content. Setting `OTEL_LOG_USER_PROMPTS=1` would change that; we don't.
