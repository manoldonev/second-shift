# Dev-Pipeline Cost Tracking — Setup

**Opt-in, local, experimental.** The dev-pipeline works fine without this. If you want each PR to carry a cost block in its description, follow the steps below.

The goal: the lean lane's build session computes the block once at [`build-lean`](skills/build-lean/SKILL.md) step 7, by invoking `pipeline-cost-block.sh --stateless`, and pastes it into both the PR description and the run's closing comment. The script reads OTel metrics emitted under the session ids it is handed, clamps them to the run's own wall-clock fence (supplied as `--start`/`--end`) so a co-resident run or a `/dev-pipeline:pipeline-retro` session sharing the same `session.id` doesn't leak in, and renders one cost block to stdout (or to `--out`).

```bash
pipeline-cost-block.sh --stateless --sessions <id[,id…]> --start <iso> --end <iso> [--out <file>]
```

**State-less mode is the script's only mode** (#574 deleted the stateful branch, unreachable since #348 removed its only writer), and it is deliberately inert on everything a state file used to carry: it amends no PR (the session pastes the block itself), records no `costBlockApplied`, and writes **no** `cost-log.jsonl` row — lean runs are out of the perf corpus by declaration (D-36), so a row here would quietly contaminate cross-run analytics with a harness that has no stages. The run's own progress record is what carries the session ids to hand it.

Opting in is just steps 1–3 below (collector + telemetry env + bot wrapper) — no per-engineer hook wiring. Each id you pass is a native Claude Code session UUID (`$CLAUDE_CODE_SESSION_ID`), the same value the OTel exporter tags datapoints with as `session.id`, which is what lets the cost block match them.

## Prerequisites

- **macOS** (tested on Darwin arm64; Linux works with minor tweaks to the date commands in `pipeline-cost-block.sh`).

