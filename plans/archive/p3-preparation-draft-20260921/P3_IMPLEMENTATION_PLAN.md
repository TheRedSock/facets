# P3 implementation package — preparatory draft

Status: draft during P2 closeout. Final readiness depends on the engineering
ledger; no P3 runtime feature or successful human evaluation is claimed here.
User amendment: sole reviewer, one build/form; broader human evaluation deferred,
potentially until after P5. Atomic production is the default. Trial adoption is
deferred, so production saves and reactions use whole atomic actions.

## Contract decisions

### Run ownership and identity

Reserve profile `p3`, simulation `facets-sim-v3`, state schema 3, replay
`facets-replay-v3`, save `facets-save-v1`, content `facets-p3-content-v1`.
Codec FAC1, `facets-stream-v1`, `legacy_scan_v1`, matching and survivor policies
remain unchanged unless implementation finds a concrete incompatibility.
Support legacy P1/P2 in their original entry paths with exact frozen snapshots
and checkpoint vectors. Never silently migrate unsupported save/replay versions.

`ExpeditionState` owns catalog/rules, run identity, current room index/definition,
board/carry, settings, entry bonus, phases, monotonic revision and action/event/
removal/instance allocators, complete streams, persisted offers and chosen route.
Use a single run namespace and instance allocator across rooms; no reset to
`piece/1`. A room view may point at the current board but cannot own this history.
Every accepted boundary command records revision, stable IDs, complete state/event
digests and any choice IDs. Invalid/stale commands are pure rejection.

Phases: `briefing`, `ready`, `carry_selection`, `reward_selection`,
`route_selection`, `next_room_ready`, `results`. Failure transitions to results
with an explicit reason; completion of a nonfinal room enters carry selection.
No gameplay input during selection. `confirm_carry` accepts zero, one or two
ordered eligible IDs; `choose_reward`, `choose_route`, `enter_room` consume
persisted choices. Final room goes directly to results, with no extra reward.

`start_room` remains standalone P2. P3 `enter_room` is a transaction over the run,
retaining streams, allocators and command history, publishing a distinct room
snapshot only after preparation succeeds. Restart-expedition returns to the
original admitted expedition and resets history explicitly. Restart-room is a
development diagnostic that restores a recorded room-entry checkpoint and
truncates to its replay cursor; label it as such, not a free in-run tool.

### Family dispatch and accounting

Curated P3 metadata: T1 Quartz and T2 Amethyst -> Quartz; T5 Sapphire and T7 Ruby
-> Corundum; T6 Emerald and replacement T5 Aquamarine -> Beryl. Other entries
have no prototype reaction. Do not edit P1/P2 catalog defaults to add these tags.

Freeze each batch's source identities, component footprint, survivor ID and
adjacent obstacle IDs before applying base effects. Ordered base outcomes emit
their existing removal/consumption/promotion facts. Dispatch typed intents by
phase priority, source event ID, scope ID, reaction ID; then revalidate live
targets and emit applied/skipped reasons. No arbitrary script callback language.

Quartz: first eligible source-family match reserves +1 raw bonus and its one-use
flag. Beryl: choose the lowest tier eligible orthogonal live gem next to the live
survivor, breaking ties `(y,x)`; range T1–3, or T1–4 with Bridge. Revalidate ID,
tier and eligibility at application; only a committed promotion spends use.
No target does not spend use. Upgrade-created matches resolve before gravity,
sharing family flags. Corundum: replace the component's adjacent damage with 2;
do not schedule a separate extra one-point hit. Each component hits each frozen
target once, capped by its live durability.

Terminal T8 source-family eligibility comes from admitted metadata, never its
absence of a survivor. Quartz/Corundum can operate if such a source is authored;
Beryl cannot select without a survivor. Generic removal and subtype facts share
one removal ID and cannot double-pay. No prototype generic removal income.

One ActionContext tracks strongest base, raw bonuses, family-used flags and all
work/fact/cascade/reaction limits. Final eligible gain is
`min(3, strongest_base + raw_bonus)`, then clipped to capacity 6. Track and emit
base, raw bonus, capped award and actual gain independently. Tools/setup/
extraction descendants suppress family/Craft earnings. Suppressing a later
continuation does not erase legitimate earlier candidates. Technical cap failure
rolls back the entire production action; it never silently truncates effects.

### Carry, reward and opening

Carry only remaining T4+ instances, at most two; extracted/removed IDs cannot be
selected. Preserve ID and tier, clear temporary locks/status/gravity overrides.
Selection order is recorded; staging uses authored cells in listed order. Apply
reward replacement before generating the next board. A carried T5 Sapphire
becomes Aquamarine with the same ID/tier, no gameplay trigger and a shown preview.
Room entry Craft = `min(6, max(1,min(3,previous Craft)) + next_room_bonus)`;
consume the one-time bonus only when entry commits. Reset Work, tool allowance
and Steady Hand's room use; preserve expedition settings and roster.

Use the existing board stream continuously for opening attempts. Reserve all
carry IDs before new allocation; each retry preserves the staged pieces and
only repopulates surrounding cells. Reject duplicate, occupied, blocked or
insufficient staging cells before RNG use. Require no setup matches and at least
one normal legal swap, within 64 attempts. Failed preparation preserves the
entire prior run including RNG, bonus and displayed selections. Setup gives no
Craft/family/arrival rewards. Freeze all four concrete room definitions before
capturing reference replays; staging cells and outlet gates are authored data.

