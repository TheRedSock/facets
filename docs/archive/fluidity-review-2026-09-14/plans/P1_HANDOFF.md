# P1 implementation handoff — 2026-09-14

P1's functional batches and declared completion checks are complete. The animated
board now uses admitted configuration, pure legality and one complete atomic
transaction, with canonical state/facts, snapshot restore and replay. The proposed
5 ms p95 simulation target was assessed and **was not met**. This is a correctness
checkpoint for the P1 subset of facets.prototype.v1, not a complete room or
expedition prototype.

## Batches and exits

| Batch | Delivered boundary | Exit evidence |
|---|---|---|
| 0 — Baseline adapters and checks | Shared game assertions, exact frozen-field and historical-smoke ledgers, adjacent ownership contracts, additive registered game stages | 23 cases inventoried; unknown phase/field rejection; 113 historical assertions accounted for; frozen bytes unchanged |
| 1 — Catalog, policies and identity | Read-only admitted GameCatalog/RuleSet; explicit production resource/bootstrap; roster progression; stable instances; four RNG streams with full restore | Invalid supply fails before draws; independent seed derivation vectors; alternate Aquamarine progression; immutable nested records and clone isolation |
| 2 — Legality and matching | One local pure swap query/enumerator; virtual occupancy optimization; connected intersecting components; deterministic survivors | Frozen phase observations, directed enumeration, locks/no-ops/distant/empty rejection; 1,344 virtual-query comparisons with independent clone/full-scan reference |
| 3 — Topology, settling and openings | Raw layout admission, graph diagnostics, named in-place scheduler, explicit failure ceilings, entry-only refill, bounded playable opening generation | Nine foundation scenarios, override admission, explicit physical-cycle/cap outcomes, no-match lane refill, 64-attempt impossible opening, 16×16 bounded envelope |
| 4 — Codec and restoration | FAC1 exact-integer codec, SHA-256 identity, complete admitted snapshots, versioned self-contained replay | Independent byte vectors; reviewed action vector; malformed UTF-8/count/version rejection; every serialized leaf affects identity; exact restore and alias isolation |
| 5 — Atomic action and application | Detached action/RNG/counters, one fixed cost, immutable lifecycle facts, fact-derived EventTimeline, cancelable ActionPlayer, composable input gates | Failure injection after swap/promotion/spawn/before commit and all cap types preserves complete state/recording; source-family/T8/assist/removal/path checks; real scene sequential/instant/skip/restart/error/destruction checks |
| 6 — Replay and package | 100 fixed seeds with all checkpoints and midpoint resume; clean Windows package; actual executable interactions; owning guides updated | All 11 integrated stages pass; 2,000 accepted commands; fresh replay and resume match all state/event checkpoints; package audit/probe and release interaction observations below |

## Evidence and exact commands

[Integrated stage report](../artifacts/game/p1-implementation/integrated-checks.json)
records all eleven required completion markers and successful classifications:
import, source_check, test_board_consumer, test_run_delivery, test_smoke,
test_rng_cross_platform, test_game_rules, test_game_state, test_game_transaction,
test_game_replay and test_game_playback.

```powershell
& ./tools/check_engine.ps1 -Only import,source_check,test_smoke,test_rng_cross_platform,test_board_consumer,test_run_delivery,test_game_rules,test_game_state,test_game_transaction,test_game_replay,test_game_playback
& ./tests/test_check_result.ps1
& ./tools/build_game_package.ps1 -AssetPack generated/gem-assets.pck -Probe -FrameBudgetMs 16.7
```

Smoke passed 114 assertions with zero failures. The stage classifier passed its
10 cases. Game state passed 1,396 assertions; transaction passed 137; replay passed
1,301; playback passed 12. The corpus completed in about 329 seconds. Two earlier
intermediate replay runs were deliberately stopped for query optimization and
completion of event/playback work; they are incomplete attempts, not passes.

[Replay corpus](../artifacts/game/p1-implementation/replay-corpus.json): seeds 0–99,
20 accepted commands each, 2,000 commands total. All 100 runs reached budget
exhaustion; none failed or were discarded. Every accepted command retains ordered
state and event digests. Fresh self-contained replay and midpoint snapshot resume
matched every checkpoint. These results establish same-build determinism on
Windows/Godot 4.6.1; they do not claim another OS or engine version was tested.

[16×16 stress](../artifacts/game/p1-implementation/stress.json): admitted board,
16 original occupants, 240 exact movement segments, convergence in 16 scan rounds.
Oversize layouts reject before allocation. This is a correctness envelope, not a
16×16 production UI or latency guarantee.

[Frozen integrity](../artifacts/game/p1-implementation/frozen-integrity.json): all
19 frozen files match their P0 SHA-256 entries and current fixture bytes match
the frozen cases. The historical P0 verifier/report was not rewritten.

## Package and actual release observations

Build directory:
[generated/desktop/20260914-142519-4424](../generated/desktop/20260914-142519-4424/).
Run [Facets.exe](../generated/desktop/20260914-142519-4424/Facets.exe) beside
Facets.pck and gem-assets.pck. It uses the existing delivered art pack unchanged.

