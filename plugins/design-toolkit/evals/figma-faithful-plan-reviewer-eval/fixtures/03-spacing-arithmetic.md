# translation plan — acme #447 · Storefront returns request form

planned_from: 4c0a29fe7b1d8635e2a0f94cd7b31e58a06f2d9c

## Screen

`apps/storefront/src/features/returns/ReturnRequestForm.tsx` — a shopper-facing form: an order
picker, a reason picker, a free-text note, a photo upload row, and a Submit action. Rendered
inside the storefront's branded, host-relative theme.

Figma: `fileKey` `Rd7Yc1BqLm4Nt8Ex0PvW`, `nodeId` `77:1904`.

## Analog

`apps/storefront/src/features/support/ContactForm.tsx` — same single-column form shell, same
footer submit, same branded surface.

## Token table

| node | Figma value | Figma token | Repo output |
| --- | --- | --- | --- |
| form column padding | 24px | `--gap/lg` | `paddingInline: 6, paddingBlock: 6` |
| field → field gap | 16px | `--gap/md` | `rowGap={2}` |
| label → control gap | 8px | `--gap/xs` | `gap={2}` |
| header block → form block gap | 16px | `--gap/md` | `rowGap={2}` |
| form block → upload block gap | 24px | `--gap/lg` | `rowGap={6}` |
| upload block → footer gap | 40px | `--gap/xl` | `rowGap={10}` |
| submit button min inline size | 200px | — | `minWidth: '200px'` |
| helper text color | branded | — | `color='text.secondary'` |
| section title type | `Text/Section title` | — | `<Typography variant='sectionTitle'>` |

## Layout context

The form mounts as the page's single content block inside `ReturnsPage.tsx`. The header block and
the form block are siblings in the same column; the upload block is a sibling of the form block,
not nested in it.

## Resolved components

| node | repo component | why this component |
| --- | --- | --- |
| `[v3] Picker` (order) | `Select` from `@acme/acme-ui` | the frame shows a closed control listing the shopper's recent orders with a chevron and no free-text entry |
| `[v3] Picker` (reason) | `Select` from `@acme/acme-ui` | a fixed list of five return reasons, drawn closed with a chevron |
| `[v3] Text Entry` (note) | `TextField` from `@acme/acme-ui` | a bare bordered multi-line input with no adornments in the frame |
| `[v3] Action Button` (Submit) | `Button` from `@acme/acme-ui` | the form's single primary action |

## Dimensions

| node | dimensions | overflow |
| --- | --- | --- |
| form column | fill inline size to a 640px max, hug block size | none |
| order picker | fill inline size, 40px block size | truncate long order labels |
| reason picker | fill inline size, 40px block size | none |
| note field | fill inline size, 96px block size | scroll |
| upload row | fill inline size, hug block size | wrap to a second row at four thumbnails |
| submit button | 200px inline size, 44px block size | none |

## State → code wiring

| state | trigger | mechanism |
| --- | --- | --- |
| idle | default | form state in `useReturnRequestForm` |
| in-flight | Submit clicked | `useSubmitReturnRequest` mutation, `isPending` disables Submit |
| error | mutation rejects | `Banner tone='critical'` above the footer |
| success | mutation resolves | navigate to the returns list with a confirmation banner |

## File list

- `apps/storefront/src/features/returns/ReturnRequestForm.tsx` (new)
- `apps/storefront/src/features/returns/ReturnsPage.tsx` (edit — mount the form)
- `apps/storefront/src/hooks/useSubmitReturnRequest.ts` (new)

## Decision Ledger

No material decisions — all choices codebase-derived.
