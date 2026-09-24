# Post-P2 intervention-window trial

**Current disposition, 2026-09-21:** the engineering trial is implemented and
verified; see [the protocol](P2_TRIAL_PROTOCOL.md) and [closeout journal](P2_CLOSEOUT_JOURNAL.md).
The user deferred human sessions, potentially until after P5, and requested one
build/form. Decline production adoption for this P3 milestone, retain the
isolated comparison for later evaluation, and keep atomic production. This is
not a finding about player preference. The requirements below are the original
trial plan; its human-session gates are superseded by that explicit amendment.

Status: **required experiment, authorized by the user on 2026-09-14**. Execute
after P2's first tactical room, before freezing P3 reaction/persistence contracts.
Adoption into the main expedition is optional and requires reviewing the trial.
This is downstream work; it does not introduce reactive input during P1-A.
See the [design assessment](../docs/FLUIDITY_AND_REACTIVE_PLAY.md) for rationale
and the [overall phase plan](../docs/PROTOTYPE_BUILD_PLAN.md) for dependencies.

## Trial boundaries and initial policies

Use a separately versioned experimental RuleSet, command and replay mode. Preserve
the untimed atomic expedition as the control. Do not modify the original P0
freeze. Experiment profiles are recorded with every result.

- Offer at most one intervention per normal-swap resolution episode, after all
  automatic upgrade-created matches resolve and before the next gravity pass.
  No offer when no surviving promoted instance has an eligible matching swap.
- The intervention must involve that surviving promoted instance and an occupied,
  movable, stationary orthogonal neighbor; it must create a new match involving
  a swapped piece. No empty-cell swaps, tools, in-flight selection or portal/
  diagonal interception. Automatic chains retain priority over player input.
- Charge one additional Work for an accepted intervention. Invalid input/pass
  costs nothing. Zero remaining Work suppresses the offer. No refunds.
- Share the original episode's Craft-gain cap, family activation scope and one
  scheduled hazard boundary. No refreshed tool allowance; newly earned Craft is
  spendable only after full episode settlement. Preserve inherited suppression.
- Commit a validated prefix up to the window, then transact the decision and
  continuation. A failed segment does not publish; the committed prefix remains
  in an explicit diagnostic state with restart available. Bound work/facts/chains
  across the entire episode, not freshly for every segment.
- Record episode/window/revision, ordered cells and stable piece IDs. Reject
  stale/replaced-instance input. Pass follows the same no-intervention continuation
  as the control, including RNG and final state, allowing for explicit mode IDs.

These are implementation defaults for the bounded trial, not a decision about
the eventual game's economy. Any variant must be named and tested separately.

## Batches and exits

**T0 — freeze the trial fixtures and protocol.** Construct the promoted survivor
at `(2,3)` and the intended `(1,3)/(1,4)/(1,5)` match explicitly. Include an
automatic pre-gravity chain that consumes the would-be intervention opportunity,
an ineligible/occupied target, zero Work, one Work remaining, no opportunity,
stale input and a near-cap continuation. Freeze input ordering and episode
accounting. Exit: expected transitions can be explained without animation.

**T1 — paused decision-window control.** Extract a real resolver continuation;
the existing playback step adapter is not sufficient. Run only to the boundary,
display that authoritative state, accept one intervention/pass, then resolve the
continuation. Any precomputed no-input branch is detached speculation and cannot
consume authoritative RNG or publish rewards. Exit: complete in-memory boundary
snapshot/restore and replay equivalence, invalid-command purity, prefix/segment
failure tests, shared caps and explicit stable-only disk-save policy.

**T2 — timed comparison.** Compare the paused trial with visible 400 ms and
800 ms windows as initial hypotheses, using integer logical time. Define a
60-tick-per-second clock and deadlines of 24/48 ticks for these profiles; commands
at tick < deadline are eligible, at tick >= deadline expiry wins. Assign each
admitted input a tick and sequence number. Rendering samples the logical state;
Tween completion never decides acceptance. Begin the window only once the
boundary is presented, with the resolver parked and logical window clock at zero.
This explicit presentation handoff does not alter the board or extend an already
running deadline. Window start, decision and expiry are recorded.

Pause/focus loss freezes the experiment's logical clock and is recorded; exclude
paused attempts from unassisted reaction-time comparisons. Cosmetic reduced
motion preserves the deadline. Do not offer animation-speed controls that alter
window length in these timed profiles. Exit: replay the same accepted input/tick
stream under 30/60/120 render FPS, injected frame stalls and reduced motion with
identical outcomes; test deadline ties, queued/stale input, pause and expiry.
If frame stalls make selection misleading, surface it as a trial failure and
revise the clock/presentation policy before player evaluation.

**T3 — paired player evaluation.** Use the same authored opportunities across
atomic control, paused intervention and both timed profiles. Run 3–5 initial
qualitative sessions; counterbalance order to reduce simple learning effects.
Record opportunity frequency, meaningful successful choices, mistakes/rejections,
Work/Craft consequences, decision time, forced waiting and player preference.
Include users who prefer planning over speed. Require players to explain why
they intervened; extra clicks alone are not evidence of depth. Test timing even
if the paused version is preferred, so the reaction-based idea receives an actual
comparison. Do not claim broad demand from this small trial.

**T4 — decision and handoff.** Publish build/profile identities, fixtures,
determinism/lifecycle results, recordings and player findings. Choose explicitly:
adopt into the main mode, retain as an optional challenge, revise and retest, or
decline. Carry forward identified engine seams even if gameplay adoption is
declined. Only adoption changes P3's production continuation/save/reward scope.
Complete the experiment and document its decision before treating this task as
closed; “optional mechanic” does not mean “optional testing.”

## Deferred beyond this trial

Unrestricted moves while pieces fall, timing-dependent transient matches,
multi-window chains, tools during resolution and transport interception require
a broader logical event/occupancy/reservation model. They are not implied by
this trial or by P6 transport rooms. Any production timed mode needs a separate
accessibility/difficulty decision and performance acceptance.
