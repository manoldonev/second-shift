# Receipt — the last stage of `/intake`

Read by `/intake-toolkit:intake` only. The Receipt is intake's **one** writer of
`.claude/pipeline-state/<issue>-ledger.md`, the record a pipeline run launches from: it survives
worktree cleanup, the scheduler lints it before it claims the ticket, commits it as the lane
branch's first commit, hands it to the BUILD session — its `D-n` rows binding, its `## Fan-out` and
`## Knowledge source` context — and reads its checks and
design frames from that commit. It runs per ticket — on a split, per slice, the file named for the
slice.

`${CLAUDE_PLUGIN_ROOT}` is intake-toolkit here; the lint and the scan ship beside `plan-interview`
in this same plugin.

## The exit gates, in order

Run these before writing, in this order. Each runs once per ticket or slice, except that gate 3
runs again for a row a later step adds or changes. The probe runs after the write ("Probe the
record").

### 1. Post-merge scan

A written ticket never went through the Requirements interview's AC question. Scan its ACs for any
that can only be observed after the merge — the next run's transcript, a production metric, a later
deploy. The scope gate fails such an AC on every PR, since no diff satisfies it.

For each one, ask the operator whether it is a post-merge check (recommendation: yes, when nothing
in the diff could show it). On a yes, the answer authorizes the tracker write: move the item out of
the ACs into the body's `## Post-merge checks` section yourself, as the next `PM-n` (create the
section after the ACs if there is none), and change nothing else — on github
`gh issue view <issue> --json body`, edit, `gh issue edit <issue> --body-file <file>`; under jira,
the description. Record a `user-answered` row either way: moved, or kept as an AC the gate will
score. No such AC → nothing to ask and no row.

### 2. Duplicate scan

The receipt is the last thing written before a ticket can be queued, so it is the last place a
duplicate is caught cheaply:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/plan-interview/tools/dup-scan.sh" --issue <issue>
```

- **`0`** — nothing at or above the threshold. Record nothing; a clean scan is not a decision.
- **`10`** — ranked candidates. Judge each yourself and record one ledger row per candidate: the
  same work (fold this ticket into it, and say so), overlapping but distinct (sequence it if they
  touch the same files — a candidate carrying the *claimed* label is already being built), or
  unrelated. A sibling slice of the same split, queued after its own receipt, is related by
  construction, not a duplicate. **Never close a ticket on this output.**
- **`2`** — the scan could not run. Hard-stop: report the rc and the reason. Write no receipt and
  queue nothing; the operator fixes it and re-runs `/intake-toolkit:intake <issue>`. There is no
  proceed-with-a-flag variant: a flag in a local receipt is read by no claimant, while a queue label
  would still advertise the ticket as eligible.

Under `tracker.type: jira` it prints a not-applicable line and exits `0` — no queue label, no
corpus.

### 3. Amend the ticket

The review's first pass grades the diff against the ticket body alone, and no record row clears
its finding. So a departure that only the record states blocks every review round.

Read each `intent` row that the operator chose: `user-answered`, `user-delegated` or
`ticket-sourced`. Compare it with the whole ticket body: the ACs, the Scope bullets and all other
text. Where the row chose a behavior that differs from that text, mark the row as a departure if it
is not marked yet. Then rewrite that text in the ticket body, in place, so that it states the
chosen behavior. Keep the id and the position of that text. Change nothing else in the body. The
row's departure sentence keeps the original text.

The operator's choice of the departure authorizes the write, as in the post-merge scan. On github:
`gh issue view <issue> --json body`, edit, `gh issue edit <issue> --body-file <file>`. Under jira,
edit the description. No departure → no edit.

A later step that adds or changes an operator-chosen row ("Act on the report", "Lint it") runs
this gate again over that row, and then lints again.

## Write the receipt

The shape and every empty form are `interviewing-baseline`'s ("The intake receipt"); write the
highest version the lint knows (`ledger-lint.sh --receipt-version`).

```
# Decision record — #<issue> <title>

Receipt: v5

## Summary

