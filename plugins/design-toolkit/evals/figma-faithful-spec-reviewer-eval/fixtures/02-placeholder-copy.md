# FE spec — Storefront returns request

## Summary

A shopper opens a return request against a delivered order: pick the order, pick a reason, add an
optional note and up to four photos, submit. Confirmation navigates to the returns list.

## Actors

Shopper (authenticated, storefront). No merchant-side surface in this spec.

## Dependencies

`POST /returns`, `GET /orders?status=delivered` — acme/api#3117, shipped.

## Routes

| Route | Screen |
| --- | --- |
| `/returns/new` | Return request form |
| `/returns` | Returns list (existing; destination on success) |

## Element Inventory

### `/returns/new` — idle

| Node | Component | Copy | Visual contract | States |
| --- | --- | --- | --- | --- |
| Page header | `Typography` | `CI-1` | `sectionTitle` variant, hug block size | all |
| Intro paragraph | `Typography` | `CI-2` | `body` variant, fill inline to 640px max | all |
| Order picker | `Select` | `CI-3` label | fill inline size, 40px block size, 1px `border.default` resting / `brand.main` focus, truncates long labels | all |
| Reason picker | `Select` | `CI-4` label | fill inline size, 40px block size, same border-by-state | all |
| Note field | `TextField` | `CI-5` label, `CI-6` helper | fill inline size, 96px block size, scrolls | all |
| Photo upload row | `Stack` + `IconButton` | `CI-7` | fill inline size, hug block size, wraps to a second row at four thumbnails | all |
| Submit action | `Button` | `CI-8` | 200px inline size, 44px block size, full-width below 480px | all |
| Error banner | `Banner` | `CI-9` | fill inline size, hug block size, `critical` tone | error only |

### `/returns/new` — in-flight

Identical to idle, with the Submit action disabled and its label unchanged. The error banner is
absent.

## Screens

### Return request form

Figma: `fileKey` `Rd7Yc1BqLm4Nt8Ex0PvW`, `nodeId` `77:1904` (idle), `77:1988` (error).

Single column, 24px page padding, 16px field-to-field gap, 40px gap above the footer.

## BE field map

| BE field | FE control | Notes |
| --- | --- | --- |
| `orderId` | Order picker | required |
| `reasonCode` | Reason picker | required, closed enum of five |
| `note` | Note field | optional, 500 char cap |
| `photoIds[]` | Photo upload row | optional, max 4 |

## Components

| Figma node | Repo component | Import |
| --- | --- | --- |
| `[v3] Picker` | `Select` | `@acme/acme-ui` |
| `[v3] Text Entry` | `TextField` | `@acme/acme-ui` |
| `[v3] Action Button` | `Button` | `@acme/acme-ui` |
| `[v3] Icon Action` | `IconButton` | `@acme/acme-ui` |
| `[v3] Notice` | `Banner` | `@acme/acme-ui` |

## Copy Index

| ID | String | Node |
| --- | --- | --- |
| CI-1 | Request a return | Page header |
| CI-2 | {Description} | Intro paragraph |
| CI-3 | Order | Order picker label |
| CI-4 | Reason | Reason picker label |
| CI-5 | {Label} | Note field label |
| CI-6 | Optional. Tell us what went wrong. | Note field helper |
| CI-7 | Add photos | Photo upload row |
| CI-8 | Submit request | Submit action |
| CI-9 | Option 1 | Error banner |

## Acceptance Criteria

- A shopper can submit a return against any delivered order in the last 90 days.
- Submitting with no order selected shows the order picker's required-field error and does not
  call the API.
- A rejected `POST /returns` renders the error banner and preserves every entered value.

## Open Questions

None.

## Out of scope

Merchant-side return approval; refund processing; the returns list itself.
