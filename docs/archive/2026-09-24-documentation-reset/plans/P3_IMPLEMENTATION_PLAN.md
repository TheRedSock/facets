# P3 implementation package

**G5 reconciliation, 2026-09-22:** the successor's incremental kernel, repeated
interventions, isolated default lookahead and streaming room are implemented.
Replay/restore and scoped diagnostic reaction seams are verified in G5.
[P3_READINESS_SUCCESSOR.md](P3_READINESS_SUCCESSOR.md) G6/G7 engineering exits
now pass on the [declared current-machine profile](../tests/game/MERGE_FINAL_READINESS.md).
All seven P3 batches below are implemented and their engineering exits pass on
the [declared profile](../tests/game/P3_FINAL_VERIFICATION.md). See
[the execution journal](P3_EXECUTION_JOURNAL.md) and
[checkpoint/evidence map](../tests/game/P3_IMPLEMENTATION_STATUS.md). The sole-reviewer policy
defers broader human evaluation, potentially until after P5.

## Contract and fixture owners

The [tracked P3 contract](../core/run/P3_PREPARATION.md) owns behavior. [p3-preparation.json](../tests/game/p3-preparation.json) fixes four room layouts, staging, reward eligibility, eleven save phases and eighteen named acceptance specifications. `test_p3_preparation` checks structural consistency, inherited P0 expectations, reward pools and delivery bindings; it does not itself execute P3 gameplay. The current evidence map links each named specification to implemented behavioral coverage. The superseded atomic contract/spec/test are checksum-archived under `plans/archive/p3-atomic-contract-before-g5-20260922/`.

## Implementation batches and exit witnesses

| Batch | Work | Required verification before checkpoint |
|---|---|---|
| P3.1 | Separate content profile, bounded family dispatcher and accounting | Frozen source-family promotion, Quartz once per paid move/cap/clipping, Corundum replacement/dedup, Beryl tie/no-target/revalidation/induced chain, intervention precedence, T8/suppression, unpublished-batch rollback with published prefix retained |
| P3.2 | Aquamarine, Steady Hand, Bridge and previews | Old controls unchanged, full ladder/metadata, carry conversion IDs, effective costs, accepted-only use, exact range, no hidden supply changes |
| P3.3 | Expedition state, run-wide allocation, carry/staging and entry transaction | Zero/one/two carries, stale/duplicate IDs, failed load/opening rollback, retries preserve carry, monotonic IDs, complete history and streams |
| P3.4 | Typed extraction objectives and suppressed continuation | P0 outlet fields, threshold/blocked gates, ordered candidates/stop-at-demand, last Work, no double removal/carry/recovery award, one script witness per objective |
| P3.5 | Four rooms, rewards/routes and complete run flow | Every reachable reward pair and both routes; persisted offers, no RNG on reopen/rejection; complete success/failure replays |
| P3.6 | Complete committed-boundary save schema/atomic file operation and Continue | Restore stable and parked phases, accepted reservations exactly once, assisted timed resume, >2^53 integers, incompatible/corrupt/truncated save, interrupted writes and recovery, live-run preservation |
| P3.7 | Integrated keyboard/mouse UI, delivery preflight and tuning runner | Release lifecycle matrix, overlapping page ownership, family/tool/extraction explanations; deterministic named seeds/policy output; review material |

Build functional views alongside each batch; P3.7 integrates rather than defers
all presentation. Each checkpoint includes focused regressions and affected
legacy controls. Final integrated run uses immutable source/package manifests,
completion markers, full replay checkpoints, actual executable release probes
and both native display sizes. Do not reuse a P2 latency pass under expedition
load; repeat CPU/frame/memory measurements. Human learning, difficulty, feel and
reaction preference remain explicit deferred debt under the user's review policy.
