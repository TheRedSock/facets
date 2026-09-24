# P2 closeout audit — 2026-09-21

Baseline source is `43ab9c9`; fresh `s0-baseline/run.json` records 18 passing,
completed, source-stable stages. Source/test reading establishes the anchors
below; a passing test establishes only its stated witness. The cumulative frozen
field inventory is `artifacts/game/p2-closeout/20260921-implementation/audit-fields.json`.
It accounts for every expected field in all 23 P0 cases without changing the P1
ledger or frozen bytes. The 113 historical smoke dispositions remain unchanged.

| Requirement | Source / test anchor | Finding and closure |
|---|---|---|
| Directed swaps, connected components, portal exclusions | ActionLegality.can_apply; MatchClassifier.survivor; test_game_rules | Confirmed by frozen fixtures and virtual-query equivalence; no correction |
| Spawn/topology/16×16 cap | BoardPhysics, StateAdmission; test_game_transaction topology cases, test_smoke | Confirmed; nine custom scenarios and explicit unsupported sizes remain bounded |
| Complete P1 identity, exact integers, immutable content | RunState.to_dict/restored, CanonicalCodec, GameCatalog; test_game_state | Independent codec vectors, leaf mutations, malformed admission and clone checks pass; no correction |
| P1 action identity and replay | ActionTransaction, ReplayRecord; action-v1, p1-checkpoints, test_game_replay | All 2,000 original checkpoint pairs pass; preserve unchanged |
| P2 cross-revision replay | RoomTransaction; test_game_room_replay | Missing historical per-action report repaired by pre-change characterization capture; semantic fixtures remain independent oracle |
| P2 complete identity/admission | RoomState.restored, RoomDefinition.admit; test_game_room | Existing coverage checks selected corruption. Add all P2 leaf identity plus malformed structural/counter cases before optimization |
| Atomic rollback | ActionTransaction, RoomTransaction, ResolutionBudget; test_game_transaction/test_game_room/test_game_tools/test_game_recovery | Rejection and injected failures after all meaningful cost/effect stages preserve state, RNG, allocators and replay; no correction |
| Rubble components/source footprint | ActionContext.match_step, ObstacleResolver; test_game_room | Dedup and direct multi-hit tests exist. Add one integrated two-component shared-target witness to ensure batch semantics |
| Final Work/victory/terminal restore | RoomBoundaryResolver; test_game_room frozen first/last-action fixtures | Confirmed; completion before exhaustion, stable boundary, single result and no terminal recovery |
| Tool tier/identity/allowance/suppression | RoomActionLegality, ToolResolver, CraftPolicy; test_game_tools | Existing boundary and descendant tests pass. Add T5 Refine rejection and same-tier instance exchange; retain exact rejection purity |
| Tool-only readiness | RoomBoundaryResolver.finish/validate | Implementation checks tools after swaps, but explicit no-swap/affordable-tool witness missing; add before optimization |
| Recovery stream, multiset, locked/high-tier retention | RecoveryResolver; test_game_recovery | Actual stream isolation, full piece multiset and 64 exhaustion pass. Add locked/high-tier mixture and controlled final-candidate success; distinguish controlled witness from real-RNG corpus |
| Motion/cancellation | MotionPlan, ActionPlayer; test_game_motion/test_game_playback/test_game_room_playback | Concurrent/serial/instant/skip equivalent; custom paths, rubble pockets and await cancellation covered. Release matrix still needs expansion |
| UI/audio | RoomHudModel, RoomPanel, RoomAudio; test_game_room_playback/check_presentation_content | Costs, target preview, keyboard, bounded voices, mute/cancellation pass under Dummy driver. Human dense listening deferred by user |
| Package ownership | build_game_package.ps1, GemForge; historical package report | Baseline 223 source / three release hashes previously checked; rebuild and actual-executable lifecycle still required |
| CPU measurement | ActionProbe/RoomProbe stats and complete apply_action | Debug fails 5 ms. ActionProbe already uses nearest rank; verify RoomProbe separately. Profile before modifying validation or encoding |

## P3 seams: source findings, not implemented features

- `TurnController.execute_turn` owns the full loop; `prepare_turn` precomputes.
  Trial needs a genuinely parked resolver and complete admitted pending state.
- `ActionContext.match_step` freezes component sources/targets before applying
  obstacle hits. This is the P3 family dispatch boundary; Corundum replaces base
  damage, and Craft needs distinct base/bonus/cap/gain accounting.
- `RoomDefinition`/`RoomBoundaryResolver` admit and resolve only marked rubble.
  Outlet/extraction belongs in the resolver, with a shared suppression budget.
- `RunController.start_room` creates a new session and `_publish_session` clears
  history. Expedition transition must be a separate run-owned operation.
- Board namespace/allocator starts locally. Carry requires run-wide allocation,
  explicit staging and preserved IDs through opening retries.
- Tile catalog identity lacks P3 metadata. Introduce a separate P3 content profile
  without silently changing old catalog/default replay identities.
- `SaveService` JSON writes are not admitted, exact, atomic Continue support.
  Stable selection/gameplay phases need an explicit P3 save envelope and tests.
- GemForge preflight currently owns the upcoming set. P3 must test old-board,
  carry and reward view overlap before changing loading ownership.

No framework rewrite or P3 gameplay is justified by these findings. Correctness
coverage additions are C1; performance/release are C2; trial and P3 contracts
remain independent work. Human evaluation is deferred under the user's amendment.
