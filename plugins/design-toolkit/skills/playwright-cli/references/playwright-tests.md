# Running Playwright Tests

When a repo ships its own E2E framework, prefer its package scripts — they set the expected config and base URLs. Before creating or modifying a spec, read the repo's E2E guide(s) if any exist.

## Running specs

Run tests through the repo's scripts. When an agent runs Playwright tests, always add `--retries=0` so each failure is reported once and the first error is not obscured by retries:

```bash
# Run the repo's check/build step before running a changed spec, then the targeted spec:
npx playwright test tests/<area>/<name>.spec.ts --retries=0

# Update intentional visual-regression diffs through the repo's screenshot script
```

Point the run at the repo's dev-server URL (the repo's scripts usually set this for you).

## Test shapes

Follow the repo's own layout and conventions. A typical suite separates concerns, e.g.:

- **Functional specs** under a per-area directory, importing from the repo's test fixture rather than directly from `@playwright/test`.
- **Visual specs** with their own config, using `toHaveScreenshot()` and the repo's deterministic setup (fixed clock/timezone, stable route params) rather than ad hoc screenshots.

Reuse the repo's page objects, services/helpers, and seeded-data constants; clean up any test data through the repo's helpers.

# Debugging Playwright Tests

To debug a failing Playwright test interactively, use `--debug=cli`. This command pauses the test at the start and prints debugging instructions.

**IMPORTANT**: run the command in the background and check the output until "Debugging Instructions" is printed. Make sure to stop the command after you have finished.

Once instructions containing a session name are printed, use `playwright-cli` to attach the session and explore the page.

```bash
npx playwright test tests/<area>/<name>.spec.ts --debug=cli --retries=0
# ...
# ... debugging instructions for "tw-abcdef" session ...
# ...

# Attach to the test
playwright-cli attach tw-abcdef
```

Keep the test running in the background while you explore and look for a fix.
The test is paused at the start, so you should step over or pause at a particular location
where the problem is most likely to be.

Every action you perform with `playwright-cli` generates corresponding Playwright TypeScript code.
This code appears in the output and can be copied directly into the test. Most of the time, a specific locator or an expectation should be updated, but it could also be a bug in the app. Use your judgement.

After fixing the test, stop the background test run. Rerun with `--retries=0` to check that test passes.
