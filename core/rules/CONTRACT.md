# Deterministic rules protocol

GameCatalog and RuleSet are admitted, recursively read-only values. Simulation
has no Node, translated label or presentation lookup. GameBootstrap is the
resource composition boundary. The starter roster has eight explicit tiers;
supply is ordered T1–T4 with integer weights 4/3/2/1. Promotion follows that roster,
including alternate admitted rosters. Invalid supply fails before drawing RNG.

ActionLegality is the common pure query. A swap requires ready phase, positive
budget, two occupied movable local orthogonal cells and a new match involving a
swapped cell. Same-group exchanges reject. A virtual occupancy line check is
compared to the independent full-board scan in regression tests. Enumeration
preserves directed origin/destination and orders origins and destinations by
(y,x), so survivor choice is reproducible.

Version identifiers are `facets.prototype.v1` (P1 subset), `facets-sim-v1`,
`facets-codec-v1`, `facets-stream-v1`, `legacy_scan_v1`, and `facets-replay-v1`.
RuleSet records matching, survivor, progression, budget, fill and opening policy
IDs plus hard limits: 256 settling rounds per physical pass, 50 cascade groups,
20 additional pre-gravity chain rounds, 64 opening candidates, 1,000,000 work
units and 100,000 facts. Reduced diagnostic limits are admitted; raised limits
or unknown policy versions reject. There is one economy: each accepted swap
costs one. Craft, room budgets and objectives are not implemented by this subset.

RngStreamBank owns board/rewards/routes/recovery. Stream seeds derive from the
SHA-256 protocol text in rng_stream_bank.gd (first 15 hex digits). Snapshots carry
master seed, engine build and each stream's seed and complete state. Restore
sets seed before state. Same-build equivalence is tested; cross-version or
cross-platform binary sequence compatibility is not promised.

CanonicalCodec wire format starts with ASCII FAC1. Value tags: null 0, bool 1
(one byte 0/1), signed i64 2 (little endian), UTF-8 string 3 (i64 byte length),
Vector2i 4 (two i64 with int32 bounds), array 5 and map 6 (i64 counts). Map keys
are strings in strict UTF-8 byte order. StringName normalizes to string. Floats,
objects and resources reject. Limits: 16 MiB total, depth 32, 100,000 collection
members, 1 MiB string and 1,000,000 nodes. Decoding rejects malformed lengths,
trailing bytes, duplicate/out-of-order keys and noncanonical encodings.
SHA-256 of these exact bytes is authoritative. BoardState.compute_hash is only a
60-bit compatibility adapter. Independent Python-produced codec vectors are
checked in; tests must not regenerate expected bytes from production code.

Encoding uses a little-endian StreamPeerBuffer and per-call UTF-8 string reuse.
Native normalized string sorting preserves UTF-8 lexicographic order; wire tags,
limits, exact integer representation and decoder admission remain unchanged.
There is no cache of mutable board/state values and no weakened identity digest.

State identity includes board dimensions, every introduced cell/tile value,
portal and ordered fill configuration, unique instance IDs and allocator,
mechanical definitions/supply/rules, budget, phase, session counters, recovery
counts and all RNG positions. Readable JSON reports are diagnostic; exact state
and replay use the canonical codec. Presentation and debug retention are excluded.
Rule facts retain immutable source/old/new snapshots, event/removal IDs, ancestry,
assist classification and ordered path segments. Debug log truncation never
reuses indexes. Save slots and complete expedition persistence belong to P3.
# P2 command and replay extension

RoomCommand admits Begin, normal swap, Reposition, Chisel and Refine with exact
fields, revision and selected instance/obstacle identities. RoomActionLegality
owns pure admission and tool enumeration. Room actions use simulation v2 and
replay v2; legacy SwapCommand/replay v1 remain unchanged. All seeded shuffle draws
explicitly call the SeededRng instance; the unqualified global RNG is forbidden.
ActionContext carries causal facts and reward suppression during execution;
RuleFactBuilder remains the legacy projection. See the
[room protocol](../run/ROOM_CONTRACT.md) and [effect ownership](../game/CONTRACT.md).
