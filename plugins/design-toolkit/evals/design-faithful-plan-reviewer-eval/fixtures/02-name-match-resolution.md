# translation plan — acme #604 · Shipment exception queue filters

planned_from: c7a20b5e91d4386af0c25de71b83f4990ad6e213

## Screen

`apps/console/src/features/logistics/ExceptionFilters.tsx` — the filter rail of the shipment
exception queue: a carrier picker, a delay-threshold numeric field, a date-range control, and a
Clear-all link.

Claude Design handoff: project `pj_3Wm9Rz`, screen `exception-filters`.

### States the spec declares

| RS-n | state (what must be visible) |
| --- | --- |
| RS-1 | empty — every control at its default, Clear-all hidden |
| RS-2 | filtered — at least one control set, Clear-all visible |
| RS-3 | cleared — controls back at their defaults, query params stripped |

## Analog

`apps/console/src/features/logistics/ShipmentFilters.tsx` — same rail shell, same stacked filter
groups, same Clear-all treatment.

## Placement

The rail mounts in `ExceptionQueuePage.tsx` as the left column of the page's two-column grid, a
sibling of the results table — the handoff shows it outside the table's card, not inside it.

## Resolved components

| node | repo component | why this component |
| --- | --- | --- |
| `Carrier Picker` | `Select` from `@acme/acme-ui` | the handoff node is called `Carrier Picker` and the component catalog's alias table maps `Picker` to `Select` |
| `Delay Threshold` | `NumberField` from `@acme/acme-ui` | closest match |
| `Date Range` | `DateRangePicker` from `@acme/acme-ui` | the handoff draws two linked date inputs opening one shared two-month calendar, which is what `DateRangePicker` renders |
| `Clear all` | `Link` from `@acme/acme-ui` | rendered as inline text with no button chrome in the handoff, and it navigates no route — a `Link` styled as an action |

## Dimensions

| node | RS | px | dimensions | overflow |
| --- | --- | --- | --- | --- |
| rail | RS-1 | 264×- | fixed 264px inline size, fill block size | scroll |
| carrier picker | RS-1 | -×40 | fill inline size, 40px block size | truncate the selected label |
| delay threshold | RS-1 | 96×40 | 96px inline size, 40px block size | none |
| date range | RS-1 | -×40 | fill inline size, 40px block size | none |
| Clear all | RS-2 | -×20 | hug inline size, 20px block size | none |

## State → code wiring

| state | trigger | mechanism |
| --- | --- | --- |
| RS-1 | mount with no query params | all controls at their defaults, Clear-all hidden |
| RS-2 | any control changes | filter state lifted to `ExceptionQueuePage`, serialized into the URL query |
| RS-3 | Clear-all clicked | reset the filter state and strip the query params |

## File list

- `apps/console/src/features/logistics/ExceptionFilters.tsx` (new)
- `apps/console/src/features/logistics/ExceptionQueuePage.tsx` (edit — mount the rail)
- `apps/console/src/features/logistics/ExceptionFilters.test.tsx` (new)

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Do filters persist across navigation? | Yes — serialized into the URL query, as the existing shipment filters already do. | codebase-derived |