[Build report](../artifacts/package-build/20260914-142519-4424/report.json),
[exact package inventory](../artifacts/package-build/20260914-142519-4424/inventory.json)
and [runtime probe](../artifacts/package-build/20260914-142519-4424/runtime-probe.json)
passed. Export used a fresh runtime-only staging project and explicit path list;
no developer source tree or factory dependencies were available to the probe.
All 64 views loaded delivered textures, and the prefetched animation burst caused
no extra page loads. Probe p95 was 9.466 ms during the animation burst and 9.843 ms
at steady rest, both below 16.7 ms. This probe uses the editor binary with the
exact exported PCK. These are not release-executable ETW measurements.

The actual shipped Facets.exe was separately operated using Windows computer use
(mouse drags/clicks, not simulation injection). Initial seed 366232:

- Opened Menu → Play and observed a complete 8×8 board and 20 moves.
- Distant drag and adjacent same-group exchange left the board/count unchanged.
- Played 20 accepted actions down to zero, including a four-gem match that cost
  exactly one. Budget changed before animation completed.
- Used Skip through short and longer cascades; the count stayed at the committed
  value. The sequential animation path also completed naturally between actions.
- At zero, the HUD reported no moves remaining; a further swap did not go negative.
- Restart restored the initial seed, board and 20 moves.
- Started a lower-board cascade and used Menu during playback; returned to the
  menu without stale presentation work.
- Closed the process, temporarily withheld gem-assets.pck and relaunched. Play
  showed the missing-pack error and hid the board. Skip could not reveal it.
- Restored the pack byte-for-byte. In-app Restart did not retry the failed library
  startup; closing and relaunching restored normal play (seed 524580). The release
  test process was closed after verification. No held/renamed package file remains.

Screenshots: [exhaustion](../artifacts/game/p1-implementation/release-exhausted.png),
[delivery error](../artifacts/game/p1-implementation/release-delivery-error.png),
[restored launch](../artifacts/game/p1-implementation/release-restored.png).
Initial computer-use app access timed out once; its retry succeeded. This was not
a failed game test.

## Performance assessment and limitations

The ordinary 8×8 headless corpus measured **131.716 ms p95**, **313.257 ms maximum**
for complete apply_action calls, including invariant admission, canonical identity,
fact projection and publication. Maximum observed work was 16,468 units and maximum
movement-path length summed across facts was 124 segments per action. No cap
failure occurred. Animation/loading were outside this measured interval.

The proposed **≤5 ms p95 target is not achieved**. Pure legal queries were optimized
from whole-board cloning to virtual line checks and validated against the reference,
but complete snapshot/admission/encoding costs remain in the action path. Profile
those stages before broader gameplay load; preserve the protocol and golden
checkpoints during optimization. Selected live release HUD observations were
roughly 24–119 ms, but these are spot observations, not a replacement benchmark.

Sequential per-segment playback deliberately preserves physical ordering and can
be slow on long cascades. Skip is usable; future scheduling optimizations must
compare against the fact-derived sequential reference. Full BoardScene decomposition
and polished UI remain P4. Restoring a pack after startup failure requires relaunch;
hot asset retry was not added. Disk saves/Continue and cross-build replay migration
are outside this P1 checkpoint.

## Frozen fixture handoff and next owners

[Fixture ledger](../tests/game/fixture-disposition.json): **15 full, 5 partial,
3 deferred** cases, all interpreted at their named phase. Craft expectations in
match_4/match_5, recovery results, first/last objective-action completion remain P2.
The lock query uses an explicit capability adapter; seal damage/removal remains
P6. Outlet/carry/completion remains P3. Unknown expected fields cannot silently
be ignored. [Smoke ledger](../tests/game/smoke-disposition.json) records the two
intentional fixture/expectation changes and retained observations.

P2 owns RoomState, Work/room budgets and win precedence, Craft, rubble, tools and
automatic recovery. It should use apply_action and the existing invariant/fact
boundary; do not create a second cost/refund calculation. P3 owns families,
rewards/routes, carry/extraction and complete expedition persistence. Add their
rule-relevant fields to the codec/admission/mutation/replay corpus when introduced.
P6 owns transport-room content and seals, using the tested foundation queries.

Read the adjacent [board](../core/board/CONTRACT.md),
[rules](../core/rules/CONTRACT.md), [run](../core/run/CONTRACT.md) contracts and
[game test guide](../tests/game/README.md) before extending these owners.
Opening generation is now explicitly bounded local rejection (64 draws per cell,
64 candidates, shared work ceiling), then stability/match-free/playability checks;
normal refill remains independent weighted draws. This implementation choice is
part of bounded_opening_v1, and opening goldens/checkpoints must change explicitly
if its distribution changes.

Existing edits to AGENTS.md, README.md and project.godot were preserved. No commit,
branch change, room feature, optical recalibration or new art acceptance is claimed.
The local plan/handoff and artifacts remain gitignored; runtime contracts, tests,
seed manifest and goldens are intended repository changes.

Final package/source integrity was rechecked after the missing-pack scenario:
[package integrity](../artifacts/game/p1-implementation/package-integrity.json)
has zero differences, including every runtime source hash and all three shipped
files. [Final stage logs](../artifacts/game/p1-implementation/logs/) are retained
beside the integrated report so later checks cannot replace this evidence.
