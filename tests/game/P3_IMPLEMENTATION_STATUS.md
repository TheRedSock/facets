# P3 implementation and evidence

All seven P3 implementation batches and required engineering exits are complete
on the declared current-machine profile; see [the measured evidence](P3_FINAL_VERIFICATION.md).
Human learning, balance,
listening and reaction comfort remain deferred under the sole-reviewer policy.

## Checkpoints

| Batch | Commit | Focused evidence under `artifacts/game/p3/` |
|---|---|---|
| P3.1 family transactions | `5711ed2` | `b1-r3`, `b1-final` |
| P3.2 settings/previews | `efa731e` | `b2-final` |
| P3.3 expedition/carry/entry | `0bf5f15` | `b3-final` |
| P3.4 extraction | `ffefb4e` | `b4-final` |
| P3.5 authored flow/replays | `931784c` | `b5-flow-r2`, `b5-final` |
| P3.6 save/recovery | `4af1757` | `b6-r2` |
| User-confirmed opening extraction | `b40f31b` | `opening-confirmed-r1`, `opening-confirmed-r2` |
| P3.7 integrated views and release diagnostics | `437e46c` | `b7-ui-r2`, `native-ui-r5` |
| Terminal ownership, preview/input and tuning corrections | `64b689e` | `b7-audit-r1`, final r6 native/tuning evidence |
| Accelerated legacy test drain correction | `c7a1b47` | `final-cleanup-r6`, five corrected verbose diagnostics |

The old commission reference is preserved and explicitly incompatible; its
separately named corrected reference collects qualifying opening gems on Begin.
Deep-seam reference bytes remain unchanged. See the fixture directory README.

## Behavioral specification ownership

`test_p3_preparation` remains structural. Each named specification now has
executable assertions in the following registered owners:

The frozen preparation JSON's "not implemented" status describes its handoff
date; it is preserved as historical specification text. This status map and the
behavioral evidence below describe the current implementation.

| Specification | Behavioral owner |
|---|---|
| quartz_shared_cap, corundum_replaces_base | `test_p3_families` |
| beryl_lowest_yx, beryl_no_target, beryl_terminal_no_survivor | `test_p3_families` |
| tool_and_extraction_suppression | `test_p3_families`, `test_p3_extraction` |
| ordered_extraction_stops_at_demand, frozen_outlet_delivery | `test_p3_extraction` |
| carry_conversion, steady_hand_rejection | `test_p3_settings` |
| entry_craft, room_entry_atomic_rollback | `test_p3_entry` |
| unpublished_batch_cap_rollback | `test_p3_families`, `test_p3_extraction` |
| intervention_new_scope | `test_p3_families`, retained merge commands/seams |
| exact_save_rng, interrupted_save, parked_save, reserved_save | `test_p3_save` |

`test_p3_flow` exercises every reachable reward pair, both routes and actual
three-room successes. `test_p3_replay` re-executes complete frozen success and
real Work-exhaustion failure checkpoints. Save tests cover all eleven declared
phases and all six file interruption points; recovery never silently rerolls.

## Release evidence

`native-ui-720-r6` and `native-ui-900-r6` each pass 283 actual-executable
assertions, including complete routes/replays, every reward pair, 0/1/2 carry,
retained board/preview ownership, failure/retry, Continue and routed input.
Earlier failures are retained: r1 mouse-coordinate probe error, r2 asynchronous
preview capture/lifecycle errors, r3 strict WeakRef typing caught during import.
The 39-stage integrated matrix is closed with the separately verified legacy
test-drain correction; ten legacy actual-release stages pass. Normal CPU, all
four native timing profiles, final-package CPU smoke and 200 tuning runs pass.
The full doubled-computation corpus also passes: 1,500 rooms / 64,542 batches,
zero deadline failures and exact equality to every normal-corpus outcome.
The final verification report links the one tested build, optional review form,
source/package identity audits and retained raw evidence.
The historical whole-action 5ms failure and editor harness stalls are unchanged
claims; old readiness evidence is not evidence of implemented P3 load.
