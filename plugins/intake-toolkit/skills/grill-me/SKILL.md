---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Load `interviewing-baseline` first (Skill tool) — its loop rules govern this interview (explore-first, ≤2 questions per turn, grounded recommendations only, never re-ask).

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree resolving dependencies between decisions one by one.

If a question can be answered by exploring the codebase, explore the codebase instead.

For each question, provide your recommended answer when one is grounded.

Record each resolution into the `## Decision Ledger` of the artifact under discussion (provenance `user-answered`, per the baseline contract); if the artifact has no ledger section yet, add one. Routing between the intake-role skills lives in the `intake` router — this skill stays user-initiated.
