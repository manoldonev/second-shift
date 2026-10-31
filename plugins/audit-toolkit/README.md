# audit-toolkit

Keeps a log of the tools the agent actually called in each session, so you can check what it did against what it says it did.

- Hooks record each tool call, each failed tool call, each subagent stop and each expanded slash command as a JSON line under the repo's `.claude/audit/`.
- `/audit-toolkit:audit` queries the current session's log.
- `/audit-toolkit:audit-history` summarizes the logs across recent sessions.

## What it runs and sends

The log stays on your machine, in the main checkout's `.claude/audit/`; add that folder to `.gitignore`. Nothing is sent anywhere. The log records commands as the agent ran them, so a secret typed into a command line ends up in it. Treat the folder like shell history.

## More

[The second-shift README](https://github.com/manoldonev/second-shift#get-started). License: MIT.
