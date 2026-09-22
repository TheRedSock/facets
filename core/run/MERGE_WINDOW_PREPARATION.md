# Merge-window resolution — proposed successor contract

Status: G0-G5 implementation and focused acceptance, 2026-09-22. Incremental
resolution, repeated paid inputs, worker/default lookahead, streaming presentation
and replay/restore are implemented. G6 performance and G7 release acceptance are
still pending; no P3-readiness or human-feel pass is claimed. Existing atomic
P1/P2 and the one-window trial remain controls.
Implementation and acceptance belong to [the successor goal](../../plans/P3_READINESS_SUCCESSOR.md).
This proposal replaces the atomic-only assumption for the next P3-readiness
experiment; it does not silently change the shipped P2 or frozen P0 behavior.

## User-directed behavior

- Compute the next merge batch during the initiating swap animation, or during
  the preceding gravity animation. Publish its complete result before enabling
  input in that merge animation.
- Open intervention input throughout every merge animation. The newly promoted
  gem can be targeted while its appearance animates; unrelated legal swaps are
  also allowed. Removed pieces are visual ghosts, never live targets.
- Every accepted swap is an ordinary paid move by default. A move accepted in a
  merge window has an explicit intervention classification for future pricing,
  reactions and archetypes. There is no one-intervention-per-turn cap.
- A timely intervention precedes the next automatic promotion-created match.
  The user explicitly selected this precedence on 2026-09-21. This differs from
  the old trial's automatic-chain-first rule and requires a successor protocol.
- On window expiry with no accepted swap, resolve any pending automatic match
  first; otherwise release gravity. Gravity is never applied through a live
  decision barrier. Equilibrium restores ordinary unrestricted thinking time.
- Human review remains optional and the user is the sole current reviewer;
  no session-count or focus-testing gate is introduced.

## Three independent notions of progress

`SessionState` owns committed simulation state and recorded commands. A worker
owns one detached candidate. `PresentationCursor` owns which committed batch is
currently visible and actionable. Never use animated positions as rule input.

The executor cannot publish or authoritatively advance through an unresolved
decision. During a window it may prepare exactly one detached no-input candidate
using private RNG state: the next automatic merge, or gravity if no match is
pending. A timely intervention discards that candidate. Never search possible
player moves or publish speculative facts. The immutable published post-merge
snapshot remains input authority throughout the window.

Gravity hold is a resolver condition, not a blanket input-enabled flag. Input is
open in `ready` and `merge_window`; it is closed while a newly accepted swap is
reserved/resolving/animating, during gravity, loading, errors and terminal states.
Every merge window accepts at most one command. A separate presentation buffer
can hold one unadmitted gesture during swap/gravity motion; it grants no rule
input authority. The next merge opens another window, with no cap on repeated
paid interventions.

## Resolution cycle

1. In `ready` or `merge_window`, validate the gesture against the exact published
   board revision, origin/destination IDs, phase and available resources. Only
   occupied orthogonal swaps that create a new match involving a swapped gem are
   legal. Existing matches elsewhere never make an unrelated invalid swap legal.
2. Reserve the first valid command atomically, close that window and quote/reserve
   its cost. Start swap feedback immediately after cheap validation. A reserved
   command is not yet a committed simulation batch; there is no second acceptance
   on the same revision. Invalid attempts neither charge nor extend the timer.
3. Compute the swap and exactly one deterministic merge batch on a detached
   candidate: all currently matching components in canonical order, their base
   outcomes, bounded same-batch reaction intents, and live-target revalidation.
   Freeze source identities/footprints before effects. Do not resolve the next
   promotion-created match. Detect that pending work and park before it.
4. Publish the candidate and immutable batch when admission succeeds. Before the
   swap animation ends, its complete result, visuals, hit map and next phase must
   be ready. At merge presentation start, expose the post-merge board and open the
   window. There is no additional countdown after the merge animation.
5. A valid gesture in that window reserves the next move against the post-merge
   board immediately. Compute its batch while the remaining merge decoration and
   its own swap feedback play. Swap motion begins as soon as both endpoint poses
   are transferable; normally immediately because survivors have fixed cell
   anchors. Blend/cancel their decorative scale/upgrade tracks, preserve other
   removal ghosts, and avoid an added global wait for those decorations.
6. On expiry with no reserved move, emit a free `release_window` continuation.
   If an automatic match is pending, compute/present the next merge batch while
   keeping gravity held; that batch gets its own intervention window. Otherwise
   commit a gravity/refill batch, start its animation, and compute its next merge
   batch or equilibrium outcome during that animation.
