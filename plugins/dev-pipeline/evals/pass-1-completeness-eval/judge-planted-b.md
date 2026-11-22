You are given one acceptance criterion of a ticket and the numbered findings of a code review. The code change under review implements this criterion, but no test proves it. PASS only if at least one finding says that this criterion has no test, or that its tests do not prove it. FAIL if the only finding about this criterion says it is not implemented, if no finding is about this criterion, if the criterion is mentioned only as background for another problem, or if there are no findings. Answer with JSON only: {"pass": true|false, "finding": "F<n> or null", "reason": "<one sentence>"}.

<criterion>
{criterion}
</criterion>

<findings>
{findings}
</findings>