<2-4 sentences: what the ticket changes.>

Open regions: <each OR-n and its default, in a few words; or "none">.

Provenance legend: `user-answered` = the operator chose. `user-delegated` = the operator gave the choice to the agent. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region. `ticket-sourced` = the operator decided in a linked ticket comment, or the linked parent or sibling ticket states it.

Open region legend: `pause-and-ask` = the build stops and asks. `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger
## Open Regions
## Test intent
## Surface Inventory
## Checks
## Design frames        (on a repo whose config sets design.provider)
## Intake steps

Requirements: <the route and what it did — requirements.md, "Outcome for the receipt">

Split: <not split and why, not triggered and why, or the slices — split.md>

Explore: <what you explored — explore.md>

Fan-out: <ran, with its item count; or the skipped/failed form — explore.md>

Dup-scan: <the scan's result>

Post-merge scan: <the ACs moved, or none>

Sizing: <opus or sonnet — the weight you decided>

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source
## Fan-out

</details>
```

The readers are the operator who merges and the reviewer who scores the rows. Put their needs
first. Write no decision counts in the Summary. A build edit can change the provenance of a row,
and then the counts are false. The Summary never states a rule more broadly than its row does.
In each legend, define only the values that the record uses. Put a blank line between two step lines. Without it, GitHub shows
the seven steps as one paragraph. Open the `<details>` fold after the last step line, and close it
after the Fan-out section. Do not close the fold inside Knowledge source, because the lint refuses
an unindented line there.

Write the whole record in plain technical English:

- One instruction or one fact per sentence. Max 25 words per sentence.
- Active voice. Simple tenses. Use the same word for the same thing every time.
- No semicolon chains and no chained dashes. Split them into sentences.
- Use articles (a, the). Do not use noun clusters longer than three words.
- Technical names stay as they are: paths, flags, commands, and ids such as D-3 and OR-1.

Write each `Intake steps` key once, in the order above, at the start of its line. Write what the
step did, or why it did not run. Never write an empty outcome
or a bare dash. Example: "Requirements: the ticket body as written. spec-reviewer: implementable.
The interview resolved 2 gaps."

- **Decision Ledger** — five columns (`Kind` included). Write the Decision cell as a short
  question or noun phrase. Write the Resolution cell as the answer. Put the chosen value first and the
  reason after it. Write one decision per row. Never split one
  decision into several rows to make the cells shorter. Each extra row is one more row for the
  review to score. Keep a cell to 40 words when no condition is lost. A cell can be longer only to
  keep a condition, because only the rows bind the build. Put each condition in its own sentence.
  End every `codebase-derived` cell with its evidence. Use one of three forms:
  ``run: `<command>` → <decisive output>``, `cited (convention|adr): <path:line>` or
  `cited (kb): <kb-page>`. Run a command when one can be run. Use `cited (kb)` for a fact from the
  answer of the knowledge source. Escape a `|` in the evidence as `\|`. The evidence does not
  count toward the 40 words, and neither do the `Inputs:`, `Outputs:` and `Errors:` sentences of a
  contract row. A row that records your own choice is not `codebase-derived`. Ask
  the operator.
  Write the alternatives you weighed in an `Options weighed:` list under the table, one bullet per
  row: `- D-n: <option A> or <option B>. <the decider that the Provenance cell names> chose <X>.`
  This list does not bind the build.
- **Open Regions** — every `open` row cites a declared `OR-n` with its disposition token. Under the
  table, write one short block per `reversible-default-and-flag` region: `OR-n default:` then the
  default, who chose it, and what reversing it costs. Use a list when there is more than one
  default.
- **Surface Inventory** — every surface `decided (D-n)`, `contract (D-n)` or
  `out-of-scope — <reason>`. Mark `contract` on each interface that code outside the change calls
  or parses: an HTTP endpoint, an SDK or library method, an event or message, a CLI or script
  interface, or output a machine reads. Its cited row states `Inputs:` (each input, required or
  optional), `Outputs:` and `Errors:` (each status, error or exit code)
  (`interviewing-baseline`, "The Surface Inventory"). Write the Surface cell in at most 10 words.
  Write an `out-of-scope` reason in one sentence.
