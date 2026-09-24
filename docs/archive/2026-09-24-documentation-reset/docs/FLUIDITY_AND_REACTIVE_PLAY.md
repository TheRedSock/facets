# Fluidity, simulation timing and reactive play

Review date: 2026-09-14. This review records verified source behavior, a new
diagnostic and proposed work. No production runtime changed during this review.
The current game remains the untimed, atomic-action `facets.prototype.v1` subset.
The [P1 fluidity amendment](../plans/P1_FLUIDITY_AMENDMENT.md) reopens presentation
and performance acceptance; reactive play remains an experiment requiring a
separate rule decision. Earlier documents are preserved in the
[verified archive](archive/fluidity-review-2026-09-14/manifest.json).

Subsequent user decision: implement P1-A and **test the intervention window after
P2**. The [trial plan](../plans/P2_INTERVENTION_TRIAL.md) supersedes references
below to optional authorization: conducting the experiment is now required,
while adoption into the main game remains optional. Findings below describe the
pre-amendment implementation; current implementation evidence belongs in the
P1-A handoff rather than rewriting these historical measurements.

## 1. Was the regression planned?

The migration deliberately introduced a sequential reference player and disabled
unproven spatial overlap. That was a defensible correctness checkpoint. Making
that reference the normal player, with one awaited tween per one-cell movement,
was an overly conservative implementation and an inadequate final fluidity gate.
The user did not approve a large permanent reduction in physical coherence.
Basic concurrent falling belongs in P1, before judging the tactical room; it is
not dependent on P4 art, UI decomposition or sound production.

The earlier implementation did contain substantial motion design. The retained
[BoardScene helpers](../scenes/board/board_scene.gd) consolidate multi-step travel,
animate multiple tiles together, arrange incoming spawn stacks, overlap some
removal and falling work, and use landing bounce. `_build_async_timeline_groups`
also groups components and derives spatial dependencies. The
[AnimationSequencer](../scenes/board/animation_sequencer.gd) explicitly couples
duration to the gravity curve so different fall distances share an acceleration
profile. This is evidence of prior thought about fluidity, not proof that every
old overlap/path case was correct.

The current [ActionPlayer](../scenes/board/action_player.gd) instead:

- Awaits each individual gravity event, then starts the next tile/segment. An
  unrelated tile cannot begin while that tween runs.
- Calls `fall_duration(1)` for each event and does not apply the configured
  gravity transition/easing. Multi-cell journeys repeatedly restart their motion.
- Waits for the gravity list before spawning that step's new tiles. It does not
  restore the old full spawn journeys, removal overlap or landing treatment.
- Correctly owns cancellation, stale generations, skip and the committed final
  snapshot. These protections must survive the amendment.

This is primarily a playback scheduling regression, alongside a real computation
problem. Faster rule execution alone will not fix the serial falls. Conversely,
concurrent tweens will not remove the synchronous action-computation hitch.

The earlier plan specified profiling and a sequential correctness reference, but
did not specify an executable fluidity restoration milestone, meaningful
concurrency acceptance or actual-action frame profiling. The handoff's functional
success therefore overstates readiness for gameplay-feel assessment. Preserve its
test results; correct the milestone interpretation.

## 2. Evidence and performance limits

The [P1 handoff](../plans/P1_HANDOFF.md) reports 100 seeds / 2,000 accepted actions,
with **131.716 ms p95 and 313.257 ms maximum** for headless complete `apply_action`.
The proposed 5 ms p95 target was missed. That timing excludes animation/loading
and includes identity, validation and publication. There is no matched old/new
benchmark establishing a numerical regression ratio.

A new [detached stage diagnostic](../artifacts/game/fluidity-review/profile.gd)
ran seeds 0 and 1, 20 accepted commands each, then compared every state and event
digest with production `apply_action`: **40/40 exact comparisons, zero errors**.
Its [retained aggregate report](../artifacts/game/fluidity-review/profile.json) records the original measurements; its provenance note explains loss of the first diagnostic's per-action timing rows during P1-A. The original second diagnostic and full P1 corpus remain preserved. This first sample used Windows,
Godot 4.6.1 debug/editor headless execution. Stage means were:

| Stage | Mean ms |
|---|---:|
| Legal check, copies and swap | 0.838 |
| Resolution including intermediate board hashes | 31.374 |
| Phase determination and facts | 0.835 |
| Full snapshot re-admission | 5.089 |
| Fact projection and final board copy | 0.663 |
| State and event checkpoint hashes | 11.075 |

The subsequent real calls averaged 50.909 ms, p95 82.032 ms. These are a small,
warmed, ordered diagnostic sample, **not** a replacement for the 100-seed result,
a release benchmark or evidence that performance has improved.

An [instrumented copy of TurnController](../artifacts/game/fluidity-review/turn_profile.gd)
then timed its existing `board.compute_hash()` calls without changing their
results. The [second report](../artifacts/game/fluidity-review/profile-with-step-hashes.json)
again matched all 40 production checkpoints. Intermediate board hashing averaged
20.612 ms out of 29.249 ms in resolution (about 70% of that stage in this sample).
The physical-step loop hashes the same final settled board repeatedly. Each
compatibility hash invokes the full canonical board digest. Audit consumers and
remove redundant diagnostic work before rewriting gravity or matching. Final
authoritative state/event checkpoints remain required; optimize equivalent
encoding and immutable definition reuse rather than silently dropping identity.
Full re-admission is another measured cost; any trusted-state fast path needs
equivalent invariants and failure tests, with full admission kept at input/restore
boundaries. No allocation attribution was measured in this diagnostic.

The first sample's current-player fall schedule is separately computable from
the trace: `(gravity segments + nonempty spawn steps) × 0.2 seconds`. It averages
1.69 seconds, p95 3.2 seconds and reaches **11.2 seconds**, excluding swaps,
removals, upgrades and frame quantization. These are calculated tween durations,
not measured screen recordings. A longer logical journey should cost its own
travel duration, not the sum of every tile's serialized one-cell duration.

The previous package probe's approximately 9.5 ms frame p95 exercised delivered
gem views/upgrade clips, not real `apply_action` plus cascade playback. It cannot
establish fluidity or rule-computation latency. P1-A must measure those actual
paths. The new diagnostic initially hit a startup crash with the default log
location; an explicit workspace log path completed. Its instrumented draft had
a typed-array call error, corrected before the successful report. A certificate
store warning remained in the completed offline runs. Neither failed attempt is
counted as evidence, and no visual improvement is claimed from this review.

## 3. Independent visuals without visual authority

The two desired principles are compatible for the current game: the engine
resolves a complete action first, while presentation schedules a partial order
of visual work. A canonical sequence fixes rule evaluation, RNG allocation and
facts; it need not impose a global wait between every pair of animations.

For an L-shaped clear, release all newly unsupported stacks together once their
support is visually removed. Use coherent distance-dependent travel so short
falls land first and long falls continue. Preserve relative stack spacing and
continuous velocity across ordinary straight cell boundaries. The old cubic
duration curve models increasing acceleration, not constant Newtonian gravity;
it is a reasonable stylized baseline. A quadratic curve with square-root
duration can model constant acceleration. Do not mix one curve with the other's
duration formula. Default per-stack stagger to zero for simultaneous release;
decorative stagger must not recreate the serial delay.

The first amendment may retain a **whole settling-wave barrier before presenting
the next match**, while allowing concurrency within that wave. That is a visible
compromise on local responsiveness, not a dependence of rules on animation.
Automatic upgrade-created chains still occur before gravity: the inner match loop
in [TurnController](../core/run/turn_controller.gd) rechecks the promoted board
before invoking BoardSettler. Preserve and visibly demonstrate that behavior.

An advanced player could start a later match's clearing once its own participants
are visually ready while unrelated long falls continue. It may only present an
already committed match. The current rules scan again after full physical
settling; a temporary line formed en route is not a new legal match merely
because pixels align. If earlier arrivals should produce different matches,
survivors, supply draws or cascades, that is a rule change, not an animation
optimization.

Safe overlap needs more than endpoints or a shared parent ID:

- Track stable instances, full paths, cell entry/exit, destination reservations,
  spawn creation and removal/promotion prerequisites.
