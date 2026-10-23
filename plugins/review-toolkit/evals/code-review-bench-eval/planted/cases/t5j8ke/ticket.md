# Parsing with Unix Timestamp tokens X/x and strict mode results in Invalid Date

**Describe the bug**

When `x` and `X` from [dayjs/plugin/advancedFormat](https://day.js.org/docs/en/plugin/advanced-format) is used with strict mode parse fails:
```js
dayjs(`/Date(${dayjs().format('x')})/`,"/[Date](x)/").format('/[Date](x)/')
> "/Date(1623787200000)/"
dayjs(`/Date(${dayjs().format('X')})/`,"/[Date](X)/").format('/[Date](X)/')
> "/Date(1623787200)/"

dayjs(`/Date(${dayjs().format('x')})/`,"/[Date](x)/",true).format('/[Date](x)/')
> "Invalid Date"
dayjs(`/Date(${dayjs().format('X')})/`,"/[Date](X)/",true).format('/[Date](X)/')
> "Invalid Date"
```
**Expected behavior**
last 2 examples should parse correctly as fist 2 cases do.

**Information**
tested on recent version of chrome (in dev tools of https://day.js.org/)

looks like related to:
https://github.com/iamkun/dayjs/pull/1467
https://github.com/iamkun/dayjs/issues/929
https://github.com/iamkun/dayjs/pull/1467

## Acceptance criteria

- AC-1: With customParseFormat, `dayjs('1410715640.579', 'X')` parses the input as seconds since the epoch, as Moment.js does.
- AC-2: `dayjs('1410715640579', 'x')` parses the input as milliseconds since the epoch, as Moment.js does.

A format that wraps X or x in other text, as in the examples above, is left to a separate change.
