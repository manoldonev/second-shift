# FE spec — Console notification preferences

## Summary

A workspace admin sets which notification categories the workspace receives and how often digests
are sent. One toggle per category, one digest-frequency picker, one Save action.

## Actors

Workspace admin (console, `settings:write` scope).

## Dependencies

`GET /notification-preferences`, `PUT /notification-preferences` — acme/api#3488, shipped.

## Routes

| Route | Screen |
| --- | --- |
| `/settings/notifications` | Notification preferences |

## Element Inventory

### `/settings/notifications` — loaded

| Node | Component | Copy | Visual contract | States |
| --- | --- | --- | --- | --- |
| Page header | `Typography` | `CI-1` | `pageTitle` variant, hug block size | loaded, loading, error |
| Preferences panel | `Card` | — | fill inline size to 720px max, hug block size, flat: `elevation={0}` overriding the resting shadow, 1px `border.default` | loaded, loading, error |
| Panel title | `Typography` | `CI-2` | `sectionTitle` variant | loaded, loading, error |
| Category toggle row | `Stack` | — | fill inline size, hug block size, 12px row gap | loaded, error |
| Category switch | `Switch` | — | 36px inline size, 20px block size, `border.default` track off / `brand.main` track on | loaded, error |
| Category label | `Typography` | `CI-3`…`CI-6` | `bodyStrong` variant | loaded, error |
| Category description | `Typography` | `CI-7`…`CI-10` | `helper` variant, `text.secondary`, wraps to two lines then truncates | loaded, error |
| Digest frequency picker | `Select` | `CI-11` label, `CI-15`…`CI-18` options | 240px inline size, 40px block size, 1px `border.default` resting / `brand.main` focus, defaults to `Daily` | loaded, error |
| Save action | `Button` | `CI-12` | hug inline size, 36px block size, disabled until the form is dirty | loaded, error |
| Error banner | `Banner` | `CI-13` | fill inline size, hug block size, `critical` tone | error only |
| Loading skeleton | `Stack` | — | fill inline size, four rows at 44px block size each | loading only |
| Help card | `Card` | `CI-14` | fill inline size, hug block size, flat, sibling of the panel with a 16px gap | loaded, loading, error |

### `/settings/notifications` — loading

Page header and help card present and unchanged; the preferences panel renders the loading
skeleton in place of the toggle rows, the digest picker and the Save action.

### `/settings/notifications` — error

Identical to loaded, plus the error banner above the Save action. The help card is present in all
three states.

## Screens

### Notification preferences

Figma: `fileKey` `nMk3QpVx7ZhT2Ld0RaBw`, `nodeId` `1180:0442` (loaded), `1180:0517` (loading),
`1180:0589` (error).

Single content column, 24px panel padding, 16px title-to-list gap, 12px row-to-row gap, 24px
list-to-picker gap, 16px picker-to-footer gap, 16px panel-to-help-card gap.

## BE field map

| BE field | FE control | Notes |
| --- | --- | --- |
| `categories.billing` | Billing toggle | boolean |
| `categories.security` | Security toggle | boolean |
| `categories.product` | Product updates toggle | boolean |
| `categories.usage` | Usage alerts toggle | boolean |
| `digestFrequency` | Digest frequency picker | closed enum: `realtime` \| `daily` \| `weekly` \| `never` |

## Components

| Figma node | Repo component | Import |
| --- | --- | --- |
| `[v3] Toggle` | `Switch` | `@acme/acme-ui` |
| `[v3] Picker` | `Select` | `@acme/acme-ui` |
| `[v3] Action Button` | `Button` | `@acme/acme-ui` |
| `[v3] Panel` | `Card` | `@acme/acme-ui` |
| `[v3] Notice` | `Banner` | `@acme/acme-ui` |

## Copy Index

| ID | String | Node |
| --- | --- | --- |
| CI-1 | Notifications | Page header |
| CI-2 | What you get notified about | Panel title |
| CI-3 | Billing | Billing category label |
| CI-4 | Security | Security category label |
| CI-5 | Product updates | Product category label |
| CI-6 | Usage alerts | Usage category label |
| CI-7 | Invoices, payment failures and plan changes. | Billing description |
| CI-8 | New sign-ins, password changes and API key events. | Security description |
| CI-9 | Feature releases and changes to existing behaviour. | Product description |
| CI-10 | Warnings when a workspace approaches a plan limit. | Usage description |
| CI-11 | Digest frequency | Digest picker label |
| CI-12 | Save changes | Save action |
| CI-13 | We couldn't save your preferences. Nothing was changed. | Error banner |
| CI-14 | Notification emails are sent to every admin on the workspace. | Help card |
| CI-15 | As it happens | Digest picker option (`realtime`) |
| CI-16 | Daily | Digest picker option (`daily`) |
| CI-17 | Weekly | Digest picker option (`weekly`) |
| CI-18 | Never | Digest picker option (`never`) |

## Acceptance Criteria

- Toggling any category enables Save; saving persists every category and the digest frequency in
  one `PUT`.
- A rejected `PUT` renders the error banner and leaves every toggle in its edited position.
- The first load renders the skeleton, not an empty panel.
- Save stays disabled while the form is clean.

## Open Questions

None.

## Out of scope

Per-user notification preferences; the notification delivery channel itself; email templates.
