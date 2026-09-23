# github tracker adapter

Active when config `tracker.type: github`. The queue-and-claim model: a labelled work
queue, atomic claim, and bot-authored status comments — the pipeline **writes back**
to the tracker (`tracker.writes: true`).

## Implementation

The github adapter is shell tools at the tools root (`../../`) plus the GitHub-shaped steps
of the scheduler, [`run.sh`](../../../skills/run/run.sh). It
has no scripts of its own in this directory — see [`../README.md`](../README.md) ("Why
the github tools live in `../`").

Since #348 the **implementation is the contract**: the prose that used to state the
label-swap ordering and the bot-identity rules lived in the deleted staged `SKILL.md`,
and the surviving statement of each is the script that enforces it. The rows below point
at the enforcing script rather than at a doc restating it.

| Concern | Where |
| --- | --- |
| Atomic claim (queue label swap, add-before-remove, confirm-add) | [`../../claim-issue.sh`](../../claim-issue.sh) — selftest `../../claim-selftest.sh` |
| Bot wrapper bootstrap (GitHub App key → installation token → `gh-as-bot.sh`) | [`../../install-gh-bot.sh`](../../install-gh-bot.sh) |
| Bot-identity contract (which writes use `$GH_BOT`; REST-canonical forms) | [`../../gh-bot.sh`](../../gh-bot.sh); config surface in [`docs/config-schema.md`](../../../../../docs/config-schema.md) (`tracker.bot.*`) |
| Queue-label confirm + do-not-pick-up guard | [`run.sh`](../../../skills/run/run.sh) preflight (`not-queued`) |
| PR creation + `Closes #<issue>` | [`run.sh`](../../../skills/run/run.sh) — the BUILD prompt, then the scheduler's PR conventions check |

## Config

```jsonc
"tracker": {
  "type": "github",
  "writes": true,
  "keyPattern": "[0-9]+",
  "branchPrefix": "claude/acme-",
  "bot": {
    "enabled": true,
    "envVar": "GH_BOT",
    "wrapperPath": "~/.config/acme/gh-as-bot.sh",   // optional: explicit path both writer + reader use
    "app": {
      "clientId": "Iv1EXAMPLECLIENTID000",
      "appName": "acme-dev-pipeline",
      "privateKeyFilename": "acme-dev-pipeline.private-key.pem"
    }
  }
}
```

`wrapperPath` and `app.*` are read by `install-gh-bot.sh` (writer) and `claim-issue.sh`
(reader) so onboarding a different repo’s bot app is a config edit, not a script edit.
When `wrapperPath` is omitted both fall back to `$HOME/.config/<repo-basename>/gh-as-bot.sh`.
