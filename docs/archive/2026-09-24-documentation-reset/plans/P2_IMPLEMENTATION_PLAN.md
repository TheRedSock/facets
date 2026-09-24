# P2 implementation plan — one tactical room

**Historical planning boundary, 2026-09-21:** B0–B6 are implemented; commands labelled proposed/not runnable below describe the original planning state. Current runnable checks are registered in `tools/engine_checks.json` and documented in `tests/game/README.md`. Current closeout work, deferred human review policy and fresh evidence are in [the execution journal](P2_CLOSEOUT_JOURNAL.md). Preserve the source findings below as dated review evidence.

Status: **implementation underway, 2026-09-14**. Current evidence and remaining gates are recorded in [P2_HANDOFF.md](P2_HANDOFF.md). The original planning review below did
not itself implement P2, rerun checks, certify a package, or close
P1-A acceptance. The requested build-plan path resolves to
[docs/PROTOTYPE_BUILD_PLAN.md](../docs/PROTOTYPE_BUILD_PLAN.md).

The outcome is the first mechanics proof: an 8×8 **Open seam** room, four marked
two-hit rubble cells, 16 Work, Craft, three tools, deterministic recovery and real
win/fail/restart flow, using the existing delivered gems and concurrent playback.
The required intervention experiment follows this room and precedes the P3
contract freeze. Its adoption into the expedition remains a separate decision.

Implementation checkpoint, 2026-09-14: P1/P1-A committed as `95a02f7`; B0
policy freeze committed as `5e71dcb`. B1–B4 simulation is implemented and passes
16 registered stages, including the unchanged 2,000-action legacy corpus and a
new 100-seed / 1,194-action mixed room corpus (4,355 assertions, 77 complete,
23 failed). Evidence: `artifacts/game/p2/simulation/`. This combined simulation
checkpoint closes the interdependent transaction/state/tool/recovery boundary;
B5 playback is committed as `e46ecc3`; workshop presentation/package work as
`f746c05`. The third resonant material sound set was accepted by the user and
promoted on 2026-09-14. B2 human seed vetting, B7 player acceptance and T0–T4 remain
open. The inherited CPU and player-feel gates remain open. Current release and
audio checkpoint evidence is recorded in the handoff and tracked checkpoint ledger.
## 1. Authority, review basis and boundaries

Read the following in this order when implementing:

1. [P0 decisions](../docs/P0_BASELINE.md) and the frozen
   [fixture contract](../tests/fixtures/game_prototype_v1/README.md): target rules,
   not permission to change frozen expectations.
