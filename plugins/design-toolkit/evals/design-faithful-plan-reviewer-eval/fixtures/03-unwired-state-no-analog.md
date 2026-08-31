# translation plan — acme #672 · Return-label request modal

planned_from: 9d3b6f1408ac7e25b0f4d91e6a7c58302be4197f

## Screen

`apps/console/src/features/returns/ReturnLabelModal.tsx` — a modal for requesting a return label:
a reason select, an optional note field, a carrier radio group, and a Request / Cancel action pair.

Claude Design handoff: project `pj_5Tq7Bn`, screen `return-label-modal`.

### States the spec declares

| RS-n | state (what must be visible) |
| --- | --- |
| RS-1 | default — reason unselected, Request disabled |
| RS-2 | in-flight — Request shows a spinner, both actions disabled |
| RS-3 | success — the modal closes and a confirmation snackbar names the carrier |
| RS-4 | error — an inline critical banner above the footer, Request re-enabled |

## Placement

The modal mounts at the page level in `ReturnsPage.tsx`, portalled above the returns table.

## Resolved components

| node | repo component | why this component |
| --- | --- | --- |
| reason select | `Select` from `@acme/acme-ui` | the handoff draws a closed single-choice control over six fixed reasons with no search field |
| note field | `TextArea` from `@acme/acme-ui` | the handoff draws a three-line resizable multiline input with a character counter below it |
| carrier group | `RadioGroup` from `@acme/acme-ui` | the handoff draws three mutually exclusive labelled radios in a vertical stack |
| Request / Cancel | `Button` from `@acme/acme-ui` | primary and secondary footer actions, labelled `Request label` and `Cancel` in the handoff |

## Dimensions

| node | RS | px | dimensions | overflow |
| --- | --- | --- | --- | --- |
| modal | RS-1 | 480×- | fixed 480px inline size, hug block size | scroll the body above 560px |
| reason select | RS-1 | -×40 | fill inline size, 40px block size | truncate the selected label |
| note field | RS-1 | -×96 | fill inline size, 96px block size | scroll |
| carrier radios | RS-1 | -×32 | fill inline size, 32px block size each | none |
| footer buttons | RS-1 | -×36 | hug inline size, 36px block size | none |

## State → code wiring

| state | trigger | mechanism |
| --- | --- | --- |
| RS-1 | mount | `reason` unset in form state, Request `disabled` |
| RS-2 | Request clicked | `useRequestReturnLabel` mutation, `isPending` disables both actions and swaps the Request label for a spinner |
| RS-3 | mutation resolves | close the modal and enqueue a snackbar naming the carrier |

## File list

- `apps/console/src/features/returns/ReturnLabelModal.tsx` (new)
- `apps/console/src/features/returns/ReturnsPage.tsx` (edit — mount the modal)
- `apps/console/src/hooks/useRequestReturnLabel.ts` (new)
- `apps/console/src/features/returns/ReturnLabelModal.test.tsx` (new)

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Is the note field required? | No — optional, per the handoff's "optional" helper text. | ticket-sourced |
