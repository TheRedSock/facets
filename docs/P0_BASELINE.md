# P0 — frozen prototype baseline

Completed 2026-09-14 for **`facets.prototype.v1`**. This is the implementation target for the three-room experiment, not an assertion that these mechanics already exist. P1 remains unstarted. The optical engine and gameplay source are unchanged by P0.

## Completion evidence

| P0 requirement | Result | Evidence |
|---|---|---|
| Named rules and explicit decisions | Complete | Decision register below; [rules index](../artifacts/game-p0/facets-prototype-v1/rules.json); frozen design documents |
| Source, local delta and asset baseline | Complete | [Baseline manifest](../artifacts/game-p0/facets-prototype-v1/manifest.json), exact working-tree patch, project file and copied PCK/catalog/manifest |
| Ordered rewrite backlog | Complete | Dependency-ordered backlog below, mapped to prior source findings and fixture IDs |
| Required AGENTS.md changes identified | Complete | Contract migration table below; current invariants have not been silently rewritten |
| Controlled board fixtures | Complete | [23 target fixtures](../tests/fixtures/game_prototype_v1/cases.json) and [fixture semantics](../tests/fixtures/game_prototype_v1/README.md) |
| Prototype delivery coverage | Complete | [Fresh mounted-pack check](../artifacts/game-p0/delivery-check.json): nine gems, 18 semantic bindings, all 16 pack pages decoded/verified |

The whole intended loop is: fixed eight-tier collection → rubble room → carry up to two T4+ pieces → one reward → choose rubble or commission room → carry/reward → extract T5+ through a vault outlet → results. Work limits swaps; Craft funds tactical tools; Quartz/Corundum/Beryl alter which positions and routes are desirable. Higher tiers are the appraisal progression. No additional value score or currency is needed.

## Frozen source and asset identity

Git HEAD: `6aa7da1e58126495669046a6efa77bbe65924ea6`. The manifest records the branch, all existing tracked-file hashes and original working-tree status. A commit plus its preserved patch defines the code baseline; the copied design files define the intended rules. No commit or branch change was made in P0.

The pre-existing `project.godot` delta moves `application/run/max_fps=120` and `display/window/vsync/vsync_mode=3` to different positions within their existing sections. A section/key/value comparison against HEAD found **identical settings**. The exact original bytes and diff are preserved; nothing has been reverted or normalized. This establishes the edit's effect, not who or what produced it.

The baseline directory holds a copy of the current `gem-assets.pck`, the loose library manifest and `default.tres` presentation catalog. SHA-256 records make later replacement detectable. The fresh Godot check mounted the actual PCK, confirmed its manifest matches the loose one, checked all required prototype rest/upgrade mappings and decoded/checksummed every page through the runtime library. It exited successfully with `CHECK_COMPLETE: game_p0_delivery`.

Current assets are suitable **baseline bindings**, not final game art approval. Rest still maps to `idle`; upgrade maps to the existing `turn`. P4's shorter optical tilt, tier badges and quartz/sapphire studies remain planned. No new bake, GPU timing, live-board recognition test or human playtest was performed. The existing root-certificate-store error was emitted by Godot; it did not prevent completion and is retained in [the log](../artifacts/game-p0/delivery.log).

## Decision register

The frozen copies of [GAME_DESIGN.md](../artifacts/game-p0/facets-prototype-v1/design/GAME_DESIGN.md) and [CONTENT_SYSTEMS.md](../artifacts/game-p0/facets-prototype-v1/design/CONTENT_SYSTEMS.md) contain the detailed target. This register fixes the first experiment and resolves small implementation choices; it does not activate speculative expansion examples.

The register itself is preserved as [P0_DECISIONS.md](../artifacts/game-p0/facets-prototype-v1/P0_DECISIONS.md). Changes to implemented behavior after this freeze need an explicit rules revision and corresponding fixture review.

