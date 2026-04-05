# Tests

Headless smoke tests for the Facets simulation engine. All tests run without a scene tree and verify the core pipeline from board creation through full cascade resolution.

## Running Tests

```bash
godot --headless --script tests/test_smoke.gd
```

Returns exit code 0 on success, 1 on failure. Output shows PASS/FAIL per test with a summary count.

## Native Extension Test

```bash
godot --headless --script tests/test_native_trace_kernel.gd
```

Verifies the C++ `GemTraceKernel` GDExtension loads, registers, instantiates, and exposes the expected methods. Requires the native extension to be compiled (see Building the Native Tracer in the project README). Skips gracefully if the extension is not available.

## Test Coverage (40+ tests)

### Data Layer
- Board creation, bounds checking
- CellState properties (gravity direction, spawn entry, fill sources, tags)
- TileState properties (gravity override, immovable, unmatchable, merge_target_id, duplicate)
- BoardLayoutResource (apply layout with blocked cells, gravity, portals, fill sources)
- Topology: `get_neighbor()` standard, out-of-bounds, and portal override
- Effective gravity: default, cell override, tile override priority
- Swap rejection for immovable tiles
- Board hash determinism and change detection
- ConflictResolver deduplication with Vector2i keys

### Match Detection
- Standard horizontal match-3
- Unmatchable tile breaks runs
- Holes break runs
- Match classification (base, 4, 5+, L/T)

### Merge Mechanic
- Base match: 2 removes + 1 upgrade
- 4-match: 3 removes + 1 upgrade
- Max-tier match: all removes, no upgrade

### Board Physics
- Standard downward gravity
- Gravity over blocked cells
- Custom cell gravity direction (LEFT, RIGHT, etc.)
- Per-tile gravity override
- Immovable tile as barrier
- Iterative convergence on L-shaped gravity paths
- Diagonal fill from configured sources
- Portal gravity routing
- Move event recording
- Gravity determinism
- Cycle safety (MAX_SETTLE_ROUNDS cap)

### Pipeline Integration
- Effect planning (merge mechanic output)
- Conflict resolution
- Effect resolution (remove + upgrade with event collection)
- Integer-only weighted spawn pick
- Spawn determinism (same seed = same board)
- EventTimeline structure (cascade steps with all event types)
- Full TurnController cascade
- SeededRng determinism

### Verification
- Deterministic replay (same seed + 5 turns = identical board hashes)
- BoardValidator cycle detection
- BoardValidator portal target validation

## Cross-Platform RNG Test

```bash
godot --headless --script tests/test_rng_cross_platform.gd
```

Prints 100 reference RNG values for seed 42. Run on each target platform (Windows, Android, iOS, web) and compare outputs. If they match, integer RNG is cross-platform safe.

## Optional Simulation Harness

For longer balance / throughput runs with a simple greedy swap picker:

```bash
godot --headless res://tests/test_simulation.tscn
```
