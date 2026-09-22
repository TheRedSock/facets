# Merge-window successor acceptance specifications

Status: execution underway, 2026-09-22. These are the required fixture
specifications; [the readiness ledger](merge-readiness-status.json) identifies
implemented checks and outstanding release evidence. Implement and register checks during the
[successor goal](../../plans/P3_READINESS_SUCCESSOR.md). The
[owning contract](../../core/run/MERGE_WINDOW_PREPARATION.md) defines behavior.
Preserve existing P0/P1/P2 and trial goldens unchanged.

## Required witnesses

Each fixture records its admitted initial state, exact command transcript,
expected semantic outcomes and complete checkpoint digests. Hand-explain changed
outcomes before capturing successor vectors. Tests must assert their results,
not merely absence of exceptions. Use small hand-constructed boards for semantic
cases and seeded corpora for breadth. Proposed group names below become registered
stages only after their implementations and completion markers exist.

| ID | Witness and required result | Group |
|---|---|---|
| MW01 | Single legal equilibrium swap publishes exactly one complete merge batch, parks before any newly created match/gravity, and charges normal Work once. | kernel |
| MW02 | Two disjoint simultaneous matches resolve in canonical order in one batch with one board-wide window; survivor/component identity is fixed before reactions. | kernel |
| MW03 | Promotion makes an automatic match. Pass resolves it next without gravity and opens another window. | kernel |
| MW04 | The same promoted survivor can legally move out of that pending match into a hand-authored stronger match. Accepted intervention denies the original automatic match; only the new board's rescan resolves. Compare with MW03. | commands |
| MW05 | A legal match elsewhere is accepted; an unrelated invalid swap is rejected even though a pending automatic match exists elsewhere. Untouched pending matches belong to the new active move scope when subsequently resolved. | commands |
| MW06 | A constructed sequence supports at least four successive interventions, including a promoted-gem move and a remote match. Each legal command gets a fresh move ID, normal cost/turn accounting and a new window; no one-window cap. | commands |
| MW07 | Same occupied match neighborhood and resources in equilibrium versus a parked board with holes elsewhere produce equal default price/base effects. Only admitted context and resulting causal metadata differ. Empty, locked, stale and nonadjacent endpoints reject purely. | commands |
| MW08 | Where semantics are unchanged, passing all successor windows reaches the legacy board/resources/RNG under the explicit semantic projection. Deliberate early-terminal differences have hand-explained exact successor expectations, never projected-away board mismatches. Original P1/P2 and trial controls still match their own exact bytes. | compatibility |
| MW09 | No-input automatic batches share one Craft entitlement cap; repeated paid moves get fresh caps. Capacity-clipped entitlement is consumed, not reclaimed after spending. No duplicate awards at publication/replay. | accounting |
| MW10 | A tool-caused merge opens a swap window. Pass preserves tool suppression; paid intervention starts fresh normal eligibility/tool allowance without rewarding old tool facts. Tool commands themselves reject in a merge window. | accounting |
| MW11 | Intervention context propagates through its automatic descendants; direct-batch-only predicates exclude later cascades. A later paid move replaces active context while preserving earlier fact ancestry and room/run uses. | accounting |
| MW12 | Diagnostic intervention discount consumes a finite charge using integer units; ordinary moves retain base price. Diagnostic reward fires exactly at its declared scope. Missing charge, insufficient funds, stale quote and illegal move consume nothing. | accounting |
| MW13 | Last-Work completion wins before another decision. Zero-Work nonterminal state finishes required automatic work before loss. Holes never trigger recovery; recovery occurs only at equilibrium. No optional gravity/refill after terminal commitment. | kernel |
| MW14 | Technical cascade/chain/fact/work limits remain effective across automatic continuations. Injected failure discards the unpublished batch and reservation; prior published states/costs/facts remain intact. New paid moves reset only their specified scopes. | kernel |
| MW15 | New promoted identity and hit map exist on the first merge frame. A completed gesture before decoration ends can move it; live/ghost ownership remains correct through pooling, overlap and resize. Consumed ghosts cannot be selected. | playback |
| MW16 | Remote legal swaps work while another merge decorates. Accepted feedback begins promptly without a board-wide decorative wait; competing gestures cannot both consume the same window. | playback |
| MW17 | Receipt tick 19 accepts; tick 20 expires. Pointer-down at 19 and completion at 20 expires. An on-time receipt survives worker delay; invalid attempts do not reset or freeze the deadline. | clock |
| MW18 | Identical admitted transcript at 30/60/120 FPS produces identical mechanical checkpoints. Focus/stall pause, restore, reduced motion, practice and skip follow their explicit policies; assisted records cannot appear as unassisted performance evidence. | clock |
| MW19 | Default automatic-match speculation commits only on pass. On intervention its board, RNG, IDs, Work, Craft, facts and injected branch failure are discarded. Accepted intervention equals the synchronous non-speculative reference; selecting a failed default invokes the specified failure policy. | executor |
| MW20 | Default gravity/refill speculation has MW19 isolation, including RNG-consuming refills. Clock ticks do not invalidate its mechanical base or get overwritten by it; final publication binds the current decision/transcript digest. A cancelled speculative job yields promptly to paid input at the latest legal receipt tick. | executor |
| MW21 | Inject delayed, duplicate and wrong-generation completions across restart/menu/restore/room re-entry. None publish or touch freed views. Worker shutdown is bounded; repeated lifecycle cycles leak no jobs. | executor |
| MW22 | Commit state, charged cost, replay record and batch visibility atomically. Failures before/at publication never leave half a commit; provisional swap feedback visibly returns to the last committed board on failure. | executor |
| MW23 | Queue capacity never exceeds two committed batches plus one detached default candidate and one reserved command. Underflow holds a coherent state and records starvation; backpressure never crosses an unresolved decision. | executor |
| MW24 | Restore every committed phase, pending automatic match, gravity boundary and reserved-command snapshot; rebuild a reservation from its immutable command/base, never from serialized worker objects. Replay also covers multiple interventions, expiry, terminal and diagnostic failure. | persistence |
| MW25 | Corrupt/missing context, wrong profile, allocator collision, stale window and truncated transcript reject without live-state mutation. Preserve exact integers above 2^53 and complete RNG state. Altered assist/tick decisions change the relevant identity. | persistence |
| MW26 | P3 diagnostic dispatcher proves once-per-move/room/run scopes, source-family identity, live-target revalidation, tool suppression, intervention predicate and accounting coexist at batch boundaries. No full new family content is required. | p3_contract |
| MW27 | P3 extraction/room-completion policy, carry allocation and save/Continue schema explicitly accept or reject every new phase. Unsettled state cannot silently become an old equilibrium save. Future P3 fixture inventory is reconciled with reasons, not claimed executed. | p3_contract |
| MW28 | Swap-to-merge, gravity-to-merge, automatic-merge-to-merge and expiry-to-gravity meet the frozen end-to-end deadlines in the release corpus; queue, admission, hashes and publication are included. | performance |
| MW29 | Injected slow computation and cancellation exercise deadline recovery. Normal frozen workloads and required 2x-compute stress have zero starvation; intentionally excessive delays produce honest misses, closed input and later full-duration windows. | performance |
| MW30 | Actual packaged executable verifies keyboard/mouse, terminal/restart/menu, reduced motion, focus loss, repeated windows, automatic redirection and gravity default at both native display sizes. Package manifest matches tested source and delivered bytes. | release |

