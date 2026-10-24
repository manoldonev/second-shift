# UTC Plugin Milliseconds parsing

**Describe the bug**
When I use the UTC-Plugin and try to parse a string with milliseconds, it changes the time (I'm CET). If I append a "Z" to my string, this does not happen (see example)

**Expected behavior**
Parsing a string without milliseconds creates a correct representation of the date (with or without "Z" at the end). Adding milliseconds to the script should not change this behavior.

**Example**
```
dayjs.utc('2019-03-25T06:41:00');
/** { [Number: 1553496060000]
      '$L': 'en',
      '$u': true,
      '$d': 2019-03-25T06:41:00.000Z,
      '$y': 2019,
      '$M': 2,
      '$D': 25,
      '$W': 1,
      '$H': 6,
      '$m': 41,
      '$s': 0,
      '$ms': 0 }
*/

dayjs.utc('2019-03-25T06:41:00Z');
/** { [Number: 1553496060000]
      '$L': 'en',
      '$u': true,
      '$d': 2019-03-25T06:41:00.000Z,
      '$y': 2019,
      '$M': 2,
      '$D': 25,
      '$W': 1,
      '$H': 6,
      '$m': 41,
      '$s': 0,
      '$ms': 0 }
*/
// They are the same

dayjs.utc('2019-03-25T06:41:00.654321');
// This one is one hour of (the first example isn't)
/** { [Number: 1553492460654]
      '$L': 'en',
      '$u': true,
      '$d': 2019-03-25T05:41:00.654Z,
      '$y': 2019,
      '$M': 2,
      '$D': 25,
      '$W': 1,
      '$H': 5,
      '$m': 41,
      '$s': 0,
      '$ms': 654 }
*/

dayjs.utc('2019-03-25T06:41:00.654321Z')
// This one isn't one hour off (as I would expect it for the previous one too)
/** { [Number: 1553496060654]
      '$L': 'en',
      '$u': true,
      '$d': 2019-03-25T06:41:00.654Z,
      '$y': 2019,
      '$M': 2,
      '$D': 25,
      '$W': 1,
      '$H': 6,
      '$m': 41,
      '$s': 0,
      '$ms': 654 }
*/
```

**Information**
 - Day.js Version: v1.8.11
 - OS: Windows 10
 - Browser: Chrome, Jest

## Acceptance criteria

- AC-1: With the utc plugin, `dayjs.utc('2019-03-25T06:41:00.654321')` is `2019-03-25T06:41:00.654Z`, the same instant as `dayjs.utc('2019-03-25T06:41:00.654321Z')`.
- AC-2: `dayjs('2019-03-25T06:41:00.999999999')` has the same value and the same millisecond as Moment.js gives for that string.
