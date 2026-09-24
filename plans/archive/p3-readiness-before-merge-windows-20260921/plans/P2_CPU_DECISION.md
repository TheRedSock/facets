# P2 CPU gate — measured milestone decision

2026-09-21. Decision pending; the 5 ms complete-action p95 target still fails.
Human-testing deferral does not change this technical target. All other closeout
engineering deliverables are implemented; the single review build/form is
`generated/reviews/Facets-P2-Review-20260921.zip`.

## Evidence

Exact release r3, Godot 4.6.1, Windows, Intel i9-14900HX, RTX 4060 Laptop GPU.
The CPU corpora run the actual release executable headlessly and time the full
`RunController.apply_action`, including transactional resolution, admission,
projection, complete hashes and publication. Legal enumeration is measured
separately. Quantiles use nearest rank. Fixed policies/seeds match retained
state/event checkpoints; these are automated policies, not player sessions.

| Workload | Count | p50 ms | p95 ms | Maximum ms |
|---|---:|---:|---:|---:|
| P1, 100 seeds × 20 actions | 2,000 | 14.162 | 32.637 | 73.181 |
| P2, 100 seeded mixed-command rooms | 1,194 | 17.308 | 37.640 | 77.164 |
| Native frames, 1600×900 | 2,295 | 12.665 | 15.803 | 69.633 |
| Native frames, 1280×720 | 2,289 | 12.430 | 15.827 | 67.968 |

The frame p95 target of 16.7 ms passes; individual commit stalls remain visible.
No extra warmed-burst gem loads occurred. Gem payload 3,133,568 bytes, non-gem
RGBA estimate 280,576 bytes and decoded PCM 328,320 bytes meet their payload
budgets. Font/scene/decode/driver overhead and allocations are unmeasured.

`artifacts/game/p2-closeout/20260921-implementation/release-r3/` contains raw
frames, per-action CPU/work/facts/segments, tool-kind/startup/Begin/query
statistics, native screenshots and exact package hashes. The ordinary P2 corpus
contains no recovery actions; zero samples do not mean zero recovery cost.
Recovery correctness is separately exercised in the actual lifecycle probe.
Near-cap rollback is tested semantically; it has no release performance claim.

The bounded wire-string cache, native ID validation and empty-metadata shortcut
preserve full admission and exact canonical bytes. On the isolated repeated
P2 seed-7 stage probe, transaction median fell 26.713 → 25.194 ms; admission
7.518 → 6.323 ms and state digest 5.633 → 4.960 ms. These editor microbenchmarks
are not summed into a complete-action result or compared as release speedups.
They are too small a gain to close the gate. A target of 5 ms would require about
an 87% reduction from the measured P2 p95, so another trivial cache is not a
credible completion plan.

## Options for the user

1. **Proceed with P3, explicitly retain CPU debt (recommended for this prototype).**
   The P3 implementer owns this gate. Before freezing the P3 replay/save/content
   baseline, profile the growing expedition transaction and prototype a bounded
   canonical-encoding/admission optimization behind the unchanged external
   contract. Compare all retained bytes and malformed-admission cases; discard
   candidates that cannot justify their complexity. If a native implementation
   or data-layout change is needed, record its measured feasibility and estimate
   before broad integration. Repeat release CPU/frame/memory measurements at
   P3 integration. The 5 ms target must pass or receive another explicit scope
   decision before P5 acceptance; it is never silently marked passed.
2. **Keep P3 activation blocked and tackle performance first.** Reopen a dedicated
   performance implementation batch now with the same invariants and exact
   corpus checks. This can require a larger codec/admission/data-layout change;
   no measured evidence currently promises 5 ms without that investigation.

Either path must include a targeted recovery/high-work workload, actual release
measurements, maxima, source/package identity and unchanged legacy controls.
Removing replay hashing, weakening external admission, moving elapsed time out
of the measured transaction, or substituting frame p95 does not satisfy the gate.
