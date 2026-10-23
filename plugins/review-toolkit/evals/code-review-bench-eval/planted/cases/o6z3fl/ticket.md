# Duration format result is not as expected

**Describe the bug**
When use duration format for an ISO8601, result it's not as expected :
`myDuration = dayjs.duration('PT3M39.096S')`
`myDuration.format("HH:mm:ss") => "NaN:03:39.096"`
`myDuration.format("mm:ss")       => "03:39.096"`
`myDuration.format("ss")              => "39.096"`
`myDuration.format("SSS")             => "undefined"`

**Expected behavior**
`myDuration.format("HH:mm:ss") => "00:03:39"`
`myDuration.format("mm:ss")       => "03:39"`
`myDuration.format("ss")              => "39"`
`myDuration.format("SSS")             => "096"`

**Information**
 - Day.js Version [1.10.5]
 - OS: [Windows]
 - Browser [chrome 90]

## Acceptance criteria

- AC-1: A component that an ISO 8601 duration string leaves out counts as 0, so `dayjs.duration('PT1H').format('YYYY-MM-DDTHH:mm:ss')` returns `0000-00-00T01:00:00` and no component formats as `NaN`.

The fraction of a second in `ss` and `SSS` is left to a separate change.
