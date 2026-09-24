# Engineering boundaries for the remaining prototype

Status: current owner map and redesign policy, 2026-09-24. This replaces the
pre-P1 architecture backlog. Read the actual affected owner before editing it.

## Preserve guarantees; evaluate implementations

| Area | Default treatment | Evidence or reason required to change |
|---|---|---|
| Deterministic simulation and state identity | Preserve behavior, ordering, stable IDs, RNG and complete replay/save guarantees | Concrete defect or separately decided mechanic; compatibility and regression plan |
| Offline gem authoring/rendering | Reuse production capabilities and provenance | Demonstrated content requirement unsupported by current capabilities |
| Runtime delivery | Preserve validation, explicit bindings, preflight, ownership and failure behavior | A measured target-experience need; delivery/version/lifetime implications |
| UI composition and presentation assets | Open to replacement | Evidence that the selected direction works in play |
| Scene/API/presenter structure | Keep, adapt, refactor or replace according to need | Desired experience, specific obstruction, responsible owner and verification |
| Current mechanics and scope | Preserve during presentation exploration | Explicit proposal with player benefit, alternatives and timing/save/replay consequences |

Neither minimum diff nor wholesale replacement is the objective. Reuse should
serve the target. Perform necessary foundational work instead of accumulating
special cases, but do not create a general framework for hypothetical content.

## Current owners

| Responsibility | Start here |
|---|---|
| Board storage, matching/topology | [Board code](../../core/board/), [rules contract](../../core/rules/CONTRACT.md) |
| P3 families, rooms, rewards, carry, persistence | [P3 contract](../../core/run/P3_PREPARATION.md), [ExpeditionState](../../core/run/expedition_state.gd), [ExpeditionSave](../../core/run/expedition_save.gd) |
| Incremental batches, reservations, worker, window clock and published input | [Merge-window contract](../../core/run/MERGE_WINDOW_PREPARATION.md), `core/run/merge_*.gd` |
| Current expedition shell and playable room | [ExpeditionView](../../scenes/run/expedition_view.gd), [MergeRoomView](../../scenes/run/merge_room_view.gd) |
| Current streaming board presentation | [MergePlayer](../../scenes/board/merge_player.gd), [BoardScene](../../scenes/board/board_scene.gd), [TileView](../../scenes/tile/tile_view.gd) |
| Atomic controls and their playback | [Run contract](../../core/run/CONTRACT.md), [room contract](../../core/run/ROOM_CONTRACT.md), [board presentation](../../scenes/board/CONTRACT.md) |
| Existing UI/audio baseline | [UI contract](../../scenes/ui/CONTRACT.md), [RoomAudio](../../scenes/ui/room_audio.gd) |
| Gem delivery and packaging | [Delivery contract](../../core/delivery/CONTRACT.md), [tools](../../tools/README.md) |
| Offline optical production | [Authoring workflow](../AUTHORING_WORKFLOW.md), [factory contract](../../core/lapidary/factory/CONTRACT.md) |

The atomic and P2 UI contracts retain their declared scope; they do not describe
every P3 class. A proposed unified presenter/catalog in an older design document
is not proof that such a complete abstraction exists today.

## Boundaries a redesign must respect

Simulation owns legal commands, objectives, costs, ordered facts and committed
state. Presentation consumes those facts and submits intents through the same
admission boundary for keyboard, mouse and any future control scheme. Do not
reconstruct family payouts or extraction in a scene callback.

P3's published snapshot/cursor establishes the actionable board. Worker candidates
are private until admitted. The merge window, clock and reservation policies are
mechanical inputs; decorative transforms, clip playback and labels are not.
Preserve revision/instance checks, assistance records and cancellation ownership.

Keep optical production offline and runtime assets prebuilt. Gem delivery owns
pages and residency; views and previews can keep pages live after cache eviction.
Error/retry must preserve committed state, choices and RNG. Navigation cannot
unlock a different generation or leave stale animations/audio behind.

Stable semantic IDs separate vocabulary, media and rules. A presentation profile
should be able to select theme, text and cues without changing simulation identity.
The full profile/pivot proof remains planned work, not established by this guide.
Descriptions should derive costs and thresholds from admitted data.

## How to justify an architectural change

Write a short record in the relevant implementation proposal:

1. The player-visible behavior or production need being enabled.
2. The current obstruction, with source or experiment evidence.
3. Options: retain, adapt, refactor, replace; their cost and ownership tradeoffs.
4. The proposed API/data/lifetime change and compatibility impact.
5. The smallest integrated proof and relevant regression checks.

For example, reward/carry composition may warrant replacing the current generic
phase UI, while retaining transactional choice admission and preflight. A new
motion treatment may warrant separating hit-map/cursor authority from decorative
tracks. These are investigation candidates, not preapproved replacement designs.

## Verification discipline

Use [registered checks](../../tests/README.md) and the relevant game suite. Preserve
frozen controls and historical failures. Check completion markers, source/package
identity and actual release behavior where required. Cosmetic changes should
retain identical mechanical outcomes for identical recorded commands; timing
changes require additional scrutiny because P3 includes explicit windows.

Reconcile source/contract disagreements instead of copying old advice into new
code. Update the owner contract when behavior changes. Keep package allowlists
explicit; offline sources, candidates and authoring dependencies stay out of the
runtime export. No runtime or contract changes are performed by this documentation
reorganization.
