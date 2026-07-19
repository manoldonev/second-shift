# Releasing

Every consumer upgrade is a deliberate PR (third-party marketplaces never auto-update), so
every release must make that PR easy to open and easy to trust.

Checklist (in order):

1. Every plugin whose content changed since the last tag carries a bumped `plugin.json`
   `version` — CI enforces (`scripts/check-plugin-version-bumps.sh`); the version string is
   the **update cache key**: an unbumped plugin updates NOBODY.
2. Update `CHANGELOG.md`: move the "(in progress)" section(s) under the release heading —
   the changelog tracks marketplace releases, one section per release, migration notes
   inline for consumers using changed features.
3. Set `.claude-plugin/marketplace.json` `metadata.version` to the release version
   (release-lockstep practice).
4. Run the trace gate (the pre-push hook runs it anyway) — it must print clean.
5. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
6. **GitHub Release on the tag** — the body MUST contain a "**What breaks / what to do**"
   section (write "Nothing breaks." explicitly when true), plus the consumer upgrade
   recipe: one PR bumping the settings `ref` AND `.claude/second-shift.lock.json` together,
   then `claude plugin marketplace update second-shift` + reinstall, then re-run the repo's
   validation gates. `/second-shift:onboard` resolves `releases/latest` — cutting the
   Release IS the publish step.
   - **Section-catalog changes are breaking-class.** Adding, renaming, or tombstoning a row
     in `plugins/review-toolkit/scripts/section-catalog.txt` changes what
     `check-review-context-sections.sh` accepts. Before tagging, check the new catalog against
     known-consumer `review-context.md` headings (propagation is pull-only, so a consumer only
     sees it on their next bump) and list any heading that would newly flag in the What-breaks
     body, with the rename command. A rename ships as a `deprecated-alias-of:` row (never a
     bare deletion) so the linter can print the exact fix instead of a bare failure.
7. Schema-breaking change? → major version + `configVersion` bump + `docs/migrations/vN-to-vN+1.md`
   BEFORE the tag (config-lint points at it) — the contract in `docs/migrations/README.md`.
8. Plugin renames: never silently. Use the official marketplace.json **`renames` map**
   (supported since Claude Code v2.1.193; append-only — `"old-name": "new-name"`, or `null`
   for a retirement) AND disclose the rename in the Release notes; consumer repos migrate
   in their own PR.
9. Update the pinned-ref examples in the docs (README quick start, `docs/onboarding.md`
   settings-pin example) to the new tag — a dead example tag is how onboarding docs rot
   (the `v1.1.0` lesson).

Rollback = consumers revert their upgrade PR. This works because catalog entries at the
reverted tag still resolve and the install cache is keyed by version string; doctor flags
version-AHEAD engineers symmetrically and prints the downgrade reinstall.
