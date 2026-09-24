# P1-A — fluidity and performance amendment

Proposed implementation plan, 2026-09-14. The user requested assessment and
document changes; these batches have **not** been implemented by this review.
The [assessment](../docs/FLUIDITY_AND_REACTIVE_PLAY.md) owns evidence, design
tradeoffs and the optional reactive-play proposal. The original
[P1 handoff](P1_HANDOFF.md) remains evidence of the completed functional baseline.
Presentation and latency acceptance are reopened before P2 gameplay-feel signoff.

## Invariants and scope

Preserve `facets.prototype.v1` rule results, canonical state/event bytes, ordered
commands, stable IDs, RNG consumption and complete transaction failure behavior.
Preserve automatic upgrade chains before gravity. Normal actions still finish
in core before their first presentation await; no mid-cascade input in P1-A.
Keep the serial reference as a diagnostic mode and instant/skip as lifecycle paths.
Concurrent normal playback must become the default, not an optional workaround.

Reuse delivered gem assets and pooled views. No art-generation, optical, room,
economy or full BoardScene decomposition work is needed to restore basic motion.
Do not blindly restore old spatial grouping or flatten portal/diagonal paths.

## Batch A0 — reproducible action and motion evidence

Create a registered actual-action fluidity/performance check, separate from the
view-only delivery burst. Preserve current traces/checkpoints and report schema,
machine, Godot/build mode, package/source identities, warmup, seed selection,
sample counts and explicit completion marker. Keep all admitted corpus results,
including failures. Use the existing 100 seeds / 20 commands for rule latency;
separately measure legal-input enumeration, loading, frame time and playback.

Add small authored motion fixtures: L-shaped holes with unequal fall distances,
multiple supported stacks released together, a long column with refill, a
promotion-created pre-gravity chain, two disconnected cascade regions, diagonal
waterfall contention, a direction change and a portal landing. Reuse admitted
topology fixtures rather than inventing transport-room gameplay.

Exit: traces identify per-piece paths and visible phase boundaries; the current
serial reference demonstrates the scheduling defect; CPU stage and actual-action
frame measurements cannot be confused with asset probes. Save original state and
event checkpoints independently of future expectations.

## Batch A1 — presentation plan and concurrent journeys

Build a pure fact-to-presentation plan, consumed by ActionPlayer. Retain the full
stable-instance path and traverse it in order. Coalesce consecutive straight
travel into a continuous motion span; do not restart a curve at each grid cell.
Represent bends, portal departure/arrival, removal and spawn explicitly. Index
views by stable instance while motion is in flight, with cell maps updated at
defined visual milestones; one destination overwrite must not lose another view.

For the initial supported implementation, use conservative match/settle-wave
boundaries. Within a wave release independent stacks concurrently when support
clears; animate incoming stack journeys with spacing and correct path origins.
Read authored spawn direction/entry policy; synthetic off-board visual starts
must not create new rule spawns. Resolve path conflicts with occupancy/reservation
dependencies, not frame callbacks into core. For custom unsupported overlap cases,
use a documented conservative schedule while preserving every admitted path.

Use distance/curve pairs consistently. Start with the old coherent cubic profile,
zero decorative release stagger, and independently cancelable landing decoration.
Keep projected causal readiness distinct from decorative completion. Preserve
short-fall-before-long-fall ordering and no overtaking within a stack.

Exit: independent L-fixture stacks start in the same scheduled frame and short
falls land first; the long column's duration follows the longest dependent
journey, not total cell segments. All paths and identities are retained. The
chain fixture visibly promotes and chains before falling. Cross-wave early
clearing remains explicitly conservative unless proven safe in A4.

## Batch A2 — integrate and protect lifecycle

Make concurrent playback the production normal path while retaining serial and
instant test modes. Keep epoch cancellation and owner-token input gates. Every
spawn, movement, landing effect, cue and awaited continuation belongs to one
generation/action. Skip snaps once; restart/navigation cancels all pending work;
asset failure cannot be unlocked by a stale completion. Final views match both
committed identity and presentation properties, including alpha/scale and pools.

Exit: real-scene checks cancel during removal, short/long concurrent travel,
spawn, chain promotion and landing tails. No orphan view/tween, duplicate release,
late signal, repeated spending or wrong-instance hit occurs. Concurrent, serial,
instant and interrupted playback preserve identical authoritative checkpoints.
Record and inspect actual motion clips; screenshots alone cannot prove fluidity.

## Batch A3 — profile and reduce synchronous action cost

The review measured intermediate compatibility hashing as approximately 70% of
the resolver stage in a small sample. Audit every consumer of step `board_hash`
and remove/cache redundant computation where its meaning is unchanged; repeated
post-settle copies of the same hash are the first candidate. Preserve required
diagnostics and all authoritative state/event digests. Avoid rebuilding immutable
definitions and canonical map-key encodings unnecessarily. Profile again before
choosing deeper changes to settling, matching or allocation.

