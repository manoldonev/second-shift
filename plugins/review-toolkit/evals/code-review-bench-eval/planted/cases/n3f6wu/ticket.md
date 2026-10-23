# `Duration.toISOString()` fractional seconds still have precision issues with certain values

Problem: originally submitted in #2366 - I didn't completely fix this apparently. I mistakenly assumed I could round the milliseconds value alone, and then add it to the integer of seconds. However Javascript will encounter floating-point rounding errors occasionally and the same precision issues are seen.

Expected behavior

Example:

Input: duration(2812)
Expected: PT2.812S
Actual: PT2.8120000000000003S
Information

Day.js Version [e.g. dev]
OS: All
Browser All
Time zone: N/A

## Acceptance criteria

- AC-1: The seconds of `toISOString` carry no floating-point error: a duration of -2812 ms gives `-PT2.812S`, of 3121632.27382247 ms gives `PT52M1.632S`, and of 7647826.525774224 ms gives `PT2H7M27.827S`.
