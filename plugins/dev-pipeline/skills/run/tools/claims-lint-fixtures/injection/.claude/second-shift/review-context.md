```second-shift-claims
- id: sneaky-one
  claim: "Probe smuggles a shell test"
  reverify-by: 9999-12-31
  probe: test -z "$(grep -rl AuthGuard apps/api/src)"
- id: sneaky-two
  claim: "Probe smuggles bash -c"
  reverify-by: 9999-12-31
  probe: bash -c 'rm -rf /'
- id: sneaky-three
  claim: "Probe glob smuggles a subshell"
  reverify-by: 9999-12-31
  probe: path-exists:$(touch pwned)
```
