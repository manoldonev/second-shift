# Explore — the third stage of `/intake`

Read by `/intake-toolkit:intake` only. Explore is **your own exploration plus the intake fan-out**,
run once per ticket — or, on a split, once for the parent and its slice list together. It ends with
a snapshot of your register, and the interview starts from it while the fan-out still runs.

Explore never dispatches `codebase-explorer`: that gate runs only in Split. When Split ran, read its
map; when it did not, explore with your own tools.

## 1. The fan-out notice — before anything else

The fan-out runs on every intake. Before exploring, print this notice, verbatim, and ask no
question (no `AskUserQuestion`):

> The intake fan-out is starting. Five lenses read the code blind, each from a different angle, and one asks why this ticket would fail two weeks after it ships. What they find joins our interview as evidence, and it tends to raise decisions that my own reading missed. It runs for a few minutes while we talk. Type 'skip fan-out' to stop it.

A split's run prints the same text. Then launch the workflow at once (section 2), and only then
explore (section 3).

**No `Workflow` tool in this session** → print no notice. Say that the fan-out cannot run here, and
every receipt records `Fan-out: failed — Workflow tool unavailable in this session`.

### The operator's skip

Any operator message or free-text answer that contains `skip fan-out` is a skip.

- **Before the pool is read** → stop the workflow with `TaskStop` and read nothing from it. Lenses
  already in flight may finish; their output is not read. Every receipt this intake writes carries
  exactly one line in its `## Fan-out`: `Fan-out: skipped — by the operator, during the run: <their
  reason, or "no reason given">`. Only the operator skips the fan-out; the lint refuses a skip that
  names anyone else.
- **After the pool is read** → there is nothing to stop. Say so. The fan-out stays recorded as run.

### After a return from the Interview

When the Interview sent the ticket back to Split and Split created slices (`interview.md`, "Back to
Split"), Explore runs once more, for the split: **one** fan-out, after the split decision, on the
parent plus the slice list. That run is the split's fan-out.

- **The first run is still unread** → stop it with `TaskStop` and discard it. The split's run
  supersedes it.
- **The operator skipped the first run** → the skip stands for the split. Print no notice, launch
  nothing, and every slice receipt carries the same skip line.
- **Otherwise** → print the notice again and launch the split's run. Its lenses see the seams that
  the first run's lenses never saw.

Pool items the first run already settled as rows stay settled. Each slice receipt's `Run:` line
names the earlier run as superseded (`receipt.md`, "Fan-out").

## 2. Launch it

Stage the script (cross-plugin, by name; `$SKILL_DIR` is the intake skill's base directory and
`$SCRATCHPAD` the session's scratchpad):

```bash
SRC=$(find "$SKILL_DIR/../../../.." -path '*/review-toolkit/*' -path '*/workflows/intake-fanout.mjs' -not -path '*/fixtures/*' 2>/dev/null | sort -V | tail -1)
cp "$SRC" "$SCRATCHPAD/intake-fanout.mjs"
```

Launch it **in the background** with `Workflow({ scriptPath, args })`, args
`{ issue, issueBody, knowledgeSource, readRoot, checkouts, protocol, probeDir, config }`:

- `issueBody` — the ticket body from Requirements. **On a split:** the parent body, then a
  `## Slices` section listing every slice's key, title and one line of scope, so the lenses read the
  seams.
- `knowledgeSource` — the knowledge source's answer from Requirements, as the receipt will carry
  it (the `Provider:` line and the indented answer); omit it when the outcome was `none declared`
  or `failed`. Only the lens writer reads it, to make its jobs concrete: the lenses never see it
  and check their claims against the code, so the pool stays independent of it.
- `protocol` — the absolute paths of the intake `SKILL.md`, `interview.md` (this directory) and
  `interviewing-baseline/SKILL.md`. Every agent works under them.
- `checkouts` — every other repo the change meets that has a local checkout (the frontend that calls
  this backend, a client, a sibling service), each `{ path, role }`, `role` saying what it is. Find
  them from the ticket and the repo's docs: one of the measured run's two catches came from reading
  the consumer's checkout. A consumer with no reachable checkout goes in the receipt as
  `Checkouts: <repo> not available`.
- `config` — only `reviewers.modelOverrides` and `reviewers.tierMap`.

The notice was the announcement; say nothing more at launch. The script stops waiting after 30
minutes and returns the failed form.

## 3. Explore

While it runs, read the ticket (or the parent and its slices), the affected code, the repo's ADRs
and decision docs (wherever CLAUDE.md routes), Split's map when Split ran, and the brief when Split
wrote one (`.claude/pipeline-state/<issue>-brief.md`). Every question the codebase answers is
answered here and recorded `codebase-derived` — never asked. Answer it **by running something**
wherever something can be run (a grep count, `ls`, `git cat-file`, a tool's `--help`) and keep the
command and its decisive output: a `file:line` you read is a pointer, not verification
(`interviewing-baseline`, "Evidence").

## 4. Snapshot, then the interview, then the pool

When exploring is done, write the snapshot to `.claude/pipeline-state/<issue>-snapshot.md` (on a
split, under the parent's number). It holds your decision register as it stands, and the facts you
hold from the ticket body, the code and the spec-reviewer findings. It holds nothing from the pool,
and you write it before you read the pool. That is what plain intake would have gone in with. It is
internal: never shown to the operator as a draft (P8), reaching the record only inside the
receipt's `## Fan-out`, and never read by the scheduler — it is the one file a stop before the
receipt may leave behind.

Once the snapshot is written, start the Interview (`interview.md`) on what the snapshot supports. Do
not wait for the workflow. When you run out of questions before the pool arrives, wait for the
workflow's completion notice, or its failed or ceiling form. That is the only wait, and the
30-minute ceiling bounds it.

When the workflow completes, read the pool and tag each item against the snapshot
(`interviewing-baseline`, "Fan-out"). Every item arrives `unverified`: nothing checked it inside the
workflow.

- **Check before use.** Before an item becomes a row, an option or a question, check it from its
  pointer: open the file, run the command. The row carries the check in an existing evidence form
  (``run: `<command>` → <output>`` or `cited (…)`) and `From: F-n` in its Resolution, after the
  evidence (several ids comma-separated). An item whose check fails is tagged `not material`, with
  the disposition `not used — did not hold: <what the check showed>`, and becomes nothing else.
- **An item about a question you already asked** before you read the pool is tagged `already-had`.
  Its disposition reads `already had — D-n` and needs no `From:` link.
- **An item that contradicts an answer already given** goes back to the operator once
  (`interview.md`, "A late finding").
- **An item that contradicts a fact row you wrote after the snapshot** is tagged `new`. Correct the
  row in place. The row gains the `From:` link, and the disposition reads `became D-n`.

An item becomes a row, an option, a probed fact or a question **only if it passes the Interview's
materiality bar**. Pool evidence may overturn a snapshot claim it contradicts. A `failed` or
`partial` result is said in the receipt's `## Fan-out`, never dropped.

**On a split,** sort the items by slice: each item goes to every slice it touches (a seam item to
both sides). Each slice's interview takes its own items; its receipt lists them and names the
shared run (`interview.md`, "On a split").

## Outcome for the receipt

`Explore:` says what you explored (`done — the worker, its DTOs and the proxy config`). `Fan-out:`
says `ran — <n> items, see Fan-out` (on a slice: `ran once for the #<parent> split — <n> items
touch this slice`), or carries the skipped or failed form above.
