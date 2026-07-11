# Inspecting Element Attributes

When the snapshot doesn't show an element's `id`, `class`, `data-*` attributes, or other DOM properties, use `eval` to inspect them.

## Repo selector guidance

The E2E config sets `testIdAttribute: 'data-test'`, so Playwright `getByTestId()` resolves `data-test` in this repo. Some existing admin code also uses `data-testid`, `rnd-data-id`, or explicit `[data-test=...]` locators.

Preferred selector order for committed tests:

1. Existing page-object locators and methods.
2. `getByTestId()` for `data-test` attributes.
3. Role/name locators when they match stable user-visible UI.
4. Explicit `data-testid`, `data-test`, or `rnd-data-id` locators used by nearby page objects.
5. CSS only when no stable semantic/test attribute exists.

Use `playwright-cli eval` to discover attributes, then put the durable selector in the relevant page object or spec.

## Examples

```bash
playwright-cli snapshot
# snapshot shows a button as e7 but doesn't reveal its id or data attributes

# get the element's id
playwright-cli eval "el => el.id" e7

# get all CSS classes
playwright-cli eval "el => el.className" e7

# get a specific attribute
playwright-cli eval "el => el.getAttribute('data-testid')" e7
playwright-cli eval "el => el.getAttribute('aria-label')" e7

# get a computed style property
playwright-cli eval "el => getComputedStyle(el).display" e7
```
