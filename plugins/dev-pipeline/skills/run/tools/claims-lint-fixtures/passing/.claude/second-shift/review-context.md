# Review context (fixture)

## Maturity

```second-shift-claims
- id: no-auth-system
  claim: "No auth system exists yet; hardcoded userId placeholder"
  reverify-by: 9999-12-31
  verified-against: v9.9.9
  probe: pattern-absent:"AuthGuard|@CurrentUser|passport" in apps/api/src
- id: no-web-tests
  claim: "No component test infrastructure in the web app"
  reverify-by: 9999-12-31
```
