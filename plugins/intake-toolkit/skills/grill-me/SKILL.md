---
name: grill-me
description: Interview the user relentlessly about a plan or design and record each resolution in the artifact's Decision Ledger, with its provenance. Use when the user wants a plan stress-tested, asks to be grilled on a design, or says "grill me".
---

Load `interviewing-baseline` first (Skill tool) — its loop rules govern this interview (explore-first, each decision as its own question, the decision-question shape, never re-ask).

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, and ask a decision only once the decisions it depends on are answered.

If a question can be answered by exploring the codebase, explore the codebase instead.

For each decision question, give your recommended answer when one is grounded. When none is, say so and name the missing fact (the baseline's rule 3).

Record each resolution into the `## Decision Ledger` of the artifact under discussion (provenance `user-answered`, per the baseline contract); if the artifact has no ledger section yet, add one. Routing between the intake-role skills lives in the `intake` router — this skill stays user-initiated.
