# P1 — verified implementation plan

Reviewed and implemented 2026-09-14. Status: functional batches and declared
checks complete; the proposed 5 ms simulation p95 target was not met. See
[P1 handoff](P1_HANDOFF.md) for exact evidence and limitations. The user selected fixed swap cost, bounded playable openings and
the full required foundation topology tests during this review.

Build P1, with the corrections below. The existing board/resolver stages are a
useful base; authoritative legality, complete state and transaction ownership
must be repaired before rooms and family reactions depend on them. P1 ends with
the existing animated board using those boundaries. It does not establish that
the three-room game is fun, balanced or complete.

## Authority and review evidence

The [P0 decisions](../docs/P0_BASELINE.md) own frozen mechanics. The current
[build plan](../docs/PROTOTYPE_BUILD_PLAN.md),
[architecture addendum](../docs/ARCHITECTURE_HARDENING.md) and
[lifecycle contract proposal](../docs/CONTENT_SYSTEMS.md#7-lifecycle-events-and-deterministic-reactions)
own the intended implementation boundaries. The addendum explicitly brings raw
layout admission into P1 and requires extra topology fixtures. Its later date
resolves the older B11 scheduling discrepancy; this is not an unresolved choice.

This review inspected those authorities, game design, source review, integration
and delivery contracts, fixture data, relevant presentation/engine documentation,
current simulation/orchestration/UI callers and the registered validation tools.
Archived documents were not re-audited; their historical proposals do not override
the current freeze/addendum. No optical or mineral-source reassessment is claimed.

New evidence is retained in
[artifacts/game/p1-review-20260914](../artifacts/game/p1-review-20260914/):

- Six registered stages passed: import, source_check, test_smoke,
  test_rng_cross_platform, test_board_consumer and test_run_delivery.
  [Stage results](../artifacts/game/p1-review-20260914/baseline-checks.json).
- Smoke: **113 passed, 0 failed**, with its completion marker. These assertions
  exercise current behavior; they do not accept the proposed P1 repairs.
- The existing six-case diagnostic was copied into the review artifact directory
  without changing its original. All six defect flags reproduced; the final
  invocation passed the result classifier and completion check.
  [Probe](../artifacts/game/p1-review-20260914/probe.json),
  [gate result](../artifacts/game/p1-review-20260914/probe-result.json).
- tests/test_check_result.ps1 passed all 10 classifier cases.
- All 19 frozen manifest files and the current fixture bytes match P0; HEAD
  matches. Of 823 source-manifest entries, only AGENTS.md and README.md differ,
  consistent with the documented root-guide rewrite.
  [Integrity results](../artifacts/game/p1-review-20260914/baseline-integrity.json).
- Initial sandboxed import/probe attempts encountered Godot cache/certificate
  access errors. Normal-environment retries passed; the failed attempts are not
  counted as passes. No new release build, GPU timing, human playtest or second
  operating-system comparison was performed.

Existing working-tree edits to AGENTS.md, README.md and project.godot, and the
untracked frozen fixture directory, were present before this review. Preserve
them. The frozen P0 checker itself was not rerun because it writes its historical
report; the checksum comparisons above were performed separately.

## Reassessment of the four original decisions

| Decision | Verified recommendation | Reason and status |
|---|---|---|
| Topology breadth | Retain the nine small P1 fixtures and bounded 16×16 stress coverage. | User selected. Existing source and smoke tests already support custom gravity, portals, holes and tile overrides. Versioning their scheduler while omitting positive trajectory/contention tests leaves the repaired contract unverified. Transport rooms and production transport UI remain P6. |
| Move economy | One fixed-cost policy: every committed normal swap costs 1; no refunds. | User selected. Bring this small D06 migration forward from P2. Craft, tools, room budgets and win/fail precedence remain P2. A named policy does not require a second implementation. |
| Batch order | Define state/content/event contracts early; implement legality, then settling, then freeze codec/checkpoint goldens, then integrate the transaction. | Adopt a qualified reorder. Delaying final byte goldens is sensible; delaying all B03 work until after settling is not. Stable IDs, detached content, RNG ownership and event shape are dependencies of settling. |
| Save/replay | Full in-memory snapshot/restore and versioned replay for all P1 state. Atomic save files and Continue remain P3. | Adopt. Include decoder admission and incompatible-version rejection now, even without disk I/O. A digest alone cannot restore a run: replay must carry the initial snapshot plus admitted mechanical definitions, or resolve an exact immutable content package. |

The original “both economies” recommendation is optional comparison scope, not a
P1 requirement. GAME_DESIGN allows retaining the legacy policy only as an explicit
balance-harness comparison; it does not require building that comparison now.
Remove duplicated refund calculations from current callers. Do not describe the
P1 checkpoint as a complete implementation of facets.prototype.v1: it implements
that rules target only for the P1 feature subset.

An additional consequential decision was resolved with the user: move the
no-carry part of D17 opening generation into P1. Generate at most 64 candidates,
accept only a physically stable, match-free board with a legal swap, and report
invalid content on exhaustion. No free opening merges. Carry staging and
mid-room low-tier reshuffle recovery remain P2/P3.

## Corrections and omissions in the supplied plan

Direct source anchors for implementation review (function names are stable
references; current line numbers are recorded here only as evidence):

| Claim | Source at review |
|---|---|
| Duplicate action paths, late accounting, layout loss | [RunController](../core/run/run_controller.gd): start_new_run 23, reroll_board 68, begin_swap 89, finalize_swap 144, attempt_swap 160 |
| Mutation/query/hash boundaries | [BoardState](../core/board/board_state.gd): swap_cells 90, move_tile 107, get_effective_gravity 136, apply_layout 164, compute_hash 206 |
| Portal matching / incomplete components | [MatchDetector](../core/board/match_detector.gd): _collect_run 54; [MatchClassifier](../core/board/match_classifier.gd): classify 7 |
| Silent settling / occupied entry fallback | [BoardPhysics](../core/board/board_physics.gd): resolve_gravity 18, find_spawn_eligible_cells 118 |
| No-match exit / chain and cascade caps | [TurnController](../core/run/turn_controller.gd): step_cascade |
| Catalog and progression fallbacks | [SpawnResolver](../core/board/spawn_resolver.gd): _spawn_tile 69, _weighted_pick_int 84; [EffectResolver](../core/board/effect_resolver.gd): apply |
| Incomplete state and event identity | [RunState](../core/run/run_state.gd): to_dict 17; [EventLog](../core/rules/event_log.gd): push 11; [SeededRng](../core/rules/seeded_rng.gd) |
| Playback gates / duplicated bot legality | [RunScene](../scenes/run/run_scene.gd): _on_swap_requested; [simulation harness](../tests/test_simulation.gd): _find_best_swap |

The major defect descriptions are supported by source. In particular:

- RunController's two swap paths check only bounds/budget before mutation and
  accept any resulting match; BoardState.swap_cells silently rejects immovable
  occupants. A distant or ineffective swap can therefore be accepted. Matching
  follows portal-aware neighbors without a traversal bound; classification pairs
  runs instead of finding complete intersecting components.
- Board hashing omits dimensions, portals, spawn/fill configuration and several
  cell/tile values. Status values are ignored and status keys follow insertion
  order. RunState serialization omits the board, supply and RNG position.
- Spawn eligibility confuses “no empty entry” with “no configured entries”.
  TurnController exits on no match before doing needed physical work and accepts
  cascade/chain caps silently. BoardPhysics silently returns after its cap.
- Rule services obtain TileRegistry through the scene tree and permit debug or
  malformed-weight fallbacks. EventLog shallow-copies payloads and derives IDs
  from retained length. Accounting/checkpoints occur after animation with no
  once-only guard. RunScene has competing private input-lock writes.

Important qualifications and additions:

1. BoardState.move_tile already returns bool. Its missing immovability check and
   cross-caller capability consistency are the issues; do not claim it returns
   void. swap_cells does return void.
2. Aquamarine's resource points to Alexandrite, but EffectResolver can replace
   that target with the run's selected tier-6 definition. The stale pointer is
   not proof that every live Aquamarine upgrade produces Alexandrite. Replace
   this two-source progression logic with the active roster directly.
3. Refill's empty-array fallback exists in BoardPhysics's eligibility query;
   SpawnResolver.refill_spawn_entries itself iterates the supplied array despite
   its misleading comment. Empty eligible lists must remain empty end to end.
4. There are **five**, not four, validate_action fixtures. Twenty cases have at
   least one P1 observation; that does not mean twenty fully passing cases.
   Craft, seal removal and recovery outcomes need explicit per-field deferrals.
5. Reroll currently drops the chosen layout. Preserve the admitted layout,
   roster, rules and supply when creating the next seed's board.
6. tests/test_simulation.gd independently mutates boards to probe swaps and
   duplicates the refund calculation. Migrate it to the shared action query and
   committed results; do not preserve it as a second legality implementation.
7. Existing UI dependency grouping is spatial. New canonical facts require a
   sequential reference projection; adding IDs does not prove the old grouping
   safe. Full BoardScene decomposition remains P4b.
8. Explicit static tile-gravity overrides already exist. Retain their query and
   movement behavior, validate their directions, include them in state identity,
   and conservatively check possible travel edges for termination. Do not add
   dynamic gravity-changing effects in P1.

## Scope and concrete contracts

### Admission and state

Compile raw BoardLayoutResource and gameplay definitions into detached immutable
records. No resource or Node references enter the simulation. Start with simple
complete scans and copied mutable state; share only definitions whose immutability
is enforced. A mutable dictionary advertised as immutable is insufficient.

Use one admitted starter roster (D01), supply targets T1–T4 and integer weights
4/3/2/1. Admit an alternate T5 Aquamarine roster in tests, without reward UI.
Roster[tier + 1] owns promotion. Tier matching uses the admitted active tier;
reject inconsistent definition/tier combinations. Keep detection/classification
separate from merge outcomes; matching connects intersecting runs, not every
adjacent same-tier tile or merely touching parallel runs.

Introduce only concrete policies: orthogonal line matching, canonical survivor
selection, roster promotion, fixed action cost, integer supply, local fill,
legacy scan and bounded opening generation. Unknown policies reject. Initial
board budget can remain the demo's configured 20; 16/20 room-specific budgets
arrive with RoomDefinition in P2. Internally use resource.action_budget; the
existing “Moves” label is compatible with neutral mechanical IDs.

Raw admission validates types and bounds before allocation/application: dimensions
1–16 on each axis, nonempty active mask, canonical coordinate keys, duplicate
references/IDs, cardinal gravity (ZERO as fallback), valid local fill offsets,
portal fields/endpoints/directions, entries on active cells, supported policies,
roster completeness and valid supply. Nonnegative weights need a positive bounded
sum and at least three positively supplied tiers; total fits the signed 32-bit
sampler range. Reject invalid values rather than silently correcting them.

Return code, severity, resource ID, field path, implicated cells/edges and message
key. Layout reachability diagnostics respect local fill and blocked cells;
geometric reachability alone is not a solvability proof. An occupied valid spawn
entry is not an invalid layout. It simply cannot spawn yet.

Keep holes, occupants and movement restrictions separate. A minimal lock record
or capability owner must block swap/gravity while permitting matching; fixture
seal records exercise that capability without shipping seal damage/removal.
Do not reinterpret a seal as an unmatchable tile or topology hole. Preserve or
explicitly migrate existing status fields. Reject unsupported production
capabilities (for example an unimplemented protective effect) instead of promising
they work because a boolean exists. No rubble durability, floor effects or family
handlers are needed in P1.

### Legal actions and ownership

can_apply_action is pure: no live-state mutation, RNG consumption, event emission
or ID allocation. Validate command shape, bounds, distinct cells, active ordinary
orthogonal adjacency, occupancy, movement/lock capability, logical phase/budget
and actual newly created matching involving a swapped cell. A virtual swap view
or detached scratch board is sufficient. Existing unrelated matches cannot grant
legality; unchanged same-tier swaps cannot do so either.

enumerate_legal_swaps returns deterministic **ordered** commands. Preserve both
A→B and B→A where legal: their occupancy exchange is identical but their preferred
survivor can differ. Sort by origin then destination flat cell ID. UI geometric
selection does not replace this query; bots/hints consume it too.

Sort matched members by ascending (y,x); components by their smallest member cell
ID, with stable match key as a tie-breaker. Merge intersecting runs transitively.
First match batch prefers destination then origin, else greatest (y,x); all later
match batches use greatest (y,x), including pre-gravity upgrade chains. T8 removes
all members with terminal-recovery facts and no promoted/consumed survivor.

### Settling and openings

Version legacy_scan_v1: primary movement, then local fill, both bottom-to-top and
right-to-left, mutating in place. Preserve declared fill-source order. A tile can
move repeatedly in a scan; record its actual segments. Gravity is tile override,
then nonzero cell gravity, then DOWN, reevaluated at each visited cell. Match/swap
neighbors use active local orthogonal adjacency; gravity alone follows directed
portal overrides. Local fill never acquires portal adjacency accidentally.

Use explicit fill_empty_cells and entry_only policies. Eligible spawn iteration
uses canonical row-major order; normalize authored entries at compile time.
Changing fill-source priority is mechanical; changing dictionary insertion order
is not. Settle gravity to rest, refill eligible empties, and repeat until neither
movement nor spawning is possible. Then detect matches. Resolve all upgrade
chains before the next gravity phase. “Stable” does not require every cell filled:
an entry-only pocket may be unreachable or blocked by an immovable occupant.

Admit only acyclic conservative travel graphs. Fill edges run from source to
destination, so mixed gravity/fill cycles must be checked in that direction.
For static tile overrides, include each admitted override direction at each cell
it could visit; conservative rejection is acceptable and reported. Runtime
repeated-state detection applies at a fixed physical phase with identities and
movement-relevant state, not just a tier grid. Any match/spawn loop also has a
total-work guard. A failed transaction consumes no committed RNG, IDs or budget.

Initial proposed guard values are the existing 256 settling scans, 50 cascade
batches and 20 additional pre-gravity chain batches, plus 64 opening candidates.
Give every counter exact increment/boundary semantics. Add a total action-work
ceiling of 1,000,000 counted cell visits/effect applications and 100,000 retained
facts/path segments. These are proposed safety limits, not measured needs; verify
them against the corpus before freezing protocol v1. At a limit, allow a bounded
quiescence check to distinguish completion exactly at the limit from remaining
work. Never silently enlarge a limit to hide an admitted failing case.

Generate openings on detached candidates from explicit integer draws using the
board stream. Stabilize physical occupancy without resolving matches; reject a
candidate if any matches remain or no legal swap exists. Advance the candidate
stream across attempts (do not reset to the same seed for every attempt). Allocate
initial IDs deterministically for the accepted candidate; failed candidates are
not published. Exhaustion preserves any previously committed session. Record
attempt count and accepted RNG states; no setup payout. Tests may construct
intentionally unresolved fixtures directly without the opening generator.

### IDs, facts, snapshots and replay

Use per-session monotonic instance/action/event/removal counters, persisted in
the snapshot. Fixture IDs have a fixture namespace plus row-major initial index;
spawned IDs cannot collide. Promotion preserves instance ID. Rejected/failed
actions publish no IDs or facts; candidate allocator changes are discarded.

Specify the envelope before implementing producers: event_id, root_action_id,
parent_event_id, causal depth, phase/round/component, cause and inherited reward
eligibility, plus applicable instance IDs and immutable source/old/new snapshots.
Use an explicit null parent for roots; every other parent must already exist.
Do not implement a generic reaction dispatcher in P1.

Canonical action order is: root command/cost reservation; the two ordered swap
journeys; assist (only the swapped helper absent from all initial components);
ordered component facts and outcomes; subsequent pre-gravity match batches;
physical movement/spawning; later match batches; one action_settled. Each batch
reads a frozen source snapshot. For each removal emit one TileRemoved fact and,
for merge consumption only, a TileConsumed subtype referring to that removal ID;
then promotion with old/new identity. Record T8 recovery by tier/definition without
counting it as outlet delivery. Disjoint components cannot double-own an instance.

A TileMoved fact represents one uninterrupted journey, with every actual segment
and its physical sequence/phase retained. Assign journey order by first segment
occurrence; a spawn fact precedes its instance's first journey. Coalesced journey
envelopes can span interleaved movement of other pieces, so the segment sequence
remains available for occupancy-dependent playback. The envelope is a completed
journey fact, not a new live microstep callback. A later logical effect or match
phase starts a new journey. Projection must preserve spawn/movement and vacated
cell dependencies; flattening by event type is only a statistics view.

Canonical snapshots include dimensions/active topology, transport/fill/spawn
policies, cells/tiles/status values/locks, immutable mechanical content and roster,
supply, budget, logical phase, introduced recovery records/counters, allocator
positions, master seed and all stream seeds/states, schema/rule/protocol IDs.
Exclude scene state, debug log retention, selection, animation time, vocabulary,
textures, paths to presentation assets and optical grade data. Removed obsolete
fields need a documented migration, not a claim that every historical property
must forever be hashed. Shared immutable definitions are covered by exact content
bytes/digest; changing a definition changes effective state identity.

Codec: explicit tags, fixed schema field order, signed 64-bit little-endian
integers, one-byte booleans, bounded UTF-8 lengths, bytewise-sorted map keys, sorted
sets and order-preserving arrays. Reject unknown/duplicate fields as specified by
schema, truncation, overflow, unsupported types and excessive counts before
allocation. SHA-256 canonical bytes; no engine hash or JSON number round-trip.
Test negative/boundary integers and values beyond 2^53. JSON transport, if used,
encodes 64-bit values as validated canonical decimal strings.

Keep SeededRng and capture/restore seed followed by state. Introduce the four
literal streams board/rewards/routes/recovery using the addendum's exact
facets-stream-v1 SHA-256 derivation and fixed vectors. Only board is consumed by
P1 gameplay; the other stream states still round-trip. No float draws in gameplay.
Record Godot/RNG implementation identity; no old-demo sequence compatibility.

Replay contains the initial stable snapshot and admitted content (or exact
resolvable immutable package), rules ID, schema/simulation/RNG/settling versions,
ordered accepted commands, per-action state and ordered-event digests. Restore
validates all references, unique IDs and allocator bounds before publishing.
Malformed snapshots or unsupported versions leave the live session unchanged.
Disk slot names, atomic replacement, last-known-good files and Continue are P3.

### Transaction and playback

apply_action revalidates against the current state/revision, resolves on detached
state/RNG/counters, verifies bounded completion and invariants, then publishes
state, facts and accepted command/checkpoint exactly once. Distinguish legality
rejection from resolution failure. Return pre/post view snapshots, ordered facts,
digests and explicit result codes. Preview success does not reserve a future move.

The complete transaction, including the one-point cost, commits before the first
accepted-swap animation awaits. No renderer callback spends budget, emits rule
facts, finalizes a checkpoint or rolls back committed rules. UI retains its own
pre-action view state; it must not read already-final occupancy to infer movement.

Replace begin/resolve/finalize callers together where practical. If a temporary
adapter remains, it holds one action handle/result and does not resolve again;
finalize becomes acknowledgment only and repeated acknowledgments are harmless.
Reject stale handles by session generation/state revision. Identical coordinates
later may be a new action; do not use them as an idempotency key.

Compose public loading/playback/modal/error gates and generation tokens. Releasing
playback never releases an error/loading gate. Cancel/skip snaps to the committed
snapshot; restart/menu invalidate every outstanding playback/load completion.
On resolution failure, retain the pre-action board and show a diagnostic with
restart/menu access. Zero budget prevents further swaps. A stable board with no
legal swaps is reported explicitly in the P1 demo, with manual reroll/restart;
it is not yet P2 automatic recovery or the final room board_locked outcome.

Keep pooled views and existing delivered clips. Implement a sequential projection
for the new facts. Preserve spatial overlap only if dependency tests establish
equivalent final views; otherwise disable that mode during migration. Core portal
journey fixtures and projection data tests belong in P1; polished transport-room
visuals do not. Prefetch from the admitted roster and its actual reachable
progression, not stale static merge_target_id chains. Keep board_changed for
start/reroll only. Full UI decomposition and production HUD/theme remain later.

## Implementation batches

These seven bounded batches replace the supplied plan's “five batches” numbered
0–5. Each batch updates its adjacent contract and runs its relevant checks. Final
P1 acceptance requires the integration batches; an early partial batch is not P1.

| Batch | Implementation owners and deliverables | Completion evidence |
|---|---|---|
| 0 — Harness and protocol outline | tests/game/fixture_adapter.gd, explicit assertion disposition, registered test_game_rules/state/transaction stages; state-field/ID/event/order inventory in adjacent contracts. Capture baseline and preserve frozen inputs. | Adapter rejects unknown phases/expected keys; no silent skip; registry classifier tests and retained smoke baseline. |
| 1 — Minimal state/content seam | Pure RuleSet/GameCatalog/layout schema under resources/definitions and core/rules/board; bootstrap compilation; detached copies, stable allocators, RNG capture/stream bank; starter roster and explicit supply in data/game/rules. Replace scene lookups/fallbacks in resolver/spawner. | Strict malformed-content tests, roster promotion including Aquamarine→Emerald, clone isolation, exact RNG restore/derivation vectors. No final whole-state byte goldens yet. |
| 2 — Legality and match ownership | core/rules action/legality service; BoardState purpose/capability queries; detector/classifier/planner repairs; ordered action enumeration. Migrate bot query use. | Frozen legality/match observations plus out-of-bounds, budget/phase, pure-query, newly-created-match, directed survivor and touching-but-not-intersecting tests. |
| 3 — Admission, settling and opening | core/board layout admission/compiler, BoardPhysics/SpawnResolver/TurnController; adapt tools/board_validator.gd; explicit policies/failures, segment paths, deterministic 64-attempt openings; reroll retains admitted configuration. | Frozen physical observations, all nine additional fixtures, static tile-override tests, graph cycles, cap boundaries, invalid raw entries, impossible openings and 16×16 envelope/oversize rejection. Local resolver failure must already be explicit; full session rollback is accepted in batch 5. |
| 4 — Canonical codec and restore | core/rules canonical_codec, RunState snapshot/restore, separate content/rule/presentation identity, versioned replay records; schema and byte/event vectors finalized after producer fields are known. | Field-mutation matrix, insertion-order independence, ordered-source sensitivity, exact integers, decoder corruption/version rejection, clone aliasing and restore continuation. |
| 5 — Atomic action and application adapter | core/run/action_transaction plus RunController; EventLog/Timeline fact projection; fixed cost; all command/allocator/checkpoint publication centralized; RunScene/BoardScene public gates, view snapshots, cancellation and sequential playback; bot consumes committed accounting. | Failure injected after swap, promotion, RNG draw/spawn and at each cap restores complete pre-state; accepted actions commit once before playback; acknowledgment/skip/restart/stale callbacks cannot mutate rules or unlock an error. Retained delivery tests extended. |
| 6 — Replay, packaged checkpoint and handoff | ≥100 fixed seeds with ordered commands/checkpoints; headless/restore/UI presentation equivalence; package export/audit entries; owning guides and current phase plan updated with actual evidence. | All registered suites pass; clean package audit/probe, focused actual-release interactions, explicit scope and remaining P2/P3 fixture deferrals. |

Update export_presets.cfg and tools/audit_game_package.gd as runtime paths land.
data/game is currently absent from the audit's allowed roots. Run the final clean
package only after the integrated checkpoint is ready; do not discover missing
class/resource ownership for the first time in the release handoff.

## Exact frozen-fixture disposition

All 23 fixture bytes/IDs remain unchanged. Report **fully verified**, **partially
verified** and **deferred** separately, with every expected field assigned an owner.
The intended P1 coverage below is a target, not a result of this planning review.

| Cases | P1 assertions | Deferred assertions |
|---|---|---|
| match_3 | All first-match expectations | None |
| match_4, match_5 | Component size, survivor, promotion, removal count | base_craft_candidate → P2 |
| match_l, match_t, multi_intersection | All snapshot/component/survivor expectations | None |
| distant_swap_rejected, same_cell_rejected, empty_swap_rejected, blocked_swap_unrelated_match | All rejection and unchanged state/RNG expectations | None |
| locked_swap_rejected | Rejection/unchanged state through explicit lock capability adapter | Seal content and damage are outside this query |
| locked_gem_matches | Matching participation, component size and survivor | seal_removed_before_merge → later seal implementation (P6) |
| occupied_spawn_entry | Empty eligible list under explicit entry_only fixture adapter | None |
| entry_refill_settles | Full lane, spawn origins and setup root cause | None |
| portal_not_match_adjacency, zero_gravity_fallback | All named query expectations | None |
| status_value_hash, portal_hash | All state-identity expectations | None |
| recovery_possible, recovery_impossible | legal_swaps_before; witness remains frozen data | Recovery multiset/resource/result/state-preservation behavior → P2 |
| first_action_win, last_action_win | None of the full-action acceptance claim | Complete action including rubble/objective/Work/win precedence → P2 |
| outlet_delivery | None of the extraction acceptance claim | All outlet/carry/completion outcomes → P3 |

This yields **15 fully observed cases, 5 partial cases and 3 deferred cases** if
all P1 targets pass. The lock rejection result establishes the adapter-backed
capability, not seal lifecycle acceptance. Mapping work/craft aliases and explicit
entry_only policy in the adapter does not change frozen bytes. Unknown expected
fields must fail the inventory check rather than disappearing.

Retain all nine additional B04 fixtures: irregular mask with supported pockets;
sideways-to-down turn; upward zone; directed portal landing; two-source contention;
immovable occupant above an entry; local diagonal fill beside a portal; mixed-edge
cycle rejection; no-match refill filling a lane. Freeze meaningful states, ordered
IDs/path segments and RNG observations, not just “terminated”. Add match-source
family preservation and cross-family promotion with a synthetic admitted catalog;
shipping family handlers/metadata remains P3.

Map each of the existing 113 smoke assertions to retained behavior, intentional
change or replaced coverage. In particular, the old cycle-cap smoke only checks
boundedness; it must be supplemented/replaced by explicit failure and rollback
expectations. Do not keep unsafe behavior merely to preserve a pass count.

## Final verification and handoff

Register test_game_rules, test_game_state and test_game_transaction as bounded CPU
stages with their own CHECK_COMPLETE markers and nonzero failure exits. Dedicated
presentation tests may be added if they have a separate completion contract. Run
only relevant subsets during batches, then the integrated command:

```powershell
& ./tools/check_engine.ps1 -Only import,source_check,test_smoke,test_rng_cross_platform,test_board_consumer,test_run_delivery,test_game_rules,test_game_state,test_game_transaction,test_game_replay,test_game_playback
& ./tests/test_check_result.ps1
& ./tools/build_game_package.ps1 -AssetPack generated/gem-assets.pck -Probe -FrameBudgetMs 16.7
```

All five game stages are registered and the integrated command passed; see the
[handoff](P1_HANDOFF.md) for the final report and additional replay/playback stages. Keep the existing optical registry
unchanged except for additive game entries. A stage passes only with its required
marker and result classification; timeout/exit-zero errors do not pass.

Use a checked-in ≥100-seed manifest. For each seed, create an admitted opening,
select commands by a deterministic policy independent of gameplay RNG, and record
ordered commands and every state/event checkpoint. Compare uninterrupted runs,
fresh replay and restore at stable action boundaries. Stop at budget exhaustion
or an explicitly reported no-legal-swap condition; do not silently discard failing
seeds. Exercise rejected commands and forced failures separately. Test animation
skip/cancel/acknowledgment using the real application adapter; compare a controlled
action corpus under sequential and instant playback. Merely running the pure
resolver twice does not verify the UI boundary.

Measure ordinary 8×8 simulation latency separately from animation/loading; report
p95, maximum, work/segment counts and cap failures. Use the proposed ≤5 ms p95 as
a target to assess, not evidence already earned. Measure 16×16 stress separately;
it is a bounded correctness/convergence envelope, not a 16×16 production UX or
5 ms performance guarantee. Change protocol limits only explicitly before freeze,
with the corpus rerun. No optimization by changing contention or event order.

The package probe exercises the exact exported PCK using the editor binary. Also
exercise the actual release executable for start, valid/invalid swap, budget
exhaustion, skip/cancel or navigation during playback, restart and delivery error.
Record which paths were automated/manual. Do not label probe frame timing as
actual-release ETW evidence or repeat unrelated optical acceptance work.

P1 is complete only when the animated board uses one transaction, admitted
openings/configuration survive restart/reroll, failure is atomic, the canonical
codec/restorer and replay corpus pass, the frozen assertion ledger is accurate,
and the clean packaged checkpoint meets its declared checks. Update adjacent
core/board, core/rules and core/run contracts plus tests/tools guides and the
current prototype plan with actual results. Preserve all frozen historical files.

P2 then owns RoomState, room budgets/Work completion precedence, Craft, rubble,
tools and automatic recovery. P3 owns family/reward/route/carry/extraction systems
and complete on-disk expedition persistence. P4 owns the full UI split and art;
P6 owns transport rooms and seals. No additional product decision is blocking
this P1 plan; numeric guards and exact wire constants remain implementation
choices to test and freeze, not unverified support claims.

## Implementation closure

All batches 0–6 are delivered. The [handoff](P1_HANDOFF.md) supersedes prospective
status statements in this review and records final owners, exits, 100-seed replay,
release interaction, performance and scope. The historical source-review anchors
above describe the pre-implementation baseline. Opening generation uses bounded
local weighted rejection (64 draws per cell, 64 candidates, shared work limit),
then physical/match/playability checks. The canonical EventTimeline projection and
synchronous cancellation wake-up were added during final playback verification.


