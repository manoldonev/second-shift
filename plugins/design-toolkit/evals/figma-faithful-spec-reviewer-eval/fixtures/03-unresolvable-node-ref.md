# FE spec — Console bulk price adjustment

## Summary

A catalog manager selects products in the grid, opens a drawer, and applies a percentage or
fixed-amount price change across the selection. A preview line states how many products will
change before Apply is enabled.

## Actors

Catalog manager (console, `catalog:write` scope).

## Dependencies

`POST /catalog/bulk-price-adjust` — acme/api#3402, shipped behind the `bulkPricing` flag.

## Routes

| Route | Screen |
| --- | --- |
| `/catalog` | Product grid (existing) + bulk price drawer (new) |

## Element Inventory

### `/catalog` — drawer open, idle

| Node | Component | Copy | Visual contract | States |
| --- | --- | --- | --- | --- |
| Drawer shell | `Dialog` (drawer variant) | — | fixed 420px inline size, fill block size, scrim at 40% | open, in-flight, error |
| Drawer title | `Typography` | `CI-1` | `sectionTitle` variant | all |
| Amount field | `NumberField` | `CI-2` label | 128px inline size, 40px block size, 1px `border.default` resting / `brand.main` focus, steppers intended | all |
| Unit picker | `Select` | `CI-3` label | 88px inline size, 40px block size, same border-by-state | all |
| Preview line | `Typography` | `CI-4` | fill inline size, hug block size, truncates the selection label | all |
| Error banner | `Banner` | `CI-5` | fill inline size, hug block size, `critical` tone | error only |
| Apply action | `Button` | `CI-6` | hug inline size, 36px block size, disabled until the preview resolves | all |
| Cancel action | `Button` | `CI-7` | hug inline size, 36px block size | all |

### `/catalog` — drawer open, in-flight

Identical, with both footer actions disabled and the Apply label unchanged.

## Screens

### Bulk price drawer

Figma: the **Catalog — DEV-READY** section of the console design file
(https://www.figma.com/design/nMk3QpVx7ZhT2Ld0RaBw/Acme-Console?node-id=0-1). The drawer frames
live under that section next to the bulk-tag drawer.

Single column, 24px drawer padding, 16px title-to-form gap, 24px form-to-preview gap.

## BE field map

| BE field | FE control | Notes |
| --- | --- | --- |
| `productIds[]` | Grid selection (existing) | required |
| `adjustmentType` | Unit picker | `percent` \| `fixed` |
| `adjustmentValue` | Amount field | required, two decimal places |

## Components

| Figma node | Repo component | Import |
| --- | --- | --- |
| `[v3] Quantity Entry` | `NumberField` | `@acme/acme-ui` |
| `[v3] Picker` | `Select` | `@acme/acme-ui` |
| `[v3] Action Button` | `Button` | `@acme/acme-ui` |
| `[v3] Notice` | `Banner` | `@acme/acme-ui` |
| `[v3] Modal` | `Dialog` | `@acme/acme-ui` |

## Copy Index

| ID | String | Node |
| --- | --- | --- |
| CI-1 | Adjust prices | Drawer title |
| CI-2 | Amount | Amount field label |
| CI-3 | Unit | Unit picker label |
| CI-4 | 24 products will change | Preview line |
| CI-5 | We couldn't apply that change. Nothing was updated. | Error banner |
| CI-6 | Apply | Apply action |
| CI-7 | Cancel | Cancel action |

## Acceptance Criteria

- Applying a percentage change updates every selected product and closes the drawer.
- A rejected request leaves every price unchanged and renders the error banner.
- The Apply action stays disabled while the preview count is resolving.

## Open Questions

None.

## Out of scope

Scheduled price changes; per-variant overrides; the product grid's selection model.