7. Prepare the single default successor during the current merge window. If a
   promotion already created another match, prepare that next merge batch;
   otherwise prepare exact gravity/refill trajectories and the ending board.
   This closes the timing gap at expiry: neither the first gravity animation nor
   an automatic merge has an intervening swap to hide its calculation behind.
   Commit only after expiry, after checking the window, base revision and branch.
   An accepted intervention cancels/discards speculation and gets worker priority
   at bounded cancellation checkpoints. Restart and failure also invalidate it.
   Its RNG, allocators, costs, rewards and facts never affect live state before
   commit. Never animate invented destinations. Missing the expiry handoff is
   measured as starvation, not hidden by a new waiting animation.

This limited default-path lookahead is the explicit exception to computing only
during swaps and gravity. It prepares one possible next batch, never an entire
cascade tree. On committing an automatic merge, its own input window opens and
the cycle repeats. A player can move a promoted gem out of a pending automatic
match into a stronger legal match; the discarded automatic result has no effect.
Likewise, failure in a speculative branch is private until that branch is chosen.
An intervention discarding it must not inherit its error. If expiry selects a
failed default result, apply the ordinary unpublished-batch failure policy.

If a batch is late, hold the last coherent visual state, keep input closed and
record starvation. Never shorten the next window to hide lateness, use stale
results, make up events or slow the animation profile to pass a benchmark.
The later window begins only when its result and first actionable frame are ready.

## Merge animation and buffered targeting

Tool selection in the successor is reversible: unaffordable/unavailable tools
cannot enter targeting. Selecting the same tool, Escape, or Cancel returns to
swaps, and rejected targets release selection without cost. Committed batch
presentation emits coalesced match, promotion and rubble cues in normal and
reduced motion; speculation emits no effects. The older trial's instant/reduced
path summarizes the same committed cue types rather than muting all effects.

At the first merge frame, show the survivor's new identity/tier at its final cell
anchor, even if its material/scale transition is unfinished. Keep departing pieces
as separately owned noninteractive ghosts. Stationary pieces elsewhere remain
targetable. The hit map uses post-merge cell/instance IDs, not sprite rectangles
in transit. Consumed pieces cannot be selected by clicking their ghost image.

Mouse tap/drag and keyboard selection use one gesture adapter. A gesture is
complete when its destination is committed (tap, drag threshold or key confirm);
pointer-down alone does not reserve a move across expiry. A timely complete
gesture may be accepted before the promoted gem's decorative animation ends.
Capture its window/revision/IDs at acceptance and recheck at the worker boundary.
Visible acknowledgment marks the buffered/accepted move; it is not silently
retargeted if a view is pooled or the screen is resized.

