# Arm 1 (#746) — the realised substrate, per run

Recorded 2026-09-01, alongside the transcripts it describes. Every line below is a property of the
**apparatus**, measured before or after the sessions ran, not a result. The scoring lives in
[`scoring.tsv`](scoring.tsv); the reading lives in [`docs/skill-ablation.md`](../../../skill-ablation.md) §1.

`docs/skill-ablation-addendum.md` §A registers the substrate as *gate and skills absent from the
working tree, installed plugin cache present on disk and readable*, realised by a throwaway
`git clone` at a pinned base commit with `plugins/` and `.claude-plugin/` deleted from the working
tree and left as unstaged deletions.

## The invocation — identical across all eight scored sessions

```bash
printf '%s' "$(cat <prompt-template.txt + ticket-<n>.md>)" \
  | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
      -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
      -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT -u CLAUDE_EFFORT -u CLAUDE_PID \
    claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob" \
      --add-dir /Users/mdonev/.claude/plugins/cache
```

The frozen bare-arm recipe (`docs/skill-ablation-pre-registration.md`:22-27) with its bracketed
`--allowedTools` **taken**, plus `--add-dir` on the plugin cache. The `--add-dir` is not a change of
substance — same model, same prompt, same `--setting-sources ''` — it is what makes the registered
substrate's *"installed plugin cache … readable by the session's tool allowlist"* actually true. See
"The cache was not reachable" below for the measurement that made it necessary.

The prompt inputs are unchanged from the registered run: `prompt-template.txt`, `ticket-636.md` and
`ticket-647.md` each carry exactly one commit, `8d5d0897`, which is the commit §1 was scored on.

```bash
git log --oneline -- docs/plans/skill-ablation/c1-build/prompt-template.txt \
  docs/plans/skill-ablation/c1-build/ticket-636.md docs/plans/skill-ablation/c1-build/ticket-647.md
```

## The plugin cache — resolved, not guessed

```bash
claude plugin list --json | jq -r '.[] | select(.id|startswith("dev-pipeline@")) | .installPath'
# -> /Users/mdonev/.claude/plugins/cache/second-shift/dev-pipeline/12.2.3
```

Present and readable in every run: `ls <path>/skills` returns `build-lean perf-retro
pipeline-retro pr-revision review-lean run-lean`, and `<path>/skills/build-lean/SKILL.md` is the
48-line file under test.

**The addendum's own printed form does not work.** `docs/skill-ablation-addendum.md`:65-67 shows
`jq -r '.[].path'`; the field is `installPath` and `.path` yields `null` for every row. The addendum
is a registration and is not edited by this arm — the working form is recorded here instead, and
the discrepancy is stated rather than silently corrected.

## The arms

| arm | status | construction |
| --- | --- | --- |
| **A1-max** | registered (`docs/skill-ablation-addendum.md`:74-94) | clone at the pinned commit; `plugins/` and `.claude-plugin/` deleted from the working tree, left as unstaged deletions |
| **A1-min** | registered, conditional (`…`:224-247) | A1-max, additionally removing `docs/plans/`, `.claude/SECOND-SHIFT.md`, `.claude/second-shift.lock.json`, `.claude/lean-overrides.tsv` |
| **A1-sealed** | **disclosed post-hoc** | the A1-max tree, with the repository re-initialised so the kit is absent from history as well as from the working tree |
| **A1-sealed-min** | **disclosed post-hoc** | A1-sealed plus A1-min's registered removal list |

The two sealed arms are post-hoc and say so. They were added after A1-max ran, for the reason
recorded under "The leak" below; they could not have been pre-registered, because the fact that made
them necessary is something A1-max measured. They are labelled the way §1's own sensitivity run was
(`docs/skill-ablation.md`:56-58), and the registered arms are reported in full beside them rather
than replaced by them. A1-sealed-min exists because A1-sealed keeps `docs/plans/`, so a `covered`
there is open to exactly the objection A1-min was registered to close.

## Per-run realisation, verified

Eight scored sessions: four arms × two samples. `636` and `647` are the frozen C1 samples C1-a and
C1-b.

| property | max | min | sealed | sealed-min |
| --- | --- | --- | --- | --- |
| checkout | `dfd68a47` / `b657907f` | same | same† | same† |
| `plugins/`, `.claude-plugin/` on disk | absent | absent | absent | absent |
| `SKILL.md` files on disk | 0 | 0 | 0 | 0 |
| `lean-gate.sh` on disk | 0 | 0 | 0 | 0 |
| **plugin cache reachable** | **yes** | **yes** | **yes** | **yes** |
| `docs/plans/` on disk | present | absent | present | absent |
| `.claude/SECOND-SHIFT.md`, lockfile, `lean-overrides.tsv` | present | absent | present | absent |
| `.claude/second-shift.config.json` copied in | yes | yes | yes | yes |
| `CLAUDE.md` | present | present | present | present |
| **`git show HEAD:plugins/…` reachable** | **yes** | **yes** | no | no |

† A sealed arm's working tree is byte-identical to the pinned commit with `plugins/` and
`.claude-plugin/` removed and the config copied in — `diff -rq` against a fresh `git archive <sha>`
of the same tree reports **0 differences** for both samples — but its repository carries a single
fresh commit rather than the pinned commit's history. That is the whole of the seal: the kit is
absent from the object store as well as from the working tree.

Cache reachability is verified per run from the session's own tool calls, not asserted: every
`plugins/cache` read is in the transcript log, and the counts are in "What each arm actually read"
below.