- **Checks** — start from the repo's verification recipe (its CLAUDE.md, the config's `commands.*`)
  and list only what the configured lanes would miss — the selftest the ticket touches, a script its
  ACs name — one command per line; or the empty form.
- **Design frames** — on a `design.provider` repo, walk the handoff with the operator: one row per
  screen and state the ticket renders, with the frame id, and agree each row's `must-show` now (the
  element that proves the right state rendered — the empty-state copy on an empty row, not the page
  title every state shares). A ticket that renders nothing disarms with `Design: none — <reason>`.
- **Fan-out** — the `Lenses:` line, the tally, the tagged pool and the snapshot indented four
  spaces (`interviewing-baseline`, "Fan-out"), or exactly one skipped or failed line. The skip form
  is the operator's: `Fan-out: skipped — by the operator, during the run: <reason>`. Each row that
  came from a finding carries `From: F-n`, and the tally counts what the rows show: the lint checks
  both. **On a slice:** list only the items
  Explore sorted to this slice, add a `Run:` line naming the shared run
  (`Run: shared with the #<parent> split — slices #a, #b, #c`), and embed the shared snapshot. When
  the ticket came back to Split from the Interview, the `Run:` line also names the pre-split run
  this one superseded (`; supersedes the pre-split run on #<parent>`). Write each claim cell in one
  sentence, with its pointer. Write each disposition cell in max 15 words.
- **Knowledge source** — Requirements' outcome (`requirements.md`, "The knowledge source"), in
  exactly one form: `Provider: <plugin>:<agent>` and under it the provider's whole answer, verbatim,
  every line indented four spaces; `Knowledge source: none declared`; or `Knowledge source: failed
  — <the first line of the error, or what is malformed>`. **On a slice:** the whole answer the
  parent's dispatch got, the same in every slice receipt.
- **Test intent** — transcribe the ticket's AC ids onto one `ACs: AC-1 AC-2 …` line, exactly as
  labeled (holes stay holes; a `PM-n` item is never one), or `ACs: none — <reason>` when the ticket
  has no AC block. Under it, one line per id: draft `AC-n: <the observable behavior its test must
  prove>` from the AC's own text. Each `AC-n` line keeps the meaning of the ticket's criterion with
  that id, unless the operator chose a departure that a `D-n` row records. An AC no test can prove
  (docs, config) is an exemption, and **every exemption is the operator's**: put it to them as a
  question, record the answer as a `user-answered` row, and only then write
  `AC-n: exempt — <reason>`. Never exempt one silently. Two more forms are the operator's the same
  way, each asked and recorded as its own `user-answered` row:
  `AC-n: holds — <the existing behavior its test keeps>` for an AC about behavior that already
  exists ("X still works": its test passes without the change, so the scheduler keeps it off the
  fails-without-the-change check), and `AC-n: unchecked — <tier and
  reason>` for one whose test sits on a tier the scheduler cannot run (a black-box API suite that
  needs the running app). Both must still be tagged on a test task.
  The build's test-first plan is held to these ids (`interviewing-baseline`, "Test intent").

## Probe the record

The build reads the record, not your context. So the probe reads what the build reads. It runs
whenever the ticket has an AC block. A ticket with no AC block gets no probe, and its
`Requirements:` step line says so and why. A silent skip is the failure this rung exists to catch.

Dispatch `intake-toolkit:implementability-probe` via `Task`. Hand it the path of the finished
record and the ticket body. Hand it nothing else: no interview, no findings from this session, no
issue thread. It only works blind: what the elicitation left in your context is exactly what the
cold implementer will not have. It returns guess-points, and it reports the record against the
ticket's criteria. No `Task` tool → say on the `Requirements:` step line that the probe was
skipped and why. Never inline it.

### A partial report