User-approved amendment, 2026-09-22: during swap/gravity motion (including a
late result's coherent hold), collect one completed mouse or keyboard swap.
Hit-testing follows currently drawn live gem poses; ghosts are excluded. Store
the two stable gem IDs, not their old cells or an already-priced command. A newer
complete gesture replaces the pending pair. Cyan outlines/link and a status
message indicate the buffer; Escape, right-click or Cancel clears it.

At the first eligible merge window or equilibrium, resolve both IDs on the
current committed board and run ordinary full command admission exactly once.
Missing gems, nonadjacency, locks, invalid matches or insufficient resources
cancel visibly and spend nothing; never retry silently at a later window or
substitute replacement gems. A legal buffer uses the full normal swap animation
and a new calculation deadline starting at actual admission. Its normal cost
and equilibrium/intervention classification derive from that phase. Queue-time
acknowledgment and admission-time feedback are separate telemetry events.

Incomplete gestures do not reserve future input. Focus loss, pause, terminal
state, error, restart, menu and restore discard unadmitted intent. Snapshots and
replays retain the resulting admitted command/tick, not a presentation gesture
that has spent nothing; restore cannot unexpectedly execute an old buffer.
This adapter amendment leaves simulation/session/replay wire identities and
original profiles unchanged. Legacy P2/trial controls do not acquire buffering.
Registered `test_merge_input` and `test_merge_input_native` cover the extension;
packaged release witnesses additionally exercise gravity buffering in both
normal and reduced motion.

All simultaneous disjoint match components form one published merge batch and
one board-wide window. Pending automatic matches are rescanned after intervention;
never execute stale pre-intervention match lists. By default the new paid move
owns all subsequently resolved components, including an untouched pending match
elsewhere. This explicit active-move ownership avoids concurrent reward contexts;
event ancestry still preserves already committed facts from earlier moves.

## Logical timing contract

Frozen G0 profile: swap feedback 9 ticks (150 ms), merge window 20 ticks
(333.333 ms), clock 60 Hz. The current player uses a 150 ms swap and approximately
180 ms removal plus 150 ms upgrade; the successor overlaps input with that merge
interval instead of appending the trial's 400/800 ms wait. These are initial
tuning values frozen at G0, not established player preferences.

`window_presented` at the first actionable merge frame starts tick zero exactly
once. Accept receipt tick < 20; expiry wins a tie at tick 20. Engine input events
are stamped on receipt and arbitrated before the scheduled expiry decision for
that frame, so a delayed worker cannot retrospectively reject an on-time input.
The serialized transcript contains the admitted integer tick/sequence/outcome;
playback FPS and worker completion order do not determine the rules.

One monotonic adapter produces clock events. Ordinary ticks update clock metadata
without reconstructing/cloning the whole board or rescanning legal swaps. Pause,
focus loss and visible stalls freeze logical time and are recorded as assisted
attempts. Do not give unrecorded deadline extensions. Reduced motion preserves
the same actionable duration and identity cues with simpler animation. Paused
practice and altered timing are separately identified modes; they are not evidence
of unassisted reaction performance. Skip records explicit passes and snaps only
committed batches; it cannot invent missed player choices or reroll RNG.

Separate the mechanical base revision from the clock/transcript sequence. A
clock tick cannot invalidate an otherwise correct default board candidate, and
a candidate cannot overwrite newer clock/assist metadata. At publication bind
the candidate to the actually admitted expiry/input decision and current ordered
transcript, then complete the session envelope/digest. Include that final binding
cost in deadline telemetry; a speculative digest is not evidence of a committed
session with a different decision history.

## Move accounting and extension points

Reserve distinct `move_id`, `segment_id`, `window_id`, global event/removal IDs
and session generation. Equilibrium and intervention swaps use the same command
shape and base cost (1 Work), ordinary match rules, Craft eligibility and normal
tool-allowance refresh. `move_context = equilibrium | intervention` is derived
by the engine from the admitted phase, never trusted from an input payload.

Each accepted paid swap starts a fresh move scope: strongest Craft base,
raw bonuses and per-move family uses. Automatic continuation, clock ticks and
window expiry retain the active move scope. When a new paid move takes over,
finalize the old scope; do not reset room/run uses. All facts caused by the new
move inherit its intervention classification, including subsequent gravity
cascades, until another paid move takes over or equilibrium is reached. A future
reaction may narrow its predicate to the direct input batch. The new content
contract must make this distinction visible to authors.

Settle newly earned Craft at each committed merge boundary so visible counters
are available to the next decision. Track cumulative entitled award separately
from actual capacity-clipped gain: add only the increase in `min(3, best_base +
raw_bonus)`, then clip that increment to capacity 6. Entitlement already clipped
away cannot be reclaimed after spending Craft. No-input chains share one cap;
each new paid move receives its normal fresh scope. Tool commands remain
equilibrium-only in this goal; intervention does not imply mid-animation tool
input. A tool-caused merge still opens the ordinary swap window. Passing retains
the tool scope's suppression; a new paid intervention starts a normal eligible
scope without retroactively rewarding the earlier suppressed tool effects.

Provide one typed command-price/eligibility hook and typed fact predicates for
intervention-only costs/rewards. Default output must equal an ordinary move.
Diagnostic fixtures demonstrate an intervention-only discount and reward without
shipping new gems/settings. Use integer resource units and immutable source-order
modifier application. Do not change the established Work unit just to represent
half-price moves. A future zero-cost effect must consume an explicitly bounded
charge; reject a content configuration that permits unlimited zero-cost commands
without another finite resource. Safety caps limit automatic resolution work and
bounded queues, not the count of otherwise legal paid interventions.

Check objective completion before offering another window. Completion wins on
final Work and stops further input/gravity/refill when the objective's policy
allows it. At zero Work, finish required automatic resolution, then decide loss;
do not fail prematurely at a merge boundary. Board recovery is equilibrium-only,
never a response to a paused board with holes. Keep outlet/extraction production
deferred to P3, with explicit stable-boundary objective policy hooks.

## Executor and presentation architecture

Prefer one persistent simulation worker with a single writer and detached inputs.
The main thread performs bounded gesture admission, owns the presentation queue
and publishes worker candidates after generation/base-revision verification.
No worker touches scenes, TileViews, audio, GPU resources or mutable autoload state.
Audit current shared catalog/resources, static codec caches and callbacks before
enabling it. Prepared immutable DTOs and worker-owned codec/context state cross
the boundary; do not share mutable GDScript dictionaries by convention alone.

Implemented owners are MergeSession, MergeKernel, MergeMoveContext, MergeExecutor,
MergeReplay, MergeClock, MergePlayer and MergeRoomView. The conceptual interfaces
below describe their responsibilities; batches are transferred candidate/packet
records rather than another mutable global service:

- `ResolutionSession`: authoritative phases, committed state, active move scope,
  reservations, expected base revision and cancellation generation.
- `ResolutionCursor.advance_batch`: resumes match, reaction, gravity or terminal
  work, returning a candidate batch, decision barrier, stable result or failure.
- `ResolutionExecutor`: synchronous reference executor and asynchronous executor
  over the same deterministic kernel. Optional cooperative scheduler is acceptable
  only if measured main-thread and deadline exits pass; it is not a silent fallback.
- `ResolutionBatch`: batch ID, base/end revision and digests, move/context IDs,
  immutable facts and trajectories, post-state, actionable hit map, pending cursor
  and next-phase information. No mutable event list may be extended after publish.
- `StreamingActionPlayer`: consumes only committed batches, owns ghost/live view
  transfer, animation cursor, queue watermark and visible input acknowledgment.
- `InterventionInputAdapter`: view-to-ID gesture mapping, receipt stamps and timer
  arbitration; no game-rule evaluation in Tween callbacks.

Keep one active worker job, at most one detached default successor, one reserved
input and at most two queued committed batches. Apply backpressure at that
watermark and always at an unresolved input barrier. A speculative job yields to
an accepted command at bounded checkpoints; no unbounded branch queue is allowed.
Clear publication through generation invalidation on restart/menu/restore/error.
Worker completion must not access a freed scene; shutdown and joins have bounded
timeouts. Re-entering a room never adopts a late result from its previous run.

Each unpublished batch is transactional. On technical failure discard it and
release its reservation; retain all earlier committed costs, board state, RNG
and facts. If its provisional swap feedback already played, snap explicitly to
the last committed board with a diagnostic message and recovery controls. Never
roll back earlier published/animated batches. Candidate publication updates rule
state, cost, event/replay records and queue visibility atomically.

Hashes and external admission remain complete. Replace redundant internal work
only with explicit invariant coverage and immutable-data rules; moving expensive
work off the main thread does not authorize omitting it. Maintain one ordered
input/commit transcript. Diagnostic scheduling, latency and worker telemetry are
separate from mechanical identity except recorded window/assist decisions.

## Compatibility and P3 reconciliation

Implemented profile `p3-ready-merge-v1`, simulation `facets-sim-merge-v1`, content
`facets-p2-merge-content-v1`, session envelope `facets-resolution-session-v1`
and replay `facets-replay-merge-v1`. The embedded P2 structural state is admitted
inside this complete envelope; it is not an unsettled RunState v2 save.
Preserve FAC1 and RNG/settling versions if their bytes/behavior remain unchanged.
P3's final version names must explicitly incorporate this model before reference
capture; the previously reserved atomic P3 identities do not prove compatibility.

The session snapshot includes phase, complete board/rules/content/RNG, cursor,
all allocators, active move context and earned entitlement, pending automatic
work, reservations, committed replay cursor, window identity/tick/sequence,
generation-independent revision and any objective progress. Restore into detached
state, validate every field and reconstruct presentation from committed facts.
Do not serialize threads, Tween objects or wall-clock timestamps as simulation.

Complete in-memory restore/replay for every boundary is required here. Production
disk Continue is still P3 work. Its revised schema must support a parked merge
window or explicitly suspend at a reconstructible committed boundary; do not
silently save an older equilibrium state. Restored timed windows are paused and
marked assisted until resumed; no offline time is charged as reaction time.

Retain the exact original P1/P2 corpora and old trial replay path. Successor
all-pass runs must preserve final board/resource/RNG outcomes where semantics
are unchanged, using an explicit comparison projection. New intermediate commits,
Craft settlement facts and IDs legitimately differ and require new reviewed
vectors. Never regenerate old goldens. Intervening before an automatic match is
a deliberate semantic change with hand-explained fixtures.
Stopping at a newly introduced terminal merge boundary can also change a final
board that the atomic profile would have settled further. Give those cases exact
successor expectations and an explicit difference record; never hide a board or
resource mismatch by removing it from the comparison projection.

Update P3 family scopes, suppression, terminal checks, save phases and failure
semantics before declaring readiness. Other planned rooms/rewards/carry remain
in scope for P3 and are not implemented just to pass this preparatory goal.

The [acceptance specifications](../../tests/game/MERGE_WINDOW_ACCEPTANCE.md)
provide the tracked fixture inventory and performance exits. Complete G0 contract
reconciliation, G1 batch kernel, G2 paid inputs/accounting, G3 executor/lookahead,
G4 streaming room, G5 restore/P3 audit, G6 measured correction and G7 release
handoff in that order, checkpointing verified implementations. The local goal
plan and tracked readiness ledger distinguish focused checks from final release
acceptance. Publishing this contract alone establishes no runtime result.
