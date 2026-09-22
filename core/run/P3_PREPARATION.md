# P3 implementation contract

Current execution status: P3.1–P3.7 are implemented and checkpointed. Required
engineering exits pass on the [declared profile](../../tests/game/P3_FINAL_VERIFICATION.md).
See [the current evidence map](../../tests/game/P3_IMPLEMENTATION_STATUS.md).
The batch notes below preserve what each checkpoint established.

P3.1 implementation, 2026-09-22: separate `P3Content` and schema-4 rules/state,
bounded `FamilyDispatcher`, family accounting and source-family reactions are
implemented. `test_p3_families` executes these behavioral requirements; the
original preparation fixture remains a structural specification. A P3 family
room is accessible beside the unchanged controls. Later expedition/reward/save
batches and their release-load engineering exits were still open at that checkpoint.

P3.2: Aquamarine replacement and carry/ladder previews, Steady Hand effective
pricing with accepted-only room use, and Bridge's T4 target range are implemented.
Settings and uses are part of schema 4. P1/P2 bytes remain unchanged. Preview
conversion creates no gameplay facts and preserves supply. Reward selection and
room transitions are owned by subsequent batches, not this content helper.

P3.3: `ExpeditionState` owns briefing, current session, room outcomes, ordered
carry and detached entry publication. The opening generator preserves staged
IDs across retries with continuous RNG/allocation. Asset failure may reject a
prepared entry without changing the prior run. Selection decisions retain
global revisions/event/action IDs; room sessions start from that run identity.
Reward/route transitions and whole-expedition external admission follow in P3.5.

P3.4: typed schema-2 room objectives and unique delivery records are implemented
for P3 only. `ExtractionResolver` runs at equilibrium before recovery/exhaustion,
stops at demand and suppresses descendants. Merge windows retain outlet occupants.
`test_p3_extraction` executes the inherited P0 outlet fixture, gate/order/final-Work,
rollback and complete replay witnesses. The view marks outlets and delivery tiers.

P3.5: `P3Rooms` freezes all four authored definitions. Expedition selections,
persisted reward offers, both routes and final results are implemented with
complete external replay admission. Successful seed-7 command witnesses for
both routes are frozen under `tests/fixtures/p3_expedition_v1`; seed-1 first-swap
policy witnesses a real loss. `test_p3_flow` covers every reachable reward pair.
These establish reachability and deterministic execution, not player balance.

P3.6: `ExpeditionSave` implements bounded FAC1 payloads in a length/SHA-256
envelope, safe slots, verified temporary writes and last-known-good recovery.
Continue reports invalid/incompatible data or recovery explicitly and admits
the complete replay before replacing a run. All eleven committed phases,
reservation exactly-once resume, assisted timed restore, signed >2^53 values
and six interrupted-write points pass `test_p3_save`. Preferences remain separate.

P3.7 implementation: expedition controls support keyboard and mouse, retained
board/choice preview ownership, asset preflight, failure/retry and manual disk
Continue. A committed terminal batch publishes its expedition outcome before
the visual tail finishes. Saving such a boundary normalizes a detached snapshot
to carry/results without mutating the live run; admission rejects unnormalized
terminal saves. Presentation callbacks never determine the mechanical outcome.
Packaged lifecycle probes, named deterministic tuning and P3 content-load
measurement are separate tools; their measured exits are recorded in the status
map, rather than inferred from this implementation inventory.

Historical G5 reconciliation, 2026-09-22: the implemented incremental kernel, repeated-input
accounting, executor and streaming room now provide the resolution foundation.
Replay/restore and P3 seams are verified under the
[merge-window contract](MERGE_WINDOW_PREPARATION.md). G6/G7 engineering readiness
passes on the [declared profile](../../tests/game/MERGE_FINAL_READINESS.md).
At that checkpoint, families, rooms beyond P2, expedition and disk Continue were
specified work. Their later implementation is recorded in the batch notes above.
The earlier atomic specification is checksum-archived locally before this edit.
The old complete-action 5 ms failure remains historical evidence. The user is
the sole current reviewer; broader human evaluation remains deferred.

## Contract decisions

### Run ownership and identity

Reserve profile `p3-merge`, simulation `facets-sim-p3-merge-v1`, state schema 4,
replay `facets-replay-p3-merge-v1`, save `facets-save-p3-merge-v1`, content
`facets-p3-merge-content-v1`. These deliberately replace the unused atomic P3
reservations. Embed a versioned resolution session; do not reinterpret RunState
v2 as an unsettled expedition or silently load the old P3 proposal as this schema.
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

