# Prototype v1 acceptance fixtures

These declarative fixtures are the P0 handoff for `facets.prototype.v1`.
They describe **target behavior**, including known failures and systems not yet
implemented. They are not a passing Godot regression suite or production room data.

`cases.json` fixes the board, action, seed, observation phase and expected outcome.
Coordinates are zero-based `[x,y]`, with rows increasing downward. `0` is empty;
`1..8` select the corresponding active roster tier. Give each initial tile a stable
instance ID derived from fixture ID and initial row-major index. New spawned tiles
need distinct monotonically allocated IDs. An empty cell under an obstacle is not
a permanent topology hole. Unspecified cells use downward gravity.

The named observation phase matters:

- `swap_then_first_match`: validate/swap, inspect the first match batch before
  gravity/refill. Expected Craft is a base candidate, not final turn earnings.
- `match_snapshot`: inspect an intentionally unresolved board directly. Do not
  stabilize it as an opening board before checking the match components.
- `validate_action`: rejected actions must preserve state and RNG. The unrelated
  match fixture is deliberately not a normal stable input boundary.
- `spawn_query`, `gravity_query`, `state_identity`: query only the indicated layer.
- `settle_refill`: inspect physical occupancy before resolving any new matches.
- `stable_extraction`: evaluate the outlet on the given stable board.
- `complete_action`: eventually run a complete transaction through the room
  resolver. Use the default supply and the recorded seed. Assert the specified
  outcome, not an invented final random population.
- `recovery_query`: verify no legal swaps and recovery eligibility. The low-tier
  witness preserves the multiset and has a legal swap, proving recovery is
  possible; it does not prescribe the engine's first shuffled arrangement.

The P0 consistency check validates board geometry, first-match components,
survivors and recovery witnesses independently of Godot. This does **not** prove
the future simulator passes the fixtures. P1 adds adapters for existing rule
layers and regression assertions; P2/P3 add room/outlet adapters. Seal fixtures
reserve their semantics for later implementation without shipping seal content.

Retain each case ID when turning a known defect into a regression test. Do not
change expected results merely to make the old prototype pass. Change the named
rules version and review the design if intended behavior changes.