| ID | Frozen prototype decision |
|---|---|
| D01 — Collection | T1 Quartz, T2 Amethyst, T3 Peridot, T4 Topaz, T5 Sapphire, T6 Emerald, T7 Ruby, T8 Diamond. Aquamarine is the only initial alternative and replaces T5. One active definition per tier. |
| D02 — Appraisal/grade | Tier is the only value band. No numerical appraisal table. One provisional specimen/grade intent per gem, recorded in `rules.json` alongside its existing grade resource. No automatic grade→tier/optics formula, grade workshop or dynamic quality stat. |
| D03 — Supply | Explicit targets T1/T2/T3/T4, integer weights 4/3/2/1. Independent draws via SeededRng. Collection and supply are separate data; no supply-redirection setting ships yet. |
| D04 — Match legality | Orthogonally adjacent occupied movable/unlocked cells. Swap must create a match involving a swapped cell. Invalid actions preserve state and RNG. Portals never create swap/match adjacency. |
| D05 — Ownership | Intersecting same-tier runs form one component. First-cascade survivor prefers destination, then origin; otherwise greatest `(y,x)`. Later components use greatest `(y,x)`. Remove N−1, promote once; upgrade-created matches resolve before gravity. T8 terminal recovery has no successor and does not fulfill an outlet demand. |
| D06 — Work | Ordinary rooms 16, finale 20. Every valid normal swap costs one, independent of match size. No baseline refunds; no carry between rooms. Completion on the last Work wins. At zero Work after resolution, no new tool/action is accepted. |
| D07 — Craft | Capacity 6; first-room starting amount 1. Best normal-action match awards 0/1/2 for 3/4/5+ or intersection. Family gains plus base award cap at 3 for the whole action. Next-room entry is `max(1,min(3,carried Craft))`, then a selected one-time reward bonus, capped at 6. Earnings become spendable at the next input boundary. |
| D08 — Tools | Reposition 2 Craft, Chisel 2, Refine 3. One activation between valid swaps, available on room entry; no Work cost or hazard tick. Chisel can damage an obstacle/lock or remove T1–3; Refine promotes T1–4 once. Tool descendants grant no resource/family/reaction refunds. A setting's explicit upfront cost discount still applies. |
| D09 — Families | Quartz: first qualifying match +1 Craft. Corundum: adjacent match obstacle damage is 2 instead of 1. Beryl: once per normal action promotes lowest T1–3 neighbor of survivor, ties ascending `(y,x)`; no legal target does not consume use. Source family is captured before promotion. |
| D10 — Effects | Immutable facts, typed intents, root/parent cause and inherited eligibility. Match consumption, effect clearance, terminal recovery and extraction have distinct removal reasons. One removal identity prevents duplicate counting. No scene callback determines a perk. |
| D11 — Hazards | Ship rubble only: 2 durability, no gem in its cell; one hit per adjacent committed component per obstacle, modified by Corundum. Permanent holes, obstacle occupants, locks and floor overlays have separate ownership. Seal fixtures reserve future semantics, not extra prototype content. |
| D12 — Settings | Only Steady Hand and Beryl Bridge initially, unique/nonstacking, three equipment slots. First Chisel each room costs 1 with Steady Hand. Bridge extends Beryl targets through T4 without a second activation budget. Other candidate settings remain deferred. |
| D13 — Carry | Select up to two remaining T4+ pieces; extracted pieces cannot carry. Preserve tier/instance ID; clear temporary statuses. Reward conversion changes identity at that same tier with no reaction. Staging overwrites generated pieces without payout. |
| D14 — Extraction | Automatic at stable boundaries, ascending `(y,x)`, one demand unit per qualifying gem. Stop on completion before another refill/hazard tick. Otherwise resolve extraction continuation with inherited reward suppression. Commission requires three T3+ deliveries; vault one T5+. |
| D15 — Room sequence | Open seam: four marked 2-hit rubble, 16 Work. Then choice of six marked rubble/16 Work or commission/two bottom outlets/16 Work. Vault: two rubble gates/two outlets/20 Work. All 8×8. Exact full room layouts/opening seeds become admitted P2/P3 content; the P0 local fixtures are not complete expedition rooms. |
| D16 — Rewards | After each nonfinal room, choose one of three distinct offers drawn once from eligible Aquamarine replacement, unowned prototype settings and one fallback (+1 next-room starting Craft). No duplicate fallback cards to pad a pool. The initial four-offer pool remains large enough for both reward screens after one choice. Persist offers and selection. |
| D17 — Opening/recovery | Choose 64 as the bounded opening-generation attempt limit; preserve carry, admit no opening matches and at least one legal swap. Exhaustion is invalid content, not loss of a carried gem. Dead-board recovery reshuffles only movable T1–3 when no swap/usable tool exists, at most 64 attempts. No payout or cost; unrecoverable result is `board_locked`. |
| D18 — Presentation | Keep current delivered bindings through P1–P3. Tier badges on by default when UI work lands. Stable shapes/backings must support overlapping mineral colors; no arbitrary gem tint or mid-run palette reassignment. All simulation commits precede playback. |

