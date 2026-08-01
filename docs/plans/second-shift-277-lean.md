# second-shift#277 — comment-add must validate the receipt shape, not just the URL scheme

## Problem

`statectl.sh comment-add` only checks `--url` matches `^https?://`. A completion-gating
receipt can therefore point at any http(s) URL — a PR URL, a PR review URL, a comment on
the wrong issue — and every downstream completion gate (`require_comment_receipts`)
accepts it as proof the mandated stage comment exists. Observed on the #263 run: the PR
URL was recorded instead of the mandated `stage: pr` issue comment, and the run closed
green with an incomplete marker trail.

## Fix

In `cmd_comment_add` (`plugins/dev-pipeline/skills/run/statectl.sh`), after the existing
`^https?://` check and after `current` (the state document) is read, additionally require
`--url` to match the state file's own `.ticketKey` as an issue-comment permalink:

```
.../issues/<ticketKey>#issuecomment-<digits>
```

Anchored on `ticketKey` (not just the `#issuecomment-` fragment) so a PR **conversation**
comment (`/pull/<n>#issuecomment-<id>`, which shares the fragment shape) and a comment on
a **different** issue are both refused by the same predicate. Host-agnostic: match the
`/issues/<key>#issuecomment-<digits>` path tail, not `github.com`, so a GHES consumer is
unaffected.

Routed through the existing `guard_fire`/`guards_settle` mechanism (the same one the
`code-review` ordering precondition already uses in this function) so `--force` remains
the crash-recovery escape and a forced call records a `waivers[]` entry instead of
silently accepting a malformed receipt.

No `tracker.writes` guard: a read-only tracker posts no comments by contract, so this call
site is unreachable there (mirrors the existing note in the function for the ordering
check).

## Acceptance Criteria

- AC-1: `comment-add` rejects (exit 1) a `--url` that is not an issue-comment permalink
  for the state file's own `ticketKey` — covering: a pull-request URL, a PR review URL
  (`#pullrequestreview-`), a PR conversation comment (`/pull/<n>#issuecomment-<id>`), an
  issue-comment URL for a different issue number, and a bare issue URL with no
  `#issuecomment-` fragment.
- AC-2: `comment-add` still accepts a well-formed
  `.../issues/<ticketKey>#issuecomment-<digits>` URL, including on a GitHub Enterprise
  host (no hardcoded `github.com`), and the existing `code-review` ordering precondition
  (review-lead must be loaded first) is unchanged.
- AC-3: `--force` permits a malformed receipt for crash-recovery and records it as a
  `waivers[]` entry via `guard_fire`/`apply_waivers`, rather than accepting it silently.
- AC-4: `statectl-selftest.sh` covers AC-1/AC-2/AC-3 with behavioral cases, and every
  existing fixture that calls `comment-add` (`statectl-selftest.sh`, `scenario-lib.sh`,
  `scenario-liveness-selftest.sh`, `stage8-perrepo-review-selftest.sh`,
  `e2e-replay-selftest.sh`'s minted `gh` shim) is updated to post a receipt shaped as a
  real issue-comment permalink for the ticket it's writing to, so the full selftest sweep
  stays green under the new gate.

## Out of scope

- Verifying the comment actually exists on the tracker (network read).
- Any change to `require_comment_receipts` or the marker enum.
- #272's ledger corroboration.
