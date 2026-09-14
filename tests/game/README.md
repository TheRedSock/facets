# P1 game checks

Run the registered `test_game_rules`, `test_game_state`, `test_game_transaction`,
`test_game_replay`, `test_game_playback` and `test_game_motion` stages through tools/check_engine.ps1
after import. Every stage has a required completion marker and nonzero failure
exit. These tests use explicit synthetic catalogs/delivery fixtures; production
bootstrap never falls back to them.

fixture-disposition.json assigns every expected field in all 23 immutable P0
cases: 15 full P1 observations, 5 partial and 3 deferred. “Full” concerns the
fixture's named phase, not complete expedition behavior. Craft and recovery
outcomes are P2; outlet/carry are P3; seal lifecycle is P6. Unknown phase/field
names fail the inventory. Locks in matching tests are capability adapters.

smoke-disposition.json accounts for 113 historical assertions, including the
formatted weighted-frequency label. Smoke now runs 114 assertions: it first
rejects the old layout's fill source pointing into a hole, then uses a valid
local source for retained layout observations. The previous cycle termination
assertion now requires explicit physical_cycle failure. Complete atomic rollback
is separately tested for work/fact/settle/cascade/chain caps. Catalog injection
and deterministic survivor ordering intentionally replace legacy fallback rules.

The nine topology scenarios cover irregular supported pockets, sideways-to-down,
upward in-place scanning, directed portal landing, source contention, immovable
occupants above entries, local diagonal fill beside a portal, mixed travel cycles
and no-match lane refill. 16×16 yields exactly 240 movement segments; oversize
layouts reject before allocation. Work and ordinary timing are reported separately.

codec-v1.json contains independent Python reference vectors. action-v1.json is a
reviewed 13-fact match_3 baseline captured after semantic, ancestry and projection
checks: action, swap pair, displaced helper, component, two removal/subtype pairs,
promotion, two spawns and settlement. Its exact bytes and SHA-256 checkpoints are
fixed. tools/game/capture_action_vector.gd writes only a candidate under artifacts;
it never refreshes expected values. JSON-readable facts are diagnostic, while
fact_bytes is the exact wire representation. Protocol changes require review and
an explicit version decision; tests must not rewrite goldens to pass.

seeds.json fixes 100 seeds and an ordered legal-command policy independent of
rule RNG. Each run records every accepted state/event checkpoint, fresh replay
and midpoint snapshot continuation. No failed seed is discarded. The report is
artifacts/game/p1-implementation/replay-corpus.json. Same-build equality is the
claim; RNG build mismatches reject. The proposed 5 ms p95 is measured and assessed,
not presumed. test_game_playback uses the real RunScene/BoardScene adapter for
sequential, instant, skip, restart, rejected bounce, delivery error and destruction.
Its accelerated animation clock changes presentation only. Release-executable
interaction is a separate package handoff check.

P1-A adds `p1-checkpoints.json`: all 2,000 state/event pairs captured from the
original completed P1 corpus, with the source report SHA-256. Every replay-corpus
action now compares to this frozen baseline as well as fresh replay/restore.
Do not regenerate it from optimized code. Codec vectors remain independent.

The frozen fixture directory, codec/action goldens and P1 checkpoint file disable
Git newline conversion through .gitattributes. Preserve their exact bytes across
checkouts; do not renormalize them as part of formatting or platform setup.

`test_game_motion` checks L-shaped holes, simultaneous release, unequal landing
times, sampled lane spacing, long entry-only refill, disconnected regions,
direction changes, upward zones, portals, diagonal fill and supported pockets.
It also checks a positive pre-gravity promotion chain and real concurrent/serial
playback, cancellation during travel/landing, restart, error and destruction.

`game_action_probe` is a registered GPU stage using the real delivered pack and
normal RunScene. It measures 20 seed-0 actions, including synchronous commit
frames, input response, planned/observed playback and page loads, plus lifecycle
checks. Functional completion is separate from its reported 5 ms CPU / 16.7 ms
frame targets. Run the same opt-in probe in the actual release executable; the
older delivered-view burst does not substitute for it.
# P2 simulation checks

Registered `test_game_room`, `test_game_tools` and `test_game_recovery` cover
room/obstacle admission, P0 first/last-Work completion, transactional failure
injection, identity-checked tools, suppression, allowance, bounded deterministic
recovery and stream isolation. `test_game_room_replay` runs 100 explicit seeds
with mixed tools/swaps, canonical midpoint restore, stale-command rejection and
complete replay. Its new evidence goes to artifacts/game/p2/simulation.
These establish simulation behavior; player teaching, pacing, release performance
and the separate intervention trial require their own evidence.