Separate external admission from internal invariant checks only after listing
the same required invariants, proving them with corruption/failure tests and
keeping full restore admission intact. Do not replace complete identity with a
partial board hash. Cache only genuinely immutable values or invalidate on every
mechanical mutation. A copied mutable Dictionary is not immutable by assertion.

Exit: rerun the 100-seed replay/midpoint corpus and exact canonical goldens,
topology/stress/termination cases, failure injections, legality and opening tests.
State and event digests match the preserved baseline. Report stage distributions,
complete `apply_action` p95/max, work/segment counts and allocation evidence where
instrumentation supports it. Do not relabel a changed sequence as optimization.

Retain the proposed ordinary 8×8 **p95 ≤5 ms complete-action target**, measured
on the named workstation in a declared build; publish debug and release results
separately. No silent target relaxation or claim that view-frame timing meets it.
If the target remains unmet, record the result and a concrete remaining-cost
assessment; request an explicit milestone decision before declaring full P1-A
latency acceptance. Threading is not the first repair: it adds publication,
snapshot and lifecycle complexity and does not fix serial visual scheduling.

## Batch A4 — optional overlap beyond a settling wave

Attempt only after A1–A3, if the conservative wave barrier still creates material
idle time. Derive a dependency graph that includes participants, cell/path
reservations, support and relevant empty-cell reads. Start the next committed
match once its prerequisites are visually ready, even if unrelated decoration
or proven-independent travel continues. Keep facts and RNG in canonical order.

Exit: an authored disconnected fixture shows a later clear during independent
travel; diagonal contention, shared portal exits and intersecting regions remain
ordered. Verify intermediate visible causality and stable identity, not merely
the final board. No transient visual alignment creates a new match. If the graph
cannot prove independence, retain the wave barrier and state that limitation.
A4 is optional for P1-A; it is not a back door to changing match-scan policy.

## Batch A5 — release acceptance and handoff

Run the registered gameplay/delivery integration checks appropriate to changed
files, clean package audit and actual-action release probe. Exercise accepted
swaps, invalid swaps, chain promotion, uneven/long falls, skip, restart, navigation
and delivery failure in the actual executable. Recheck source/package identity.
The existing view-only probe remains useful for delivered asset residency but
cannot replace this action probe.

Required evidence:

- Exact before/after rule checkpoint equivalence across the fixed corpus; no
  unexplained rejected commands, missing cases or cap truncation.
- Scheduled release times identical for simultaneously unsupported independent
  stacks; observed start skew no more than one rendered frame on the ordinary
  fixture. Paths continuous across straight cell boundaries, no overlap/overtake
  in the same lane, and short falls land before longer ones.
- Observed playback duration agrees with the dependency plan within a stated
  frame tolerance; report motion/clear/pause time separately. No per-cell serial
  waits across independent columns. Compare recordings on identical fixtures.
- Actual-action release frame p95 ≤16.7 ms as an initial presentation target;
  report maximum, number of frames over budget and input-to-first-motion latency
  as well. Include the synchronous commit frame; p95 alone can hide its hitch.
  Zero extra cold page loads in the declared warmed burst.
- Report the 5 ms action target independently. If a target fails, label the
  relevant gate open even when functional tests pass.
- Human review confirms coherent concurrent motion, readable promotion chains
  and predictable interaction. Record the tested build and feedback; no automated
  final-snapshot assertion substitutes for this review.

Handoff lists completed batches, retained whole-wave barriers, topology fallbacks,
all measurements, unresolved limitations and the next phase owner. Archive prior
active-plan revisions with verified checksums; preserve the frozen P0 baseline.
P2 data authoring can proceed, but do not accept first-room pacing on the current
serial player or attribute its wait time to the tactical design.

## Downstream amendments

| Phase | Change |
|---|---|
| P2 | Use accepted concurrent motion for room/tool playtests; separate decision time from forced waiting. Introduce effects without coupling their visual durations to rule order. Preserve one cost per accepted normal swap. |
| Optional trial after P2 room | Evaluate one explicit pre-gravity intervention window under a separate rules profile. First paused, then timed if useful. Approve economy, episode caps and prefix-commit behavior before implementation. Do not delay P1-A for it. |
| P3 | Keep family/reward caps and stable-save semantics clear. If the trial is adopted, version episode/subcommand/continuation identity, recording, failure and persistence before integrating it into the expedition. Otherwise retain current atomic contracts. |
| P4 | Finish art, audio, HUD decomposition, accessibility and timing polish on top of coherent motion. Optional deeper overlap must prove dependencies. Speed/reduced-motion settings remain cosmetic for v1. |
| P5 | Compare real action latency, input response, frame stalls, waiting and readability in release. A timed variant requires a separate accessibility/difficulty and replay assessment. |
| P6 | Extend the motion/path and interaction matrix to transport/asymmetric rooms. Moving-tile interception or logical-time gravity is a new scope decision, not an implied consequence of portals. |

No reactive command, new save field or mechanical timing policy is accepted by
this document. The optional trial's proposed defaults and adoption questions are
specified in the assessment so a later decision is concrete.
