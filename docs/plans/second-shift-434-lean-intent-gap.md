issue: 434
run_id: lean-434-a
session_id: acfe299d-7de3-46cb-a37f-3b9f11199523
region: undeclared
disposition: reversible-default-and-flag
ratified: yes
ratified_by: https://github.com/manoldonev/second-shift/issues/434#issuecomment-5227624705

## Gap

D-9 settles **that** a voided round gets its own state marker, and names the mechanism: "a
distinct `failureContext` reason alongside the existing `scope-blocker-no-code-remedy`
short-circuit". That mechanism cannot coexist with D-8, which the same receipt settles.

`failureContext.reason` is written only by `statectl mark-failed`, which sets top-level
`status: failed`. Once it is set, `require_mutable` (`statectl.sh:600`) refuses every
subsequent mutating subcommand without `--force` — including `pr-add`, `comment-add` and
`mark-completed`. D-8 routes the void "straight to the existing draft + `needs-deep-review`
human handoff", which is precisely those writes. So a void recorded as a `failureContext`
reason cannot reach the handoff D-8 mandates.

The receipt's own comparator shows the mis-recollection: `scope-blocker-no-code-remedy` is
**not** a `failureContext.reason`. It is a comment status in the `code-review` marker row of
`state-schema.md:372` — a documentation-only column that the generated validators never see
(`state-schema.md:377`). That path records its outcome with `review-rounds --set N
--exhausted` and continues to Stage 9; it never marks the run failed.

So the decision the receipt does not cover is **which state surface carries the void**, not
whether it ships (D-9 settles that), nor what it is for (D-9 settles that too: countable in
the retro corpus, distinguishable from a scope handoff), nor what the round does next (D-8).

## Disposition followed

Took the reversible default and flagged it. The void is recorded as
`statectl review-rounds --set N --voided` → `codeReviewVoided: true`, the exact structural
sibling of the `--exhausted` flag the scope-blocker short-circuit already writes:

- **additive-only** and never written false, so a later plain `--set` cannot erase it;
- carried in `state-schema.md` as a field entry, plus `review-void-zero-coverage` in the
  `code-review` marker row's Statuses-emitted column — so the void is distinguishable from a
  scope handoff in both the state file and the issue thread;
- read straight out of the run's state JSON, which is what "countable in the retro corpus"
  means — strictly stronger than a comment status, which is documentation-only;
- leaves `status: in_progress`, so the D-8 handoff writes all succeed and the run reaches its
  terminal `mark-completed`.

It also satisfies D-9's two stated obligations literally: it carries a schema row, and it
carries a statectl acceptance case (`--voided` is a real flag on a real subcommand, unlike a
comment status, which has nothing for statectl to accept).

Reversible: the flag is one `case` arm plus one `jq` clause in `cmd_review_rounds`, one field
entry in `state-schema.md`, and its two test cases. Removing it leaves the void reported by
its comment status alone — less countable, but not a broken gate, and every other AC stands
unchanged.

## Ratification provenance

The maintainer read this gap in the build session, approved it there, and the run posted the
ratifying comment under their identity. So `ratified_by:` cites a comment the RUN typed on the
maintainer's behalf, not one they typed — and the comment itself says so.

Written down because the boundary cannot infer it. `check-lean-chain.sh` delegates this arm to
`lean-evidence.sh:502-517`, which checks only that `ratified: yes` carries a `ratified_by:` URL;
unlike the claim arm it applies no author filter, so an operator-authored ratification and a
run-authored one are indistinguishable to it. A reader of this record should not have to take
the authorship at face value.
