# acme #418 — shipping rules editor

**Issue:** acme/console#418

## Goal

Merchants can define per-zone shipping rules with a weight threshold, from Settings → Shipping.
Today the zone list is read-only and thresholds are configured by support.

## Design

Figma: `fileKey` `nMk3QpVx7ZhT2Ld0RaBw`, `nodeId` `914:2207` (Shipping rules — populated),
`914:2311` (Shipping rules — empty).

| RS-n | route | state | AC refs |
| --- | --- | --- | --- |
| RS-1 | `/settings/shipping` | populated | AC-1, AC-2 |
| RS-2 | `/settings/shipping` | empty | AC-4 |

## Translation plan

planned_from: 6f2c81a9d4e3b57a0c19e4d8f6b2a3c50d7e9184

### Token table

| node | Figma value | Figma token | Repo output |
| --- | --- | --- | --- |
| panel padding | 24px | `--gap/lg` | `paddingInline: 6, paddingBlock: 6` |
| header → table gap | 16px | `--gap/md` | `rowGap={4}` |
| rule row inner gap | 12px | `--gap/sm` | `gap={3}` |
| rule row → rule row | 8px | `--gap/xs` | `rowGap={2}` |
| rule label color | `#5A6472` | — | `color='text.secondary'` |
| rule title type | `Text/Card title` | — | `<Typography variant='cardTitle'>` |

### Resolved components

| node | repo component | why this component |
| --- | --- | --- |
| `[v3] Quantity Entry` (weight threshold) | `NumberField` | the frame draws increment and decrement controls on the inline end |
| `[v3] Picker` (zone) | `Select` | a closed list of six zones, no free-text entry |
| `[v3] Grid` (rules table) | `DataTable` | column headers and per-row actions are drawn in the frame |

## Acceptance Criteria

- **AC-1** — the Shipping settings page renders a rules panel listing every rule for the
  workspace, with zone, weight threshold and rate columns.
- **AC-2** — a rule's weight threshold is editable inline and persists through
  `PATCH /shipping-rules/:id`; the row shows an in-flight state while the mutation is pending.
- **AC-3** — a failed mutation surfaces an inline error above the table and leaves the edited
  value in the field.
- **AC-4** — a workspace with zero rules renders an empty state carrying the "Add rule" action.
- **AC-5** — the panel mounts as a sibling of the existing Shipping settings section, not nested
  inside it.

## BE dependencies

`GET /shipping-rules`, `PATCH /shipping-rules/:id`, `POST /shipping-rules` — all shipped in
acme/api#2205.

## Out of scope

Rate calculation itself; the zone editor; bulk import.
