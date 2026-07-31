# Stage 1. Intake + Decomposition (with atomic pickup)

> **Tracker delta (config `tracker.type: jira`).** The prose below is the **github**
> default (queue query + atomic claim + bot label swap). Under the jira adapter
> ([`tools/tracker/jira/`](../tools/tracker/jira/README.md)) Step 1.A is replaced by
> an operator-supplied JIRA key — there is **no queue, no claim, and no label
> mutation** (`tracker.writes: false`). The ticket is fetched via the Atlassian MCP's
> `getJiraIssue` — under whichever namespace the session exposes (`mcp__atlassian__*`,
> `mcp__plugin_atlassian_atlassian__*`, or `mcp__claude_ai_Atlassian_Rovo__*`;
> `ToolSearch` to discover a deferred tool; see [`tools/tracker/jira/`](../tools/tracker/jira/README.md))
> (Step 1.B reads it there instead of `gh issue view`),
> the `sub-issues` verdict **presents** sub-ticket specs to the operator rather than
> auto-creating them, and the design-detection below is the
> design-provider path (see `tracker/jira/README.md` and the `design.provider` axis —
> `figma` | `claude-design`). Everything else in this stage (intake orchestration, AC snapshot,
> `statectl` writes keyed off `ticketKey`) is tracker-agnostic.

#### Step 1.T: Target routing (config `topology.type: be-fe-pair` only)

> **Skip entirely unless `topology.type == "be-fe-pair"`.** A `standalone`/`monorepo` topology has one repo — the host (`path: "."`) is the implicit sole target — and this step is a no-op. This block is purely additive: it never runs for a single-repo consumer.

A **be-fe-pair** ticket targets one or both repos, routed by each repo's `topology.repos.<id>.ticketTag` (e.g. `"[BE]"` / `"[FE]"`). **Ordering:** this block EXECUTES after Step 1.A's pickup + `statectl init` (it needs both the fetched ticket **title** — github: the queue/`gh issue view` title; jira: the `getJiraIssue` summary — and an initialized state file for the `mark-failed` / `target-repos-set` writes). Resolve `TARGET_REPOS` and **persist it** via `statectl target-repos-set` so Stage 2 (and the downstream per-repo stages) loop over the targets without re-deriving from the title. `TARGET_REPOS` drives Stage 2's per-repo worktree loop, Stage 6's per-repo verify, and Stage 9's per-repo PRs (each keyed by `worktree-set --repo <id>` / `verify-attempts --repo <id>` — see state-schema.md "be-fe-pair note").

```bash
TOPO=$(jq -r '.topology.type // "standalone"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo standalone)
if [[ "$TOPO" == "be-fe-pair" ]]; then
  # $TITLE = the fetched issue/ticket title. Collect every repo whose ticketTag
  # appears in it (both tags present ⇒ cross-repo, i.e. TARGET_REPOS="be fe").
  TARGET_REPOS=$(jq -r --arg t "$TITLE" '
    [ .topology.repos | to_entries[]
      | select((.value.ticketTag // "") as $tag | $tag != "" and ($t | contains($tag)))
      | .key ] | join(" ")' "$SECOND_SHIFT_CONFIG")

  # No recognizable tag ⇒ ambiguous. Autonomous: fail closed (never guess which
  # repo to touch). Interactive: present the title and ask.
  if [[ -z "$TARGET_REPOS" ]]; then
    statectl.sh mark-failed "$ISSUE_NUMBER" --reason targetRepos-ambiguous \
      --json "$(statectl.sh build-failure-context --reason targetRepos-ambiguous --kv-lines title="$TITLE")"
    exit 0   # autonomous abort (rc=0); interactive mode asks instead
  fi

  # Reachability: every target repo's path (topology.repos.<id>.path) must resolve
  # to a directory in THIS session — a sibling FE repo must be added via
  # `claude --add-dir <path>`, else nothing downstream can operate on it.
  MAIN_ROOT="$(git rev-parse --show-toplevel)"
  for r in $TARGET_REPOS; do
    RP=$(jq -r --arg r "$r" '.topology.repos[$r].path' "$SECOND_SHIFT_CONFIG")
    if [[ ! -d "$MAIN_ROOT/$RP" ]]; then
      statectl.sh mark-failed "$ISSUE_NUMBER" --reason fe-repo-unreachable \
        --json "$(statectl.sh build-failure-context --reason fe-repo-unreachable --kv repo="$r" --kv path="$RP")"
      exit 0
    fi
  done
  # Persist the resolved targets so Stage 2+ loop over them without re-deriving.
  statectl.sh target-repos-set "$ISSUE_NUMBER" --repos "$TARGET_REPOS"
  echo "[stage-1] be-fe-pair target routing: TARGET_REPOS='$TARGET_REPOS'"
fi
```

