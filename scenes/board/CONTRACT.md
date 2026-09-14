# Committed board presentation

ActionPlayer consumes committed before/after snapshots and the canonical
fact-derived EventTimeline. MotionPlan is a pure presentation projection; neither
class advances simulation, spends Work, draws RNG or accepts mid-cascade input.
Automatic promotion-created chains are presented before gravity. Normal playback
is concurrent; `serial_reference` and instant playback remain diagnostic paths.

For a dense rectangular board with DOWN gravity, no movement locks/immovable
pieces, fill-source edges or portals, each settling wave is projected into full
per-instance journeys. Existing pieces and the incoming refill stack start
together. Cubic ease-in uses the matching distance-duration formula; straight
cell boundaries do not restart movement. New pieces retain canonical final
ordering and start in a spaced stack above their column. Landing scale decoration
runs independently per journey while other pieces continue falling.

Other topology uses conservative ordered travel. Full path identity and every
segment are retained. Portal traversal fades out at departure, jumps to the
admitted landing and fades in; it never flies through intervening cells. Custom
spawn entries fade at their logical cell to avoid inventing a route through a
blocker. This fallback deliberately does not claim the normal lane's physical
fluidity. Transport-specific motion remains later work.

Match/settle-wave barriers remain. No transient visual line forms a new match.
Cross-wave early clearing is deferred until support, path reservations and
relevant empty-cell dependencies can be proved; endpoint overlap or parent IDs
alone are insufficient.

Moving and newly created views are indexed by stable instance. The cell map is
published together after a concurrent wave, avoiding overwrites by trailing
pieces. Cancellation owns all movement/fade/scale tweens and releases spawned
views that have not yet entered the cell map. Epoch invalidation wakes suspended
callers before scene destruction. Skip snaps to the committed state; restart,
navigation and delivery failures cannot leave stale work or unlock another gate.

Tests: `tests/game/test_game_motion.gd` verifies trajectory spacing/concurrency,
refill paths, custom-topology fallbacks, pre-gravity chains and real-scene
lifecycles. `test_game_playback` covers application accounting/gates. The opt-in
ActionProbe measures actual scene actions in source and the shipped executable;
headless timing is not GPU/frame acceptance and final snapshots alone do not
establish visual quality.
