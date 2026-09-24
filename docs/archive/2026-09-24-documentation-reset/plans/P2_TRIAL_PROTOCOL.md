# Intervention engineering trial protocol — implemented T0

Implemented in `e7069cf`, with restart/readiness correction `2defe1a`.
The source-adjacent contract is [INTERVENTION_CONTRACT.md](../core/run/INTERVENTION_CONTRACT.md).
T4 disposition: decline adoption into P3 production now and retain the isolated
comparison for later review. Human preference remains unmeasured; this decision
implements the user's deferred evaluation policy and atomic default.

This isolated experiment does not enable reactive input in the expedition.
Profiles: `trial-paused-v1`, `trial-24-v1`, `trial-48-v1`; envelope/replay identity
`facets-intervention-trial-v1`, commands `trial.start`, `trial.presented`,
`trial.advance`, `trial.pause`, `trial.decide`. P1/P2 wire formats remain unchanged.
The user deferred human testing; T3 delivers comparison material only. Production
retains atomic actions until an explicit later adoption decision.

The resolver must actually park after automatic promotion chains and before
gravity. Its cursor retains cascade count, first-swap priority and next phase.
Context retains all facts, IDs, ancestry, journeys, work/fact counters, best Craft
and suppression. No speculative branch advances authoritative RNG.

At each pre-gravity boundary collect surviving promoted IDs from the episode's
committed prefix. Keep occupied movable/unlocked survivors with at least one
orthogonal occupied movable/unlocked neighbor whose swap creates a match.
Choose the survivor by `(y,x,instance_id)` ascending; order its targets by `(y,x)`.
An episode offers at most once. No remaining Work means no offer. Automatic
chains run before selection, so consumed/promoted-away opportunities are not
offered. A surviving further-upgraded instance remains the same eligible ID.

The root swap costs one Work and advances normal-turn count once. Intervention
costs one extra Work and no normal turn/tool refresh; its matches share original
Craft eligibility/budget. Pass and invalid input cost nothing. Stable trial state
retains separate intervention spending, so it never masquerades as an admitted
P2 state with inconsistent Work accounting. Disk save remains stable-only.

Each decision and continuation is transactional. A technical failure after a
window leaves the committed prefix visible in diagnostic state with restart.
No earlier rewards are spendable before complete episode settlement. Shared caps
are preserved across segments, including continuation after snapshot restore.

The window starts at tick zero only on `trial.presented`. Input carries window,
revision, ordered cells, expected IDs, tick and monotonic sequence. Invalid or
stale input does not mutate state. Paused profile has no deadline. Timed profiles
use 60 logical ticks/s and 24/48 ticks; tick >= deadline expires before input.
Pause/focus loss freezes tick progression and is recorded; these attempts are
excluded from unassisted timing comparisons. Reduced motion never changes time.
Rendering samples the clock; it cannot decide simulation. Record stalls; a
severely delayed visible window requires explicit pause/resume before evaluation.

Snapshots include initial admitted state, root command, profile, transcript,
current board/RNG/allocators, context, cursor, committed prefix, phase and clock.
Admission replays the bounded transcript from initial state and compares the
complete canonical envelope, rejecting forged pending state or omitted fields.
Reconstruction occurs in a detached session and publishes nothing on failure.

Hand-explained primary fixture: a vertical T1 match at `(2,1),(2,2),(2,3)`
promotes the ordered-swap destination `(2,3)` to T2. Its occupied left neighbor
`(1,3)` can exchange with that survivor, making T2 at `(1,3),(1,4),(1,5)`.
The initial swap is `(3,3) -> (2,3)`; these are zero-based coordinates. Additional
fixtures must cover an automatically consumed opportunity, no opportunity,
empty/locked/stale targets, zero/one Work remaining and a continuation cap.
An atomic control and pass must have identical P2 facts, full state and RNG;
only the trial envelope/transcript differ. Intervention has its own fact identity.
