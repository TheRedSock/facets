# Facets — game design

Status: recommended design, 2026-09-14. This is a proposal for the game to build, not a description of implemented gameplay. The user selected a balanced emphasis on family builds and tactical board objectives. Numbers below are initial tuning hypotheses. The [content systems design](CONTENT_SYSTEMS.md) specifies appraisal/grade, readability, cuts, event reactions, family expansion, room themes, settings and special pieces. Its prototype/expansion labels distinguish foundations from future content. Current implementation, integration, art review and milestones are in the [rewrite review](GAMEPLAY_REWRITE_REVIEW.md), [integration plan](GAME_ENGINE_INTEGRATION.md), [gem review](GEM_ART_REVIEW.md) and [build plan](PROTOTYPE_BUILD_PLAN.md).

## 1. Direction

P0 selected the initial prototype subset as **`facets.prototype.v1`** on
2026-09-14. The [frozen decisions and baseline](P0_BASELINE.md) govern its
implementation; expansion examples below remain proposals. P1's functional
foundation has been implemented; its fluidity/performance acceptance is reopened
in the [P1-A amendment](../plans/P1_FLUIDITY_AMENDMENT.md).

**Build a collection of real gemstones, turn it into a distinctive merge engine, and use that engine to solve a sequence of constrained boards. Carry your best pieces forward and extract a flagship gem from the final chamber.**

The primary mode is a single-player, untimed, turn-based expedition. Adjacent swaps create three-or-more matches; each match condenses into one higher-rank gem. Limited actions, awkward terrain and valuable pieces competing for board space create the tactical problem. Drafted gems and jewelry settings change how the player solves it.

### Motion and player timing

The intended presentation is physically coherent and locally concurrent: newly
unsupported stacks begin together, short falls finish sooner, and independent
motion need not wait for decorative effects elsewhere. The engine resolves the
whole current-mode action before playback. Animation duration, frame rate and
cosmetic gravity do not change matches, costs, RNG or outcomes. Upgrade-created
matches chain before gravity; preserve this rule and make it visible.

P1-A restores concurrent motion with conservative settling-wave barriers first.
Early presentation of a later committed match is allowed only with proven visual
dependencies; transient alignment during a fall is not an additional v1 match.
Basic fluidity is a foundation requirement, not deferred art polish.

An optional future direction is a player intervention on a surviving promoted
gem before gravity. This could add tactical authorship and reaction skill, but
changes the current untimed action boundary. The
[reactive-play assessment](FLUIDITY_AND_REACTIVE_PLAY.md) proposes a separate,
bounded experiment after the first P2 room, beginning with an untimed window and
then testing time pressure. Costs, episode reward caps, input eligibility,
failure/publication and replay need explicit policies. Neither reactive input
nor timing-dependent matching is adopted into `facets.prototype.v1` by this
proposal. Preserve the option architecturally without building a clocked engine
in P1 or changing the frozen baseline.

The game should make the player say both “that combination made my build work” and “I put the survivor in the right place.” A numerical combo without a spatial decision, or a puzzle with irrelevant rewards, fails the direction.

Product targets:

- Windows desktop first, 1920×1080 reference layout; scalable UI and touch-compatible actions, with mobile validation later.
- Initial prototype: three rooms, roughly 10–15 minutes, one branching choice and a rank-5 extraction finale.
- First complete game slice: six rooms, roughly 25–40 minutes, three family archetypes, a rank-7 finale and optional rank-8 distinction. These durations require playtests.
- Loss ends the expedition. Restart is immediate; no energy system, purchased rescue moves or permanent stat grind.
- Long-term progression unlocks alternate starting collections, settings and room challenges. A fresh profile must already have a viable complete game.

## 2. What each inspiration contributes

These are selected design lessons, not promises to reproduce entire games.

