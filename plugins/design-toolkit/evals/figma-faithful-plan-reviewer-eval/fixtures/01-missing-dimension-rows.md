# translation plan — acme #418 · Shipping rules editor

planned_from: 6f2c81a9d4e3b57a0c19e4d8f6b2a3c50d7e9184

## Screen

`apps/console/src/features/shipping/ShippingRulesPanel.tsx` — a settings panel with a rules
table, a per-rule weight-threshold control, a per-rule zone picker, and a "Add rule" action in the
panel header. Reached from Settings → Shipping.

Figma: `fileKey` `nMk3QpVx7ZhT2Ld0RaBw`, `nodeId` `914:2207`.

## Analog

`apps/console/src/features/tax/TaxRulesPanel.tsx` — same panel shell, same header-action
placement, same table-of-rules structure with an inline editable numeric column.

## Token table

| node | Figma value | Figma token | Repo output |
| --- | --- | --- | --- |
| panel padding | 24px | `--gap/lg` | `paddingInline: 6, paddingBlock: 6` |
| header → table gap | 16px | `--gap/md` | `rowGap={4}` |
| rule row inner gap | 12px | `--gap/sm` | `gap={3}` |
| rule row → rule row | 8px | `--gap/xs` | `rowGap={2}` |
| panel → sibling notice | 16px | `--gap/md` | `rowGap={4}` |
| rule label color | `#5A6472` | — | `color='text.secondary'` |
| threshold unit suffix color | `#8D96A5` | — | `color='text.disabled'` |
| rule title type | `Text/Card title` | — | `<Typography variant='cardTitle'>` |

## Layout context

The panel mounts as a **sibling** of the existing Shipping settings section inside
`ShippingSettingsPage.tsx`, not nested inside it — the frame tree shows both under the same
column with a 16px gap. The "Add rule" action sits in the panel header, inline-end aligned.

## Resolved components

| node | repo component | why this component |
| --- | --- | --- |
| `[v3] Quantity Entry` (weight threshold) | `NumberField` from `@acme/acme-ui` | the frame draws increment and decrement controls on the inline end of the input, which is exactly what `NumberField` renders; a plain `TextField` would drop them |
| `[v3] Picker` (zone) | `Select` from `@acme/acme-ui` | a closed list of six shipping zones, no free-text entry in the frame; `Select` renders the closed control with a chevron, matching the mock |
| `[v3] Action Button` (Add rule) | `Button` from `@acme/acme-ui` | a standard labelled action in the panel header |
| `[v3] Grid` (rules table) | `DataTable` from `@acme/acme-ui` | column headers, per-row actions and sorting are all drawn in the frame |

## Dimensions

| node | dimensions | overflow |
| --- | --- | --- |

## State → code wiring

| state | trigger | mechanism |
| --- | --- | --- |
| idle | default | rules from `useShippingRules(workspaceId)` |
| saving | Save clicked | `useUpdateShippingRule` mutation, `isPending` disables the row |
| error | mutation rejects | inline `Banner tone='critical'` above the table |
| empty | zero rules | `EmptyState` with the "Add rule" action repeated |

## File list

- `apps/console/src/features/shipping/ShippingRulesPanel.tsx` (new)
- `apps/console/src/features/shipping/ShippingRuleRow.tsx` (new)
- `apps/console/src/features/shipping/ShippingSettingsPage.tsx` (edit — mount the sibling)
- `apps/console/src/hooks/useShippingRules.ts` (new)
- `apps/console/src/hooks/useUpdateShippingRule.ts` (new)

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does the weight threshold accept decimals? | Yes — two decimal places, matching the BE field's precision. | ticket-sourced |
| D-2 | Where does the panel mount? | As a sibling of the Shipping settings section, per the frame tree. | codebase-derived |
