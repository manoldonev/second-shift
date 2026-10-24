# Spanish days and months should be lowercase

Spanish speaking people do not capitalize their months or days.

## Acceptance criteria

- AC-1: In the es locale, `dayjs('2018-4-28').locale('es').format('dddd D, MMMM')` is `sábado 28, abril`, with the month name in lowercase as Moment.js writes it.
