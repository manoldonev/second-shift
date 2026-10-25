# All stats card and repo features are down. Error cannot fetch user is shown on all cards including your readme #bug

Every card shows "Could not fetch user": the one GitHub token the deployment uses has hit its rate limit.

## Acceptance criteria

- AC-1: When a token is rate limited, the request is retried with the next token, `PAT_1` through `PAT_8`. After the last one it fails with "Maximum retries exceeded".
- AC-2: When GitHub cannot fetch the user, the stats card shows the message GitHub returns.
- AC-3: The repo pin card fetches through the same token rotation as the stats card.