#### Step 1.A: Atomic Pickup

**Argument override:** if the skill was invoked with an explicit issue number (`/dev-pipeline <N>`), skip the queue query below and use that issue. The argument overrides queue ordering only — every other check still applies: the issue must be open, must carry `ready-for-dev`, and must pass the do-not-pick-up guard. An argument-specified issue that fails those checks is a reject (report why and stop), not an exemption.

```bash
# Label vocabulary is config-driven (tracker.labels — #11); defaults reproduce the
# shipped six. github-only (a jira repo has no queue/claim/label model). Every site
# below — the queue query, the claim swap, and the do-not-pick-up guard — reads these.
QUEUE_LABEL=$(jq -r '.tracker.labels.queue // "ready-for-dev"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "ready-for-dev")
CLAIMED_LABEL=$(jq -r '.tracker.labels.claimed // "in-progress"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "in-progress")
BLOCKER_LABELS=$(jq -r '(.tracker.labels.blockers // ["epic","needs-intake-review","needs-spec-work","needs-plan-review"]) | join(" ")' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "epic needs-intake-review needs-spec-work needs-plan-review")

# Queue pickup (no argument given). The whole sorted page is RETAINED (no `| .[0]`)
# so the predecessor gate below can advance past a blocked candidate without a
# re-query, and `body` is fetched here so the gate, the intake fan-out and the AC
# snapshot all read ONE body per candidate rather than re-fetching it three times.
CANDIDATES=$(gh issue list --label "$QUEUE_LABEL" --json number,title,body --limit 10 --jq 'sort_by(.number)')
```

- If no issues: print "No issues in queue", stop.
- Walk `CANDIDATES` in order; the first candidate that passes the predecessor gate below becomes `ISSUE_NUMBER` / `ISSUE_TITLE` / `ISSUE_BODY`.
- `RUN_ID` is already generated by the **Pre-flight** step at the top of `SKILL.md` (runs before Invocation Routing so the mode-compat reject path can pass it to `statectl init`). Use the inherited value here.

**Pre-claim predecessor gate (`sub-issues-sequential` ordering — github adapter only).** Runs after a candidate's number resolves and **BEFORE** the claim sequence's step 1 — never at the post-claim race re-verify, because the whole point is to skip *without* claiming. Under `tracker.type: jira` this block is **SKIPped with a note** (both reads are session-side MCP, unreachable from a shell tool — the *preflight-read* precedent; ordering is operator-enforced there). See [`../tools/tracker/README.md`](../tools/tracker/README.md) → **predecessor-read**.

The routine path never reaches this gate: a sequential decomposition leaves blocked successors out of the queue entirely. It exists for the **early-labelled** successor — one an operator queued before its predecessor merged.

```bash
# github only. KEY_PATTERN mirrors config tracker.keyPattern so trailer keys are
# read in the adapter's own shape.
if [[ "$(jq -r '.tracker.type // "github"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo github)" == "github" ]]; then
  KEY_PATTERN=$(jq -r '.tracker.keyPattern // "[0-9]+"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "[0-9]+")
  GATE="${CLAUDE_PLUGIN_ROOT}/skills/run/tools/predecessor-gate.sh"

  # 1) Extract this candidate's trailers from the body already in hand (no fetch).
  TRAILERS=$(printf '%s' "$ISSUE_BODY" | KEY_PATTERN="$KEY_PATTERN" bash "$GATE" extract)
  PREDECESSOR=$(printf '%s\n' "$TRAILERS" | sed -n 's/^predecessor=//p')
  SUCCESSOR=$(printf '%s\n' "$TRAILERS" | sed -n 's/^successor=//p')

  # 2) The predecessor-state read is paid ONLY when a key was printed.
  if [[ -n "$PREDECESSOR" ]]; then
    PRED_STATE=$(gh api "repos/{owner}/{repo}/issues/$PREDECESSOR" --jq .state 2>/dev/null | tr '[:upper:]' '[:lower:]')
    # Unreadable predecessor (404, transferred, cross-repo key, gh failure) is
    # treated as BLOCKED — fail closed. Nothing is claimed yet, so there is no state
    # file to mark-failed into and no new failureContext.reason is required; this is
    # the pre-flight-gate posture, not the failureContext posture.
    [[ "$PRED_STATE" == "open" || "$PRED_STATE" == "closed" ]] || {
      echo "[stage-1] predecessor #$PREDECESSOR state unreadable — treating as blocked (fail-closed)" >&2
      PRED_STATE=open
    }
    if ! bash "$GATE" verdict "$PRED_STATE"; then
      # exit 3 = skip-blocked. NOTHING is mutated: no label swap, no claim comment,
      # no state file. QUEUE PATH: advance to the next candidate in the SAME query
      # result (bounded by the --limit page above; never re-query). ARGUMENT PATH:
      # reject and stop, naming the open predecessor.
      echo "[stage-1] #$ISSUE_NUMBER is blocked by open predecessor #$PREDECESSOR — not claiming" >&2
      # queue path: continue the walk; argument path: stop here.
    fi
  fi
fi
```