## Performance acceptance frozen at G0

The old complete-action 5 ms p95 remains a failed historical metric. It cannot be
relabelled as passing because a different subset is measured. Successor readiness
uses the following proposed thresholds, with end-to-end deadlines as the primary
responsiveness evidence. These are engineering hypotheses, not player findings.

Reference presentation is 60 Hz, 150 ms swaps, 333.333 ms merge windows and the
existing distance-dependent gravity profile with a 100 ms minimum. Record exact
configured durations and actual presentation boundaries. Do not lengthen them
after seeing benchmark results to manufacture a pass.

| Measurement | Required normal-profile exit |
|---|---|
| Valid completed gesture receipt to visible accepted/swap feedback | p95 <= 16.7 ms; maximum <= 33.4 ms |
| Total main-thread simulation admission/publication/scheduling time per active frame, including multiple callbacks | p95 <= 5 ms; maximum <= 16.7 ms; renderer time reported separately |
| Demand job ready for the next merge | p95 ready-latency / available interval <= 0.25; maximum <= 0.50; zero presentation deadline misses |
| Default next merge or gravity candidate | Validated candidate available by window expiry; zero starvation; expiry-to-visible next batch p95 <= 16.7 ms, maximum <= 33.4 ms |
| Native frame duration at 1280x720 and 1600x900 | p95 <= 16.7 ms; report p99/max and correlate stalls with input/commit telemetry |
| Required modeled 2x computation stress | Zero deadline misses/starvation with unchanged animation/window durations; report input and main-thread thresholds separately |
| Lifecycle and bounded memory | Zero residual workers/queues/views after teardown; no extra warmed-burst asset loads; retain existing payload budgets and report worker/snapshot peak memory |

