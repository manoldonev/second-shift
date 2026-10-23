# add month will change hour when use utcOffset

**Describe the bug**
z = dayjs().utcOffset(-480);
z.hour() !== z.add(0, 'month').hour() // true

**Expected behavior**
z.hour() !== z.add(0, 'month').hour() // false

**Information**
 - Day.js Version 1.8.29
 - OS: MacOS 10.14.5
 - Browser chrome 83
 - Time zone: GMT+08:00

## Acceptance criteria

- AC-1: In utcOffset mode, adding or subtracting months keeps the hour: for an instance at offset +10 or -8 with hour 6, `add(1, 'month')` and `add(-2, 'month')` keep hour 6.
- AC-2: In utcOffset mode, setting the hour and adding hours give the expected hour.
- AC-3: The existing immutable test sets an offset that differs from the machine's own offset, so it holds in every time zone.
