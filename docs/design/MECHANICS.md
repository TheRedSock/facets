# Current game mechanics map

Status: implemented P3 orientation, 2026-09-24. This is a concise semantic map,
not a second rule specification. Exact ordering, parameters and compatibility
belong to the linked contracts/source. Check them before changing behavior.

## The player's loop

1. Enter a room with its objective, Work, Craft, current collection and settings.
2. Make legal adjacent swaps to merge same-tier pieces. Position survivors,
   trigger family reactions, use tools and address the objective.
3. During a merge window, optionally pay for another legal swap, including one
   using the newly promoted gem. At equilibrium, take unrestricted thinking time.
4. Complete the room; select eligible gems to carry and choose a reward. The first
   transition also offers a route choice. Reach the final extraction objective
   or end the expedition on failure.

There are three rooms in a run, selected from four authored definitions:
Open seam, a deeper seam or Commission branch, then Vault. The current definitions
and exact transition order are owned by [P3](../../core/run/P3_PREPARATION.md).

## Concepts that must remain intelligible

| Concept | Current meaning | Owner |
|---|---|---|
| Tier / rank | One match/progression/appraisal band, T1–T8; not a second score or mineral price | [P3 content](../../core/run/p3_content.gd), [catalog](../../core/rules/game_catalog.gd) |
| Collection | One active gem definition per tier; determines the resulting next-tier piece | [P3 contract](../../core/run/P3_PREPARATION.md) |
| Supply | Separate integer-weighted refill selection; replacing a roster entry does not silently change supply | [P3 contract](../../core/run/P3_PREPARATION.md) |
| Work | Room move budget; valid interventions are paid moves, invalid attempts spend nothing | [Merge-window contract](../../core/run/MERGE_WINDOW_PREPARATION.md) |
| Craft and tools | Bounded tactical resource; Reposition, Chisel and Refine have admitted costs/targets and equilibrium-only use | [P3 contract](../../core/run/P3_PREPARATION.md), [legality](../../core/rules/room_action_legality.gd) |
| Family | Curated source-gem identity selecting a bounded reaction; not matching by color | [Family dispatcher](../../core/run/family_dispatcher.gd) |
| Setting | Expedition modifier: currently Steady Hand and Beryl Bridge | [P3 content](../../core/run/p3_content.gd) |
| Carry | Up to two eligible remaining T4+ instances in selected staging order, preserving identity/tier | [Expedition state](../../core/run/expedition_state.gd) |
| Reward | Persisted offer with explicit roster/setting/next-room benefit; previews and retries do not reroll | [P3 contract](../../core/run/P3_PREPARATION.md) |
| Extraction | Automatic qualifying outlet delivery at an authoritative stable boundary; unique consumption and objective accounting | [Extraction resolver](../../core/run/extraction_resolver.gd) |

Quartz provides bounded Craft support; Corundum changes adjacent rubble damage;
Beryl promotes an eligible neighbor of its survivor. The source identity, target
selection, suppression and per-paid-move accounting matter. Animation must explain
those facts without recomputing them. Aquamarine replaces the T5 Sapphire entry,
making a concrete family tradeoff and converting relevant carry with a preview.

Clear-rubble completion and stable-boundary extraction have different timing.
Extraction can also occur on Begin for qualifying opening occupants. Completion
on final Work wins. Extraction is not ordinary merge consumption or terminal-tier
recovery, and a delivered piece cannot also be carried.

## Interaction and time

The [merge-window contract](../../core/run/MERGE_WINDOW_PREPARATION.md) is essential
reading for motion/input work. The published post-merge board is actionable;
consumed visual ghosts are not live targets. A timely paid intervention precedes
a pending automatic match. There may be repeated windows, with at most one
accepted command per window. Visual positions never become rule input.

Reduced motion preserves the mechanical opportunity. Buffering, focus-loss
pauses, assistance and restored windows have explicit policies. Do not import
the older atomic “complete whole action, then play it” assumption into this mode.

## Persistence and failure

[Expedition saves](../../core/run/expedition_save.gd) and the P3 contract cover
committed phases, parked windows, accepted reservations, offers and full identity.
Continue is manual; restored timed windows are paused/assisted. Asset preflight
failure preserves the run and choices. Incompatible or corrupt saves are reported,
not silently replaced by a new run.

Readable explanations of costs, targets, carry, rewards and failure reasons are
presentation work. Altering those underlying rules requires an explicit design
decision, protocol/serialization review and appropriate regression expectations.
