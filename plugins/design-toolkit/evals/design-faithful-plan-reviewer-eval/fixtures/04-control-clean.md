# translation plan — acme #715 · Webhook endpoint editor

planned_from: 2a86f0c395d1b7e4086cf5219da3b7640e19c8d5

## Screen

`apps/console/src/features/developers/WebhookEndpointEditor.tsx` — a form for creating or editing
a webhook endpoint: a URL field, an event-type multi-select, a signing-secret field with a reveal
toggle, an "active" switch, and a Save / Cancel action pair.

Claude Design handoff: project `pj_6Yh4Ls`, screen `webhook-endpoint-editor`.

### States the spec declares

| RS-n | state (what must be visible) |
| --- | --- |
| RS-1 | create — empty fields, Save disabled until the URL validates |
| RS-2 | edit — fields seeded, secret masked behind the reveal toggle |
| RS-3 | in-flight — both footer actions disabled |
| RS-4 | error — an inline critical banner above the footer |

## Analog

`apps/console/src/features/developers/ApiKeyEditor.tsx` — same single-column form shell, same
masked-secret treatment, same footer action pair and validation-gated primary.

## Placement

The editor mounts as the content of the developers settings route in `DeveloperSettingsPage.tsx`,
a sibling of the endpoint list — the handoff shows the list collapsing to a rail beside it, not
the editor nested inside a list row.

## Resolved components

| node | repo component | why this component |
| --- | --- | --- |
| URL field | `TextField` from `@acme/acme-ui` | the handoff draws a single-line bordered input with helper text below and no adornments |
| event-type picker | `MultiSelect` from `@acme/acme-ui` | the handoff draws selected events as removable chips inside the control with a searchable dropdown, which `Select` does not render and `MultiSelect` does |
| signing secret | `TextField type='password'` with `endAdornment` | the handoff draws a masked value with an eye toggle in the trailing slot; `TextField`'s `endAdornment` mounts the toggle without a new primitive |
| active switch | `Switch` from `@acme/acme-ui` | the handoff draws a track-and-knob control with a trailing label, not a checkbox |
| Save / Cancel | `Button` from `@acme/acme-ui` | primary and secondary footer actions, labelled `Save endpoint` and `Cancel` in the handoff |

## Dimensions

| node | dimensions | overflow |
| --- | --- | --- |
| form column | fixed 560px inline size, hug block size | none |
| URL field | fill inline size, 40px block size | none |
| event-type picker | fill inline size, hug block size (grows with chip rows) | wrap chips onto a second row, then scroll at 3 rows |
| signing secret | fill inline size, 40px block size | truncate the masked value |
| active switch | hug inline size, 24px block size | none |
| footer buttons | hug inline size, 36px block size | none |

## State → code wiring

| state | trigger | mechanism |
| --- | --- | --- |
| RS-1 | mount with no endpoint id | empty form state, Save `disabled` until the URL field's schema validation passes |
| RS-2 | mount with an endpoint id | form seeded from `useWebhookEndpoint(id)`, secret rendered masked with the reveal toggle unset |
| RS-3 | Save clicked | `useSaveWebhookEndpoint` mutation, `isPending` disables both footer actions |
| RS-4 | mutation rejects | `Banner tone='critical'` above the footer, message from the error body, Save re-enabled |

## File list

- `apps/console/src/features/developers/WebhookEndpointEditor.tsx` (new)
- `apps/console/src/features/developers/DeveloperSettingsPage.tsx` (edit — mount the editor)
- `apps/console/src/hooks/useWebhookEndpoint.ts` (new)
- `apps/console/src/hooks/useSaveWebhookEndpoint.ts` (new)
- `apps/console/src/features/developers/WebhookEndpointEditor.test.tsx` (new)
- `apps/console/src/routes/developerRoutes.tsx` (edit — register the editor route)

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Is the signing secret editable, or rotate-only? | Rotate-only — the field is read-only with a separate Rotate action, per the handoff. | user-answered |
| D-2 | Does an inactive endpoint still validate the URL? | Yes — validation is independent of the active switch, matching ApiKeyEditor. | codebase-derived |
| D-3 | Which event types are available at launch? | Deferred to the platform team's event catalog; the picker reads the catalog endpoint, so the list is data, not a code decision. | deferred |
