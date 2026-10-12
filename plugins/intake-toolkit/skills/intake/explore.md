# Explore — the third stage of `/intake`

Read by `/intake-toolkit:intake` only. Explore is **your own exploration plus the intake fan-out**,
run once per ticket — or, on a split, once for the parent and its slice list together. It ends with
a snapshot of your register and the fan-out's pool in hand, for the Interview.

Explore never dispatches `codebase-explorer`: that gate runs only in Split. When Split ran, read its
map; when it did not, explore with your own tools.

## 1. The fan-out notice — before anything else

The fan-out runs by default. Before exploring and before launching, give the operator **one**
notice and **one** question (`AskUserQuestion`, the run option first). The notice says, plainly:

- the fan-out runs by default on every intake;
- what it does: a sealed writer sets four angles and a pre-mortem; five lenses work them blind,
  alternating Opus and Fable; every claim faces a refuter from the other family and is dropped
  unless confirmed; what survives joins the interview as evidence;
- why: on consumer tickets whose intake decision was later reversed, intake with the pool caught
  decisions plain intake missed;
- what it costs: it runs alongside exploration for up to 30 minutes, and questions start when it
  returns; it uses Fable where the account has it (subscription usage) and Opus where it does not;
- **on a split:** it runs once, on the parent and the slice list, so its lenses see the seams
  between slices; every slice's interview takes the items that touch it;
- what is recorded: the receipt's `## Fan-out` shows what it added over plain intake.

The options are **Run the fan-out (default)** and **Skip it for this ticket** (on a split, "for
this split"); the operator may add a reason. Ask once: an answer is not reopened in the session, and
on a split it covers every slice — no slice gets a notice of its own.

- **Skip** → launch nothing, and every receipt this intake writes carries exactly one line in its
  `## Fan-out`: `Fan-out: skipped — by the operator at the intake notice: <their reason, or "no
  reason given">`. Only the operator skips the fan-out; the lint refuses a skip that names anyone
  else.
- **No `Workflow` tool in this session** → ask nothing; say the fan-out cannot run here, and every
  receipt records `Fan-out: failed — Workflow tool unavailable in this session`.

## 2. Launch it

Stage the script (cross-plugin, by name; `$SKILL_DIR` is the intake skill's base directory and
`$SCRATCHPAD` the session's scratchpad):

```bash
SRC=$(find "$SKILL_DIR/../../../.." -path '*/review-toolkit/*' -path '*/workflows/intake-fanout.mjs' -not -path '*/fixtures/*' 2>/dev/null | sort -V | tail -1)
cp "$SRC" "$SCRATCHPAD/intake-fanout.mjs"
```

Launch it **in the background** with `Workflow({ scriptPath, args })`, args
`{ issue, issueBody, readRoot, checkouts, protocol, probeDir, config }`:

- `issueBody` — the ticket body from Requirements. **On a split:** the parent body, then a
  `## Slices` section listing every slice's key, title and one line of scope, so the lenses read the
  seams.
- `protocol` — the absolute paths of the intake `SKILL.md`, `interview.md` (this directory) and
  `interviewing-baseline/SKILL.md`. Every agent works under them.
- `checkouts` — every other repo the change meets that has a local checkout (the frontend that calls
  this backend, a client, a sibling service), each `{ path, role }`, `role` saying what it is. Find
  them from the ticket and the repo's docs before launching: one of the measured run's two catches
  came from reading the consumer's checkout. A consumer with no reachable checkout goes in the
  receipt as `Checkouts: <repo> not available`.
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

## 4. Snapshot, then the pool

When exploring is done, write your register as it stands to
`.claude/pipeline-state/<issue>-snapshot.md` (on a split, under the parent's number). That is what
plain intake would have gone in with. It is internal: never shown to the operator as a draft (P8),
reaching the record only inside the receipt's `## Fan-out`, and never read by the scheduler — it is
the one file a stop before the receipt may leave behind.

Only then read the fan-out's result, waiting for its completion notice if it is still running. No
question goes to the operator before the pool is in.

Consume the pool like your own findings: verify what you need from each item's pointer. An item
becomes a register row, an option, a probed fact or a question **only if it passes the Interview's
materiality bar**. Pool evidence may overturn a snapshot claim it contradicts. A `failed` or
`partial` result is said in the receipt's `## Fan-out`, never dropped.

**On a split,** sort the items by slice: each item goes to every slice it touches (a seam item to
both sides). Each slice's interview takes its own items; its receipt lists them and names the
shared run (`interview.md`, "On a split").

## Outcome for the receipt

`Explore:` says what you explored (`done — the worker, its DTOs and the proxy config`). `Fan-out:`
says `ran — <n> items, see Fan-out` (on a slice: `ran once for the #<parent> split — <n> items
touch this slice`), or carries the skipped or failed form above.