Reward pool, in stable ID order before deterministic shuffle:
Aquamarine replacement (if not already selected), Steady Hand (if unowned),
Beryl Bridge (if unowned), +1 next-room Craft (one fallback candidate per screen).
Emerald is already in the starter ladder, so Beryl Bridge is eligible before
Aquamarine. After any first choice at least three candidates remain; test all
four choices and every second-screen combination. Sample three distinct legal
offers without replacement on the rewards stream and persist IDs/order once.
Reopening/reloading does not draw. No repeated fallback to fill empty slots;
an insufficient pool is a content error, not a duplicated reward screen.

Steady Hand's first accepted Chisel in a room costs 1 instead of 2; invalid or
canceled previews do not spend it. Bridge affects only Beryl's target range,
sharing the normal once-per-action family budget. Supply stays T1–4 with weights
4/3/2/1; replacing the T5 roster entry does not introduce T5 into refill supply.

### Objectives and flow

Run: Open seam (16 Work, four 2-hit marked rubble) -> carry -> reward ->
two-card route -> chosen six-rubble seam (16 Work) or commission (16 Work,
three T3+ deliveries through two bottom outlets) -> carry -> reward -> Vault
(20 Work, two rubble gates near two outlets, one T5+ delivery) -> results.
All boards are 8×8. T6 Vault delivery earns cosmetic distinction only.

Typed objective admission: clear-marked-rubble or extraction with nonempty
outlet cells, minimum tier and positive demand. Outlets must be active reachable
cells, with explicit admitted gate/lock requirements. No dust/seal production
rooms; compatibility lock adapters do not imply complete seal lifecycle.

At a stable boundary, qualifying unlocked outlet occupants are removed in `(y,x)`
order, one unique removal identity and demand unit each. Stop immediately when
demand completes, before any further extraction/refill/hazard/recovery. Otherwise
settle/refill/match under inherited suppression within the same action and limits,
then evaluate again. A completed objective wins on final Work. Extraction is not
merge consumption or T8 recovery and cannot later be carried. Emit facts that
presentation can explain; scenes never count delivery independently.

### Stable saves and asset preparation

Save all seven stable phases, including pending carry/reward/route decisions.
No mid-action disk save in production. Complete envelope: version/content identity,
catalog/rules, run/room identity, board/topology/objective progress, ordered carry,
settings and room uses, Craft/Work/entry bonus, complete streams and counters,
persisted offer/route IDs/order/selection, revision and replay cursor/checkpoints.
Presentation volume/mute/reduced motion are separate preferences.

Use canonical bytes inside a bounded checksummed envelope. Validate magic,
length/checksum/version/content and full state before changing the active run.
Write a safe-slot temporary file, flush/close, read/admit it, then replace with
last-known-good recovery. Inject failures at each step; preserve a valid prior
slot or recovery copy. Reject traversal names. Continue reports corruption or
incompatibility explicitly; it never silently starts fresh or rerolls offers.
Test signed RNG integers above 2^53 and interrupted/truncated writes.

Preflight all reward/carry/roster roles before finalizing a choice; retain old
board views during transition until cancellation/commit releases them. Exercise
both boards and choice previews as live page owners. Failed/retried loads keep
displayed choices and last committed run/RNG unchanged. P3 UI/FX/audio additions
follow accepted P2 material cues; their audition is distinct from mechanics.

## Implementation batches and exit witnesses

| Batch | Work | Required verification before checkpoint |
|---|---|---|
| P3.1 | Separate content profile, bounded family dispatcher and accounting | Frozen source-family promotion, Quartz once/cap/clipping, Corundum replacement/dedup, Beryl tie/no-target/revalidation/induced chain, T8 and suppression, shared-cap rollback |
| P3.2 | Aquamarine, Steady Hand, Bridge and previews | Old controls unchanged, full ladder/metadata, carry conversion IDs, effective costs, accepted-only use, exact range, no hidden supply changes |
| P3.3 | Expedition state, run-wide allocation, carry/staging and entry transaction | Zero/one/two carries, stale/duplicate IDs, failed load/opening rollback, retries preserve carry, monotonic IDs, complete history and streams |
| P3.4 | Typed extraction objectives and suppressed continuation | P0 outlet fields, threshold/blocked gates, ordered candidates/stop-at-demand, last Work, no double removal/carry/recovery award, one script witness per objective |
| P3.5 | Four rooms, rewards/routes and complete run flow | Every reachable reward pair and both routes; persisted offers, no RNG on reopen/rejection; complete success/failure replays |
| P3.6 | Incremental stable save schema/atomic file operation and Continue | Restore every stable phase, >2^53 integers, incompatible/corrupt/truncated save, interrupted writes and recovery, live-run preservation |
| P3.7 | Integrated keyboard/mouse UI, delivery preflight and tuning runner | Release lifecycle matrix, overlapping page ownership, family/tool/extraction explanations; deterministic named seeds/policy output; review material |

Build functional views alongside each batch; P3.7 integrates rather than defers
all presentation. Each checkpoint includes focused regressions and affected
legacy controls. Final integrated run uses immutable source/package manifests,
completion markers, full replay checkpoints, actual executable release probes
and both native display sizes. Do not reuse a P2 latency pass under expedition
load; repeat CPU/frame/memory measurements. Human learning, difficulty, feel and
reaction preference remain explicit deferred debt under the user's review policy.