| Reference | Adopt in Facets | Limit |
|---|---|---|
| [Merge Maestro](https://store.steampowered.com/app/3519530/Merge_Maestro/) | Drafted pieces and powers create combinations through merging | Do not copy its placement/combat loop or content volume |
| Gems of War: Treasure Hunt | A surviving upgraded piece makes match resolution accumulate value | Do not require indefinite extra-turn survival; its detailed rules are not treated as current implementation requirements |
| [Slay the Spire](https://store.steampowered.com/app/646570/Slay_the_Spire/) | Consequential rewards and visible route tradeoffs | No separate combat/health subsystem in the prototype |
| [Balatro](https://store.steampowered.com/app/2379780/Balatro/) | A small familiar grammar becomes expressive through interacting modifiers | Build interactions serve spatial contracts; no separate exponential appraisal score |
| [Dead Cells](https://store.steampowered.com/app/588650/Dead_Cells/) | Distinct routes, quick return after failure and learning across runs | No reflex pressure or action-combat imitation |
| [Candy Crush level modes](https://candycrush.zendesk.com/hc/en-us/articles/360000754897-Which-game-modes-will-I-find) | Location-specific clearing, delivery targets and constrained move budgets | No monetized retries or indiscriminate destruction of accumulated gems |

## 3. Design pillars and boundaries

1. **Readable decisions.** Shape identifies rank; name/color identify the gem; a separate icon identifies family. Show the next upgrade and the reason a rule fired.
2. **Investment survives.** Ordinary room hazards constrain space or access. They do not silently delete a flagship gem. Destructive tools require an explicit target and preview.
3. **Build changes tactics.** A family perk must change which merge or route is desirable, not only multiply an end-of-room number.
4. **Finite pressure.** Player actions consume a room budget. Cascades reward planning without generating an unbounded supply of moves.
5. **Real gems, fictional systems.** Mineral relationships and appearance have sources. Magical upgrading and compressed appraisal bands are game rules.
6. **The asset engine serves the game.** Beautiful images must read on a busy board. Every new optical feature needs a demonstrated game-content requirement.

Do not build combat, crafting currencies, a full shop economy, T9 artifacts, 72 gems, procedural crystal growth or multiple match grammars for the initial prototype.

## 4. Identity: appraisal tier, specimen and family

**Tier is the single appraisal axis.** T1–T8 are broad game value bands for authored specimen profiles, informed by material, grade, size context, desirability and scarcity. “Rank” in current code/docs means this same tier, not a second stat. Remove the earlier independent `1, 3, 9, …` appraisal score. Use tier thresholds/counts for commissions and results.

| Concept | Meaning | Consequence |
|---|---|---|
| Appraisal tier, T1–T8 | Broad value band of the selected specimen profile | Match class, silhouette, next-tier progression, contract eligibility |
| Gem definition | A named material/variety and admitted specimen intent | Stable identity, family, art and optional signature |
| Grade profile | Authored quality rationale for that specimen | Supports tier placement and later bounded grade variants; not a second power/value level |
| Family | Curated species/group relationship | Shared reaction and supporting rewards |
| Reward weight | Internal frequency of an offer | Balance parameter, not a player-facing second rarity grade |

Amethyst is quartz; emerald/aquamarine are beryl; ruby/sapphire are corundum. Garnet and tourmaline are groups; alexandrite belongs to chrysoberyl, not beryl. Keep source-backed membership in metadata. Cross-family themes such as Patterned are called **affinities** and grant nothing unless a rule references them. See [source notes](GEM_ART_REVIEW.md#mineral-and-value-source-notes).

The current ladder remains a provisional selection of representative specimens, not a universal market ranking. Grade can justify limited adjacent-band variants of the same material later. It cannot make every mineral fit every tier. Existing `GemGrade` axes are descriptive metadata; they do not calculate appraisal or alter optics. Use material-appropriate grade rationale rather than a universal “higher tier = clearer, harder, more saturated” law. The [appraisal and grade policy](CONTENT_SYSTEMS.md#2-appraisal-tiers-and-grade) defines the catalog review and future grade exchanges.

Upgrading is a magical exchange abstraction. Three amethysts becoming peridot is not geological growth, cutting or heat treatment. A later cosmetic recut preserves tier; an admitted grade exchange is an explicit roster change with a preview.

## 5. The collection is the deck

### One active gem per rank

The run contains eight ordered slots, exactly one gem definition in each. Rank-1 to rank-4 spawns draw from those slots; upgrades always resolve into the next active slot. Rank-5 to rank-8 are normally merge products. A roster strip permanently shows all eight slots and their arrows.

The starter collection remains:

`Quartz → Amethyst → Peridot → Topaz → Sapphire → Emerald → Ruby → Diamond`

A gem draft **replaces a slot**. It does not add another matching color to an already crowded board. A Smoky Quartz offer replaces Amethyst at rank 2; it changes appearance and, once concrete individual traits are added, behavior. An Aquamarine offer replaces Sapphire at rank 5, increasing access to beryl reactions while giving up a corundum entry point.

Family matching does not mean merging unlike gems. Three beryl pieces of different ranks cannot match. Same-colored gems do not automatically match. Rank identifies the active match class because only one definition is active at each rank.

Replacement occurs only between rooms. Retained pieces in the replaced slot convert to its new gem identity, preserve rank and stable instance identity, and emit no gameplay triggers. Show this conversion on the reward preview. The new roster is frozen before the next board is generated. This prevents mixed old/new matching groups within a room.

### Draw rules

Begin with the current integer spawn weights `[4, 3, 2, 1]` over ranks `[1, 2, 3, 4]`. Show these as 40/30/20/10 percent in the collection panel. These are independent weighted draws, not a finite bag and not guarantees about the visible board after merges.

Keep **collection** and **supply** separate in data. Collection selects one definition per appraisal tier and owns ascending upgrades. Supply entries point to collection tiers with integer weights. A future setting can redirect the third supply entry to T5: that gem keeps its T5 silhouette/matching and upgrades to T6, while T3 remains reachable through merging. This is the recommended interpretation of “a T5 gem in the T3 slot”; do not create a hidden second tier on the same piece. See [supply settings](CONTENT_SYSTEMS.md#3-collection-versus-supply-the-high-tier-slot-setting).

The prototype implements only the default supply mapping. Later weight/target changes are explicit between-room transactions. Admit at least three distinct supplied tiers, no hidden adaptive luck, and no additional unrelated match colors. Save effective supply and RNG state.

## 6. Board rules

### Input and matching

- Normal action: swap two orthogonally adjacent, occupied, movable, unlocked gem cells. A normal swap must create a match involving a swapped cell. Invalid swaps cost nothing and alter no rule state or RNG.
- Three or more identical active match classes in a straight horizontal or vertical line match. Connected intersecting runs of the same class form one match component, with one survivor. No diagonals or 2×2 rules initially.
- Survivor: swap destination, then origin if it belongs to that component; otherwise greatest `(y, x)` among the component's cells. This makes the old informal “bottom-right” rule explicit even for intersections.
- Remove every other member and upgrade the survivor exactly one rank. Larger matches still produce one survivor; their compensation is Craft, below.
- Recheck upgrade-created matches before gravity. Resolve gravity/refill and further cascades until stable.
- Rank-8 matches are terminal collections: remove the matched pieces and record recovered specimens by tier, never create rank 9. Terminal recovery does not satisfy an outlet contract. A rank-8 piece meant for extraction remains valuable until actually consumed.
- Portals affect falling only. Matches and normal swaps use ordinary orthogonal topology. Route all topology decisions through `BoardState`; never let a scene calculate game legality.

### Work and Craft

**Work** is the room's action allowance. Start testing ordinary rooms at 16 Work, finales at 20. Every accepted normal swap costs one. No baseline rule refunds Work. Work resets to the next room's budget and does not carry.

**Craft** is a visible tactical resource, 0–6. Start each room at 1. After an accepted normal swap, award Craft from the strongest match anywhere in that turn: 3-match = 0, line-4 = 1, line-5+ or L/T = 2. Do not add the reward separately for every cascade. Family/settings bonuses may raise the total earned in one normal turn to at most 3. Unspent Craft carries between rooms, capped at 3 on entry, with a floor of 1.

Baseline tools, available to every build:

| Tool | Cost | Exact effect |
|---|---:|---|
| Reposition | 2 Craft | Exchange two orthogonally adjacent movable gems without requiring a match. Locks still prevent movement. Resolve any resulting matches normally. |
| Chisel | 2 Craft | Deal one damage to a chosen blocker/lock; alternatively remove one chosen rank-1–3 gem. Preview the target. Never remove rank-4+ gems. |
| Refine | 3 Craft | Upgrade one chosen rank-1–4 gem by one slot; then resolve resulting matches. It cannot directly produce rank 6 or higher. |

Only one tool activation is allowed between accepted normal swaps; entering a room opens this allowance. A tool costs no Work and does not advance hazard timers. **Tool-origin cascades grant no Craft, family reactions or setting refunds.** They can progress objectives. This avoids profitable tool loops. A normal swap reopens the tool allowance.

This replaces the prototype's `-1 / 0 / +1` move policy. It is a proposed mechanics change and requires the documented move-rule contract to be updated when implementation begins. Keep the old policy only as an explicitly selected comparison in the balance harness.

### Hazards

Use separate obstacle/lock/floor layers; do not overload a gem's rank with “T0.” A blocked topology cell is permanent terrain, not a breakable obstacle. Later catalyst/cargo pieces have an explicit piece kind; opaque or organic materials may instead be ordinary appraised gems. See [special pieces and materials](CONTENT_SYSTEMS.md#10-t0-t9-and-patterned-or-organic-materials).

| Hazard | State and interaction | Tactical purpose |
|---|---|---|
| Rubble | Occupies a cell without a gem; 2 durability; cannot swap or fall. A committed match adjacent to it deals 1 damage, once per match component per obstacle. At zero, opens the cell for gravity/refill. | Choose a merge position, create access |
| Seal | A 1-durability lock over a gem; gem cannot swap/fall but can participate in matches. An adjacent match removes the seal; a match containing the sealed gem removes the seal before its normal merge. | Restrict movement without requiring random destruction |
| Encroaching dust | Cell overlay, no mineral claim. Every third accepted normal swap, one dust cell spreads to one eligible orthogonal neighbor. A match involving a dusty cell clears its dust. Dust blocks extraction while present, but not matching or falling. | Prioritize an announced deadline |

For spread, choose source and destination using stable cell order and `SeededRng`, and preview the scheduled target at the previous turn's end. A cleared/invalid target cancels that scheduled spread; do not secretly retarget. New dust waits for the next scheduled spread. No spread occurs after room completion. Start with rubble only; seals and dust enter later phases.

Abilities that damage rubble/seals never damage adjacent gemstones. The visual effect can be a burst without implying a board-wide gem explosion.

## 7. Family builds and settings

Family mechanics are fictional abilities inspired by relationships, not claims that stones heal, attack or manipulate matter. For the first slice, each supported family has one reaction shared by its members; individual gem traits come later only when replacements need more differentiation.

| Family | Reaction during normal-swap resolution | Build consequence |
|---|---|---|
| Quartz | First quartz-family match in a turn grants +1 Craft, within the total gain cap of 3 | Reliable access to tools from low-rank activity |
| Corundum | Its matches deal 2 rather than 1 adjacent damage to rubble/seals | Choose hazard-heavy routes and position rare merges carefully |
| Beryl | Once per turn, after a beryl match, upgrade the lowest-rank orthogonal neighbor of its survivor among ranks 1–3. Ties use `(y, x)` ascending. If none exists, do nothing; the reaction is used only when a target exists. | Engineer a high-rank merge beside a low-rank chain starter |

A family is active when a matched gem carries that verified family tag; there is no additional “equip two members” threshold. A Beryl-created upgrade can form a match, but cannot activate Beryl a second time in the same turn. Reaction budgets are shared by the whole family, not per tile or per chain. Other families and independent gems are ordinary pieces until their actual behavior is admitted. The [family expansion map](CONTENT_SYSTEMS.md#6-family-vocabulary-and-mineral-relationships) proposes Garnet consumption, Tourmaline assisted swaps, Feldspar routing, Chrysoberyl alternation and Fluorite arrivals; none is required in the prototype.

This initially makes Quartz the accessible tool economy, Corundum the spatial demolition build, and Beryl the chain-building option. Their access differs: Quartz appears early, Beryl/Corundum need high-rank products. Reward offers must show this timing; the first room must not demand a rare family reaction to win.

A **reaction** is an event-triggered ability; a **signature** distinguishes a particular gem; a **technique** enhances one collection entry; a **setting** modifies the expedition. Settings fill the relic/boon role—do not introduce three parallel equipment systems. Family identity remains scientific metadata; its game ability is fictional.

The [lifecycle contract](CONTENT_SYSTEMS.md#7-lifecycle-events-and-deterministic-reactions) separates arrival, movement, assisted swaps, committed matches, consumed members, promotion into a new identity, removal causes and extraction. Preserve source snapshots and root causes; select typed effects with deterministic budgets. The first three family handlers exercise that shared foundation without requiring a general scripting framework.

Consider six nonstacking settings, maximum three equipped. At capacity, replacing one is explicit. Apply them in fixed slot order; never depend on dictionary iteration.

| Setting | Initial rule | Role |
|---|---|---|
| Deep Pockets | Carry three gems between rooms instead of two | Investment |
| Steady Hand | The first Chisel in a room costs 1 Craft | Terrain control |
| Quartz Lens | The first Reposition in a room costs 1 Craft if a quartz match has occurred in that room | Consistency |
| Beryl Bridge | Beryl's eligible neighbor range becomes ranks 1–4 | Chain building |
| Corundum Teeth | A corundum match also deals 1 damage to each obstacle exactly two orthogonal steps from any matched cell; deduplicate targets; walls block the path | Route specialization |
| Patient Cutter | Enter each room with at least 2 Craft instead of 1 | Flexible setup |

These are concrete first experiments, not six mandatory prototype features. No random parameter dictionaries, unlimited stacking, two-to-one merges or permanent free-turn generators.

Example build decision: replace Sapphire with Aquamarine to activate Beryl before rank 6. That opens Refine/chain setups near emerald, but delays Corundum's hazard advantage until Ruby. Choose an open extraction route instead of a rubble-heavy route; a later Corundum setting may reverse that decision.

## 8. Rooms, persistence and run flow

### Structure

`Start collection → Room briefing → Play → Carry selection → Reward → Route choice → Next room → Finale → Results`

Rooms use authored layouts with seeded gem populations and small admitted variations. Offer two room cards at selected transitions. Each card shows objective, action budget, terrain thumbnail, pressure rule and reward category. Never hide a rule that can invalidate a build. Route generation filters incompatible objectives against the selected roster and reachable ranks.

| Objective | Completion rule | Prototype role |
|---|---|---|
| Commission | Extract the displayed number of gems at or above a minimum tier through marked outlets; each gem fulfills one demand unit | Learn merge-versus-bank choices |
| Clear the seam | Remove all marked rubble; ordinary unmarked rubble is optional | Spatial planning |
| Flagship extraction | Extract one gem at or above the target rank through an unlocked marked outlet | Finale, combines investment and positioning |

Extraction is automatic at a stable board boundary when a qualifying gem occupies an active outlet. Clearly mark qualifying tiles and outlet thresholds. Qualifying gems leave in `(y, x)` order and fulfill one demand unit each. No separate numerical appraisal score is calculated. If the objective completes, stop room simulation before refill or hazard tick. Otherwise settle/refill and resolve again; extraction-caused cascades do not generate Craft or family/settings reactions. This continuation is still part of the same authoritative action, not another Work expenditure.

For a normal turn, finish match/trait/gravity resolution, apply eligible extraction/objective progress, then—if incomplete—advance the scheduled hazard, settle again if necessary, and evaluate failure. **Completion on the last Work wins.** No waiting for animation to decide the result. A room with zero Work cannot accept another tool; any qualifying final extraction has already resolved.

### Keep investment without carrying the entire board

At room completion, freeze the board. Select up to two remaining rank-4+ gems to carry (three with Deep Pockets). Keep rank, gem identity and stable instance ID. Clear temporary locks/dust/statuses; no automatic upgrades, merging, triggers or sale income. Extracted gems have already been consumed and cannot also carry.

Next room uses a fresh layout. Carried gems replace the generated occupants of predefined staging cells in carry-slot order; those displaced ordinary pieces produce no rewards. Preview these staging cells in the briefing. Generate/retry the surrounding opening population so it has no automatic opening match and at least one legal swap, without silently changing the carried gems. Generation is bounded and records attempts. If constraints cannot be satisfied, report invalid content; do not destroy an investment to recover.

This is intentionally a small inventory. Keeping every high-rank piece would turn transitions into free storage and erase board-space pressure; resetting every piece would undermine the merge fantasy.

### Initial three-room expedition

1. **Open seam:** 8×8, 16 Work, four marked 2-hit rubble cells, starter collection. One reward after clearing.
2. **Route choice:** either a 6-rubble seam (16 Work) or a commission (16 Work, extract three rank-3+ gems, two bottom outlets). Both offer a reward; carry selection after completion.
3. **Vault:** 8×8, 20 Work, two rubble gates near two outlets, extract one rank-5+ gem. A rank-6 extraction earns a cosmetic distinction, not a requirement.

Use vetted opening seeds for the first human sessions. Difficulty and quotas are not yet established. Expanding to six rooms adds seal/dust variants and a rank-7 finale only after observed reachability supports it.

## 9. Rewards and economy

After each nonfinal room choose one of three distinct offers: a legal gem replacement, an eligible setting, or a conservative fallback (+1 starting Craft in the next room, applied once and capped at 6). Offer generation excludes duplicates, unavailable families with no foreseeable access and replacements that would make a required objective impossible. A displayed reward must not reroll on reload.

Prototype rewards are free. Appraisal is represented by tier; commissions count eligible deliveries. There is **no separate appraisal score or spendable currency**. Gold, silver, dust crafting, shops and risky treatments remain later extensions. This keeps room choices and roster decisions testable without an economy masking their problems.

Gem replacements must eventually offer real tradeoffs. Amethyst/Smoky Quartz currently share family and slot, so a cosmetic-only replacement is not an acceptable sole gameplay reward. Exclude such offers until a concrete trait, condition-independent gameplay effect, or paired setting gives them a reason to exist. Reuse their art in selection/review without pretending it is a different build.

## 10. Dead boards, runaway chains and fairness

- Enumerate legal actions in simulation at every input boundary. Hints and automation use the same query.
- If no legal normal swap exists but a legal affordable tool exists and the tool allowance is open, show that option.
- If neither exists, perform a deterministic reshuffle of movable rank-1–3 pieces only, preserving higher-rank investment, obstacles, Work and Craft. Seek no immediate matches plus a legal swap in at most 64 attempts. Show one “rearranging loose stones” event; grant no rewards.
- If reshuffling cannot recover, end with a distinct “board locked” result and capture the seed. This is a tuning/content failure candidate, not a hidden gem reroll. Do not change high gems or create a match to force recovery.
- Caps for effect reactions, settling and cascades are error guards. Reaching one returns an explicit failed transaction/debug record, not a silently accepted unresolved turn. Production must be tuned so this never occurs in admitted content.
- Make randomness visible at the decision level: advertised spawn weights, fixed reward cards, scheduled hazard targets. Never claim to preview unknown future draws.

## 11. Art, interface and feedback

Work, Craft, tools and settings are current presentation terms, mapped from stable
mechanical IDs. Vocabulary, Theme, UI assets and audio/VFX are selected through a
game presentation profile; changing the setting or labels cannot alter replay
results. The [architecture audit](ARCHITECTURE_HARDENING.md) specifies that boundary.
The [presentation production specification](PRESENTATION_ASSETS.md) defines the
prototype's exact non-gem asset inventory, generation methods and acceptance.

The visual direction is **a restrained jeweler's work surface with vivid, readable stones**. Keep the physically grounded gem render, but simplify surrounding detail. Backgrounds, rank badges and hazard shapes do the semantic work that optics cannot reliably carry.

At 1080p, budget a roughly 960px board area for 8×8 cells with 112px gem canvases and spacing. Put collection/next-upgrade information on one side and objective/Work/Craft on the other. Do not enlarge 112px deliveries to 200px as the default. At smaller windows scale the whole composition or switch to a stacked HUD; validate at 80px effective cells before considering mobile.

Required information during a turn: objective and threshold, Work, Craft, tool allowance/costs, active settings, next hazard tick/target, selected tile's name/rank/family/next upgrade, and the eight-slot collection. Full mineral notes belong in an optional collection inspector.

Use a ring/corner marker for selection instead of tinting the stone yellow. Give hazards durability pips and distinctive textures/icons. Rank numerals and family icons must remain readable in grayscale. Color-change gems keep one stable board color; demonstrate their change under different illumination in the inspector, not as an idle matching cue.

Readability must survive a roster containing fluorite, green tourmaline and emerald together. Tier numerals are on by default; strengthen silhouettes and offer clean tier-shaped backing motifs. Optional “jersey” colors belong on those UI surrounds, not as arbitrary mineral recoloring. Admitted natural-looking variants can improve contrast, but do not replace shape/badge recognition. Cut skins stay within a tier envelope: cushion-like and princess-like T2 variants are possible; round T6 or heart T2 defaults are not. Techniques are explicit mechanical enhancements, never hidden skin benefits. Full policies are in [readability and cuts](CONTENT_SYSTEMS.md#4-readability-under-any-admitted-collection).

Rest is still. Upgrade uses a brief optical tilt and return; the renderer handles convergence, translation and scale. Tools and family reactions get distinct short sound/shape cues. Limit simultaneous audio voices; do not give every cascade a louder sound indefinitely. Reduced motion substitutes a short opacity/scale cue and still gem art, with identical rule results. Add mute, volume, animation speed, keyboard selection and a hold-to-inspect equivalent for touch.

First-session teaching: one three-match with a highlighted survivor, one deliberate four-match and Craft spend, one rubble interaction, one carry selection and one roster reward preview. Avoid opening with a mineral encyclopedia or all eight families.

## 12. Tuning and falsification

The ideal pure three-to-one ladder costs `3^(rank−1)` rank-1 equivalents; rank 8 is 2187. This is an internal merge-investment diagnostic, not appraisal, score, currency or a run-length prediction. Rank-2–4 spawns, opening cascades, larger matches, Refine and carryover change the economy. With the starting weights, a direct spawn averages `(4×1 + 3×3 + 2×9 + 1×27)/10 = 5.8` rank-1 equivalents before subsequent play. Measure actual generation/consumption and chain depth instead of copying archived board-frequency percentages.

Track per seed/build: room win/fail and reason; Work spent; highest rank created/extracted; carried ranks; Craft earned/wasted/spent; legal-swap count; tool usage; hazard damage; reaction sources; reshuffles; cascade caps; wall-clock decision/playback time. Record whether goals were completed by a planned swap, a tool or a spawn cascade.

Test these failure hypotheses first:

- If the best policy ignores objectives until the end, locations/pressure are too weak.
- If Quartz always wins because it funds every tool, reduce its frequency or increase alternative benefits before adding gems.
- If Beryl cannot activate until a room is nearly over, adjust access/rewards rather than claiming a working family build.
- If Refine replaces most deliberate matching, narrow it or raise its cost.
- If players cannot predict a survivor after instruction, improve preview/tie-breaking before adding effects.
- If carryover makes the finale automatic, require delivery through meaningful terrain and reduce carry capacity; do not delete carryover invisibly.

## 13. Archived concepts: disposition

All six files in `plans/archive` were read. Their authority is conceptual only.

| Archive | Keep | Change/defer |
|---|---|---|
| `gemstone-game-design-proposal.md` | Shape vocabulary, real mineral relationships, jewelry language, broad content inspiration | Conflicting shape tables, unsupported recognition claims, 72-gem launch scope, color-based matching, blanket clears, invented mineral families |
| `gem-engine-proposal.md` | Flagship goal, deterministic effects, investment-versus-space tension | Choose merge-forward tools now; no universal modifier framework or permanent destructive A/B modes in the product |
| `family-trait-mvp-roadmap.md` | Families change room choices; objective/run logic outside board storage | Three existing supported families before four mostly new ones; no ambiguous in-family merge fallback; room proof before broad trait infrastructure |
| `deferred-systems-reference.md` | Record why speculative hooks/resources were removed | Implement only typed fields needed by concrete rules; no restoration of scaffolding by checklist |
| `getting-started-guide.md` | Small playable milestones and simulation tests | Its missing-input, portrait, anonymous-tile and rebuild descriptions are obsolete |
| `tier-visual-progression-design.md` | Need readable progression and native-size review | Reject grade→optics, monotone mineral quality, obsolete tracer knobs and presumed universal hardness/value/saturation laws |

The roadmap links `family-trait-roguelike-proposal.md`, which is absent from the supplied archive. Its contents were not inferred. The existing six documents are enough to propose this direction; a recovered document can be assessed as additional inspiration.

## 14. Content growth and decisions to revisit

The recommended prototype remains one gem per appraisal tier, three rooms, bounded Craft tools, selective carryover and three family reactions. Its foundations now explicitly include collection/supply separation, grade provenance, lifecycle facts, removal reasons, bounded reaction ownership, layered hazards and color-independent tier recognition.

Expand by pairing a build mechanic with rooms that give it purpose: Garnet consumption with local coating objectives; Tourmaline assists with arrangement; Feldspar routing with portal rooms. Add asymmetry/gaps before custom gravity/portals. Grade exchanges and compatible cut profiles enrich existing families; one later catalyst/material theme can test exceptional pieces. Heart/star masterworks are separate charged artifacts, not the ninth appraisal tier. Each step needs a readable cue, meaningful limitation and deterministic fixture.

The [content systems document](CONTENT_SYSTEMS.md) owns these expansion contracts and examples. Revisit numbers using tool dominance, family access, extraction pacing, pair-confusion data and player route choices. The [build plan](PROTOTYPE_BUILD_PLAN.md) keeps the first playable scope small; an expansion example is not a prerequisite.
