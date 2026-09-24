# Action and session ownership

RunController owns the published RunState, accepted command/checkpoint record,
session generation and presentation acknowledgments. ActionTransaction checks
legality, copies mutable state/RNG/allocators, reserves one budget point, resolves
all matching/settling/refill, builds immutable facts and validates final state.
Only success publishes. Failure or rejection preserves state, RNG, budget,
allocators and accepted commands; a diagnostic last_error may change.

Matching chains resolve before gravity; cascades repeat after physical refill.
Committed results carry before/after view snapshots, command/action/revision,
state and event digests, canonical facts and presentation work. Scene callbacks
never advance rules. The begin/resolve/finalize compatibility path resolves once
at begin; finalize and acknowledgments cannot repeat accounting.

OpeningGenerator produces at most 64 candidate boards. In each candidate it
fills row-major, rejecting backward horizontal/vertical three-runs for at most
64 weighted draws per cell. It then checks physical stability, no matches and a
legal swap. All draws use a detached board stream and the shared work ceiling;
normal refill remains independent weighted draws. Exhaustion is explicit invalid
content and preserves a prior session. This avoids free setup merges. Carry and
automatic dead-board reshuffling remain P2/P3.

Restart restores the session's initial admitted snapshot. Reroll retains current
layout, roster, supply and rules while generating another seed. RunState restore
validates schema, definitions, topology, unique instances, counters, RNG build,
physical/match stability and budget/phase consistency before publication.
Replay records carry a complete initial snapshot, its digest and ordered accepted
commands with state/event checkpoints. ReplayRecord verifies each checkpoint
through the same action boundary. Disk I/O and Continue UX are outside P1.

RunScene commits before its first playback await. BoardScene gates loading,
playback, modal and error independently, using owner tokens for releases.
ActionPlayer owns its tweens and cancellation epoch. Skip snaps to the committed
view; restart/navigation cancels pending presentation. Stale continuations cannot
release a newer gate or finalize rules. Delivery failure remains locked and hidden
until an explicit valid board load. The old BoardScene presentation helpers remain
for delivery probes; the production action path uses ActionPlayer.

Verification: atomic failure injection, complete byte/record equality on failure,
100 fixed-seed replay and midpoint restore, and real scene playback/cancellation
checks. Package audit/probe and actual release interaction evidence are recorded
in the P1 handoff, separately from simulation and optical acceptance.