For a swap, the available interval is gesture receipt to the scheduled start of
its merge animation. For a gravity follower it is gravity packet publication to
the scheduled following merge. Ready latency includes queueing, cancellation,
resolution, copying, internal validation, full encoding/hashes, main-thread
handoff and admission. Record scheduled deadlines before work; do not move them
when computation finishes late. Separately report time until feedback starts so
a delayed swap cannot inflate the apparent calculation allowance. Equilibrium
outcomes must also be ready by the end of gravity. A shorter actual interval is
the deadline; zero-motion gravity cannot borrow a nonexistent 100 ms animation.

Speculation starts only after the preceding merge candidate is available. Its
deadline is the current window's expiry, including publication and cancellation
arbitration. Measure earliest-window intervention as well as the latest legal
tick: the former can interrupt a busy default job. Default work that commits
before expiry is a correctness failure even if it improves timing.

Use three fresh repetitions of 100 fixed seeds for each applicable policy:
all-pass, first legal intervention, promoted-survivor chain, remote match, and
mixed near-expiry inputs. Give policy decisions a separate RNG stream. Cover
the existing P1/P2 boards and fixed mandatory semantic witnesses, including
recovery/tool/objective cases that ordinary policy runs might never reach.
Record counts by command and transition; a category with no samples is unmeasured.
Native gesture attempts must be attributed to explicit admission or rejection.
Only an admitted swap can start a swap-feedback sample; a rejected near-expiry
gesture cannot be timed against later gravity movement. Retain rejection codes
and attempted/accepted/expired counts, and fail unexpected rejection. Drain
completed main-thread frame records throughout a probe so ordinary-room bounded
telemetry cannot silently truncate its performance population.
Report p50/p95/p99/max, nearest-rank quantiles, raw intervals and every failed seed.
Warm-up is explicit and excludes no gameplay interval after the declared start.

Measure real release CPU/GPU runs on this i9-14900HX/RTX 4060 Laptop machine with
power mode, Godot version, load, source/build hashes and display profile recorded.
Repeat correctness under 30/60/120 FPS and varied worker completion schedules.
Required 2x stress injects extra delay equal to measured compute service time,
without sleeping the renderer, plus forced late cancellation witnesses. It is
a scheduling sensitivity test, not proof of performance on a particular weaker
CPU. Characterize 4x delay, 4x/8x bounded synthetic reaction load, shortened motion
and near-cap supported-board cases separately; do not present them as current P3
content or require ordinary-frame targets for intentional failure probes.

If a deadline, consistency or resource criterion fails, preserve the report and
identify its owner: admission, batch resolution, cancellation/queue, copy/codec,
publication or presentation. Correct the cause, rerun the failing witness and
affected controls, then repeat a fresh integrated release run. Do not discard
slow runs, loosen targets silently, skip complete hashes or add hidden animation
waits. If measured architecture cannot meet the frozen contract, record the
remaining failure and a concrete proposed contract change for review.

## Evidence and readiness

Every implemented group needs a registered completion marker, source-stable
fresh report directory and its intended assertions/counts. Exit zero alone is
insufficient. Existing checks run unchanged against their original profiles;
new versioned fixtures cover deliberate successor semantics.

Final readiness requires all MW01-MW30, performance exits, affected legacy
controls, integrated execution and an actual release lifecycle pass. Provide one
verified build and one optional sole-reviewer form explaining the new interaction
and automatic-match redirection. No human session or adoption questionnaire is a
technical gate. Player learning, reaction comfort and strategic quality remain
unverified until the user chooses to evaluate them.