- **`jq` ≥ 1.6** (ships with macOS).
- **Native session UUIDs to hand it.** State-less mode is told its session set; nothing discovers it. Each contributing session's `$CLAUDE_CODE_SESSION_ID` is recorded in the run's progress record (`.claude/pipeline-state/{issue}-lean-progress.md`), which is why that record's reconciliation keys are load-bearing rather than forward-looking. A session launched without that variable set to a UUID contributes no id, and a call with none at all exits `2` naming the missing `--sessions`.
- **A wall-clock fence to hand it.** `--start`/`--end` (ISO-8601) are the only span this mode knows: there are no per-stage windows to bucket, so the block is a single session-total row. Both are required — the fence is what keeps a co-resident run's datapoints out.

  (On the historical stateful path, retired in #574, these two came from the state file instead — `pipelineSessions[]` plus `stages.{N}.startedAt`/`completedAt`, all written by the staged lane #348 deleted.)

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

## 2. Start the collector (once, globally)

The collector is a **single global daemon** — one instance serves every repo's telemetry, keyed by `session.id`, not by which repo you launched it from. It listens on `127.0.0.1:4317`, batches every 1s, and appends JSONL to `~/.claude/otel-metrics/metrics.jsonl` (50 MB rotation, 30-day retention). It does not need a tmux/iTerm pane and it does not need to be started from any particular `cwd`.

The config ships at `plugins/dev-pipeline/otel-collector-config.yaml` inside dev-pipeline. **Don't reference that path directly** — if you installed the plugin from the marketplace it resolves to a version-pinned cache path (`~/.claude/plugins/cache/second-shift/dev-pipeline/<version>/...`) that moves out from under you on the next upgrade. Copy it to a stable location once instead:

```bash
mkdir -p ~/.claude/otel-metrics
SRC=$(find ~/.claude/plugins/cache/second-shift/dev-pipeline -name otel-collector-config.yaml 2>/dev/null | sort -V | tail -1)
cp "$SRC" ~/.claude/otel-metrics/otel-collector-config.yaml
```

(If you're working directly in a clone of second-shift itself, `SRC` is `plugins/dev-pipeline/otel-collector-config.yaml` relative to the repo root instead.)

Then launch it backgrounded with `nohup` — no dedicated pane to babysit:

```bash
nohup otelcol-contrib --config="$HOME/.claude/otel-metrics/otel-collector-config.yaml" \
  > ~/.claude/otel-metrics/otelcol.log 2>&1 &
disown
```

Verify it's live: `lsof -iTCP:4317 -sTCP:LISTEN` should show the process. It'll stay up across shell sessions until you kill it or reboot; check `~/.claude/otel-metrics/otelcol.log` if it doesn't start.

**Stopping it:**

```bash
pkill -f otelcol-contrib
# or by port:
lsof -ti:4317 | xargs kill
```

(If you set up the optional launchd appendix below, `pkill` alone won't stick — use `launchctl bootout` as shown there.)

Want it to survive reboots too? See the launchd appendix at the bottom of this file — it also uses the stable `~/.claude/otel-metrics/otel-collector-config.yaml` copy, so it never breaks on a dev-pipeline upgrade.

## 3. Tell Claude Code to export telemetry

The collector receives OTel data from any process with the right env vars, and it only sees a session that had them set **at launch**. There is no way to turn this on for a session already running, and no way to recover the cost of one that ran without it — so make it survive the next terminal.

**Recommended: a user-scope `env` block in `~/.claude/settings.json`.** Step 2 above already describes the collector as a single global daemon — one instance serving every repo, keyed by `session.id` — so the per-repo half was always the mismatched one. A user-scope block is what makes every `claude` session on the machine export, no matter which terminal, shell or directory launched it:

```jsonc
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
    "OTEL_METRIC_EXPORT_INTERVAL": "2000"
  }
}
```

Merge those keys into your existing `~/.claude/settings.json` (don't replace the file), then restart any running sessions. Verify a live one really carries it:

```bash
ps eww -p <claude-pid> | tr ' ' '\n' | grep CLAUDE_CODE_ENABLE_TELEMETRY
```

Setting it ad hoc per terminal instead is exactly what makes cost reporting depend on which window you happened to launch from: one repo's sessions carry the variable, another's carry nothing, and the difference only surfaces at the end of a run as an empty cost block. `pipeline-doctor.sh` and `lean-gate.sh entry` both warn when the shell they run in is not exporting.

**Per-repo alternative: [direnv](https://direnv.net/).** Use this when you want telemetry in some repos and not others.

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

Exporting the same vars from `~/.zshrc`, or wrapping `claude` in an alias, works too. The pipeline doesn't care how they get there — only whether they were set when the session started.

## 4. (No hook wiring step)

Cost tracking does not need a Stop hook. The build session invokes `pipeline-cost-block.sh --stateless` directly at `build-lean` step 7, before it opens the PR, and reuses that one block in the step-9 closing comment.

## 5. Verify end-to-end

1. Run a lean issue (`/dev-pipeline:run-lean <issue>`, or `/dev-pipeline:build-lean <issue>` directly). Each session it spawns records its `$CLAUDE_CODE_SESSION_ID` as a `| session |` row in `.claude/pipeline-state/{issue}-lean-progress.md`.
2. Tail the collector output: `tail -f ~/.claude/otel-metrics/metrics.jsonl` — you should see JSON lines within a few seconds of the session emitting.
3. At step 7 the build session computes the block from those ids and the run's fence, and pastes it into the PR description; step 9 repeats the same block in the closing comment. Success is the block appearing in the PR — nothing is recorded in a state file, by design.

For ad-hoc verification without a run, hand it any session id and fence:

```bash
# Any session id from ~/.claude/otel-metrics/metrics.jsonl, and a window around it.
bash pipeline-cost-block.sh --stateless \
  --sessions <session-uuid> \
  --start 2026-01-01T00:00:00Z --end 2026-12-31T23:59:59Z
```

An empty-looking block here means the query found no `claude_code.cost.usage` datapoints for that id inside that fence; the log line on stderr names which of the two it was.

## Troubleshooting

**The block is empty or absent.** The script records nothing, so the diagnosis is the stderr log line from the step-7 call — `skip(<verdict>): …`. Each verdict names a distinct root cause (before #432 one value absorbed the first four states, which made "empty cost block" undiagnosable):

- `skip(no-sessions)` — the supplied `--sessions` set was empty after filtering. Was the session launched with `$CLAUDE_CODE_SESSION_ID` set? A call with no `--sessions` flag at all exits `2` naming it instead. Recover by finding the id as a `session.id` in `~/.claude/otel-metrics/metrics.jsonl` and re-running with `--sessions <session-uuid>`.
- `skip(telemetry-off)` — no metrics file at all (neither `~/.claude/otel-metrics/metrics.jsonl` nor any rotated backup beside it), or not one datapoint from **any** session landed inside the run's window. The collector was down for the whole run, or nothing on this machine was exporting.
- `skip(otel-error)` — the jq query against the metrics file failed. Re-run from a terminal to see stderr, then follow **Manual re-run after an OTel query failure** below.
- `skip(session-not-exporting)` — the window holds datapoints from **other** sessions but none from this run's. The collector was healthy the whole time; this run's `claude` process simply had no `CLAUDE_CODE_ENABLE_TELEMETRY` set, so it exported nothing. Confirm it on a live session:

  ```bash
  ps eww -p <claude-pid> | tr ' ' '\n' | grep CLAUDE_CODE_ENABLE_TELEMETRY
  ```

  Nothing recovers this run's cost — the datapoints were never emitted. Fix it for the next one with step 3 below, which is why the recommended recipe there is user-scope rather than per-terminal.
- `skip(rotated-out)` — the oldest datapoint still on disk is **newer** than the run's start, so the file covering the run is gone: it aged out of the exporter's `max_backups` / `max_days` retention, or the collector had not started yet when the run did. As of #432 the sub-step reads rotated backups whose mtime covers the window, so a run that merely predates the newest rotation no longer lands here.
- `skip(zero-datapoints)` — rows for the supplied session ids **are** inside the window, but none of them carries `claude_code.cost.usage`. Telemetry is flowing and there is genuinely no cost to report.

The rollup lives only in the block itself — a lean run writes no `cost-log.jsonl` row (D-36).

### Manual re-run after an OTel query failure

The cost block is **best-effort** — the run's work is already done when it logs `skip(otel-error)`. Its exit contract (#188): **exit 0** whenever it ran or reported a documented skip; **non-zero (rc 2)** only when it could not be given what it needs — a missing `--sessions`/fence, or a positional-issue invocation (the retired stateful entry point, refused by name since #574). On the lean lane the enforcement is the artifact, not a field: `build-lean` step 7 requires the block in the PR description and step 9 repeats it in the closing comment.

1. **Fix the precondition that made the query fail.** Usually one of:
   - the OTel collector wasn't reachable / wasn't running when the sub-step ran — start it (steps 1–2 above) and confirm `~/.claude/otel-metrics/metrics.jsonl` is non-empty;
   - the `OTEL_*` env vars weren't exported in the shell that launched the run — load your `.envrc` (`direnv allow`) so `OTEL_EXPORTER_OTLP_ENDPOINT` etc. are set;
   - the metrics file is present but malformed — inspect the stderr from the failed run (re-run the command below to reproduce it).
2. **Re-run the call** — it needs no run in flight, only the session ids, the fence, and the metrics file:

   ```bash
   bash pipeline-cost-block.sh --stateless \
     --sessions <id[,id…]> --start <iso> --end <iso>
   ```

   Take the ids from the `| session |` rows of `.claude/pipeline-state/<issue>-lean-progress.md` and the fence from its first and last timestamps.

3. Paste the re-rendered block over the stale one in the PR description and closing comment. Re-running after success is safe — the script writes nothing anywhere but stdout/`--out`.

**Collector won't start.** Port 4317 in use? `lsof -iTCP:4317` to see what's holding it. Kill the old process or change the port in `~/.claude/otel-metrics/otel-collector-config.yaml` AND in your `.envrc` `OTEL_EXPORTER_OTLP_ENDPOINT`.

**Wrong cost numbers.** The block is the OTel-reported estimate. The authoritative billing number lives in the Anthropic Console. Expect ±10% drift versus Console (acceptable for v1; reconciliation is deferred).

## Appendix: always-on via launchd (optional)

Only worth it if you run pipelines several times a week. For occasional use, the `nohup` launch in step 2 is simpler and survives just fine until you reboot.

Point it at the stable `~/.claude/otel-metrics/otel-collector-config.yaml` copy from step 2, not the plugin-cache path — the cache path is version-pinned and goes stale on the next dev-pipeline upgrade.

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
        <string>--config=/Users/YOU/.claude/otel-metrics/otel-collector-config.yaml</string>
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