2. [Phase plan, P2](../docs/PROTOTYPE_BUILD_PLAN.md#p2--prove-one-tactical-room),
   [game design](../docs/GAME_DESIGN.md) sections 6, 8 and 10, and
   [content systems](../docs/CONTENT_SYSTEMS.md) section 7: room/economy semantics
   and causal ordering.
3. [P1-A handoff](P1A_HANDOFF.md), [P1 handoff](P1_HANDOFF.md), and the current
   [run](../core/run/CONTRACT.md), [rules](../core/rules/CONTRACT.md),
   [board](../core/board/CONTRACT.md) and
   [playback](../scenes/board/CONTRACT.md) contracts: implemented boundaries.
4. [Architecture](../docs/ARCHITECTURE_HARDENING.md),
   [presentation production](../docs/PRESENTATION_ASSETS.md),
   [integration](../docs/GAME_ENGINE_INTEGRATION.md), and
   [delivery](../core/delivery/CONTRACT.md): placement, assets and packaging.
5. [Intervention trial](P2_INTERVENTION_TRIAL.md): required downstream experiment.

The documentation index, source rewrite review, gem art review, engine readiness
summary, fluidity assessment, fixture ledger, game test guide, registered checks
and packaging sources were also consulted. Optical production details and the
historical concept archive do not add P2 scope. This is a targeted gameplay review,
not an exhaustive optical-engine audit.

Source basis: the current local working tree on HEAD
`6aa7da1e58126495669046a6efa77bbe65924ea6`. Substantial P1/P1-A files are modified
or untracked, so that commit alone does **not** identify the reviewed implementation.
Before implementation, capture current source hashes and working-tree status;
preserve unrelated edits and the original P0/P1 evidence. Existing handoff timings
are previous measurements, not new measurements from this review.

### Scope and precedence decisions

| Topic | P2 direction |
|---|---|
| P1-A dependency | Proceed on delivered concurrent playback. Keep the 5 ms complete-action p95 and player feel gates open; P2 completion cannot silently waive them. |
| Older review prose | The rewrite review describes pre-P1 defects. Current code/contracts and P1-A handoff supersede its claims about current legality, hashing, HUD polling and serial motion. |
| Families | P2 establishes inherited eligibility and action accounting. Quartz, Corundum and Beryl handlers remain P3, despite the broad P0 backlog's “P2–P3” dispatcher row. |
| Seals | Preserve movement-lock queries; Chisel can exercise the existing lock representation in focused tests. Full adjacent-match/sealed-member lifecycle and authored seal rooms remain P6. |
| Objectives | Only clear marked rubble ships. No outlet collection, carry, rewards, routes, settings or multi-room persistence. An outlet drawing primitive is presentation-only. |
| Presentation | Keep the existing ActionPlayer/MotionPlan as owners; do not create a competing TimelinePlayer merely because older design prose uses that name. Extract only responsibilities needed by P2. |
| Saving | Complete P2 in-memory snapshot/restore and replay are required. Save slots, disk-save UX and Continue remain P3. |
| Trial | T0–T4 are required after the room. No window clock, reactive input or prefix commits enter the ordinary P2 mode. |

## 2. Source findings that determine the implementation

| Current owner / verified behavior | P2 implication |
|---|---|
| `ActionTransaction.resolve` accepts `SwapCommand`, swaps, deducts one move, resolves, then re-admits the complete candidate. | Retain this publication boundary; dispatch typed root actions and reserve their distinct costs inside it. |
| `RunController.can_apply_action`, `apply_action`, replay capture and `ReplayRecord.verify` all assume swaps. | Generalize the command boundary and parser together. UI-only tool handlers would bypass replay and rollback. |
| `RunState` schema 1 admits exactly `ready`, `budget_exhausted`, `no_legal_swaps`; it infers phase using only swaps. | Introduce room/economy state and one shared stable-boundary evaluator that understands tools, objectives and recovery. |
| `RuleSet.admit` requires the exact P1 key set and policy strings. | New fields or policies require explicit schema/protocol admission, not extra unchecked dictionaries. |
| `CellState` has a gem, permanent `blocked`, tags and a lock, but no obstacle. Physics/refill often check only blocked/null tile. | Add typed rubble occupancy and audit every enter/move/spawn/setup/restore path. Rubble must never become a topology hole or a T0 gem. |
| `OpeningGenerator` fills all active cells before checking stability and legal swaps. | Install room obstacles before population, skip occupied rubble cells, and validate the actual room opening. |
| `TurnController` resolves pre-gravity chains and then settling, creates its own budget, and passes `normal_swap` into BoardSettler. | Pass an explicit action context and shared budget through all work, including tool effects and recovery. Preserve the order of existing merge and physical operations. |
| `RuleFactBuilder` reconstructs facts after resolution, hardcodes cost 1 / `normal_swap` / `reward_eligible=true`, and increments terminal-recovery counts. | Remove unconditional assumptions; make terminal recovery an authoritative resolution effect. Record ordered transitions at their actual cause boundary before projecting them for playback. |
| `EventTimeline.from_facts` projects match/removal/promotion/spawn/travel; `MotionPlan.build` detects only match and travel phases. | Add explicit root-tool, obstacle, economy, recovery and result projection. A direct Refine or Chisel must not disappear because no `match_events` exist. |
| Both ActionPlayer paths assume `result.command.origin/destination` and an initial swap. | Play typed root effects without requiring two tile views. Test single-target actions and nonmatching Reposition. |
| MotionPlan chooses ordinary travel from the initial board and stages incoming stacks above columns. | Rubble can split lanes and later disappear. Use wave-local obstacle occupancy and avoid drawing spawns through remaining rubble. |
| RunScene has useful generation/error gates but a diagnostic HUD and random demo startup. | Introduce a room entry path, immutable HUD model, target selection and results; keep diagnostics explicitly separate from player flow. |
| Export preset enumerates individual files; build staging copies that list; audit accepts only current roots and a narrow imported-asset set. | Update explicit source/assets, imported derivatives, class-cache and localization/audio coverage together. Adding a resource reference alone does not guarantee the staging project contains it. |

The practical cost is several coordinated boundary changes, not three isolated
tool buttons. Keep board matching, the seeded integer RNG, delivered assets and
the accepted ordinary motion behavior intact.

## 3. Mechanical specification for this implementation

### Room and action economy

- Starter roster stays Quartz, Amethyst, Peridot, Topaz, Sapphire, Emerald, Ruby,
  Diamond. Supply remains ordered T1/T2/T3/T4 with weights 4/3/2/1.
- Open seam starts with 16 Work, 1 Craft, capacity 6 and an open tool allowance.
  Four distinct marked rubble objects start at durability 2. Exact positions and
  vetted seeds are authored in B2; they are not frozen by the existing P0 cases.
- An accepted normal swap spends 1 Work and reopens the tool allowance. Invalid
  input changes no state, RNG, IDs, accepted-command log or counters.
- For an eligible normal action, retain the strongest component award across all
  its chains/cascades: 3 = 0, line-4 = 1, line-5+ or any intersection = 2. Do not
  sum components or pay per cascade. Final award is
  `min(3, best_base + eligible_bonus_total)`, clipped by remaining Craft capacity.
  P2 has no bonus handlers, so `eligible_bonus_total` is zero.
- Settle earned Craft once before the next input boundary. Keep the base maximum,
  raw bonus total and actual capacity-clipped gain distinct in the action result.
  A full meter must not erase evidence of a qualifying match.
- One accepted tool closes the allowance until the next accepted normal swap.
  Tools spend no Work, increment no normal-turn counter and do not tick hazards.
  An invalid/canceled target spends nothing. No action, including a tool, is
  admitted when Work is zero or the room is terminal.
- All descendants of tool effects remain reward-suppressed. They can damage
  rubble and complete the objective; they cannot grant Craft, family activations,
  setting refunds or Work. Preserve a separate inherited restriction in addition
  to root cause, ready for P3 extraction/hazard continuations.

### Tools and target semantics

Use stable command IDs `action.exchange`, `action.clear_target`, and
`action.promote_target`. Current names are presentation vocabulary.

| Action | Admission and effect | Required edge behavior |
|---|---|---|
| Chisel — 2 Craft | Explicit target layer: damage one rubble/lock by 1, or remove one T1–3 gem. Capture expected target identity/cell. | No T4+ removal; no empty/hole target; no implicit “remove gem” when a lock was selected. Break/remove then run normal matching/settling with suppression. |
| Reposition — 2 Craft | Exchange two distinct, occupied, movable, unlocked orthogonal gems; no match requirement. | Keep ordered origin/destination for survivor priority. Preserve normal swaps' legality rules separately. |
| Refine — 3 Craft | Promote one T1–4 gem through the active roster once, keeping its instance ID. | Direct result at most T5; subsequent ordinary merges can reach higher tiers. Do not impose the direct tier ceiling on descendants. |

Recommended target decisions where the design is less explicit: allow Reposition
between same-tier distinct instances (the stated effect is an exchange, and
identity is real state); preview its lack of an immediate match. Movement-only
locks do not imply promotion/removal immunity: Refine may affect a locked eligible
gem, and Chisel's explicit gem-clear mode clears any attached lock with that gem.
Chisel's lock mode leaves the gem intact. Keep these decisions named in the B0
review; a different policy requires a documented choice and dedicated fixtures,
not an accidental consequence of `can_move_occupant` reuse. No seal content ships.

For a matching Reposition, apply destination/origin priority to its initial match
batch, then the normal maximum `(y,x)` policy. A direct Refine has no swap pair;
its induced match uses the ordinary no-swap survivor policy. Chisel clearance is
`effect_clearance`, with one removal ID and no `tile_consumed` subtype.

### Rubble and the objective

Rubble occupies an active cell, excludes a gem, and blocks entry/fall/spawn/swap.
It does not change the layout mask, gravity, fill sources or permanent holes.
Use an explicit obstacle record with stable ID, kind and durability; objective
membership belongs to the immutable room's marked-ID list. Tests may author
one-hit damaged rubble and unmarked optional rubble.

For each committed component, snapshot **all source cells**, including the
survivor's cell, before removing/promoting anything. Query ordinary orthogonal
obstacle neighbors through BoardState, deduplicate obstacle IDs, and apply one
damage per component per obstacle. Removed members and the survivor are not
separate hits. Two distinct components may each hit the same obstacle; so may a
later committed chain. Diagonals, portals, animation paths and the promoted gem's
new family do not extend the footprint. Cap actual damage at remaining durability;
emit a break exactly once and skip a target already removed by an earlier intent.

Capture all same-batch source footprints before mutating that batch. Resolve
components in canonical order and each component's obstacle targets in `(y,x)`
order with stable ID as a tie-breaker. P3 Corundum will replace the base amount
inside this one plan, rather than adding an independent second hit.

Progress counts broken **marked** objects, not damage points, arbitrary removals
or terminal T8 recovery. Breaking unmarked rubble never satisfies marked demand.
Emit immutable damage/break/progress transitions with original target IDs and
actual before/after values; the HUD must not infer progress from visible sprites.

### Completion, errors and phases

Use the design's **first stable room boundary**: finish automatic match chains,
gravity/refill and resulting cascades for the action, then evaluate clear-seam
completion. Rubble progress is recorded earlier, but breaking the last object
does not interrupt an unresolved match batch or publish an unstable snapshot.
Once the stable objective is complete, freeze the room and perform no subsequent
hazard, recovery or extra refill. This interpretation matches the first/last-action
fixture notes and the content-system resolution order; pin it in B0 tests.

Evaluate terminal precedence as:

1. Objective complete → `complete`, even on the last Work or via a legal tool.
2. Otherwise Work zero → `failed / work_exhausted`.
3. Otherwise normal swap or an affordable legal tool with allowance → `ready`.
4. Otherwise attempt bounded recovery; success → `ready`, exhaustion →
   `failed / board_locked`.

Cap/admission failures are transactional errors, not losses: publish no candidate
board, costs, IDs, RNG or replay command, retain the prior state, and show a
diagnostic lock with Restart/Menu. `board_locked` is instead an admitted terminal
result, with the triggering accepted action retained.

Represent published rule phases as `briefing`, `ready`, `complete`, `failed`.
`resolving` is a private transaction phase; `presenting` is a session/UI gate over
already committed state. The application can display all six phase names without
serializing cosmetic playback into rules. Begin-room changes briefing to ready
through an explicit recorded boundary command; it costs nothing and does not
consume an action/tool/hazard allowance. Define revision versus action counters
accordingly rather than retaining the P1 assumption `revision == next_action - 1`
for every new command kind.

### Recovery

At each ready candidate boundary use the shared legal-action queries. No normal
swap is not itself failure: an affordable legal tool with an open allowance keeps
the room playable. Merely having Craft, or a disabled tool button, is insufficient.

If neither exists, shuffle only occupied movable/unlocked T1–3 pieces among their
current eligible cells. Preserve complete tile records and IDs, the multiset,
all T4+ pieces, obstacles, locks, Work, Craft and allowance. Do not reroll tiers,
call the opening generator or generate reward-producing matches.

Recommended deterministic policy: canonical eligible-cell order; each candidate
starts from the same original eligible-piece array; descending Fisher–Yates using
bounded integer draws from the dedicated `recovery` stream; reject immediate
matches and physical instability; require at least one legal normal swap. Try at
most 64 candidates under the same transaction work/fact ceiling. Define and test
the exact draw loop and candidate count. The existing `SeededRng.shuffle` already
provides the descending integer shuffle; reuse it on the recovery stream if its
draw loop is retained, and account for its work. Do not use a global array shuffle.

Only a successful candidate replaces board occupancy. On ordinary 64-attempt
exhaustion, retain the pre-recovery board and economy, publish `board_locked`, and
retain the consumed recovery RNG position/attempt count for replay. If fewer than
two eligible pieces exist, use a deterministic zero-draw fast failure. A technical
cap failure rolls back the entire action instead. The P0 impossible-recovery
fixture's `state_preserved` concerns its queried board/economy; it does not mean
that a full terminal action has no result, revision or recorded recovery attempt.
Document that adapter scope explicitly.

Show one committed “rearranging loose stones” presentation event with a stable-ID
before/after mapping; record attempts/result without emitting candidate animations
or fake gravity paths. Recovery is automatic within the transaction, never an
extra player action, Work expenditure, normal turn or allowance refresh.

## 4. Ownership and protocol changes

Proposed filenames below are implementation destinations, not claims that they
already exist. Keep each service small; share pure operations with the P1 profile.

| Owner | Proposed additions / changes |
|---|---|
| `resources/definitions/` | `room_definition_resource.gd`, room encounter/obstacle records as needed; extend `game_rules_resource.gd` for admitted economy policy. |
| `data/game/` | `layouts/open_seam.tres`, `rooms/open_seam.tres`, a P2 rules profile and an opening-seed manifest. Create an encounters directory only if reused authored populations need it. |
| `core/board/` | Explicit obstacle state, entry/occupancy queries, obstacle-neighbor query, clone/serialize/admit and physical/setup integration. |
| `core/rules/` | Typed tool and begin-room commands/parser; `action_context.gd`; shared legality facade; versioned rules/state/replay admission and ordered fact construction. |
| `core/game/` | Concrete `tool_resolver.gd`, `obstacle_resolver.gd`, `craft_policy.gd` and a short contract. No generic reaction DSL or speculative families. |
| `core/run/` | `room_state.gd`, `room_admission.gd`, `room_boundary_resolver.gd`, `recovery_resolver.gd`; extend bootstrap, opening generation and action/session orchestration. |
| `scenes/run/`, `scenes/board/` | Room input/controller adapter, immutable room HUD projection, target/obstacle layers and generalized committed playback. |
| `resources/presentation/`, `data/presentation/`, `scenes/ui/`, `scenes/effects/` | Small game profile/catalog, themed panels, cue player and cancellable feedback. GemDeliveryCatalog/GemForge retain their separate ownership. |
| `tests/game/`, `tools/game/` | Room/tool/recovery suites, P2 replay corpus and probes, presentation recipe generator/checker. |

### Canonical identity and compatibility

Preserve `facets.prototype.v1` as the P0 **design rules identity**. Recommend a P2
implementation profile and new `facets-sim-v2`, state schema 2 and
`facets-replay-v2` for the expanded grammar/state. Keep `facets-codec-v1`,
`facets-stream-v1` and `legacy_scan_v1` where their actual formats/algorithms remain
unchanged. Name the obstacle, economy and recovery policies explicitly.

Retain the P1 profile as a supported regression/control path with exact old
serialization and event identity. Do not append zero-valued room fields to v1
snapshots or redefine v1 replay to interpret tools. Share the resolver primitives;
avoid a copied second simulation. Unknown versions reject clearly, and new room
state is never silently migrated into a legacy demo. B0 freezes the exact IDs and
parser policy before capturing P2 goldens.

Schema 2 must include immutable room definition/content identity, marked target
IDs, obstacle records/durability, room result/reason, Work, Craft, tool allowance,
normal-turn count, recovery counters, all existing board/RNG/allocators, and
implemented rule-profile values. Store each live value once; derive adapter aliases
and validate cached objective counts against the actual marked-object state.
No unused reward/route/hazard queues or trial time fields are required.

The action context holds root kind/cause, inherited reward restrictions, best Craft
candidate, scoped usage and the one shared ResolutionBudget. It is transaction
local in atomic P2. It must be explicit and data-oriented so the later trial can
serialize a real continuation, but P2 does not claim continuation restore support.

Typed target commands include expected instance/obstacle identity and ordered
cells, plus admission against current revision/session. Reject stale selection;
never retarget a replacement occupant. Replay commands carry the logical revision
and identities needed to repeat admission; local presentation generation tokens
are not mechanical state. Preserve signed 64-bit RNG state through CanonicalCodec,
not a JSON numeric round trip.

### One authoritative action flow

```text
pure command admission on published state
  → duplicate state/RNG/allocators; create one action context/budget
  → reserve Work OR Craft/tool allowance; record root action
  → apply swap, targeted clearance/damage, or targeted promotion
  → snapshot components → merge/terminal effects → obstacle damage
  → recheck automatic promotion-created matches before gravity
  → settle/refill and cascade until stable
  → finalize eligible Craft once; evaluate objective and Work precedence
  → if still live, evaluate legal swaps/tools and bounded recovery
  → validate complete candidate and event limits
  → publish state + accepted command + exact state/event checkpoints together
  → present committed root/match/obstacle/motion/resource/result facts
```

Add fact kinds/payloads only for implemented transitions: tool activation, resource
spend/gain, allowance changes, obstacle damage/break, objective progress, recovery
and room outcome. Match/removal/promotion identities and causal parents remain
explicit. Use one authoritative ordered transition record; projections and debug
logs cannot award terminal recovery or reconstruct old source identity by reading
the final board. Preserve byte-identical P1 facts through the legacy profile.

## 5. Ordered implementation batches

Each batch finishes its owning contract and focused checks before the next one
depends on it. Relative sizes describe uncertainty, not calendar commitments.

### B0 — Freeze P2 policies and baseline evidence (small, first)

- Record working-tree/source identity, toolchain, delivered pack/catalog hashes,
  frozen fixture/golden hashes and existing test registrations. Store new evidence
  under a fresh `artifacts/game/p2/<run-id>/`; never overwrite P1/P1-A reports.
- Confirm the proposed protocol IDs, stable completion boundary, tool target
  semantics, recovery RNG/exhaustion policy and rule/UI phase split above. These
  are reviewable implementation decisions, not changes already made to P0.
- Record current integrated functional baseline through the maintained runner and
  retain every completion marker. Separate environmental attempts from completed
  checks. Keep any unrelated pre-existing failures visible.
- Add a P2 fixture ledger: frozen P0 fields inherited, new expectations needed,
  test owner and completion stage. Preserve the original P0 bytes.

Exit: no unresolved ambiguity about what a tool charges, which rubble gets hit,
when victory is checked, or what a failed recovery publishes. If design intent
differs materially, resolve that focused choice before implementing its branch.

### B1 — Room state, command grammar and shared action context (large; B0)

- Implement detached room/rules admission, schema 2 cloning/restore, parser
  dispatch, begin-room boundary and target identity checks.
- Extend RunController's single action API and ReplayRecord together; introduce
  the explicit action context and pass one budget through root effects,
  TurnController and BoardSettler. Remove hardcoded cause/cost/eligibility in P2.
- Separate rule state from resolving/presenting UI gates. Restart restores the
  admitted initial room/briefing snapshot and clears accepted commands and cues.
- Refactor fact ownership only as far as needed for tools, obstacle effects and
  resource settlement. Keep pre-gravity ordering and the legacy corpus intact.

Exit: a synthetic room round-trips exactly; field-mutation/admission tests cover
every introduced field; malformed/unknown/stale commands are pure; injected
failures preserve bytes/RNG/IDs/record; old replay vectors still pass.

### B2 — Rubble, Open seam authoring and normal-swap victory (large; B1)

- Add obstacle occupancy and stable IDs; update board mutation, physics, spawning,
  opening generation, snapshots and admission as one change. Include raw duplicate,
  out-of-bounds, blocked-cell, gem/obstacle collision and missing-objective checks.
- Author four strategically distinct two-hit targets on an ordinary 8×8 DOWN
  layout using the existing default spawn policy. Check local access and practical
  matching space; graph reachability alone is not proof of solvability.
- Generate around installed obstacles without free opening merges. Keep the
  existing bounded opening policy explicit; store seed, attempts and content digest.
- Implement frozen source-footprint damage, marked progress and stable-boundary
  completion. Close `first_action_win` and `last_action_win` P0 assertions through
  real transactions; retain their prescribed supply/seeds and damaged rubble.
- Add a minimal functional target overlay/result display for internal inspection.
  This is a debugging checkpoint, not yet the P2 presentation exit.

Exit: normal swaps can win or exhaust Work; last-action victory has precedence;
no spawn enters rubble; a broken cell participates in subsequent settling; one
component cannot double-hit a target; restart restores all four intact targets.

### B3 — Craft and tools, one at a time (large; B2)

1. Implement strongest-match Craft reduction, cap/settlement and allowance.
   Extend `match_4`/`match_5` P0 adapters at their named first-match phase, plus
   separate complete-action Craft tests for chains and intersections.
2. Implement Chisel first: explicit obstacle/lock/gem modes, costs, targeted
   clearance and suppressed descendants. Verify direct objective completion.
3. Implement Reposition: nonmatching and matching exchanges, ordered survivor
   priority and both displaced-piece identities.
4. Implement Refine: direct tier bounds, stable identity, automatic chain priority
   and suppressed multi-cascade outcomes.

After each tool, add legal/illegal, affordability, allowance, stale-target,
chain, replay and rollback fixtures before wiring the next. Add failure injection
after resource reservation, target effect, obstacle break and Craft settlement.
No test-only bonus family is needed in production; eligibility tests can inspect
the entire descendant fact stream and exercise the pure award policy directly.

Exit: swap → tool → rejected second tool → invalid swap → still closed → accepted
swap → open is exact; tool-origin large matches never refill Craft; none of the
tools spends Work/ticks a normal turn; rejected T4 Chisel/T5 Refine preserve state.

### B4 — Ready-boundary recovery and terminal admission (medium; B3)

- Implement shared legal tool enumeration, including actual target and cost checks,
  and the combined ready-state evaluator. Keep pure availability queries RNG-free.
- Implement bounded low-tier permutation recovery and its one summary event.
  Add attempt/work counters and explicit exhaustion versus technical failure.
- Extend state restore validation to complete, work-exhausted, recoverable/tool-only
  ready and board-locked states. Restoration validates a saved result; it must not
  secretly rerun recovery or advance RNG. Invariants cannot demand a normal swap
  when a legal tool is the only available action.
- Close the P0 `recovery_possible` and `recovery_impossible` observations without
  requiring the illustrative witness to be the first RNG permutation.

Exit: tools prevent premature reshuffle; unavailable/closed/unaffordable tools do
not; high-tier IDs and positions survive every candidate; repeat/replay/restore
use identical attempts and stream state; exhausted recovery yields a distinct loss.

### B5 — Complete committed playback and functional room UI (large; B3, B4)

- Generalize both concurrent and serial/instant ActionPlayer paths for root tool
  operations. Project direct clear/promote, damage without a match, recovery,
  economy and result facts explicitly. No fabricated swap is needed for Chisel.
- Build immutable room/HUD/inspection models: objective remaining, Work/Craft,
  actual costs, allowance, disabled reasons, selected gem/tier/next upgrade and
  starter collection. Update on changes, not per-frame rule polling.
- Add briefing/Begin, target selection/cancel/preview, win/fail/restart, asset-error
  and resolution-error panels. Input, hints and keyboard share rule admission.
  Result controls become available after playback/skip without accepting new
  gameplay input into a committed terminal room.
- Extend obstacle overlays from the displayed before-state through hit/break
  facts. Do not show final cleared rubble before the associated match. Snapshot
  snapping must update both gem and obstacle layers.
- Keep loading/playback/modal/error/terminal gates composable and token-owned;
  cancel pending selection, tweens, sounds and pooled views on restart/navigation.
  Repeated acknowledge/skip/result notifications cannot duplicate costs or wins.

**Rubble motion acceptance:** evaluate ordinary DOWN travel per settling wave
against the obstacle state at that wave. Reuse concurrent journeys in proven open
lanes. For a pocket below rubble under `fill_empty_cells`, materialize at the actual
logical spawn cell; never fly an incoming stack through the obstacle. Use a short
local fade/ordered path where no full journey is proven. Add a focused lane/pocket
projection if required for the authored room; retain custom-topology fallbacks and
whole-wave barriers. Do not globally serialize the entire rubble room by default
or claim P1-A's empty-board motion report proves this new workload is fluid.

Exit: all tools and recovery visibly explain the committed changes; concurrent,
serial reference, instant and skip produce identical final state and overlays;
same-wave lane spacing, rubble removal and refill are correct; stale playback
cannot unlock new input. The room is navigable using mouse and keyboard.

### B6 — Functional presentation assets and clean package (medium; B5)

- Implement the P2 subset of the presentation specification: shared workshop Theme,
  English vocabulary/typed cost placeholders, procedural work surface, resource/
  tool/clear-objective and needed navigation icons, two rubble images, live pips,
  tier numerals and selection/focus markers. Include the specified outlet drawing
  primitive for a visual fixture; do not display a nonfunctional outlet in Open seam.
- Create original SVG sources and deterministic WAV candidate recipes using repo
  code and Python standard libraries. Add `tools/game/build_prototype_sfx.py` and
  a minimal reference/audio-header check; these are currently planned tools.
- Generate the cues actually used by P2: UI navigation/accept/reject, swap, match,
  promotion, obstacle hit/break and room success/failure. The full 14-cue set,
  remaining icons, neutral profile and complete gallery remain P3/P4c.
- Inspect/audition candidates before promoting accepted files into runtime assets;
  record generator/runtime, recipe/seed, authorship and output hashes. Functional
  audio acceptance needs listening, not just valid WAV headers.
- Add UI/GameSFX routing, volume/mute, keyboard focus, bounded voices/effects and
  generation-owned cue cancellation. Preload required UI/SFX with the room; use
  GemForge for the starter roster's complete rest/upgrade closure.
- Update export files, excluded source-art/generated directories, staging and the
  audit's allowed runtime roots/imported dependencies. Validate actual imported
  SVG/WAV/theme/font/localization/audio-bus resources; never whitelist all imported
  files without tying them to the accepted runtime source set.

Exit: native 1600×900 and 1280×720 room screenshots show readable badges, targets,
costs and focus; mute and lifecycle tests pass; the clean release contains exactly
its admitted runtime dependencies and existing gem pack, with no source recipes.
Measure non-gem textures/SFX separately from gem residency against the proposed
16 MiB / 2 MiB / 16 MiB targets; report font/scene/decode overhead separately.

### B7 — Replay, release checks and first-room evaluation (medium, iterative; B6)

- Run all affected foundation stages and the new room/tool/recovery/presentation
  checks; retain positive completion markers and source identity through the run.
- Add P2 mixed-command fixed-seed replay and midpoint restore, including rejection,
  tool-only ready states, recovery and both terminal reasons. Pin the command
  selection policy independently of simulation RNG; preserve every failed seed.
- Build a fresh package and exercise its actual executable: Begin, purposeful use
  of each tool, win/fail, final-Work win, restart during travel/effects, skip, mute,
  keyboard targeting, menu navigation, missing/corrupt assets and explicit errors.
- Add a P2 room mode to the existing action probe (or a focused sibling) with
  explicit startup/configuration. The existing 20-action demo probe must remain
  identifiable; it does not automatically become an Open seam measurement.
- Record complete CPU, legal-action enumeration, input-to-first-motion, frame and
  playback distributions, maxima, loading and recovery counts. Compare the original
  P1-A control and the new P2 workload separately; fixed-clock movie capture is
  visual evidence, not performance evidence.
- Vet a small set of first-session opening seeds with saved winning command
  witnesses, plus a reproducible normal failure route. Do not call a seed solved
  merely because generation found a legal swap. A search/helper may use the real
  action API, but a human must still evaluate clarity and tool purpose.
- Run 3–5 short player sessions on concurrent playback. Ask players to explain
  survivor placement, rubble damage and at least two purposeful tool choices.
  Record decision time, forced waiting, stalls, misclicks, tool spending and result.
  If tools simply bypass matching, or earning Craft is too obscure without P3
  families, revise the room/teaching and repeat before adding expedition rewards.

Exit: publish `plans/P2_HANDOFF.md` with exact build/content/protocol identities,
checks, recordings, seed witnesses, player findings and open gates. Mechanical,
presentation, player and latency results must have separate statuses. Missing
participants leave player acceptance open; they are not replaceable by agent claims.

## 6. Regression and acceptance matrix

Proposed new registered stages: `test_game_room`, `test_game_tools`,
`test_game_recovery`, `test_game_room_playback`, `check_presentation_content`,
and a P2 actual-action probe. Register exact scripts, timeouts, execution mode and
`CHECK_COMPLETE` markers when they exist. These are not runnable commands today.

| Area | Minimum cases / evidence |
|---|---|
| Room admission | Duplicate/missing IDs, invalid marked references, rubble on a hole/gem, bad durability/budgets/types, empty production objective, unresolved definition version; failed entry preserves an existing session. |
| Obstacles | Survivor-only adjacency, consumed-member-only adjacency, multiple contacts deduplicated, two components/two hits, later chain hit, diagonal/portal exclusion, unmarked break, break once, refill into newly opened cell. |
| Craft | 3/4/5+/L/T/intersection, strongest late-chain match, multiple simultaneous components, capacity boundary, tool descendants, suppressed context beneath a normal root, award once after skip/ack. |
| Tools | Cost−1/cost/cap resources, allowance sequence, zero Work, terminal/briefing/stale input, Chisel T3/T4 and layer identity, Refine T4→T5/T5 rejection, same-tier and no-match exchange, induced chains and source IDs. |
| Completion | P0 first/last action fixtures, tool win, incomplete last-Work failure, optional rubble remaining, completion once, no work after terminal boundary, cap failure after would-be winning damage rolls back. |
| Recovery | No swap but legal tool, no affordable tool, closed allowance, zero Work precedence, immutable high/locked pieces, 64th success/exhaustion, immediate-match/unstable candidate rejection, dedicated stream isolation, cap rollback. |
| Identity / restore | Every new field affects canonical identity as intended; dictionary insertion order does not; invalid bounds/phase/counter/objective consistency reject; complete/failed/tool-only ready restoration; restart exactness. |
| Replay | Original independent codec/action vectors and 2,000 P1 checkpoint pairs preserved; separately versioned P2 mixed-command replay/restore; malformed commands/versions rejected; no seed dropped. |
| Playback / cues | Direct tool with no match, damaged/broken rubble, pocket spawn, independent lanes, recovery, result; concurrent/serial/instant/skip equality; cancellation at every new await/effect; no stale sounds/overlays/input release. |
| Package / usability | Exact staged runtime inventory, missing asset errors, actual-executable interactions, native-size images, real audio audition, keyboard/focus/mute, purposeful player tool choices. |

The existing baseline command is:

```powershell
& ./tools/check_engine.ps1 -Only import,source_check,test_smoke,test_rng_cross_platform,test_board_consumer,test_run_delivery,test_game_rules,test_game_state,test_game_transaction,test_game_replay,test_game_playback,test_game_motion
& ./tools/check_engine.ps1 -Gpu -Only game_action_probe
& ./tools/build_game_package.ps1 -AssetPack generated/gem-assets.pck -Probe -FrameBudgetMs 16.7
```

Run these only in an appropriate Godot/GPU environment and write fresh P2 reports.
Extend the selected stage list after registering the proposed checks. A passing
headless package probe is not an actual release interaction test; a passing frame
p95 does not close the 5 ms complete-action CPU gate. The P1-A reference is
39.907 ms release headless action p95 and 8.496 ms frame p95 on its distinct
20-action visual workload, as recorded in its handoff, not remeasured here.

## 7. Required post-P2 intervention trial and P3 handoff

The [trial document](P2_INTERVENTION_TRIAL.md) remains the detailed authority.
After B7 produces the first tactical room, execute its batches in order:

| Trial batch | Dependency / deliverable |
|---|---|
| T0 | Freeze authored intervention fixtures and a separate experimental RuleSet/command/replay profile. Include the promoted survivor at `(2,3)`, intended `(1,3)/(1,4)/(1,5)` match, chain-consumed opportunity, stale target, Work boundary and near-cap cases. |
| T1 | Extract a real resolver continuation. Park after all automatic promotion chains and before the next gravity pass; expose at most one eligible surviving promoted-piece swap per normal-swap episode. Implement complete in-memory continuation snapshot/restore and committed-prefix/atomic-segment failure tests. |
| T2 | Compare paused with 400/800 ms profiles: integer 60 Hz clock, deadlines 24/48 ticks, admitted input tick/sequence, `< deadline` acceptance and expiry winning ties. Record presentation-ready window start, decisions, expiry and pause/focus changes. |
| T3 | Run 3–5 counterbalanced qualitative sessions over atomic control, paused and both timed profiles, including planning-preferring players. Compare actual choices, mistakes, economy, opportunity frequency, waiting and explanations; do not infer broad demand. |
| T4 | Publish fixtures, builds, determinism/lifecycle evidence, recordings, player findings and an explicit adopt/optional challenge/revise-and-retest/decline decision. A revise result keeps the experiment open until its follow-up decision is recorded. |

Accepted intervention costs one additional Work; invalid/pass costs nothing;
zero Work suppresses the offer. One shared episode owns Craft/family caps,
normal-turn hazard scheduling, suppression and work/fact/chain limits. No renewed
tool allowance and no early spending of newly earned Craft. Pass must match the
atomic no-intervention continuation including RNG, after accounting for explicit
mode identity. A failed continuation does not erase its committed prefix or
publish partial segment state. Ordinary P2 keeps whole-action rollback.

Replay the same admitted input/tick stream at 30/60/120 render FPS, injected
stalls and reduced motion. Freeze/record pause and focus loss; exclude paused
attempts from unassisted reaction-time comparisons. Timed profiles cannot offer
cosmetic speed controls that change deadlines. If selection becomes misleading
under stalls, revise the policy before player evaluation.

P2 hands the trial explicit phase/context/fact seams; it does not pretend that
`prepare_turn`/`step_cascade` is a suspended resolver. Keep disk saves at stable
episode boundaries unless production continuation saves are separately admitted.
Only an adoption decision expands P3's production episode/save/reward contracts.
Unrestricted moves during falling, transient matches, tools during resolution,
multiple windows and transport interception remain outside this trial.

## 8. Risks, decision points and completion record

| Risk | Treatment / decision point |
|---|---|
| Protocol expansion invalidates P1 evidence | B0/B1 explicit v1/v2 paths and unmodified vectors; capture new goldens only after semantic review. Do not recapture old expected hashes to make tests pass. |
| Rubble leaks into occupancy or is hidden until final snap | B2 audit all board entry paths; B5 wave-local obstacle facts and before/after view tests. |
| Craft/recovery semantics create unintended loops | One allowance, inherited suppression and shared resource policy; recovery never refreshes allowance or creates matching rewards. |
| Limited Craft makes tool teaching impractical | B7 vetted opportunities and purposeful-use sessions; adjust authored layout/teaching first. Any economy change gets a named reviewed successor profile. |
| Rubble reintroduces forced serial waiting | B5 actual lane/pocket motion tests and B7 recorded decision/wait/stall separation; preserve a focused concurrent solution rather than defer all motion to P6. |
| Existing latency miss grows with new state/facts | Profile complete P2 transactions and enumeration separately; never weaken full identity/admission or remove facts to meet a number. Carry the open P1-A gate explicitly. |
| Trial implementation starts consuming P2 scope | Finish atomic room first; keep continuation/time grammar in a separate experimental profile and execute the required downstream batches. |
| Local plan is mistaken for shipped documentation | `docs/` and `plans/` are gitignored by policy. Put implemented contracts/tests with their source owners; keep this plan and handoff locally linked. |

At handoff, report independently:

- **Mechanical room:** B1–B4 plus replay/admission checks.
- **Functional presentation and delivery:** B5–B6 and actual-release checks.
- **P2 player acceptance:** B7 findings and any required iteration.
- **Inherited P1-A acceptance:** CPU and player feel status, with fresh evidence
  clearly distinguished from previous reports.
- **Required trial:** T0–T4 status and explicit decision before P3 freezes.

Update the owning contracts, tests guide/fixture coverage, tools guide and current
phase plan when implementation changes those statuses. Add the P2 handoff link
when the file exists. Preserve all frozen baseline and historical bytes; archive
superseded local documents with verified hashes if replacing them wholesale.
Do not mark P2/trial/player gates complete solely because implementation compiles.

The recommended first implementation slice is **B0 → B1 → B2**: an admitted,
replayable rubble room that wins through normal swaps. Then add Craft/tools,
recovery and the functional presentation kit before running the player and
intervention evaluations.
