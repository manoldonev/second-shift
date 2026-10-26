# Providing a computed prop to child breaks the reactivity of the computed

### Vue version

3.4.0. up to 3.4.10

### Link to minimal reproduction

https://play.vuejs.org/#eNqNVMlu2zAQ/RVCF6VALDV1T4ZjpC1yaIEuaHILe1DMsc1UolRy5Lgw/O99pBbLchsUBmTOzJuVnLeP3lVVsq0pmkVzt7S64oU0uqhKy+I+exQrWxYiTlKcPSyWRhraBbOiVVbnLPbSCLEs4WPIsJs1CuHdL/3pEL4q4+ziVWezxLU1nSQEZ49wfPgRoHDp/CRXttxqRY2rZMlHVy95ea0dk0W6meCNdslAE0L43yZzn1GsrnKCGrkQ8HrR4Ee21gc14BMK8s3VTKpvbeRx7KvvLAT2XSU5mTVvxEJctb0NhlIQb0rVjGzUywWc+54lH+NVtdsEY1tmHw4Fz9P+DiEwFVWeMUESYq70VmwnenUto1H5MgoIYFyVGYBWpQUKOYRGJw1iv/enRCtxOCANgE3YFHHDCYBRXCADxL8jrZqIVzISJisIkldDXIT/uX9hTcQh/M0pHGKAv/kHfHoKhxjg0w4+TwcziS4jdsvSrPQ6eXKlwQqEW5SRv2+dk/1asS4Nuu8vXkZZnpfPn4KObU3tg4XPhpY//6J/cjuvk9E3S47slmTU2ziza+LGfHv3hXY498aiVHUO9AvG7+TKvPY1NrD3tVEoe4AL1X4M66zN+t7d7piM65ryhR4fo4yw4B9eaP1Y7jSZBj88OkyxoYtJkVWjOTaG0yDI0RS7Ya7cLE2XysBNUa63NjHEqamK9Aaw1NaGdUETVRY30+RtcvUaj83xUJ+QKyaPtnzGaBFl0LkPEOZtJ5aMIuvn8n95R24nuUe2s/yDsbSU6Zl18Ookzx0t/XCD4MW8ZJG2K3i+RSAXv0cAInnnePKQIfZrf87Nkv1GzESMYLHnNmi0eUIoEG48YJz4UsSj3LEn5JaFMbSOjnTDhC0z/a4Q/Y4tHlhPt5Z+1dp6xmyXoaOq9ot/X6mD50OsVZ9naQk9qSPbjwn9wisC9Z1TXnT4AwzTUvY=

### Steps to reproduce

Provide a computed prop via provide / inject to a child component and use it in its template. Use vue 3.4.x.

### What is expected?

The provided computed prop should have the same value when used in the child or in the parent and it should be reactive and updated. This used to work until 3.3.13 and does not work anymore beginning with 3.4.0 up to 3.4.10.

### What is actually happening?

The provided computed prop has a different value in child and parent. The value in the child is correct, the value in the parent is not correctly updated.

### System Info

_No response_

### Any additional comments?

_No response_

## Acceptance criteria

- AC-1: Reading a computed that reads another computed leaves both computeds not dirty, also when both effects have `allowRecurse` set.
- AC-2: A computed whose source ref is written while it evaluates, by a computed it reads, is left dirty, and its next read returns the value computed from the new source.
- AC-3: A parent component that renders a computed, and renders a child whose setup changes that computed's source, renders again with the new value, so the parent and the child show the same value after the next tick.
