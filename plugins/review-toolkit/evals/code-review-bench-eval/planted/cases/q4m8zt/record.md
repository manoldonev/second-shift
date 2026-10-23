# Decision record — #3494 req.hostname: check first comma-delimited host

## Summary

When `trust proxy` trusts the connection and `X-Forwarded-Host` holds several comma-separated
hosts, `req.hostname` reads the first one. The header with a single host is unchanged.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Which host wins | The first one, the host the client asked the first proxy for. | user-answered | intent |
| D-2 | When the header is read | Only when `trust proxy` trusts the connection, as before. Otherwise the `Host` header is used. | user-answered | intent |
| D-3 | The port | Stripped from the first host by the existing port logic. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4

AC-1: a request with two hosts in X-Forwarded-Host answers req.hostname with the first
AC-2: a request with 'example.com , foobar.com' answers req.hostname with 'example.com'
AC-3: a request with two hosts and ports answers req.hostname with the first host, no port
AC-4: exempt — docs only