The report is not final while the harness marks it partial or it holds an `unverified` item.
Resume the same probe with SendMessage. When the harness marked the report partial, tell the probe
that its report was cut short and to finish the whole report. Otherwise name each unverified item
in the message and tell the probe to finish those items. Resume at most 2 times. Then ask the operator to accept the report as
partial or to resume again, and recommend a resume. A session with no SendMessage makes no resume
and asks the operator at once.

Record a partial round only on the operator's word, on the `Requirements:` step line. Each item
still `unverified` in a report the operator accepts becomes its own `OR-n` with disposition
`pause-and-ask`. A ticket AC that the accepted report does not list counts as `unverified`. Never
guess the status of an unchecked AC line or guess-point.

### Act on the report

Act on its output before the lint runs. The operator chose a change or a departure when an
`intent` row records it: `user-answered`, `user-delegated` or `ticket-sourced`.

- A build-blocking guess-point → ask the operator and record the answer as a row, or declare an
  `OR-n`.
- A criterion reported absent → ask the operator. Recommend an `AC-n` line drafted from the
  ticket's text ("Test intent" above). Record the answer: the id on the `ACs:` line with its
  `AC-n` line, and a row for any decision it needs. Or declare an `OR-n`.
- An `AC-n` whose meaning changed and the operator did not choose the change → ask the operator,
  recommending the ticket's meaning. Record the answer as a row and write the `AC-n` line to match
  it, or declare an `OR-n`.
- An `AC-n` whose meaning the operator changed → its Test intent line states the chosen behavior
  under the ticket's id, and its row is marked as a departure.
- Any other guess-point:
  - the answer is the operator's → a question, and a new ledger row;
  - the answer is knowable from code → resolve it and record a `fact` row;
  - the answer is genuinely undecided → a declared `OR-n` with a disposition.
- A reported departure that the operator chose → mark its row as a departure if it is not marked
  yet. Do not ask it again.
- A reported departure that the operator did not choose → ask the operator, or declare an `OR-n`.

A row is marked as a departure when its Resolution ends with a `Departs from AC-n:` or a
`Departs from the ticket's <part>:` sentence (`interviewing-baseline`, "Departures").

The probe runs once per ticket or slice. Only the resumes of a partial report repeat it. It never
blocks without an operator question.

## Lint it

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/plan-interview/tools/ledger-lint.sh" \
  --receipt .claude/pipeline-state/<issue>-ledger.md
```

The scheduler runs the same lint before it claims and refuses a receipt that fails, so a red lint
here is a run that will not launch. The lint prints each refusal with its remedy. Three rules it
cannot check:

- **Provenance** — when it refuses an `intent` row's provenance, ask the decision, or reclassify
  the row honestly; never edit the Kind cell to clear the lint.
- **Surface inventory** — the empty form is for work that renders nothing, not a way to clear the
  section. It is wrong when the change adds an interface that other code calls or parses: that is a
  `contract` row. The lint checks a contract only where you marked one.
- **Test intent** — re-read the ticket's AC block: the lint cannot see an id you left off the
  `ACs:` line.

Fix and re-lint until it is clean.

## After it lints clean

Only now, the tracker writes the exit owns (github; under jira there are no labels — the launcher
sizes and queues):

- **Sizing.** Label the ticket or slice `opus` or `sonnet`, your judgment of its weight, through the
  bot passthrough `split.md` resolves (`$GH_BOT_SH`, "Bot writes"):
  `$GH_BOT_SH issue edit <issue> --add-label <opus|sonnet>`. If it already carries the other label
  and the interview changed its weight, remove that one in the same call; otherwise leave an
  existing label alone.
- **A slice's queue label.** A parallel slice, and the first slice of a sequential split, gets the
  queue label now — never before its receipt lints clean, and never on a blocked successor (its
  operator queues it when its predecessor closes). Where the repo reserves queueing to the operator
  (its CLAUDE.md says so), leave every slice unqueued and say so. A ticket that was **not** split is
  never queued by intake: queueing it is the operator's.

Then hand off: name the receipt's path, its lint result, each ticket text you amended, and the
command that launches the run.
