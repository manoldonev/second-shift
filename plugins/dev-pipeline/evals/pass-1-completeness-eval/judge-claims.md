You are given the numbered acceptance criteria of a ticket and the numbered findings of a code review. For each finding, decide whether its main claim is that a requirement of the ticket is not implemented (`unimplemented`), is implemented but has no test that proves it (`untested`), or is anything else (`other`: a bug, a broken caller, over-engineering, maintainability, convention). For `unimplemented` and `untested`, give the number of the criterion the claim is about, or `null` when the claim is about ticket text that is not one of the numbered criteria. Answer with JSON only: [{"finding": "F<n>", "kind": "...", "criterion": <number or null>}], one entry per finding. No findings gives [].

<criteria>
{criteria}
</criteria>

<findings>
{findings}
</findings>
