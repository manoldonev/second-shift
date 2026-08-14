#!/usr/bin/env bash
# fixture-stamp.sh — the ONE expression that stamps fixture ownership and reads it back (#528).
#
# WHY THIS FILE EXISTS. tools/reap-lean-fixtures.sh decides whether a `leangate.*` /
# `orchestrate-lean-selftest.*` directory belongs to a LIVE suite by comparing a stamp embedded
# in its name against the same stamp recomputed for the embedded pid. Producer and consumer are
# in different files — two selftests under plugins/, one tool under tools/ — so for a while they
# carried the expression TWICE, in two shapes:
#
#   producer:  raw="$(ps -o lstart= -p "$$" | tr -cs 'A-Za-z0-9' '_')"    # tr sees the newline
#   consumer:  raw="$(ps -o lstart= -p "$pid")"; printf '%s' "$raw" | tr  # $() ate the newline
#
# Those agree ONLY on a `ps` whose lstart column carries a trailing blank before the newline.
# macOS BSD `ps` does; a `ps` that renders lstart as a fixed-width ctime slice does not — and
# there the producer's token ends in `_` and the consumer's does not, ownership silently reads
# as "not mine", and the reaper DELETES A LIVE SUITE'S FIXTURE. That is the exact harm the
# ownership check exists to prevent, and it was worse than having no reaper at all.
#
# So: one function, sourced by both sides. There is no second copy to drift, and the
# sanitization is made insensitive to the difference in the first place — a run of non-alnum is
# squeezed to a single `_` (so a name can carry at most one leading and one trailing separator),
# and those are then stripped. Whether the raw string ends in "2026", "2026 ", or "2026 \n", the
# token is the same.
#
# The token is OPAQUE. It is never parsed, ordered, or reformatted back into a date: BSD and GNU
# render `lstart` differently and a dual-form parse is this repo's documented way of failing
# dirty under the other OS. It is only ever compared for equality against itself.
#
# SOURCED, never executed — `. "<repo>/tools/fixture-stamp.sh"`. Consumers under plugins/ must
# treat it as OPTIONAL: a shipped plugin install carries no tools/ directory, so a suite that
# cannot find this file falls back to an UNSTAMPED fixture name, which the reaper governs by its
# long legacy floor alone. That fallback is the safe direction — never a stamp the reader would
# read back as somebody else's.

# fixture_stamp_sanitize <raw> — the canonical opaque token for a raw `ps -o lstart=` string.
fixture_stamp_sanitize() {
  local s
  s="$(printf '%s' "$1" | tr -cs 'A-Za-z0-9' '_')"
  # `tr -s` squeezes runs, so there is at most ONE leading and ONE trailing separator to strip.
  s="${s#_}"
  s="${s%_}"
  printf '%s' "$s"
}

# fixture_stamp_for_pid <pid> — that pid's sanitized start-time token. FAILS (rc 1) when the
# start time cannot be read at all, which callers must treat as "cannot tell", never as "not
# mine".
fixture_stamp_for_pid() {
  local raw token
  raw="$(ps -o lstart= -p "$1" 2>/dev/null)"
  [ -n "$raw" ] || return 1
  token="$(fixture_stamp_sanitize "$raw")"
  [ -n "$token" ] || return 1
  printf '%s' "$token"
}

# fixture_stamp_own — "<pid>.<token>" for the CALLING shell, for splicing into a `mktemp -d -t`
# template. FAILS when ownership cannot be established, so the caller builds an unstamped name
# rather than a stamp nothing can match.
fixture_stamp_own() {
  local token
  token="$(fixture_stamp_for_pid "$$")" || return 1
  printf '%s.%s' "$$" "$token"
}
