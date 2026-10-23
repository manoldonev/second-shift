# code-review-bench eval, planted mode — run log

Append-only. Written by `planted.py run`. One row per arm per invocation, then one `gate=` row when
both arms ran. `net=`, `gate_net=` and `p1_net=` list one value per run: right − wrong − harm over
every class, the same without P2, and on P1 alone. Each class segment counts right, wrong and noise
over its planted cases; the `control` segment counts harm. `unscorable` counts runs whose verdict
broke its arm's contract, never as an approve. These rows never compare with the known-bug rows in
`../changelog.md`.

