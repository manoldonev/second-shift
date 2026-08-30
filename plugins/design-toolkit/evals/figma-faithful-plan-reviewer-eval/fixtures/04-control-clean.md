# translation plan — acme #452 · Console notification preferences

planned_from: 90ab6c15d2e7f483b0c95a71de24f6083bc1e75a

## Screen

`apps/console/src/features/notifications/NotificationPreferencesPanel.tsx` — a settings panel
with one toggle per notification category, a digest-frequency picker, and a Save action in the
panel footer. Reached from Settings → Notifications.

Figma: `fileKey` `nMk3QpVx7ZhT2Ld0RaBw`, `nodeId` `1180:0442`.

## Analog

`apps/console/src/features/security/SessionPreferencesPanel.tsx` — same panel shell, same
toggle-list-plus-footer-action structure, same fixed-theme surface.

## Token table

| node | Figma value | Figma token | Repo output |
| --- | --- | --- | --- |
| panel padding | 24px | `--gap/lg` | `paddingInline: 6, paddingBlock: 6` |
| title → list gap | 16px | `--gap/md` | `rowGap={4}` |
| toggle row → toggle row | 12px | `--gap/sm` | `rowGap={3}` |
| toggle → label gap | 8px | `--gap/xs` | `gap={2}` |
| list → frequency picker gap | 24px | `--gap/lg` | `rowGap={6}` |
| frequency picker → footer gap | 16px | `--gap/md` | `rowGap={4}` |
| panel → sibling help card gap | 16px | `--gap/md` | `rowGap={4}` |
| category label type | `Text/Body strong` | — | `<Typography variant='bodyStrong'>` |
| category description type | `Text/Helper` | — | `<Typography variant='helper'>` |
| description color | `#5A6472` | — | `color='text.secondary'` |
| panel border | `#D6DBE3` | — | `borderColor='border.default'` |

## Layout context

The panel mounts as a **sibling** of the existing help card inside
`NotificationSettingsPage.tsx`, both in the same content column with a 16px gap — the frame tree
shows them at the same depth. The Save action sits in the panel footer, inline-end aligned.

## Resolved components

| node | repo component | why this component |
| --- | --- | --- |
| `[v3] Toggle` (per category) | `Switch` from `@acme/acme-ui` | the frame draws a two-state sliding track with no third indeterminate state, which is what `Switch` renders; `Checkbox` would draw a box and the wrong affordance |
| `[v3] Picker` (digest frequency) | `Select` from `@acme/acme-ui` | four fixed frequency options drawn as a closed control with a chevron, no free-text entry in the frame |
| `[v3] Action Button` (Save) | `Button` from `@acme/acme-ui` | the panel's single primary action, labelled `Save changes` in the frame |
| `[v3] Panel` (shell) | `Card` from `@acme/acme-ui` | a flat bordered surface — the frame draws a 1px border and no shadow, so `elevation={0}` overrides the resting elevation the catalog notes as a default that bites |

## Dimensions

| node | dimensions | overflow |
| --- | --- | --- |
| panel | fill inline size to a 720px max, hug block size | none |
| toggle row | fill inline size, hug block size | description wraps to two lines, then truncates |
| switch control | 36px inline size, 20px block size | none |
| frequency picker | 240px inline size, 40px block size | none |
| save button | hug inline size, 36px block size | none |

## State → code wiring

| state | trigger | mechanism |
| --- | --- | --- |
| idle | default | preferences from `useNotificationPreferences(workspaceId)` |
| dirty | any toggle or picker change | local form state; Save enabled only when dirty |
| in-flight | Save clicked | `useUpdateNotificationPreferences` mutation, `isPending` disables Save |
| error | mutation rejects | `Banner tone='critical'` above the footer |
| loading | first fetch | skeleton rows matching the category count |

## File list

- `apps/console/src/features/notifications/NotificationPreferencesPanel.tsx` (new)
- `apps/console/src/features/notifications/NotificationToggleRow.tsx` (new)
- `apps/console/src/features/notifications/NotificationSettingsPage.tsx` (edit — mount the sibling)
- `apps/console/src/hooks/useNotificationPreferences.ts` (new)
- `apps/console/src/hooks/useUpdateNotificationPreferences.ts` (new)

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Does Save apply per-category or for the whole panel? | Whole panel, one mutation — the frame draws a single footer action and no per-row save. | codebase-derived |
| D-2 | What happens to the digest picker when every category is off? | It stays enabled; the ticket does not scope a disabled state and inventing one would be an unwired affordance. | deferred |