If every candidate in the page is predecessor-blocked, print "No eligible issues in queue (all candidates blocked by open predecessors)" and stop. On the **argument path** (`/dev-pipeline:run <N>`) there is no walk: a blocked issue is a reject-and-stop, reported with the blocking predecessor's key — consistent with the other argument-path rejects above.

**Claim sequence (guard against race conditions):**

1. Mutate — **add `in-progress` before removing `ready-for-dev`, and confirm the add applied before removing** (Label-swap ordering rule, SKILL.md Bot Identity): the reverse order has a crash window where the issue carries neither label and is silently lost from the queue; and even in the correct order, a _silently-failed_ add followed by a successful remove reaches the same zero-label window.
   - **Single-call (GraphQL healthy):** `$GH_BOT issue edit $ISSUE_NUMBER --add-label "$CLAIMED_LABEL" --remove-label "$QUEUE_LABEL"`. This is one atomic API call — add and remove apply together or not at all, so there is no intermediate zero-label window and no separate confirm step is needed (the confirm requirement below exists only because the REST fallback splits the swap into two calls).
   - **REST fallback (GraphQL broken — doctor WARN; current in this repo):** run `bash "${CLAUDE_PLUGIN_ROOT}/skills/run/tools/claim-issue.sh" "$ISSUE_NUMBER" --queue "$QUEUE_LABEL" --claimed "$CLAIMED_LABEL"` (bot wrapper injected via `$GH_BOT`; the helper ships in the plugin checkout, never the de-vendored consumer repo — resolve it via `${CLAUDE_PLUGIN_ROOT}`, not CWD-relative; the two label args default to `ready-for-dev`/`in-progress` when omitted). It POSTs the claimed label, asserts the add applied from the response body, THEN DELETEs the queue label; on a failed add it aborts (exit `1`) **leaving the queue label intact** — a bare stop (nothing was mutated yet), NOT the step-2 undo below (which reverses _applied_ mutations). Exit `0` = claimed.
   - **Assignee:** use regular `gh` for `--add-assignee @me` separately — bot can't assign itself; skip on failure.
2. Verify via REST: `gh api "repos/{owner}/{repo}/issues/$ISSUE_NUMBER" --jq '{labels: [.labels[].name]}'`
   - Assert: `$QUEUE_LABEL` is gone, `$CLAIMED_LABEL` is present
   - If any check fails: undo mutations (add `$QUEUE_LABEL` back first, then remove `$CLAIMED_LABEL` — same add-before-remove safety), exit — another runner claimed it. (This post-verify undo reverses mutations that _did_ apply; it is distinct from the step-1 pre-DELETE failed-add abort, which is a bare stop because nothing was mutated yet.)
3. Post claim comment (REST form per SKILL.md Bot Identity) with `run_id` and `stage: claimed`. Record the receipt (completion-gated) from the response's `html_url`: `"$STATECTL" comment-add "$ISSUE_NUMBER" --marker claimed --url <html_url>`.
4. `ISSUE_BODY` is already in hand from the pickup query above (the run-authoritative early-snapshot doctrine: read once, pre-claim, and reuse for the gate, the intake fan-out and the AC snapshot). Fetch only `/comments` here: `gh api "repos/{owner}/{repo}/issues/$ISSUE_NUMBER/comments"`. On the **argument path**, where no queue query ran, read the body here instead: `gh api "repos/{owner}/{repo}/issues/$ISSUE_NUMBER" --jq .body` — but do it **before** the predecessor gate, which needs it.

**Do-not-pick-up guard:** Before claiming, verify the issue does NOT have any of the **blocker labels** (`$BLOCKER_LABELS`, resolved above — default `epic`, `needs-intake-review`, `needs-spec-work`, `needs-plan-review`). These labels block auto-pickup. The `gh issue list --label "$QUEUE_LABEL"` query implicitly excludes them (since the queue label is removed when these labels are added), but verify after claiming in case of a race condition.

