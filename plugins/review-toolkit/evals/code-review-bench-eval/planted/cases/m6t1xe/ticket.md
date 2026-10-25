# Radio input element's checked value not synced with props checked.

### Vue version

3.4.27

### Link to minimal reproduction

https://play.vuejs.org/#eNqVVGFr2zAQ/SuHv8QB1yHZYBCSsq2UrRs0ZSvsQ2yGap8TdbZkZNlNCfnvO0mWm5AR2IcQ6b13p3enk/fBp7qOuxaDebBoMsVrDQ3qtoaSic0yCXSTBNeJ4FUtlYY9KCwieGE628IBCiUrGFH0KBGJyKRoNHSsbBGWRhiOKHmJo7HnZK05LXp2nQiAXhKB3dxsUanXfjeZwOiLYrVnzX6lyNYx8IBMHW1/MY2qwlIKspTSwYmwZkNrK4JQRCDHsLyGfR+y+g6soCDQvELZ6h6mJjw6IAytvnlh9cr5d0kouVXerx5NEnKOBjnTJeJgfRStyAx8ouimc2DiNYJuZhdj58u0S5YYl3ITjhrNqPUmynQSfBdj32nDhIYAWMdxfEKnkSNOwLjgIr8TOe5CrrEy1bn/5RK66fi/Q2bWlin0rM6QKWULW6cRcCpWtNUTKlpTvW7dl7wm5ZrPSGYX0zSl0hw49eAsTY1U0YAqYaD+yH66RLY100Fx1uTbNZ+0c8s325J+GrSkybFKI3J1+qYa2GZfTNyzoEdAG0LrkmaMdgCLnHfX/U3OYb8f5vtwWEwMN4horrM/mFuRO+FM8nWwRZ3GHTRb2ZY5POFx5ovXYPKOTxNzUbuJpvKuCqnoQVs9Fz5jEjhav9ZIrGI5lx6bZ862jxpO8QLBKhPEnrIhJGeaXVlRH+WZj+5yCPX35C7J8RPr13T7qMNBRJ8furuCb+LnRgr6RtnrTIJMVjUvUfXNTwJqkjuG3JSlfPlmMa3ozXvcFvMP/LnZGSwJHhQ2qDqqbuDo5W1QO/r25z3uaD2QlczbktQXyB9Ic9caj072uRU52T7SWbd39uvKxeaxud1pFI0vyhg1yoPVJwF9am8ulP5m91383sbRCFMXf3eoTE5qIBHx7ENw+AvKk/a9

### Steps to reproduce

- open reproduction link
- click second radio input

### What is expected?

- the second radio should not been checked

### What is actually happening?

- the second radio checked => not match the value & element's prop.checked

### System Info

_No response_

### Any additional comments?

This will cause the second radio can't trigger change event, since the real element checked is true but data value is not, which is not we want.

Issue below is trigger by this problem:
https://github.com/element-plus/element-plus/issues/16497

## Acceptance criteria

- AC-1: In a radio group whose `checked` props follow a ref and whose options swap on change, each radio's DOM `checked` matches its `checked` prop after the change.
- AC-2: A re-render writes each element's `checked` prop to the DOM even when the vnode's value did not change, the way `value` is forced today.
