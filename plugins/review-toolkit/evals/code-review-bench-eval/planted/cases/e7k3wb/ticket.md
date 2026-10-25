# [Bug] When `slot` is used with `v-if`, the slot content is not displayed as expected

### Vue version

^3.2.45

### Link to minimal reproduction

https://sfc.vuejs.org/#eNqFks9ugzAMxl/Fy6WdVMgd0W5TpZ33AFwoGJo2JFES6AHx7nOAUfb/BHbsn/N9Ts9ejIm7FlnCUldYYTw49K05ZEo0RlsPPVisYIDK6gY2VLpZjo5a+VwotPNhzJdMYFJhpgqtHDHP+gb7QNpWuXT4mKmUT/NoEgUeGyNzjxQBpKfWe63guZCiuO4zNrc/hG/GxhoAr+taIkTQ9xN/GMZmPnVPpPsVk1ATFWchS4uKoGta5tNSdNBFoprHLWMA3qzuRInlqBeVn/Ipp45pyF02xSlftLAdm5yKmtzEF6cV2dyP8+YDl7EExkzIkWchztjZe+MSzl1VBCMvLta25vQX21Z50WCMrolOVt8cWX0hym7F4JTs0EYks0SL9i/ml9Jv3IAlWweS8mm3q/cic1WTaUHL8nagxIpKyTnj0klfMPU4u/+UwElriTmtHobD9p/n4KQO+Z/W9EFcres1l/KUF9ff1zXz1psa3gFE5As4

### Steps to reproduce

1. open the reproduction link
2. click the toggle button
3. observe whether the slot content is toggled.

### What is expected?

1. The provided content should be displayed when `show` is `true`.
2. The fallback content should be displayed when `show` is `false`.

### What is actually happening?

The slot content is not toggled.

### System Info

_No response_

### Any additional comments?

_No response_

## Acceptance criteria

- AC-1: When the content a parent passes into a slot turns into only a `v-if` comment, the slot renders its fallback, and when the content returns, the slot renders the content again.
- AC-2: The switch between a slot's content and its fallback replaces the old nodes instead of patching one block's dynamic children against the other's, in production and in development builds alike.
