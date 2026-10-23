# Decision record — #5659 Uploading large files > 512 MB fails

## Summary

`isFormData` checks a value's kind before it ever calls `toString`, and calls `toString` only on
a plain object with an `append` method, which is how the `form-data` package's instances look.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | What counts as a FormData | An instance of the global `FormData`; or a value with an `append` method whose kind is `formdata`; or a plain object with an `append` method whose `toString()` is `[object FormData]`. | user-answered | intent |
| D-2 | Where the check lives | `lib/utils.js`'s `isFormData`, which every caller already uses. | user-answered | intent |

## Test intent

ACs: AC-1 AC-2

AC-1: isFormData on a Buffer whose toString throws returns false, with and without an append method
AC-2: isFormData on a class with a FormData toStringTag and an append method returns true
