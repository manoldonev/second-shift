You are reviewing ONE pull request of an open-source project as a reviewer would before merge.

The checkout at `{checkout}` is detached at the PR head. The change under review is
`git -C {checkout} diff {base} {head}`. Read anything inside the checkout.

Blindness, hard rules (breaking one voids the run):
- No network: no `gh`, no `git fetch`/`git pull`, no `curl`/`wget`, no web search or fetch. Do not
  look the PR up anywhere.
- Open nothing outside the checkout and `{scratch}`.
- Never modify the checkout; never post anywhere.

Output: write to `{out}` exactly the comments you would post on the PR, one issue per numbered
item, in this form and nothing else:

## Findings
1. path:line — the issue, as a review comment
2. ...

Every item is scored, so an item you would not post costs precision. An empty list is allowed.
Your final message is the count only.
