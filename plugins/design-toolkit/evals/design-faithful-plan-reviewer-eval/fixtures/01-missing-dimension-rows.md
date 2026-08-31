# translation plan — acme #518 · Payout schedule settings

planned_from: 4f1c7a92e3b8d5061ca47f2b930ee88d5417c6a0

## Screen

`apps/console/src/features/billing/PayoutSchedulePanel.tsx` — a settings panel for the payout
cadence: a cadence select, a day-of-month numeric field, a minimum-balance currency field, a
"hold payouts" toggle, and a Save / Discard action pair.

Claude Design handoff: project `pj_8Kd2Nq`, screen `payout-schedule`.

## Analog

`apps/console/src/features/billing/InvoiceSettingsPanel.tsx` — same settings-panel shell, same
footer action pair, same "unsaved changes" affordance.

## Placement

The panel mounts at the page level in `BillingSettingsPage.tsx`, as a sibling of the payment-method
panel — the handoff shows the two stacked in the settings column, not nested.

## Resolved components

| node | repo component | why this component |
| --- | --- | --- |
| cadence select | `Select` from `@acme/acme-ui` | the handoff draws a closed single-choice control with four fixed options and no search field, which is what `Select` renders |
| day-of-month field | `TextField type='number'` from `@acme/acme-ui` | the handoff draws a plain bordered numeric input with no steppers; `NumberField` renders increment/decrement steppers the frame does not contain and exposes no prop to suppress them |
| minimum-balance field | `CurrencyField` from `@acme/acme-ui` | the handoff shows the currency symbol inside the field's leading slot, which is `CurrencyField`'s built-in adornment |
| hold-payouts toggle | `Switch` from `@acme/acme-ui` | the handoff draws a track-and-knob control with an inline label, not a checkbox |
| Save / Discard | `Button` from `@acme/acme-ui` | primary and secondary footer actions, labelled `Save changes` and `Discard` in the handoff |

## State → code wiring

| state | trigger | mechanism |
| --- | --- | --- |
| pristine | mount | form state seeded from `usePayoutSchedule()`, both footer actions disabled |
| dirty | any field edit | `isDirty` from the form controller enables both footer actions |
| in-flight | Save clicked | `useUpdatePayoutSchedule` mutation, `isPending` disables both footer actions |
| error | mutation rejects | `Banner tone='critical'` above the footer, message from the error body |

## File list

- `apps/console/src/features/billing/PayoutSchedulePanel.tsx` (new)
- `apps/console/src/features/billing/BillingSettingsPage.tsx` (edit — mount the panel)
- `apps/console/src/hooks/usePayoutSchedule.ts` (new)
- `apps/console/src/hooks/useUpdatePayoutSchedule.ts` (new)
- `apps/console/src/features/billing/PayoutSchedulePanel.test.tsx` (new)

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does "hold payouts" disable the rest of the form? | No — the handoff shows the other fields still enabled while held. | user-answered |