The five run seeds in `rules.json` and per-fixture seeds are reserved deterministic regression inputs. They are **not vetted solvable room openings**. That requires the new room generator/resolver and remains a P2/P3 exit condition. This distinction prevents old free-opening-cascade behavior from being frozen accidentally.

### Grade intent coverage

The nine entries in the rules index record a source stone hash, actual existing `GemGrade` resource reference, appraisal tier and plain-language specimen intent. Quartz is an attractive accessible specimen; amethyst/peridot/topaz progress through selected colored-gem intents; sapphire/aquamarine are alternative fine selections; emerald/ruby/diamond are exceptional/prestige/flagship selections. These are game curation decisions under the existing sourced design policy, not certified values. Existing physical sources and grade resources are unchanged.

## Ordered implementation backlog

Here **Bxx** identifies a backlog item and **P1/P2/P3** identifies a build milestone. The old rewrite review's “P0” severity label meant “repair before dependent content”; those code repairs are scheduled below, not claimed completed by this planning milestone.

| Order | Work and source owner | Acceptance / dependency |
|---|---|---|
| B01 / P1 | Authoritative action validator; `run_controller.gd` begin/attempt APIs, `board_state.gd` swap boundary | Distant, same, empty, locked and immovable/unrelated-match cases reject without state/RNG change. One shared query for UI/bots. |
| B02 / P1 | Topology-purpose queries and connected matching; `board_state.gd`, `match_detector.gd`, `match_classifier.gd` | 3/4/5/L/T/multi-intersection fixtures; one owner/survivor per component; portal never creates a match; bounded traversal. |
| B03 / P1 | Canonical state identity and injected content; board/tile/cell state, RunState, SeededRng, registry/bootstrap adapter | Hash status values/portals plus full topology, roster/supply/RNG/counters as introduced; stable IDs; no optical state or runtime scene lookup in pure rules. B01/B02 define legality/ownership being recorded. |
| B04 / P1 | Complete settle/refill and explicit failure; `board_physics.gd`, `spawn_resolver.gd`, `turn_controller.gd` | Occupied-entry and entry-refill fixtures; ZERO gravity fallback; no silent cap success; preserve admitted layout on reroll. |
| B05 / P1 | One complete action transaction and chronological events; RunController/TurnController, EventLog/Timeline | Remove duplicated rule finalization, record source snapshots and paths; acknowledgment/skip/restart cannot charge twice. B01–B04 supply trustworthy state transitions. |
| B06 / P2 | RoomState, Work/Craft, rubble, tools, recovery; core/run plus typed obstacle ownership | First/last action win, tool suppression and recovery cases. Fixture expectations become actual Godot regression assertions here. |
| B07 / P2–P3 | Family dispatcher and effect arbitration; planner/conflict/resolver | Three family rules, deterministic target selection, shared budgets, stale-target handling; no generic protection promise from currently unused flags. |
| B08 / P3 | Collection replacement, supply data, settings, carry, commission/vault and reward/route flow | Outlet delivery counted once; carry conversion/setup cannot reward; fixed offers; three-room completion with baseline art. |
| B09 / P1 then P3 | Versioned restore/replay; save/replay services, canonical snapshot | Full state boundary in P1; complete room/offer/carry restore as fields land in P3. Identical actions reproduce state; unsupported versions reject. |
| B10 / P2 then P4 | Public input gates and application flow; RunScene/BoardScene/TileView/menu | Small functional HUD in P2; full split/UI in P4. Loading/error/modal/playback gates compose; no final unlock after later failure; mouse-ignore invariant retained. |
| B11 / P3 then P6 | Raw layout admission; BoardValidator/layout resources | Reject out-of-bounds/blocked spawn entries before applying layout; validate objective access. Portal/custom gravity rooms wait for trajectory and layout gates. |
| B12 / P4–P5 | Reviewed art/short tilt, package allowlists, game acceptance tools | Recognition, release interaction, page budgets and retained engine delivery checks. No optical rewrite bundled into P1. |

