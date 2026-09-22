# P3 implementation and evidence

P3.1–P3.6 are implemented. P3.7 integrated presentation, delivery ownership,
native lifecycle probes and deterministic tuning are under verification.
**P3 engineering completion is not yet claimed.** Human learning, balance,
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

The old commission reference is preserved and explicitly incompatible; its
separately named corrected reference collects qualifying opening gems on Begin.
Deep-seam reference bytes remain unchanged. See the fixture directory README.

## Behavioral specification ownership

`test_p3_preparation` remains structural. Each named specification now has
executable assertions in the following registered owners:

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

## Release evidence in progress

`native-ui-r4` passes actual executable keyboard/mouse routes at 1280×720,
complete replay, retained old-board owners, live previews, reward-load rejection
and retry, persisted-choice Continue, restart and menu cleanup. The expanded
matrix adds every reward pair, zero/one/two carry and parked-window Continue.
Earlier failures are retained: r1 mouse-coordinate probe error, r2 asynchronous
preview capture/lifecycle errors, r3 strict WeakRef typing caught during import.
`b7-ui-r2` passes source parsing, view previews and clean headless shutdown.

Final integrated controls, CPU and 2× workload, native timing at both sizes,
expanded lifecycle, tuning, source-stable package and review bundle remain open.
The historical whole-action 5ms failure and editor harness stalls are unchanged
claims; old readiness evidence is not evidence of implemented P3 load.
