# Board simulation contract

BoardState owns mutable occupancy and topology queries. Match and swap adjacency
is local, active and orthogonal. Gravity may traverse a directed portal; fill
sources are local offsets in authored order. ZERO cell gravity means DOWN.
Static nonzero tile gravity overrides cell gravity. Movement locks and immovable
occupants prevent movement but do not prevent matching. Holes are not rubble.

LayoutAdmission validates raw resources before allocation: schema 1, dimensions
1–16 on each axis, a nonempty active mask, canonical coordinates, cardinal
gravity/portal directions, unique edges/entries and valid local fill sources.
It compiles detached read-only records. Travel cycles (including mixed primary
and fill edges) reject; contention and unreachable entry-only cells are warnings.
StateAdmission also checks each introduced static tile-override travel graph.
Diagnostics carry code, severity, resource ID, field path, cells, edges and a
message key. BoardValidator is only a string-formatting adapter.

`legacy_scan_v1` scans active cells bottom to top, right to left, in place:
primary travel first, ordered local fill second. A tile can move again when a
later scan cell is visited. Every segment retains identity, endpoints, kind,
round and sequence. Settling checks repeated occupancy and explicit ceilings.
A stable board exactly at its round cap succeeds; pending movement fails.
BoardSettler alternates settling and refill until no eligible spawn remains,
including when there were no matches. `entry_only` never falls back to other
empties; `fill_empty_cells` is the default rectangular-board policy.

Resolvers mutate only their supplied board. ActionTransaction supplies detached
state and publishes only success; calling a low-level resolver alone provides
no rollback guarantee. Shared limits cover physical rounds, match chains,
cascades, work and event volume. A cap is failure, never partial success.

MatchDetector finds maximal local lines; MatchClassifier groups intersecting
same-tier runs into connected components, with sorted members and component
order. Touching parallel runs remain separate. First-match survivor priority is
destination, origin, then maximum (y,x); later rounds use maximum (y,x). Promotion
uses the admitted roster's next tier; tier 8 removes all members as recovery.

Verification: tests/game/test_game_rules.gd, topology_cases.gd,
test_game_state.gd, test_game_transaction.gd and retained smoke assertions.
The nine foundation scenarios and 16×16 bounded envelope are correctness tests;
transport room content and seals remain later work.
# P2 obstacle occupancy

Room boards serialize a separate obstacle map, including an empty map after the
last break. Rubble occupies an active, gem-free, lock-free cell; it does not change
topology. `can_enter` owns destination occupancy for movement, refill and opening
generation. `obstacle_neighbors` snapshots orthogonal contacts, deduplicates by
obstacle ID and returns row-major targets, with no portal extension. Admission
checks exact obstacle payloads, unique cells and bounded positive durability.
Legacy boards omit this layer entirely to preserve their canonical bytes.
