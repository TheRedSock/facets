# Tactical room protocol — P2

Policy freeze: 2026-09-14, based on P1/P1-A commit `95a02f7`. Implementation is
incremental; the checkpoint ledger is `tests/game/p2-checkpoints.json`.
The legacy P1 action/state/replay contract remains supported without new fields
or changed expected bytes. This contract specifies the atomic room mode, not the
separately versioned post-P2 intervention experiment.

## Identity and ownership

P2 uses design ID `facets.prototype.v1`, implementation profile `p2`, simulation
`facets-sim-v2`, state schema 2 and `facets-replay-v2`. Codec, RNG partition and
the in-place settling algorithm keep their v1 identities. Room definitions are
detached admitted values; RunState owns current board/economy/room counters.
The board owns obstacle occupancy and topology; presentation never spends rules
resources or decides completion. Resolving is transaction-local; presenting is a
UI gate. Published room phases are briefing, ready, complete and failed.

## Frozen policies

- Start Open seam at 16 Work and 1 Craft, capacity 6, tool allowance open. Use
  the starter eight, default T1–T4 supply weights 4/3/2/1 and four two-hit rubble.
- Accepted normal swap costs 1 Work and reopens the tool allowance. Its strongest
  eligible match across the whole action earns 0/1/2 Craft for 3/4/5+ or an
  intersection. Base plus future eligible bonuses is capped at 3, then capacity.
  Earnings settle once; tools and suppressed descendants earn nothing.
- One tool between accepted normal swaps. Reposition/Chisel cost 2 Craft;
  Refine costs 3. No tool Work cost, turn advance or hazard tick. Zero Work,
  non-ready phases, invalid/stale targets and closed allowance reject purely.
- Reposition exchanges two occupied movable/unlocked orthogonal instances,
  including distinct same-tier instances. Initial matching uses ordered swap
  survivor priority. Refine promotes T1–4 once and preserves ID; induced matches
  have no swap priority. Its direct ceiling does not limit later merges.
- Chisel explicitly selects obstacle, lock or gem layer. Damage rubble/lock by 1
  or remove T1–3. Movement-only locks do not prevent targeted promotion/clearance.
  Clearing a gem also clears its attached lock; lock damage leaves its gem intact.
  Full seal lifecycle/content remains deferred.
- Rubble is a separate obstacle on an active cell, never a hole or T0 gem.
  Snapshot all source cells of each committed component, including the survivor;
  hit each orthogonally adjacent obstacle once per component. Snapshot the whole
  batch before effects, then order components and targets canonically. Portals
  and diagonals do not extend damage. Actual damage is bounded by durability.
- Record marked rubble progress on break; evaluate victory at the first fully
  stable action boundary. Complete beats Work exhaustion. Once complete, perform
  no additional hazard, recovery or refill. Failed simulation caps roll back even
  if the candidate has already broken the last target.
- If still live, offer any legal normal swap or affordable legal tool. Otherwise
  recover by permuting movable/unlocked T1–3 instances over their current cells,
  preserving all other pieces/layers/economy. Each candidate starts from the same
  original list, using descending integer Fisher–Yates on the recovery stream.
  Require physical stability, no matches and a legal normal swap in at most 64
  candidates. Fewer than two eligible pieces fails with zero draws.
- Ordinary recovery exhaustion preserves pre-recovery board/economy, records
  consumed recovery RNG/attempts and commits failed/board_locked. Technical cap
  failure rolls back the entire action. Recovery never refreshes tools or rewards.
- Begin-room is a recorded zero-cost boundary command. Revision counts accepted
  commands; normal-turn count counts swaps only. Stable state identity includes
  all implemented room/economy/obstacle/counter data, not UI clocks or selections.
- P2 snapshots/replay restore only complete stable room boundaries. No disk-save
  UI or real resolver continuation is claimed. P3 production continuation policy
  waits for the required paused/timed trial and explicit adoption decision.

Verification must keep original codec/action vectors and all 2,000 P1 checkpoint
pairs. New room, tool, recovery, replay and playback cases belong in tests/game.
The inherited 5 ms CPU gate and player feel acceptance remain open.
