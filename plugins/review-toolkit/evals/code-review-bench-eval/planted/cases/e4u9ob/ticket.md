# dayjs add duration returns Invalid Date

**Describe the bug**
dayjs().add(dayjs.duration({ "hours" : 7, "minutes" : 10) })) 

returns "invalid Date" 
only "hours" and "minutes" are in the duration object

dayjs.duration(7, "hours").add(10, "minutes") is working 

**Information**
 - Day.js Version 1.11.9
 - Time zone: GMT+02:00 [MESZ]

## Acceptance criteria

- AC-1: `dayjs().add(dayjs.duration({ hours: 7, minutes: 10 }))` equals `dayjs().add(7, 'hours').add(10, 'minutes')`, not an Invalid Date.