- Distinguish logical causality, visual path conflicts and cosmetic completion.
  A squash/bounce tail need not block the next logically ready effect.
- Account for negative dependencies: an empty cell or absent neighboring match
  may be relevant. Shared diagonal destinations, portal exits and changed support
  can couple apparently separate columns.
- Do not flatten a bent path into a straight line or interpolate across a portal
  as ordinary travel. Reuse the admitted path and explicit traversal kind.
- Use a conservative wave barrier when independence is not established. The
  current single-parent fact envelope and old touched-cell grouping do not prove
  arbitrary cross-wave independence.

Canonical fact order and RNG stay unchanged. A presentation plan may carry extra
dependencies, but it is a projection, not an alternate simulation. Final view
equality alone is insufficient: paths, identity, occupancy and visible causal
order must also be checked.

## 4. Reactive moves: validity, precedent and fit

Player-built chains during clearing/falling are an established and viable puzzle
mechanic. The original author's [Tetris Attack/Puzzle League chain demonstrations](https://www.slack.net/~ant/tetris_attack/)
show swaps after a triggering match starts, including a suspended-stack window
and moving a panel into a later chain. This is firsthand gameplay evidence, not
documentation of Facets' rules or proof that every related title behaves alike.
[Nintendo's Puzzle League description](https://www.nintendo.com/en-gb/Games/Nintendo-64/Pokemon-Puzzle-League-269657.html)
also identifies Skill Chains. [Panel Attack's own site](https://panelattack.com/)
describes falling chains and rollback multiplayer, demonstrating that interactive
chain play and deterministic recovery are compatible in a shipped implementation.
Its networking claims do not establish suitable performance budgets for Facets.

The general mechanic is not unique. Combining it with persistent promoted gems,
survivor placement, Work scarcity, family builds and extraction could give Facets
a distinctive tactical use for it. Novelty of that combination and fun are
unproven. Likely benefits are player authorship, a higher skill ceiling and fewer
passive waits. Risks are obscured planning, attention split between builds and
fast input, cascading misclicks, accessibility costs, easier reward loops and a
shift away from the chosen untimed expedition. Test whether it creates useful
choices rather than rewarding frantic extra swaps.

The user's example is a good authored test. Make ordered input end at `(2,3)`
when that cell is meant to survive the initial match; survivor selection is
direction-sensitive under the current command convention. After promotion and
all automatic pre-gravity chains, if that instance remains eligible, swapping
it from `(2,3)` to occupied, movable `(1,3)` could join same-tier `(1,4)/(1,5)`.
Explicitly construct the board/support state: the example alone does not prove
the piece is physically unsupported. If the upgrade already makes an automatic
match, that chain wins before any offered window. Do not accidentally add swaps
into empty cells, arbitrary nonmatching swaps or intervention on a consumed gem.

## 5. Three different engine commitments

| Mode | What is authoritative | Prediction and replay | Cost / recommendation |
|---|---|---|---|
| Atomic turn with concurrent visuals | Current ordered discrete resolver | Entire action known before playback; current replay unchanged | Implement P1-A now |
| Explicit intervention boundary | Resolver pauses at an admitted phase for one optional command/pass | Prefix committed; continuation conditional until decision; replay records window identity and decision | Prototype as a separate optional rule mode |
| Freely reactive falling | Logical clock, piece states, reservations, deadlines and input order | Advance only as far as known inputs; replay tick/substep input stream and complete pending state | Major engine/game pivot; defer until experiment justifies it |

Determinism does not require timeless rules. A clocked model can simulate integer
ticks or jump between discrete scheduled events faster than real time. It must
define tie ordering for arrivals, matches, input and expiry. Pixels, Tween
completion and render frame rate must never decide those outcomes.

However, three promises cannot all hold: arbitrary cosmetic timing changes,
outcomes determined by those visual arrival times, and one irrevocable final
board computed before unknown player interventions. If a visible delay changes
which match occurs, its relevant duration belongs in versioned mechanical state.
Purely cosmetic effects can still vary independently around that logical timing.

### Recommended bounded experiment

After P1-A and the first P2 room, optionally build a small isolated trial before
freezing P3 reaction/save contracts. First use an untimed explicit decision window
after automatic promotion chains and before gravity. Permit at most one
intervention per original action, only involving an eligible surviving promoted
instance and another eligible stationary grid occupant. No moving-tile picking,
tools, portals or diagonal interception in the first experiment. Pass resumes
the original continuation. This isolates tactical value; it cannot establish
whether time pressure is fun. Then compare a visible timed window on the same
fixtures if the untimed choice is worthwhile.

Proposed initial economy: an accepted intervention costs one additional Work,
with no refunds, no new tool allowance and no intervention when remaining Work
is zero. One original action plus its intervention is one resolution episode for
Craft gain caps, family activation limits and scheduled hazards. New Craft is
spendable only after episode settlement, not at the internal window. This is an
experimental policy requiring approval, not a reinterpretation of frozen D06.
Compare alternatives only as explicit profiles; do not silently grant free moves.

Proposed commit model: commit validated segments up to the window, then transact
the next command/pass on that continuation. Keep the committed prefix on later
failure, enter an explicit diagnostic phase and offer restart; never partially
publish a failed segment. This deliberately differs from v1's whole-action
rollback, and needs its own tests and version. A speculative no-input continuation
may be cached, but must not consume authoritative RNG, publish facts, award
resources or become the board that player input targets.

Window commands reference episode, window/revision, piece IDs and ordered cells.
Reject stale presentation or replacement-instance input. For an untimed trial,
window identity plus ordered decisions is sufficient; no wall-clock timestamp is
needed. A timed trial additionally needs an integer logical deadline and admitted
input tick/substep, including expiry/pass outcomes and a defined late-input rule.
Pause, speed controls, reduced motion, focus loss and queued input require named
policies. Reduced motion may change decoration; it must not secretly lengthen a
ranked timed window. A paused/untimed accessibility mode is a legitimate separate
experience, not evidence of identical challenge.

### Architectural support worth retaining now

Keep the core/view separation, stable piece/phase IDs, explicit match-before-
gravity boundary and typed commands. Keep action publication owned by the run
controller and allow a future resolver-owned continuation interface. Do not add
unused clocks, pending queues or new canonical fields in P1 merely for possibility.
Current `step_cascade` is a playback adapter after full resolution, not a resumable
simulation API. Supporting intervention will require real refactoring there.

For the experiment, continuation identity must include board/RNG/allocators,
phase, episode budgets, pending work, window eligibility and any logical time.
The existing stable-only restore schema rejects such states. Either implement
complete admitted continuation snapshots or explicitly allow saving only at
episode settlement; do not expose Continue at an unsupported window. New command,
simulation and replay versions must distinguish the mode from v1. Full moving
input additionally needs logical occupancy versus visual position, in-flight
eligibility, reservations, support changes, collision/conflict policy and bounded
event scheduling. A deterministic timeline is possible; unrestricted prediction
of unknown future choices is not.

## 6. Decisions and adoption gate

Current direction: repair P1 fluidity/performance while keeping v1 atomic and
untimed. Architecturally preserve the option; do not build a general real-time
engine or commit the main prototype to reflex play.

Before authorizing the optional trial, decide its role (optional challenge or
main mode), window policy (paused first, then timed comparison), cost/reward scope,
eligible pieces and commit/failure behavior. The proposals above provide concrete
defaults. Exact timed duration and tie rules require a playtest profile, not an
accidental animation constant. Adoption into the main expedition requires an
explicit design decision and updated frozen-baseline successor, never edits to
the original freeze.

Test paired fixtures for intentional intervention, pass equivalence, automatic
chain priority, exhausted Work, stale input, near-cap failure and family/resource
accounting. Record opportunity frequency, successful deliberate choices, rejected
or mistaken inputs, decision time, wait time and player preference. A 3–5 player
qualitative trial can reveal confusion and appeal, not establish broad demand.
Require players to explain the benefit and preserve a useful planning experience.
If the mechanic is rare, unreadable or mostly frantic, keep it outside the main
mode. P1-A is valuable regardless of that decision.