The six earlier diagnostic findings map directly to fixtures: `multi_intersection`, `status_value_hash`, `portal_hash`, `occupied_spawn_entry`, `portal_not_match_adjacency`, `zero_gravity_fallback`. Their expected outcomes describe the repaired behavior. Existing [probe evidence](../artifacts/game-design-review/probe.json) documents the old failures; P0 has not rerun it or converted it into a passing product test.

## Contract migration register

P0 originally recorded proposed edits to the then-detailed AGENTS.md here, scheduled
with P1–P3 implementation. It did not edit the root file at that stage. Following
the user's root-guide review, AGENTS.md and the root README were rewritten on
2026-09-14 as navigation and durable guidance; that rewrite is now complete.

The table below retains the behavioral topics and implementation timing. Its old
section names identify topics, not instructions to restore those sections in
AGENTS.md. Detailed updates belong in the relevant subsystem contract/guide and
regression tests when code lands. Use `ARCHITECTURE_HARDENING.md` and the source
review to route game topics until their code-adjacent guides exist. Root guides
change only when navigation, project status or enduring principles need updating.
The original P0 snapshot remains unchanged.

| Former AGENTS topic | Owning behavior/documentation update when implemented | Milestone |
|---|---|---|
| Turn Pipeline | Replace animation-separated begin/resolve/finalize with one authoritative committed transaction; playback never applies costs/checkpoints. Document canonical chronology and error rollback. | P1 |
| Adjacency / Match Detection / Board Topology | Make query purpose explicit through BoardState; matching/swaps ignore gravity portals. Preserve portal behavior for movement. This clarifies the present contradictory broad/narrow wording. | P1 |
| Gravity | Implement/document cell ZERO→DOWN fallback; floating requires a future explicit mode. | P1 |
| Merge Mechanic | Canonical component/survivor ordering; injected active roster controls next tier; remove production debug fallback/dual static-ladder claims as migration lands. | P1–P3 |
| Layer Boundaries / Key Autoloads | Move registry/config/replay lookup into bootstrap adapters; pure core consumes immutable catalog and explicit recorder/state. | P1 |
| TileState / CellState | Stable identity, complete hash/serialization, explicit piece/obstacle ownership; T0/T9 are not standard appraisal tiers. Add only fields used by implemented features. | P1–P3 |
| Move rule in Turn Pipeline | Every valid normal swap costs 1 Work; bounded Craft and tools replace the old −1/0/+1 policy. | P2 |
| Board refresh invariant | Preserve `board_changed` only for start/reroll. Introduce explicit `room_started` snapshot handoff for room transitions. | P3 |
| Deferred systems / project paths | Link current implemented game docs and mark newly delivered family/room/settings systems accurately. Do not import archived feature scaffolding. | As each phase lands |

Unchanged invariants: seeded integer simulation, BoardState-owned topology/gravity, core/render separation, TileView mouse ownership, immutable offline optical authoring, read-only runtime delivery, and explicit missing-asset failures. P0 authorizes no engine transport, compiler, grading, material or export-contract relaxation.

## Validation and next handoff

P0 validates the baseline snapshot and fixture consistency with [the review checker](../artifacts/game-p0/verify_p0.py). Its [results](../artifacts/game-p0/verification.json) distinguish structural/data checks from gameplay implementation. It verifies frozen checksums, project settings equivalence, fixture geometry/expected match components/survivors, the recoverable multiset witness, delivery completion and nine-gem coverage.

No full smoke suite rerun is necessary for these planning/fixture data additions. The prior 113 smoke assertions remain earlier evidence. No actual game rules, authored gems or scene files changed. New fixture data is versionable under `tests/fixtures/`; local design/baseline/report files follow the repository's ignored docs/artifacts policy.

Next implementation task: **B01–B03 / P1: legality, match ownership and complete state identity**, using existing sprites. Add focused Godot regression adapters for the corresponding fixture phases. Do not combine that first batch with a new gem catalog, shaders or UI redesign.

## Subsequent pre-P1 hardening addendum

The [architecture audit](ARCHITECTURE_HARDENING.md) and [non-gem asset brief](PRESENTATION_ASSETS.md)
were added after the freeze at the user's request. They specify neutral terminology,
workspace/policy boundaries, exact replay encoding, explicit RNG/settling/fill
protocols, shared future-editor admission and P2–P4 presentation production. The
frozen `facets.prototype.v1` files and 23 cases were not rewritten. These protocol
choices must be versioned when P1 is implemented; they are not existing behavior.
