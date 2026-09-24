# P3 implementation package

Status: specified and structurally verified, 2026-09-21. Activation awaits the
explicit CPU disposition in the closeout ledger; no P3 runtime feature or
successful human evaluation is claimed here.
User amendment: sole reviewer, one build/form; broader human evaluation deferred,
potentially until after P5. Atomic production is the default. Trial adoption is
declined for this milestone, so production saves and reactions use whole atomic
actions. The isolated trial remains available for later evaluation.

## Contract and fixture owners

The [tracked P3 preparation contract](../core/run/P3_PREPARATION.md) owns the concrete proposed behavior. [p3-preparation.json](../tests/game/p3-preparation.json) fixes all four room layouts, staging, reward eligibility, save field inventory and 14 named acceptance specifications. `test_p3_preparation` checks structural consistency, inherited P0 expectations, every first-reward pool and existing delivery bindings; it does not execute unimplemented P3 gameplay. The initial draft is archived with a verified checksum under `plans/archive/p3-preparation-draft-20260921/`.

## Implementation batches and exit witnesses

| Batch | Work | Required verification before checkpoint |
|---|---|---|
| P3.1 | Separate content profile, bounded family dispatcher and accounting | Frozen source-family promotion, Quartz once/cap/clipping, Corundum replacement/dedup, Beryl tie/no-target/revalidation/induced chain, T8 and suppression, shared-cap rollback |
| P3.2 | Aquamarine, Steady Hand, Bridge and previews | Old controls unchanged, full ladder/metadata, carry conversion IDs, effective costs, accepted-only use, exact range, no hidden supply changes |
| P3.3 | Expedition state, run-wide allocation, carry/staging and entry transaction | Zero/one/two carries, stale/duplicate IDs, failed load/opening rollback, retries preserve carry, monotonic IDs, complete history and streams |
| P3.4 | Typed extraction objectives and suppressed continuation | P0 outlet fields, threshold/blocked gates, ordered candidates/stop-at-demand, last Work, no double removal/carry/recovery award, one script witness per objective |
| P3.5 | Four rooms, rewards/routes and complete run flow | Every reachable reward pair and both routes; persisted offers, no RNG on reopen/rejection; complete success/failure replays |
| P3.6 | Incremental stable save schema/atomic file operation and Continue | Restore every stable phase, >2^53 integers, incompatible/corrupt/truncated save, interrupted writes and recovery, live-run preservation |
| P3.7 | Integrated keyboard/mouse UI, delivery preflight and tuning runner | Release lifecycle matrix, overlapping page ownership, family/tool/extraction explanations; deterministic named seeds/policy output; review material |

Build functional views alongside each batch; P3.7 integrates rather than defers
all presentation. Each checkpoint includes focused regressions and affected
legacy controls. Final integrated run uses immutable source/package manifests,
completion markers, full replay checkpoints, actual executable release probes
and both native display sizes. Do not reuse a P2 latency pass under expedition
load; repeat CPU/frame/memory measurements. Human learning, difficulty, feel and
reaction preference remain explicit deferred debt under the user's review policy.
