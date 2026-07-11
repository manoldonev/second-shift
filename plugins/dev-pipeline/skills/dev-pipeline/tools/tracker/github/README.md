# github tracker adapter

Active when config `tracker.type: github`. The acme lineage: a labelled work
queue, atomic claim, and bot-authored status comments — the pipeline **writes back**
to the tracker (`tracker.writes: true`).

## Implementation

The github adapter is shell tools at the tools root (`../../`) plus the GitHub prose
in [`SKILL.md`](../../../SKILL.md) (Bot Identity, Label-swap ordering) and the stage
files. It has no scripts of its own in this directory — see
[`../README.md`](../README.md) ("Why the github tools live in `../`").

| Concern | Where |
| --- | --- |
| Atomic claim (queue label swap, add-before-remove, confirm-add) | [`../../claim-issue.sh`](../../claim-issue.sh) — selftest `../../claim-selftest.sh` |
| Bot wrapper bootstrap (GitHub App key → installation token → `gh-as-bot.sh`) | [`../../install-gh-bot.sh`](../../install-gh-bot.sh) |
| Bot-identity contract (which writes use `$GH_BOT`; REST-canonical forms) | SKILL.md → **Bot Identity** |
| Queue pickup + do-not-pick-up guard | [`../../../stages/1-intake.md`](../../../stages/1-intake.md) → Step 1.A |
| PR creation + `Closes #<issue>` | [`../../../stages/9-open-pr.md`](../../../stages/9-open-pr.md) |

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
      "clientId": "Iv23linWw3EWmAuuAiZP",
      "appName": "acme-dev-pipeline",
      "privateKeyFilename": "acme-dev-pipeline.private-key.pem"
    }
  }
}
```

`wrapperPath` and `app.*` are read by `install-gh-bot.sh` (writer) and `claim-issue.sh`
(reader) so onboarding a different repo’s bot app is a config edit, not a script edit.
When `wrapperPath` is omitted both fall back to `$HOME/.config/<repo-basename>/gh-as-bot.sh`.
