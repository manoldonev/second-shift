# Intake receipt — #1023 /intake is the only way in — one sequence, one receipt writer

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Who owns the order of the stages | `/intake` runs them in order; the router's "Never chain multiple destinations yourself" rule is replaced (follows from #1016 D-7) | user-answered | intent |
| D-2 | Requirements for a written ticket | Requirements runs on every input: a rough input gets the interview, a written ticket only a spec-reviewer pass, and the result passes on in memory. Options weighed: skip it, as today | user-answered | intent |
| D-3 | When Split runs | On the `epic` label, on more than one deliverable, or when the interview's register passes ~10 material decisions (the ticket returns to Split). Options weighed: every ticket; only on request | user-answered | intent |
| D-4 | Where codebase-explorer runs | Split only, once; decomposition-reviewer uses its map; Explore never runs it. A departure from #1016 D-8 ("in Explore"), by the operator. Options weighed: map at first use; Explore before Split | user-answered | intent |
| D-5 | Filing a rough input | The sequence asks; on a yes it files through the session's tracker tool (gh; the Atlassian MCP's create tool under jira when present); else the operator files and pastes the key; the sequence continues in the same session. Intake never writes to a tracker without an explicit yes. Options weighed: stop after Requirements | user-answered | intent |
| D-6 | The fan-out on a split | One run after the split decision, on the parent plus the slice list, so the lenses see the seams; one notice; each slice takes its items and names the shared run. Options weighed: one per slice with a costed notice; one before the split; none on slices | user-answered | intent |
| D-7 | A restart that finds slices without receipts | Writes the missing receipts and leaves the others alone. Options weighed: report and stop | user-answered | intent |
| D-8 | The way into intake | The stages become supporting files under skills/intake/ that only /intake reads; an engineer's ticket enters by `/intake <issue>`; plan-interview stays a skill for plan mode only; grill-me unchanged. A departure from #1016 D-7, by the operator; breaking for consumers. Options weighed: frontmatter hiding (`user-invocable: false` still leaves auto-selection); keep entries and redirect | user-answered | intent |
| D-9 | A design-handoff input | Requirements runs design-toolkit's design-faithful-spec; the sequence continues to the receipt. Options weighed: outside the sequence | user-answered | intent |
| D-10 | Where each gate runs | spec-reviewer at Requirements; codebase-explorer at Split; the fan-out at Explore (per ticket, or once per split); implementability-probe, dup-scan and sizing at the receipt exit, per ticket or slice (from #1016 D-8 and D-4 here) | user-answered | intent |
| D-11 | Queueing a slice | Created without the queue label; labeled only after its receipt lints clean (from #1016 D-10) | user-answered | intent |
| D-12 | The Explore snapshot after a stop | Allowed: run.sh never reads it — run: `grep -c 'snapshot.md' plugins/dev-pipeline/skills/run/run.sh` → 0 | codebase-derived | fact |
| D-13 | Provenance of an escalation answer | In the session → user-answered; in a ticket comment → ticket-sourced with its URL — cited (convention): plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md:51 | codebase-derived | fact |
| D-14 | Skip-form grammar | Parked under OR-1 | deferred | open |
| D-15 | run.sh's refusal text | Names `/intake-toolkit:intake <issue>`, with a run-selftest case (follows from D-8; a run.sh behavior change lands with a case that fails without it — cited (convention): CLAUDE.md "A session-launch fix lands in the scheduler") | user-answered | intent |
| D-16 | #1022's interim claim | Receipts from intake-orchestrator are v1 and keep passing the launch lint until this ticket lands, contrary to #1022 D-12's wording — run: `grep -c 'Receipt: v' plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` → 0 | codebase-derived | fact |
| D-17 | The dup-scan-rc2 lockstep group | Today three sites; with one receipt exit the group is removed or re-paired — run: `grep -rl 'LOCKSTEP-BEGIN dup-scan-rc2' plugins \| wc -l` → 3 | codebase-derived | fact |
| D-18 | Evals and docs on the old shape | Parked under OR-2 | deferred | open |
| D-19 | Duplicate scan | No candidates — run: `dup-scan.sh --issue 1023` → "no candidates at or above threshold 12" | codebase-derived | fact |
| D-20 | Scope size | One ticket, despite ~20 decisions. Options weighed: split into one-channel-in and the Split stage | user-answered | intent |
| D-21 | Creating slices on a split | Split shows the slice list and creates the slices only on the operator's explicit yes, as Filing does for a rough input; a no records the decision and stops. Reason: D-5's "never writes to a tracker without an explicit yes" would otherwise hold for one issue-create and not the other. Options weighed: auto-create as the orchestrator did | user-delegated | intent |
| D-22 | Where ledger-lint.sh and dup-scan.sh live | They stay at `skills/plan-interview/tools/`. Reason: run.sh and the exitplan hook resolve the lint there, and moving it would break every consumer's launch lint for no behavior change. Options weighed: move them under `skills/intake/tools/` | user-delegated | intent |
| D-23 | What a restart counts as "has a receipt" | A slice whose `.claude/pipeline-state/<slice>-ledger.md` exists, or that is closed, or carries the queue or claimed label (D-11 queues only after a clean lint), is left alone; every other `Part of #N` slice gets Explore, Interview and Receipt. Reason: the receipt is local, so the labels are the only cross-machine trace of one. Options weighed: the local file alone | user-delegated | intent |
| D-24 | The fan-out when the Interview sends a ticket back to Split | If Split then creates slices, Explore runs the split's one fan-out after the split decision, on the parent plus the slice list, and it supersedes the run on the unsplit ticket. A skip at the first notice stands, and nothing is re-asked. After a run, the split gets one notice of its own, saying it is a second run. Rows the first pool settled stay settled, and each slice's `Run:` line names the superseded run. If Split decides "not split", no new run. Reason: D-6 rejected "one before the split" because those lenses never see the seams, and AC-7 asks for the run after the split decision. Options weighed: reuse the pre-split pool with no second run | user-delegated | intent |
| D-25 | Which findings of the round-1 verdict this round addresses | Operator instructed: address all findings of the round-1 verdict, notes included. This departs from the lane's default of acting only on blockers and bad rows. The instruction was relayed to the build by the operator's interactive session (second-shift-9a). The verdict reviewed e639559a, before the branch was rebased; every finding still applied at e1193e3a. B1 → D-24. N2 → the eval prompts read existing slices from the prior comments. N3 → the lint also checks the Intake steps `Fan-out:` line (ll-rv6). N4 → docs/testing.md records the `decomposition-economy` removal. N1 is not done here: the `.claude/SECOND-SHIFT.md` edit was denied as a sensitive file, so it needs an operator edit | user-answered | intent |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The skip-form allowlist's exact grammar | reversible-default-and-flag |
| OR-2 | How the intake-orchestrator eval and docs/skill-ablation.md follow the stage files | reversible-default-and-flag |

OR-1 default: case-insensitive "by the operator" at a word boundary (so "by the operator;" and "by the operator's" pass), its own named violation, the selftest's shared skip constant rewritten to the operator form, and #1022's run-selftest fixture using the operator form. A regex edit reverses it. OR-2 default: the eval targets the Split stage file with the same rubric; the ablation doc describes the stage outputs. A path edit reverses it.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The `/intake` entry and its stage order | decided (D-1) |
| S-2 | The filing prompt for a rough input | decided (D-5) |
| S-3 | The single fan-out notice on a split | decided (D-6) |
| S-4 | Slice creation and labels | decided (D-11) |
| S-5 | A restart over slices without receipts | decided (D-7) |
| S-6 | run.sh's refusal text | decided (D-15) |
| S-7 | The removed slash commands (`/plan-interview <issue>`, `/intake-orchestrator`, `/intake-interviewer`) | decided (D-8) |
| S-8 | The receipt's Fan-out skip line | decided (D-14) |
| S-9 | Docs, evals and skill text on the old shape | decided (D-18) |

## Checks

- `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint-selftest.sh`

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: control-flow-ownership opus 6/6 · gate-inventory fable 5/6 · record-compatibility opus 5/6 · interruption-and-provenance fable 2/6 · premortem fable 6/6
Tally: rows added 6 · snapshot claims overturned 1 · questions added 6

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | control-flow-ownership | No component hands control to the next stage; the router forbids chaining | already-had | became D-1 |
| F-2 | control-flow-ownership | The orchestrator writes a receipt and queues slices itself | already-had | became D-11 |
| F-3 | control-flow-ownership | A seed saved at the receipt path is enough to launch | new | became D-12 |
| F-4 | control-flow-ownership | Several live skip strings do not name the operator | already-had | became D-14 |
| F-5 | control-flow-ownership | The orchestrator eval, the ablation doc and testing.md rely on the standalone shape | new | became D-18 |
| F-6 | control-flow-ownership | A direct call to a stage skill skips the front door | new | became D-8 |
| F-7 | gate-inventory | Gate inventory: codebase-explorer is used only by the orchestrator and decomposition-reviewer | overturned (snapshot: "at Split when Split runs, else Explore") | became D-4 |
| F-8 | gate-inventory | codebase-explorer runs twice and dup-scan three times on the epic route | new | became D-10 |
| F-9 | gate-inventory | Labels are written at slice creation before any slice receipt | already-had | became D-11 |
| F-10 | gate-inventory | The lint accepts every reasoned skip; no Intake steps check exists yet | already-had | became D-14 |
| F-11 | gate-inventory | Per-slice fan-outs and notices in one session are undefined | already-had | became D-6 |
| F-12 | record-compatibility | Narrowing the regex alone turns 15 selftest cases red | new | became D-14 |
| F-13 | record-compatibility | A non-operator skip needs its own named violation | new | became D-14 |
| F-14 | record-compatibility | "by the operator" needs a word-boundary reading | new | became D-14 |
| F-15 | record-compatibility | Orchestrator receipts are v1 and keep passing the launch lint | new | became D-16 |
| F-16 | record-compatibility | #1022's fixture Fan-out line must be in the allowlist | new | became D-14 |
| F-17 | interruption-and-provenance | A crash mid-split leaves labeled slices with no receipts | new | became D-7 |
| F-18 | interruption-and-provenance | The Explore snapshot is written before the receipt | new | became D-12 |
| F-19 | premortem | A restart reads existing slices as already decomposed | new | became D-7 |
| F-20 | premortem | Nothing pins that the retired prose forms now fail | new | became D-14 |
| F-21 | premortem | The interviewer's text tells the engineer to save its seed at the receipt path | already-had | became D-12 |
| F-22 | premortem | Later slices inherit a skip the operator was never asked about | new | became D-6 |
| F-23 | premortem | The spec-review marker loses its carrier when the interviewer has no output | new | became D-2 |
| F-24 | premortem | Removing receipt exits shrinks the dup-scan-rc2 lockstep group | new | became D-17 |

### Snapshot

    # #1023 snapshot — register before the fan-out pool (internal)
    
    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Router dispatch | The router's "Never chain multiple destinations yourself — route to the FIRST skill" rule is replaced: /intake runs the stages in order (required by #1016 D-7) |
    | D-2 | When Requirements and Split run | Open: Requirements when the body has no AC-n block (or no clean spec-review marker)?; Split when the orchestrator's classification finds more than one deliverable? |
    | D-3 | spec-reviewer when Requirements is skipped | Open: plan-interview never runs spec-reviewer today (grep count 0); options: Requirements always runs a review-only pass on a written ticket; or no spec review for engineer tickets (status quo) |
    | D-4 | codebase-explorer placement | Conflict: the orchestrator needs it to decide the split (Step 2), before Explore; #1016 D-8 placed it in Explore. Options: at Split when Split runs, else Explore (a departure from #1016 D-8) |
    | D-5 | Fan-out cost on a split | Open (side note): per-slice fan-outs at ~1.2M each exceed the 3M ceiling at 3 slices; options: one shared fan-out per split; per slice with a projected cost in the notice; an explicit go above 3M |
    | D-6 | Design handoff and grill-me inputs | Open: #1016 put grill-me and design-faithful-spec out of scope; the router still routes them; does a design handoff enter the sequence as its Requirements stage? |
    | D-7 | Filing the ticket inside one sequence | Open: the receipt is keyed by issue number, but intake-interviewer never files ("Never create the GitHub issue yourself"); options: the sequence files the issue on approval and continues; or it stops after Requirements and restarts from the filed ticket |
    | D-8 | Orchestrator escalation inside the sequence | It stops (needs-intake-review + comment); the next session restarts from the ticket; comment answers are ticket-sourced (from #1016 D-11/D-12) |
    | D-9 | Slice creation and queueing | Slices created without the queue label; label only after the slice's receipt lints (from #1016 D-10) |
    | D-10 | The Product-Essence Brief | Still written under the parent number for audit; slices take it in memory |
    | D-11 | Skip-form allowlist | Lint accepts only the operator and failure forms; fixtures using other forms rewritten (from #1016 D-6) |
    | D-12 | Docs | The list in the ticket (from #1016 D-14) |
