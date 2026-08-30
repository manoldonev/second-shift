# Acme `acme-ui` catalog

Synthetic `design-tokens` extension for the `figma-faithful-reviewer` eval. Read by the
`design-toolkit` plugin skills/reviewers (`figma-faithful` component resolution,
`figma-faithful-spec` component identity).

**This file describes a fictional organization.** It exists so the eval can exercise the
reviewer's "load the repo's design-system reference" step against a two-surface reference, which
second-shift itself has none of (no FE app). Nothing here is derived from, or should be applied
to, a real product.

Maps Figma node names to the `acme-ui` component the design intends, so component identity is a
lookup, not a guess.

**How to use.** Match a Figma node name to the alias table first, then by leaf name. **Source
path** is the component file inside the `acme-ui` package. In this eval those files exist as
one-line export stubs under `fixtures/app/`, so an "is this component real?" grep has something
to resolve — that verification step is part of what the eval measures.

## Figma → component quick reference

| Figma node name        | Catalog leaf   | Source path                                                    |
| ---------------------- | -------------- | -------------------------------------------------------------- |
| `[v3] Action Button`   | `Button`       | `packages/acme-ui/src/components/Button.tsx`                    |
| `[v3] Icon Action`     | `IconButton`   | `packages/acme-ui/src/components/IconButton.tsx`                |
| `[v3] Text Entry`      | `TextField`    | `packages/acme-ui/src/components/TextField.tsx`                 |
| `[v3] Quantity Entry`  | `NumberField`  | `packages/acme-ui/src/components/NumberField.tsx`               |
| `[v3] Picker`          | `Select`       | `packages/acme-ui/src/components/Select.tsx`                    |
| `[v3] Search Picker`   | `Combobox`     | `packages/acme-ui/src/components/Combobox.tsx`                  |
| `[v3] Tickbox`         | `Checkbox`     | `packages/acme-ui/src/components/Checkbox.tsx`                  |
| `[v3] Toggle`          | `Switch`       | `packages/acme-ui/src/components/Switch.tsx`                    |
| `[v3] Panel`           | `Card`         | `packages/acme-ui/src/components/Card.tsx`                      |
| `[v3] Notice`          | `Banner`       | `packages/acme-ui/src/components/Banner.tsx`                    |
| `[v3] Chip`            | `Tag`          | `packages/acme-ui/src/components/Tag.tsx`                       |
| `[v3] Modal`           | `Dialog`       | `packages/acme-ui/src/components/Dialog.tsx`                    |
| `[v3] Overflow Menu`   | `Menu`         | `packages/acme-ui/src/components/Menu.tsx`                      |
| `[v3] Person Bubble`   | `Avatar`       | `packages/acme-ui/src/components/Avatar.tsx`                    |
| `[v3] Grid`            | `DataTable`    | `packages/acme-ui/src/components/DataTable.tsx`                 |
| `[v3] Nothing Here`    | `EmptyState`   | `packages/acme-ui/src/components/EmptyState.tsx`                |
| `Layout/Row`           | `Stack`        | `packages/acme-ui/src/components/Stack.tsx`                     |
| `Text/*`               | `Typography`   | `packages/acme-ui/src/components/Typography.tsx`                |

## Affordance notes (read before resolving on a name match)

A name match is not a resolution. These rows record what a component actually **draws**, because
that is the half a layer name cannot tell you.

| Component     | Renders                                                                 | Suppressible? |
| ------------- | ----------------------------------------------------------------------- | ------------- |
| `NumberField` | a text input **plus** increment/decrement stepper buttons on the inline end | No prop suppresses the steppers. |
| `Combobox`    | a text input, a chevron, and a clear (`×`) affordance once a value is set | `clearable={false}` removes the clear button; the chevron is fixed. |
| `Select`      | a closed control with a chevron; no free-text entry                      | Chevron is fixed. |
| `TextField`   | a bare bordered input; no adornments unless one is passed                | n/a |
| `Card`        | a surface with a resting elevation shadow **and** a 1px border           | `elevation={0}` drops the shadow; the border is set via `sx`. |

## Full catalog by category

### Actions

| Path         | Source                                              |
| ------------ | --------------------------------------------------- |
| `Button`     | `packages/acme-ui/src/components/Button.tsx`        |
| `IconButton` | `packages/acme-ui/src/components/IconButton.tsx`    |

### Inputs

| Path          | Source                                              |
| ------------- | --------------------------------------------------- |
| `Checkbox`    | `packages/acme-ui/src/components/Checkbox.tsx`      |
| `Combobox`    | `packages/acme-ui/src/components/Combobox.tsx`      |
| `NumberField` | `packages/acme-ui/src/components/NumberField.tsx`   |
| `Select`      | `packages/acme-ui/src/components/Select.tsx`        |
| `Switch`      | `packages/acme-ui/src/components/Switch.tsx`        |
| `TextField`   | `packages/acme-ui/src/components/TextField.tsx`     |

### Surfaces & feedback

| Path         | Source                                              |
| ------------ | --------------------------------------------------- |
| `Banner`     | `packages/acme-ui/src/components/Banner.tsx`        |
| `Card`       | `packages/acme-ui/src/components/Card.tsx`          |
| `Dialog`     | `packages/acme-ui/src/components/Dialog.tsx`        |
| `EmptyState` | `packages/acme-ui/src/components/EmptyState.tsx`    |
| `Menu`       | `packages/acme-ui/src/components/Menu.tsx`          |

### Data display & layout

| Path         | Source                                              |
| ------------ | --------------------------------------------------- |
| `Avatar`     | `packages/acme-ui/src/components/Avatar.tsx`        |
| `DataTable`  | `packages/acme-ui/src/components/DataTable.tsx`     |
| `Stack`      | `packages/acme-ui/src/components/Stack.tsx`         |
| `Tag`        | `packages/acme-ui/src/components/Tag.tsx`           |
| `Typography` | `packages/acme-ui/src/components/Typography.tsx`    |

## Surfaces

Two apps consume this catalog, and their token rules differ — see the sibling files:

- `acme-ui-design-tokens-console.md` — the **console** app: a fixed theme with a value table.
- `acme-ui-design-tokens-storefront.md` — the **storefront** app: a per-tenant branded,
  host-relative theme with no value table.
