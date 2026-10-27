# Decision record — #20681 Support Extracting Hostnames From Multiple Certificates

## Summary

`resolveServerUrls` reads the hostnames of every certificate in the https `cert` option, not only
of a single one, and adds them to the local URLs the dev and preview servers print.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Where the certificate names are read | A new exported `extractHostnamesFromCerts` in `utils.ts`, called by `resolveServerUrls`. | user-answered | intent |
| D-2 | A list of certificates | Every certificate of the list is read and the names are deduplicated with `unique`. | user-answered | intent |
| D-3 | A value that is not a certificate | It is skipped, so the server still starts and prints its own URLs. | user-answered | intent |
| D-4 | What the tests cover | `utils.spec.ts`: names from one and two certificates, and `resolveServerUrls` with no certificate, one, two, IPv6 and an invalid value. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2 AC-3

AC-1: extractHostnamesFromCerts on the test certificate, once or twice in a list, returns localhost, foo.localhost and vite.vite.localhost once each
AC-2: resolveServerUrls with the test certificate once or twice lists the three https URLs among the local URLs for an IPv4 and an IPv6 address
AC-3: resolveServerUrls with cert ['invalid-cert'] does not throw and lists https://localhost:3000/
