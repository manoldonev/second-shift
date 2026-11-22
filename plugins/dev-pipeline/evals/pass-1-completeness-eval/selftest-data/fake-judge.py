#!/usr/bin/env python3
"""A stand-in for the judge model, for eval-selftest.sh. It reads the findings out of the prompt and
answers by fixed words: a finding names criterion n as `C<n>`, says `not implemented` or `no test`."""
import json
import re
import sys

prompt = sys.argv[-1]
model = sys.argv[sys.argv.index("--model") + 1]
findings = re.findall(r"^(F\d+)\. (.*)$", prompt.split("<findings>")[1], re.M)


def kind(text):
    return "unimplemented" if "not implemented" in text else "untested" if "no test" in text else "other"


if "<criterion>" in prompt:
    want = re.search(r"\[(C\d+)\]", prompt.split("<criterion>")[1]).group(1)
    tests_only = "but no test proves it" in prompt
    hit = next((f for f, t in findings if want in t and kind(t) != "other" and (kind(t) == "untested" or not tests_only)), None)
    answer = {"pass": hit is not None, "finding": hit, "reason": "fixed words"}
else:
    answer = []
    for f, t in findings:
        m = re.search(r"\bC(\d+)\b", t)
        answer.append({"finding": f, "kind": kind(t), "criterion": int(m.group(1)) if m and kind(t) != "other" else None})
print(json.dumps({"type": "result", "subtype": "success", "result": json.dumps(answer), "total_cost_usd": 0.01,
                  "modelUsage": {"claude-" + model + "-0": {"inputTokens": 1}}}))