A1-min's fourth registered removal, *"the single `.claude/settings.json` allow entry naming
`lean-gate.sh` by literal path"*, is recorded **`not-reached — not present at either pinned base`**.
The committed `.claude/settings.json` at `dfd68a47` and at `b657907f` carries `hooks` and
`extraKnownMarketplaces` and no `permissions` key at all; the entry the addendum describes landed
later. Nothing was removed for it, and nothing is credited for it.

## The cache was not reachable under the frozen recipe

A first pass ran all four arms without `--add-dir`, and **none of those sessions could reach the
plugin cache** — a `claude -p` session is confined to its working directory:

```
ls in '/Users/mdonev/.claude/plugins/cache/second-shift' was blocked. For security, Claude Code
may only list files in the allowed working directories for this session: …
```

That is a substrate the addendum did not register: §A registers the cache as *present and inside
the session's tool allowlist*, and AC-2 of this ticket requires it be readable. So the first pass
does not realise the registered substrate and is **not scored**. `--add-dir` fixes it, verified by
probe from a sealed checkout:

```bash
printf '%s' 'Run: ls /Users/mdonev/.claude/plugins/cache/second-shift/dev-pipeline/12.2.3/skills' \
  | env -u CLAUDE_CODE_SESSION_ID … claude -p --model opus --setting-sources '' \
      --allowedTools "Read,Grep,Glob" --add-dir /Users/mdonev/.claude/plugins/cache
# -> build-lean perf-retro pipeline-retro pr-revision review-lean run-lean
```

The first pass's A1-max transcripts are kept as `consumer-max-confined-<n>-plan.md`, because they
are the evidence for this finding and for the next one.

## What each arm actually read

Counted from each session's own tool-call log:

| session | `git show HEAD:` / `git grep HEAD` | reads under `~/.claude/plugins/cache/` | reads under `docs/plans/` |
| --- | --- | --- | --- |
| max 636 | 12 | 0 | 2 |
| max 647 | 23 | 0 | 0 |
| min 636 | 16 | 0 | 5 |
| min 647 | 23 | 0 | 4 |
| sealed 636 | 0 | 7 | 2 |
| sealed 647 | 0 | 9 | 3 |
| sealed-min 636 | 0 | 0 | 0 |
| sealed-min 647 | 0 | 4 | 0 |

```bash
jq -r 'select(.message.content)|.message.content[]?|select(.type=="tool_use")
       |((.input.command // .input.file_path // .input.pattern)|tostring)' \
  ~/.claude/projects/-private-tmp-746-arm1-<arm>-<n>/*.jsonl
```

**Not one of the eight read `build-lean/SKILL.md` out of the cache.** The four sealed sessions had
the cache and walked to `lean-gate.sh`, `orchestrate-lean.sh` and the doctor fixtures; one of them
listed `skills/build-lean/` and did not open the file. Where the kit was reachable in the tree
instead, all four of those sessions read `SKILL.md` there. The prose is what a session reaches for
when it is a file in the repository, and not when it is an installed plugin — which is the
distinction arm 1 was filed to draw.

## The leak — measured, and it is why A1-sealed exists

**The registered construction does not realise the registered substrate.** Deleting `plugins/` from
the working tree and leaving unstaged deletions leaves the entire kit readable from the clone's own
object store, and every A1-max and A1-min session read it there.

Falsifiable in one command, in either A1-max checkout:

```bash
git show HEAD:plugins/dev-pipeline/skills/build-lean/SKILL.md   # prints the 48-line file
```

All four of those sessions read `plugins/dev-pipeline/skills/build-lean/SKILL.md` that way, and none
of them read anything under `~/.claude/plugins/cache/` — see "What each arm actually read" above.
They did not walk to the cache the substrate exists to offer; they walked to the object store the
substrate did not think to close.

Under `docs/skill-ablation-addendum.md`:201-222 that makes every item they cover provenance `tree`,
which the registered reading already calls **inconclusive** and routes to A1-min. A1-min inherits the
same hole — its removals are working-tree removals too — so it cannot lift the verdict either. That
is what the two sealed arms are for.

## The bracketed `--allowedTools` in the frozen recipe is inert

`--allowedTools "Read,Grep,Glob"` does not restrict the tool surface under `claude -p`. In the first
pass, A1-max 636 made **41 Bash calls and 6 Grep calls** and A1-max 647 made **45 Bash calls and 1
Read call**; every scored session in the second pass is Bash-dominated the same way. What
blocked anything was the ordinary permission classifier, independently: writes
(`git checkout -- .`, `git restore plugins`, redirection outside the working directory) were
refused, read-only commands were not.

```bash
printf '%s' 'Run exactly this shell command and reply with only its output: echo BASH-RAN' \
  | env -u CLAUDE_CODE_SESSION_ID … claude -p --model opus --setting-sources '' \
      --allowedTools "Read,Grep,Glob"
# -> BASH-RAN
```

This is a property of the frozen recipe, so it binds §1's already-scored runs too, and it is
checkable in their transcripts: the registered C1 run for #636 made 16 Bash calls, and **the
disclosed ablated run for #647 recovered `build-lean/SKILL.md` with
`git show HEAD:plugins/dev-pipeline/skills/build-lean/SKILL.md`** — the same leak, one sample, in
the arm §1 introduced to remove exactly that confound.

```bash
jq -r 'select(.message.content)|.message.content[]?|select(.type=="tool_use")
       |((.input.command // .input.file_path // .input.pattern)|tostring)' \
  ~/.claude/projects/-private-tmp-ablation-644-wt-abl-647/*.jsonl | grep 'git show HEAD:'
```

Reported, not acted on: correcting §1's own scoring is not this arm's scope, and it is routed in
`docs/skill-ablation.md` §1 rather than done here.
