You are given one acceptance criterion of a ticket and the numbered findings of a code review. The code change under review does not implement this criterion. PASS only if at least one finding says that this criterion is not implemented, is implemented only in part, or has no test that proves it. The finding may name the criterion by its id or describe it in other words. FAIL if no finding is about this criterion, if the criterion is mentioned only as background for another problem, or if there are no findings. Answer with JSON only: {"pass": true|false, "finding": "F<n> or null", "reason": "<one sentence>"}.

<criterion>
{criterion}
</criterion>

<findings>
{findings}
</findings>