**State:** Seed the state file via the mode-carrying init (#243) — the session substitutes the mode it resolved at Invocation Routing **as a literal** (the env var cannot be relied on to reach this shell; each harness Bash call is fresh):

```bash
MODE="${DEV_PIPELINE_MODE:-auto}"   # substitute your RESOLVED mode literally when composing this call
statectl init "$ISSUE_NUMBER" --run-id "$RUN_ID" --mode "$MODE"
```

(creates `ticketKey` + `runId` + `startedAt` + initial `status: in_progress` + `.mode` — the state transport for statectl's autonomous `--force` refusal). `RUN_ID` is generated by the Pre-flight step in `SKILL.md` and persisted to top-level `.runId` here; resumes inherit it via `statectl get "$ISSUE_NUMBER" '.runId'` so the original session and its restart share comment markers (see `state-schema.md`).

**Then record this session — immediately after `init`.** `pipelineSessions[]` is the join key the Stage-1 **ledger-corroboration** legs resolve the audit ledger through, and it used to be first written at Stage 2 — so `set-stage 1 --status completed` always evaluated against an empty join set and every Stage-1 completion took the fail-open by construction. The call is idempotent on session id, so Stage 2's stays a harmless no-op on a single-session run and cost attribution is unchanged:

```bash
if [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
  statectl pipeline-session-add "$ISSUE_NUMBER" \
    --session-id "$CLAUDE_CODE_SESSION_ID" --source interactive
fi
```

The `-n` guard is the same one Stage 2 carries: a run with no session id records no join key and corroborates nothing — **visibly**, via `ledgerCorroboration: "uncorroborated"`, rather than silently. A *set-but-malformed* id hard-fails here at the write (the subcommand validates the UUID shape), which is the intended posture: a broken harness environment surfaces at Stage 1 instead of letting the whole run proceed uncorroborated.

**Then persist this issue's own forward `Successor:` trailer** — `$SUCCESSOR` from the pre-claim `extract` above. Stage 9 renders the operator-promotion line iff it is non-null, so the null is written **explicitly**, never left absent:

```bash
if [[ -n "$SUCCESSOR" ]]; then
  statectl successor-key-set "$ISSUE_NUMBER" --key "$SUCCESSOR"
else
  statectl successor-key-set "$ISSUE_NUMBER" --none
fi
```

**Then mark the stage started — immediately, before Step 1.P and the intake fan-out:** `statectl set-stage "$ISSUE_NUMBER" 1 --status started`. Stage 1 is where this write most easily slips (the claim sequence and fan-out feel like pre-work): deferring it until the completion writes collapses `stages.1` to a ~0-min window with the whole intake (pin, fan-out, orchestrator evaluation) mis-attributed to the pre-stage gap — the same state-discipline deviation the inline reminders on stages 2/3/5/6/7 exist to stop, and one `/pipeline-retro` flags. `init` seeding the file is NOT the started-write; both are required, in this order. **And record the stage-file receipt in the same breath** — `statectl stage-file-read "$ISSUE_NUMBER" --stage 1 --file 1-intake.md` (#243 §3): `set-stage 1 --status completed` refuses unless stage 1's own file is recorded as read.

#### Step 1.P: Pin the Stage-1 read surface

Runs after the claim (Step 1.A) and BEFORE the intake fan-out (Step 1.B). Stage-1 reads (spec-reviewer, codebase-explorer, referenced-doc resolution) must ground against `origin/<baseBranch>` — never the operator's checkout, whose branch and uncommitted edits are unrelated to the run (the work branch is cut from `origin/<base>` at Stage 2 either way; an unpinned intake read is the mismatch hazard this closed). Because reads are pinned, **the current branch of the main checkout is NOT a reject condition** — the predicates are:

- **Pin established, any current branch, clean tree** → proceed **silently** (the branch name still lands in the Dynamic Context snapshot for the record).
- **Pin established, dirty working tree** (any branch; `git status --porcelain` non-empty) → emit a **WARN** — "a human appears to be mid-work in this checkout" — surfaced in the run's final report, and proceed.
- **Pin NOT establishable** (fetch or worktree creation fails) → fail closed with the retained reason:

```bash
# Pin: fetch the configured base, then a throwaway detached worktree (reuses Stage 2's
# fetch-then-pin idiom). WORKTREES_DIR = config topology.repos.<host>.worktreesDir.
BASE_BRANCH_CFG=$(jq -r '(.topology.repos | to_entries[] | select(.value.path==".") | .key) as $h | .topology.repos[$h].baseBranch // "main"' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo "main")
PIN_WT="${WORKTREES_DIR}/intake-pin-${ISSUE_NUMBER}"
PIN_ERR=$(git fetch origin "$BASE_BRANCH_CFG" --quiet 2>&1 \
  && git worktree add --detach "$PIN_WT" "origin/$BASE_BRANCH_CFG" 2>&1) || {
  statectl.sh mark-failed "$ISSUE_NUMBER" \
    --reason non-main-base-autonomous \
    --json "$(statectl.sh build-failure-context --reason non-main-base-autonomous \
        --kv pinError="$PIN_ERR" --kv baseBranch="$BASE_BRANCH_CFG")"
  exit 0   # autonomous abort (rc=0); interactive mode presents the pin failure and asks
}
```

Pass the **absolute** pin path as `readRoot` in the intake Workflow args (Step 1.B — `workflows/intake-review.mjs` prefixes every dispatch prompt with the pinned-read instruction); resolve referenced docs (max 5) against the same root. **Teardown:** best-effort `git worktree remove "$PIN_WT" 2>/dev/null || true` at EVERY Stage-1 exit — right after the Stage-1 completion write on the continue path, AND right after the terminal write/comment on every Stage-1 stop (spec fails, escalation, `sub-issues` split, `design-source-unreachable`). Stage-1 stops never reach Stage 10, so a stop that skips teardown leaks the pin permanently. Stage 10 cleanup removes it unconditionally if it survived (crash between the two points).

**Capture the pre-flight attestation (carry forward to the Stage-1 checkpoint).** The predicate outcomes above are the attestation `stageCheckpoint["1"].preflight` records (completion-gated on a well-formed `preflight`; state-schema.md row 1). Record the three fields here (the pin is established at this point — the fail-closed case above already exited), so the checkpoint write below can fold them in:

```bash
# baseBranch: the configured base ($BASE_BRANCH_CFG above). workingTreeClean: the
# porcelain emptiness that drives the clean-vs-WARN predicate (git status --porcelain
# in the MAIN checkout). guardOutcome: the free-form outcome tag — proceed-clean when
# clean, proceed-dirty-warn when the WARN fired (the pin-unestablishable / wrong-target
# cases mark-failed and never reach the checkpoint, so those tags never appear here).
if [[ -z "$(git status --porcelain)" ]]; then
  WORKING_TREE_CLEAN=true;  GUARD_OUTCOME=proceed-clean
else
  WORKING_TREE_CLEAN=false; GUARD_OUTCOME=proceed-dirty-warn   # WARN already surfaced above
fi
```

#### Step 1.B: Intake + Decomposition

**Lightweight inline intake (interactive-mode only, explicit-approval gated).** The full intake below — loading `intake-toolkit:intake-orchestrator` + the structured `intake-toolkit:spec-reviewer`/`intake-toolkit:codebase-explorer` fan-out — is the default and is **MANDATORY in `auto` mode**: the no-input-prompts invariant means `auto` has no way to express approval, so the carve-out simply does not exist there. **A human design session completed before claim (e.g. via `grill-me`) does NOT authorize skipping the auto-mode fan-out** — there is no "consolidated-into-design-session" intake mode; to legitimately use the lightweight inline path on a trivial change, run under `DEV_PIPELINE_MODE=interactive` so the approval gate can fire. A _lightweight inline intake_ performs the classification / scope / decomposition reasoning in-session (reading the touched files directly) **without** loading `intake-toolkit:intake-orchestrator` or dispatching the fan-out. It is permitted **only** when BOTH hold:

1. **Mode is `interactive`** (`DEV_PIPELINE_MODE=interactive`), AND the Stage 1 gate **prompts** and the operator **explicitly approves**. The prompt fires only when the change looks trivial and self-contained (single file / a few additive lines, no cross-module surface); on decline — or any non-trivial signal — fall through to the full intake. In `auto` mode this prompt never fires and the inline path is unavailable.
2. **The skip is surfaced (mandatory, not optional).** When the inline path is taken, the Stage 1 intake comment MUST state explicitly that `intake-toolkit:intake-orchestrator` and the `intake-toolkit:spec-reviewer`/`intake-toolkit:codebase-explorer` fan-out were skipped (operator-approved lightweight inline intake), and `stageCheckpoint["1"]` MUST record `intakeMode: "inline-approved"` (the default/full path records `intakeMode: "full"` or omits the field). An un-surfaced skip is a **silent deviation**; the surfacing requirement is what makes a legitimate inline skip visible rather than silent.

Otherwise — `auto` mode, no approval, or a non-trivial change — run the full intake:

- Load skill: `intake-toolkit:intake-orchestrator` in the calling session (Opus) with:
  - Issue body + all comments: `gh issue view $ISSUE_NUMBER --json body,comments`
  - Referenced docs/ADRs (max 5 — orchestrator picks most relevant)
  - Codebase context: Bootstrap from the repo's `CLAUDE.md` and any repo-local session-state conventions it defines (see its CLAUDE.md)

Immediately after the load, record it as completion evidence (completion-gated, unless the checkpoint carries `intakeMode: "inline-approved"`):

```bash
"$STATECTL" skill-load-add "$ISSUE_NUMBER" --stage 1 --skill intake-toolkit:intake-orchestrator
```

The skill loads orchestration instructions into the current session — the calling session gathers evidence from `intake-toolkit:spec-reviewer` and `intake-toolkit:codebase-explorer` as a **structured fan-out** that returns rationale-carrying objects (not prose): in production via the intake Workflow (`workflows/intake-review.mjs`, run with the `Workflow` tool), and under the eval harness via the `Task` tool with the structured findings mocked. Dependency analysis runs as an in-session subroutine — no sub-agent hop. The skill handles everything: issue classification, spec review, codebase exploration, dependency analysis, gap resolution, and decomposition decision.

**Sub-agent dispatch order:** `intake-toolkit:spec-reviewer` and `intake-toolkit:codebase-explorer` run in parallel — except on the clean-marker skip path (a feature body whose interviewer provenance marker proves a clean, self-contained spec), where the orchestrator dispatches `intake-toolkit:codebase-explorer` only and elides `intake-toolkit:spec-reviewer` (see `intake-toolkit:intake-orchestrator` Step 2). The dependency-analysis subroutine runs in-session after the structured `codebaseExplorer` object is in hand (it requires the impact surface as input).

**Orchestrator verdicts:**

| Verdict       | Action                                                                                                                       | Pipeline continues?                                                  |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `no-split`    | Posts spec review + decisions as comment. `stage: intake`, `status: passed` or `passed-with-decisions`                       | Yes — proceed to Stage 2                                             |
| `sub-issues`  | Creates ≤5 sub-issues, **each** with the `ready-for-dev` label. Parent gets `epic` label. `stage: intake`, `status: split-into-sub-issues` | **No** — pipeline stops. Sub-issues enter queue independently. State carve-out: success-shaped, no `mark-failed` (leaves `in_progress`; follow-up). |
| `sub-issues-sequential` | Creates ≤5 **ordered** sub-issues carrying `Predecessor:` / `Successor:` trailers. **Only the first gets `ready-for-dev`**; N>1 are created without it and the operator promotes each when merging its predecessor's PR. Parent gets `epic` label. `stage: intake`, `status: split-into-sub-issues-sequential` | **No** — pipeline stops. Each sub-issue is its own single-PR run against the configured base branch. Same state carve-out as the parallel flavor. |
| Spec fails    | True blockers found. `stage: intake`, `status: failed`                                                                       | **No** — `needs-spec-work` label + `mark-failed(intake-spec-blocked)`, STOP |
| Escalation    | Orchestrator uncertain. `stage: intake`, `status: needs-human-input`                                                         | **No** — `needs-intake-review` label + `mark-failed(intake-needs-human-input)`, STOP |

**Receipt (proceeding verdicts).** `no-split` is now the only verdict that proceeds — both sub-issue flavors stop. Record the posted intake comment's URL (completion-gated — both `claimed` and `intake` are required): `"$STATECTL" comment-add "$ISSUE_NUMBER" --marker intake --url <html_url>`. Failure-shaped verdicts stop before Stage-1 completion, so no receipt gate applies there.

**Thresholds enforced by the orchestrator:**

- Max 5 sub-issues (one cap, both flavors), max 5 resolvable gaps
- Stop after 3 true blockers from intake-toolkit:spec-reviewer
- Max 5 referenced docs read
- Flag if any sub-issue touches >10 files

**State (terminal verdicts).** When the orchestrator returns a **failure-shaped, pipeline-stopping** verdict, the pipeline — not the orchestrator — writes the state file AFTER the orchestrator's tracker actions (comment + label) complete, mirroring the `design-source-unreachable` call shape in Step 1.C. The `--reason`/`--stage` pair is passed to BOTH `mark-failed` (its `--reason` is what lands in `failureContext.reason`) AND `build-failure-context`. The state file already exists (Step 1.A `statectl init`); `mark-failed` has no worktree precondition and `--stage 1` is legal.

- **Spec fails / >5 resolvable gaps** → `intake-spec-blocked` (the `outcome` detail disambiguates the two triggers):

  ```bash
  statectl.sh mark-failed "$ISSUE_NUMBER" \
    --reason intake-spec-blocked --stage 1 \
    --json "$(statectl.sh build-failure-context --reason intake-spec-blocked --stage 1 \
        --kv outcome=true-blockers --kv-lines blockers="$BLOCKERS")"   # or --kv outcome=gap-overflow --kv-num gapCount=N
  ```

- **Escalation** → `intake-needs-human-input` (the `question` is a scalar → `--kv`, not `--kv-lines`, which would emit a JSON array):

  ```bash
  statectl.sh mark-failed "$ISSUE_NUMBER" \
    --reason intake-needs-human-input --stage 1 \
    --json "$(statectl.sh build-failure-context --reason intake-needs-human-input --stage 1 \
        --kv question="$QUESTION")"
  ```

- **`sub-issues` / `sub-issues-sequential` split** → NOT state-terminated (success-shaped: the ticket decomposed into children). No `mark-failed` — `status` stays `in_progress`. This is a declared carve-out, tracked by a follow-up (neither `mark-failed` nor `mark-completed` fits a split); the split's own tracker comment + `epic` label are the durable record on github. Both flavors take this path identically — the sequential flavor differs only in the children's labels and trailers, not in the parent's state.
- **`budgetExhausted`** orchestrator stop → a **non-failure**, transient stop (re-run with budget available). No `mark-failed` — recording `status: failed` would mis-classify a transient condition and block the invited re-run.

**Re-queue semantics (originating machine).** After an intake stop, the state file is left at `status: failed` locally. `statectl init` is idempotent and does NOT reset it (`.mode` is the one documented carve-out — re-stamped on every `init --mode`, #243), and the resume rule reads-and-exits on `failed`. So the fix-spec → relabel `ready-for-dev` → re-run flow needs the originating machine to also clear its local state file (`rm .claude/pipeline-state/{issue}.json`) before re-running. New/other machines are unaffected (no state file exists there).

#### Step 1.C: Design-driven detection (provider-aware)

Runs only when the orchestrator verdict continues the pipeline (`no-split` — the only continuing verdict), as the **last Stage-1 step before the `stageCheckpoint["1"]` write** — its result is folded into that checkpoint's payload (alongside `verdict` / decomposition fields), not a separate write.

**Provider gate first.** Read `design.provider` from the config (`PROVIDER=$(jq -r '.design.provider // "off"' "$CONFIG")`). If it is `off` (key absent), set `designDriven: false`, `designSource: null` and **skip the rest of this step** — the run behaves exactly as a non-design run. This is the common case. Otherwise detect the provider-appropriate handoff:

**Provider `claude-design`:**
1. **Detect the handoff link.** Scan the issue body for a `claude.ai/design/` URL (e.g. `grep -oiE 'https?://claude\.ai/design/[^ )"]+'`). No match → `designDriven: false`, `designSource: null` (behaves as a non-design run; skip the rest).
2. **On a match — extract `{ link, projectId, screen }`.** The DesignSync handoff is opened **by project id** (per `.project/reference/designsync-probe-findings.md`); resolve the `projectId` from the link (and `screen`, e.g. `detail`, from the issue text — the screen/component to spec + implement).
3. **Reachability probe (fail-closed).** Confirm the project can be read via the `DesignSync` tool (`get_project(projectId)` → assert `type === 'PROJECT_TYPE_PROJECT'`). On success, set `designDriven: true` and record `designSource: { provider: "claude-design", link, projectId, screen }` in the `stageCheckpoint["1"]` payload. On failure — unreachable, type mismatch, **or `DesignSync` unavailable (a headless run)** — fail closed (see the fail-closed block below).

**Provider `figma`:**
1. **Detect the handoff link.** Scan the issue body for a `figma.com/` URL (e.g. `grep -oiE 'https?://(www\.)?figma\.com/(design|file)/[^ )"]+'`). No match → `designDriven: false`, `designSource: null` (behaves as a non-design run; skip the rest).
2. **On a match — extract `{ link, figmaSources, screen }`.** `figmaSources` = the figma node URL(s)/id(s) from the issue body (the `node-id=` query param(s), one per frame to spec + implement); `screen` = the screen/component name from the issue text.
3. **Record the source.** Set `designDriven: true`, `designSource: { provider: "figma", link, figmaSources, screen }`. **Do NOT resolve the FE worktree here** — it does not exist until Stage 2. Stage 3/5 resolve it at dispatch from the ticket's `worktreePath`: a figma/design ticket is `[FE]`-tagged, so its Stage-2 worktree **is** the FE worktree, and `figma.mjs`'s `feWorktree` = the resolved `worktreePath` — exactly how the claude-design path resolves its `WT`. <!-- Reconstructed contract: figma had no in-stock stage wiring (its dispatch was consumer-side in the BE session); the figma-URL detection + figmaSources shape here mirrors the claude-design detection + figma.mjs's documented arg contract. The Figma MCP has no cheap Stage-1 reachability probe like DesignSync.get_project, so figma reachability is enforced fail-closed at the first produce dispatch (figma.mjs status:error → design-source-unreachable), not here. -->

**Fail-closed block (both providers).** On a detected-but-unreadable handoff:

   ```bash
   statectl.sh mark-failed "$ISSUE_NUMBER" \
     --reason design-source-unreachable --stage 1 \
     --json "$(statectl.sh build-failure-context \
       --reason design-source-unreachable --stage 1 \
       --kv provider="$PROVIDER" --kv designLink="$DESIGN_LINK")"
   ```

   Comment (`stage: intake`, `status: failed`) noting the unreachable handoff, keep `in-progress` for manual rescue, and **STOP** rc=0 (autonomous abort). Both providers' reads need interactive/MCP access — see the **Design Mode** launch note in `SKILL.md`: a design-driven issue should be run **interactively**, and a headless run legitimately fails closed rather than guessing a contract.

Consumers read the result downstream via `statectl get "$ISSUE_NUMBER" '.stageCheckpoint."1".designDriven'`, then branch on `.designSource.provider` (Stage 3 spec produce, Stage 4 spec gate, Stage 5 implement + verify, Stage 8 reviewer routing). See state-schema.md **Design Mode**.

#### Step 1.D: Intent snapshot (statectl-owned)

Runs when the verdict continues the pipeline (`no-split`), before the Stage-1 checkpoint write. Records the Brief pointer and the AC snapshot (run-authoritative for plan-lint + pipeline-retro, immune to later issue edits):

1. Resolve `BRIEF_PATH`: if `intake-toolkit:intake-orchestrator` wrote `.claude/pipeline-state/{ISSUE_NUMBER}-brief.md` **this run** (its Step 0.5 ran — an epic / non-engineer-authored issue), use its **absolute** path; else the literal `null` (the common acme case — interviewer-authored bodies skip Step 0.5).
2. Derive `AC_JSON` from the **fetched issue body**: explicit `AC-n` labels win; otherwise apply the AC-ID positional fallback rule ([`state-schema.md` § Intake intent snapshot](../state-schema.md) — normative). Shape: `[{ "id": "AC-n", "text": "...", "negative": <bool>, "source": "explicit"|"derived" }]`; `[]` when the issue yields no AC IDs.
3. Write it:

   ```bash
   statectl.sh intake-brief "$ISSUE_NUMBER" \
     --brief-path "$BRIEF_PATH" --acceptance-criteria "$AC_JSON"
   ```

   A decomposition now produces sub-issues, each of which carries its own ACs verbatim in its own body — so every sub-issue's scope contract is its own ticket, and the downstream gates read the ordinary full-ticket AC snapshot.

The Stage-1 checkpoint payload additionally carries `briefPath` + the AC count alongside the `verdict` / decomposition / design fields, **plus the `preflight` attestation captured in Step 1.P** — the `checkpoint 1` write folds in `preflight: { baseBranch: "$BASE_BRANCH_CFG", workingTreeClean: $WORKING_TREE_CLEAN, guardOutcome: "$GUARD_OUTCOME" }`. This is **required**: `set-stage 1 --status completed` refuses unless `stageCheckpoint["1"].preflight` is present and well-formed (state-schema.md **Completion-evidence preconditions**, row 1), and `checkpoint 1` rejects a present-but-malformed `preflight` at write time. `workingTreeClean:false` is valid (the dirty-tree WARN-and-proceed outcome).

---

_Stage 1 of the [dev-pipeline](../SKILL.md) flow. Return to the router for cross-stage contracts (Invocation Routing, Failure Contract, State Persistence, etc.)._
