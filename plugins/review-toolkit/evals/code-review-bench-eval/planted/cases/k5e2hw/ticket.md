# Duration.toISOString() returns wrong result

**Describe the bug**
dayjs.duration(dayjs.duration(1, 'minutes').toISOString()).as('minutes') returns 43200
dayjs.duration(1, 'minutes').toISOString() return 'P1M'

**Expected behavior**
Should return 1
Suppose that dayjs.duration(1, 'minutes').toISOString() should return 'PT1M'

**Information**
 - Day.js Version [1.8.24]
 - OS: [macOS Mojave 10.14.6]
 - Browser [chrome 81.0.4044.122 (Official Build) (64-bit)]
 - Time zone: [GMT+3 (Moscow Standard Time)]

## Acceptance criteria

- AC-1: A duration with minutes and no hours carries the `T` designator: `dayjs.duration(1, 'minutes').toISOString()` returns `PT1M`.
- AC-2: The existing tests that expect the wrong output are corrected: 60 seconds gives `PT1M`, and `toJSON` of 5 minutes gives `PT5M`.