Phases: `briefing`, `ready`, `merge_window`, `gravity`, `reserved_command`,
`diagnostic`, `carry_selection`, `reward_selection`, `route_selection`,
`next_room_ready`, `results`. Reserved command is derived from an admitted ticket
over the last committed ready/window state; it is not a half-applied move.
Failure transitions to results
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
No target does not spend use. Upgrade-created matches resolve before gravity
only after their preceding window expires. A paid intervention can redirect them;
rescan the new board. Automatic continuations share family flags; a new paid move
receives fresh per-move uses. Corundum: replace the component's adjacent damage with 2;
do not schedule a separate extra one-point hit. Each component hits each frozen
target once, capped by its live durability.

Terminal T8 source-family eligibility comes from admitted metadata, never its
absence of a survivor. Quartz/Corundum can operate if such a source is authored;
Beryl cannot select without a survivor. Generic removal and subtype facts share
one removal ID and cannot double-pay. No prototype generic removal income.

Each paid move owns strongest base, raw bonuses, per-move family flags and
automatic work/fact/cascade/reaction limits. Expiry retains that scope. Each merge
settles only the newly earned increase in `min(3, strongest_base + raw_bonus)`,
clipped to capacity 6; already clipped entitlement is consumed permanently.
Room/run uses survive new paid moves; room uses reset on committed room entry.
All facts retain engine-derived equilibrium/intervention context, with a separate
direct-batch predicate. Sources use their frozen pre-promotion family identity.

Tools/setup/extraction descendants suppress family/Craft earnings without erasing
already committed gains. A new paid swap during a tool/extraction-caused merge
gets its normal fresh eligible scope. Tool commands remain equilibrium-only.
Failure rolls back the unpublished batch only; published board, costs, RNG and
replay records remain committed. Unpublished room entry/reward transactions still
retain their entire prior run on failure. Caps never silently truncate effects.

### Carry, reward and opening

Carry only remaining T4+ instances, at most two; extracted/removed IDs cannot be
selected. Preserve ID and tier, clear temporary locks/status/gravity overrides.
Selection order is recorded; staging uses authored cells (3,0), (4,0) in listed order. Apply
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
sharing the normal once-per-paid-move family budget. Supply stays T1–4 with weights
4/3/2/1; replacing the T5 roster entry does not introduce T5 into refill supply.

### Objectives and flow

Run: Open seam (16 Work, four 2-hit marked rubble) -> carry -> reward ->
two-card route -> chosen six-rubble seam (16 Work) or commission (16 Work,
three T3+ deliveries through two bottom outlets) -> carry -> reward -> Vault
(20 Work, two rubble gates near two outlets, one T5+ delivery) -> results.
All boards are 8×8. T6 Vault delivery earns cosmetic distinction only.

Typed objective admission: clear-marked-rubble or extraction with nonempty
outlet cells, minimum tier and positive demand. Outlets must be active reachable
cells, with explicit own-cell obstacle/lock requirements. Adjacent rubble gates constrain physical travel and do not invent remote locks. No dust/seal production
rooms; compatibility lock adapters do not imply complete seal lifecycle.

At a stable boundary, qualifying unlocked outlet occupants are removed in `(y,x)`
order, one unique removal identity and demand unit each. Stop immediately when
demand completes, before any further extraction/refill/hazard/recovery. Otherwise
settle/refill/match under inherited suppression within the same action and limits,
then evaluate again. Extraction is checked after all pending merges and physical
motion settle, before equilibrium input/recovery or Work-exhaustion loss. It does
not remove a gem during an intervention window. Extraction also runs
at the stable boundary on Begin for qualifying opening occupants, before the first
paid input (user-confirmed 2026-09-22). This free setup scope suppresses earnings.
Clear-rubble completion is checked
after a committed merge and may stop before gravity. A completed objective wins
on final Work. Completion immediately closes input and establishes the immutable
room outcome for carry selection, even if unused holes remain. Extraction is not
merge consumption or T8 recovery and cannot later be carried. Emit facts that
presentation can explain; scenes never count delivery independently.

### Committed-boundary saves and asset preparation

Save all eleven declared phases, including parked merge windows, committed
gravity states, reserved commands, diagnostic prefixes and carry/reward/route
decisions. Never save an unpublished candidate or speculative default. Complete
envelope: version/content identity,
catalog/rules, run/room identity, board/topology/objective progress, ordered carry,
settings and room uses, Craft/Work/entry bonus, complete streams and counters,
persisted offer/route IDs/order/selection, mechanical revision, move/batch/window
IDs, active context and entitlement, per-move/room/run uses, pending cursor,
accepted input ticket, window clock/assistance, complete ordered decision chain
and replay checkpoints. Accepted reservations resume exactly once from their
committed base; private candidates are recomputed. A restored timed window is
paused and assisted. No offline clock charge or rollback to an older equilibrium.
Presentation volume/mute/reduced motion are separate preferences.

`empty`/loading has no new admitted state to save. Synchronous publication cannot
be interrupted by a save callback; capture after it returns. Room `complete` and
`failed` map atomically to carry/results as applicable. Diagnostics preserve the
valid prefix and failure record with explicit recovery controls, not free replay
of an already committed move. The fixture package owns every phase disposition.

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
