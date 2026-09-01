issue: 724
run_id: 20260831T223407Z-28860
session_id: 3b2aa7e3-bb3f-4539-b253-1535d6c42ce2
region: undeclared
disposition: took the reversible default AC-10's own text provides — every metric `unavailable` with the reason named — and flagged it here for ratification
ratified: yes
ratified_by: https://github.com/manoldonev/second-shift/issues/724#issuecomment-5498810911

## Gap

**May this ticket ship without the AC-10 bootstrap replay, given that the precondition the
replay needs is an unmet Dependency of the ticket itself?**

AC-10 requires "one fixture ticket run end to end in the consumer repo, its measured output
carried in the body of the PR". The issue also lists as a **Dependency**: "the consumer repo
must already be onboarded with the kit installed from a release pin, which is the state that
makes the measurement consumer-shaped rather than canary-shaped." That state does not hold —
the consumer's lockfile pins the marketplace at a moving branch ref rather than a release tag,
every plugin record reads `latest`, and its config is a schema generation behind. A replay run
there today would measure a canary-shaped configuration and enter it into the series under a
consumer-shaped name, as the baseline every later release is compared against.

The receipt does not cover this. D-9 asked whether the PR must prove the recipe runs and was
answered "yes, one fixture ticket end to end" — with no branch for the case where the
substrate for that run does not exist. Round 1's review named the discriminator exactly: the
unmet precondition sits under **Dependencies**, not **Deferred**, and an unmet dependency means
the ticket was not ready to build. It is not a licence for the build session to score the AC
away, and this session does not claim one.

Bootstrapping the consumer — changing another repository's lockfile, pins and config, then
filing and running a fixture ticket there — is a cross-repo, multi-hour action outside this
ticket's scope and outside an unattended session's authority. So the run cannot resolve the gap
by discharging it either.

## Disposition followed

This session is headless (`operator-override.sh state` → `headless (marked-headless)`), so it
cannot pause and ask, and no override gate in the closed enum covers an AC deferral. It
therefore took the reversible default AC-10's own text provides — each of the four metrics
recorded as `unavailable` with the named reason, in the PR body — and flagged it here rather
than presenting it as a decision made.

Reversible in both directions, and both are cheap:

- **Ratify as deferred.** The operator amends the issue with explicit deferral language and
  links a follow-up ticket carrying the consumer bootstrap plus the first fixture replay. The
  protocol document, which is the whole deliverable, is unaffected — it prescribes a recipe
  whose computability is demonstrated in the PR body against real recorded ledgers.
- **Ratify as owed here.** The consumer is onboarded from a release pin, one fixture ticket is
  run, and its four measured figures replace the `unavailable` block in the PR body. Nothing
  written this round has to be undone; the block is additive.

Ratification is an operator comment on #724. Until it lands, `lean-evidence.sh`'s
unratified-intent-gap arm holds this PR red, which is the intended state: the decision is
parked with the operator, not taken by the run.
