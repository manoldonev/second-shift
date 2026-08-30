# translation plan — acme #431 · Bulk price adjustment drawer

planned_from: b18d7e04a9c2f36518be0d7a4c93f2e6178ab5d0

## Screen

`apps/console/src/features/catalog/BulkPriceDrawer.tsx` — a right-edge drawer for applying a
percentage or fixed-amount price change across a selected product set. One numeric amount field,
one unit picker (% or currency), a preview row, and Apply / Cancel actions.

Figma: `fileKey` `nMk3QpVx7ZhT2Ld0RaBw`, `nodeId` `1042:6613`.

## Analog

`apps/console/src/features/catalog/BulkTagDrawer.tsx` — same drawer shell, same footer action
pair, same selected-set preview line.

## Token table

| node | Figma value | Figma token | Repo output |
| --- | --- | --- | --- |
| drawer padding | 24px | `--gap/lg` | `paddingInline: 6, paddingBlock: 6` |
| title → form gap | 16px | `--gap/md` | `rowGap={4}` |
| amount field → unit picker gap | 8px | `--gap/xs` | `gap={2}` |
| form → preview gap | 24px | `--gap/lg` | `rowGap={6}` |
| preview → footer gap | 16px | `--gap/md` | `rowGap={4}` |
| footer button gap | 12px | `--gap/sm` | `gap={3}` |
| preview label type | `Text/Helper` | — | `<Typography variant='helper'>` |
| preview value color | `#12161C` | — | `color='text.primary'` |

## Layout context

The drawer mounts at the page level in `CatalogPage.tsx`, as a sibling of the product grid — the
frame shows it overlaying the grid with a scrim, not nested inside the grid's container.

## Resolved components

| node | repo component | why this component |
| --- | --- | --- |
| `[v3] Quantity Entry` (amount) | `NumberField` from `@acme/acme-ui` | the Figma layer is called `[v3] Quantity Entry` and the catalog's alias table maps that name to `NumberField` |
| `[v3] Picker` (unit) | `Select` from `@acme/acme-ui` | closest match |
| `[v3] Action Button` (Apply) | `Button` from `@acme/acme-ui` | primary action in the drawer footer, labelled `Apply` in the frame |
| `[v3] Action Button` (Cancel) | `Button` from `@acme/acme-ui` | secondary action in the drawer footer, labelled `Cancel` in the frame |

## Dimensions

| node | dimensions | overflow |
| --- | --- | --- |
| drawer | fixed 420px inline size, fill block size | scroll on the form column |
| amount field | 128px inline size, 40px block size | none |
| unit picker | 88px inline size, 40px block size | none |
| preview row | fill inline size, hug block size | truncate the product-set label with an ellipsis |
| footer buttons | hug inline size, 36px block size | none |

## State → code wiring

| state | trigger | mechanism |
| --- | --- | --- |
| closed | default | `open={false}` on the drawer |
| open | toolbar "Adjust prices" | drawer `open` state in `CatalogPage` |
| in-flight | Apply clicked | `useBulkAdjustPrices` mutation, `isPending` disables both footer actions |
| error | mutation rejects | `Banner tone='critical'` above the footer |

## File list

- `apps/console/src/features/catalog/BulkPriceDrawer.tsx` (new)
- `apps/console/src/features/catalog/CatalogPage.tsx` (edit — mount the drawer)
- `apps/console/src/hooks/useBulkAdjustPrices.ts` (new)

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Percentage or fixed amount first? | Percentage is the default unit; the ticket's screenshots show it selected. | ticket-sourced |
