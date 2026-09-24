# Facets — content systems and expansion design

**Direction amendment, 2026-09-21:** the proposed
[merge-window foundation](../core/run/MERGE_WINDOW_PREPARATION.md) makes each
paid intervention a normal fresh move scope with an engine-derived intervention
classification. Automatic descendants retain that classification until another
paid move takes over; direct-batch-only predicates are explicit. Expiry is a free
continuation of the existing scope. Craft is settled incrementally by cumulative
entitlement, and speculative default matches produce no public effects until
commit. Successor G5 reconciled the family/suppression/cap assumptions in
[the owning P3 contract](../core/run/P3_PREPARATION.md).
Diagnostic discount/reward hooks establish the seam; new authored archetypes
remain later content work. The G0–G5 foundation is implemented and checkpointed;
G6/G7 release/performance exits remain open. The older trial's shared-episode
scope described below is a retained comparison profile, not the successor rule.

Status: recommended design, 2026-09-14. This extends the [game design](GAME_DESIGN.md), with the user's requested balance of collection building and tactical board objectives. Rules marked **prototype** belong in the first three-room game. **Expansion candidates** illustrate the intended design space; they are not a commitment to implement every row. Nothing here claims new runtime or optical capabilities.

Reading routes: [appraisal and grading](#2-appraisal-tiers-and-grade), [supply exceptions](#3-collection-versus-supply-the-high-tier-slot-setting), [readability](#4-readability-under-any-admitted-collection), [cuts](#5-cuts-appearance-technique-and-shape), [families](#6-family-vocabulary-and-mineral-relationships), [lifecycle rules](#7-lifecycle-events-and-deterministic-reactions), [effects](#8-effects-and-safe-combinations), [rooms](#9-rooms-hazards-and-route-identity), [special materials](#10-t0-t9-and-patterned-or-organic-materials), [settings](#11-settings-as-the-large-scale-build-layer), [prototype boundaries](#12-expansion-sequence-and-minimum-architecture).

## 1. A small grammar with several independent content axes

The scalable unit is a gem's **reaction to an event**, with a specific effect, target rule and budget. Mineral identity gives those reactions a coherent home; rooms give them a reason to matter. More content should create different decisions, rather than add more simultaneous matching colors.

| Axis | Player-facing meaning | What it may change | What remains stable |
|---|---|---|---|
| Appraisal tier | T1–T8, the specimen's broad game value band | Match class, progression, extraction eligibility, silhouette | One active gem definition per tier |
| Mineral identity | Species, variety or gem material | Family eligibility and authored appearance | Not inferred from color or the gem's name |
| Grade profile | Why this specimen belongs in its appraisal band | Admitted tier variants; later explicit treatment opportunities | No second value score; no automatic optics or combat bonus |
| Family | Related minerals with a shared gameplay tendency | Shared reactions and supporting rewards | Taxonomic membership is curated |
| Signature | A particular gem's optional distinguishing reaction | Timing, target or tradeoff within a family | At most one signature per active definition initially |
| Cut appearance | Named profile/faceting within the tier's outline envelope | Cosmetic appearance | Matching and power |
| Cut technique | Explicit enhancement on a collection entry | One bounded reaction modifier | Tier outline, mineral identity, normal upgrade destination |
| Setting | Equipped expedition-wide rule | Economy, routing, tools, supply or build constraints | No hidden changes to value or matching |
| Room | Layout, objective and pressure rule | Which tactics are useful | Core matching grammar |
| Special piece | A catalyst, cargo or masterwork | A clearly exceptional board interaction | No implicit new ordinary tier |

Expansion should usually add one new reaction or target pattern and reuse the other axes. Do not multiply every mineral by eight tiers, four grades, every cut, every color and every effect. A content release is a curated set with asset coverage and room tests, not a Cartesian product.

## 2. Appraisal tiers and grade

### One value axis

**Tier is appraisal.** Remove the earlier independent numerical appraisal table. T1–T8 are broad authored bands reflecting the kind of specimen shown: material, quality, size context, desirability and scarcity. They are not dollar brackets or a universal ranking of mineral species. Reward appearance weights are internal balance parameters, not a second collectible rarity/value stat.

The game compares representative jewelry/collector specimens. An authored definition records its reference size context and grade rationale; there is no live price feed or runtime market formula. Very large common material should not automatically outrank a small exceptional gem because its rendered image occupies more pixels. The existing engine's millimeter scale remains a physical transport input, not the game's appraisal calculator.

The current 16-gem ladder is a useful provisional roster. Preserve its bands for the first mechanics experiment; explicitly qualify them by specimen intent rather than claiming every sapphire costs more than every aquamarine. Painite's scarcity does not by itself establish its price relative to diamond, and a T8 color-change garnet is an exceptional selected specimen, not a statement about all garnets. The current authoring records are look-development specimens, not independently appraised stones.

| Band | Initial catalog intent | Current candidates; not a universal price list |
|---|---|---|
| T1 | Accessible ornamental/gem material | Quartz, fluorite |
| T2 | Selected common colored gems | Amethyst, smoky quartz |
| T3 | Finer colored specimens | Peridot, the authored green tourmaline |
| T4 | Premium selections of accessible material | The authored warm topaz, rhodolite |
| T5 | Valuable fine-gem selections | Sapphire, aquamarine |
| T6 | Exceptional selections | Emerald, alexandrite |
| T7 | Prestige specimens | Ruby, painite |
| T8 | Flagship specimens | Diamond, exceptional color-change garnet |

This ordering is game compression. Before expanding the catalog, review each candidate against neighboring bands, using comparable specimen context. If the comparison is strained, change the chosen grade/specimen or its band; do not invent a hidden multiplier to save the slot. Keep the starter ladder stable during the first playtests so appraisal research does not block testing the game loop.

### Grade has a specific job

The existing `GemGrade` contains `cut`, `clarity`, `surface` and `crystal` metadata. Those axes neither change optics nor constitute a gemological certificate. Reuse this authoring vocabulary as provenance, while adding the species-appropriate color/phenomenon and size rationale needed by game content. Do not average its four floats into tier. Colored-gem value factors interact, and the diamond cut-grading system is not a universal colored-stone grading rule. [GIA value factors](https://www.gia.edu/gia-news-research/value-factors-design-cut-quality-colored-gemstone-value-factors), [GIA cut grading](https://4cs.gia.edu/en-us/blog/gia-diamond-grading-reports-understanding-diamond-cut-grades/).

Three useful applications:

1. **Catalog placement:** a named specimen profile justifies one tier. “Fine aquamarine, T5” is enough on a reward card; detailed grade notes live in inspection.
2. **Bounded catalog variants:** later, one material can have two adjacent admitted appraisal bands. Each has its own definition and tier silhouette. This gives a family access at different points without pretending every mineral spans T1–T8. Normal draft rules still choose one definition per tier.
3. **Treatment content:** a later workshop can exchange a roster entry for an admitted better-grade variant in its destination tier, with the resulting roster explicitly previewed. It is a roster transaction, including any displaced entry, not an invisible per-tile +value buff. The first implementation should only offer complete validated exchanges; no free-form grade slider in gameplay.

A concrete future catalog example is an admitted T4 aquamarine profile and a finer T5 aquamarine profile. These are proposed game profiles, not existing assets or measured appraisals. Drafting the T4 profile replaces the T4 entry and gives earlier Beryl access; it uses the oval T4 silhouette. The T5 profile uses the lozenge. If both are selected they do not match across tiers, and they share Beryl's one activation budget. A workshop promotion offer can put the finer aquamarine in T5 while explicitly replacing T4 with another valid entry; it shows both changes and converts carried pieces by their existing tier. It does not simply vacate T4 or promote every carried tile for free. This makes grade affect collection construction without adding a second number to every gem.

Grade is not another combat level. A scratched piece need not lose appraisal during a room; a temporary “sealed” status does not rewrite its grade. An inclusion or translucency can be desirable for particular material, so “clearer always better” is invalid. For example, moonstone's appearance and value involve its sheen and translucency. [GIA moonstone buying factors](https://www.gia.edu/moonstone/buyers-guide).

**Prototype:** one reviewed grade intent per active gem, one tier per definition, no treatment screen or dynamic grading. The simulator receives the admitted tier and definition IDs. Authoring grade provenance stays outside runtime optical dependencies.

### Objectives without a duplicate value score

Use visible commission recipes: “extract three T3+ gems” or “extract one T5+ gem.” Each gem fulfills one demand unit and is consumed once. If a later commission has several demands, fulfill the highest minimum-tier demand the gem can satisfy, then stable demand ID; preview this rule. Three T3+ extractions and one T4+ extraction are different contracts, not automatically interchangeable through a hidden conversion rate.

Terminal T8 matches record recovered specimens for results, but do not satisfy an outlet-delivery objective without an explicit rule. Results can show highest tier, recovered counts by tier, rooms and Work efficiency. The quantity `3^(tier−1)` remains a diagnostic measure of ideal merge investment only; it is not appraisal, score or currency.

## 3. Collection versus supply: the high-tier-slot setting

Keep two small concepts separate:

- **Collection:** eight active definitions, one per appraisal tier; determines what a tile is and what the next merge produces.
- **Supply:** integer-weight entries selecting which collection tier enters through spawn cells. Normally four entries target T1/T2/T3/T4 with weights 4/3/2/1.

An expansion setting, **Elevated Mount**, can redirect the third supply entry from T3 to T5. Proposed first trial: weights remain 4/3/2/1, targets become T1/T2/T5/T4, and room Work is reduced by 3. This is a deliberately strong experiment requiring balance validation, not a confirmed fair exchange.

A spawned sapphire is visibly T5, matches other T5 pieces and upgrades into T6. T3 remains in the collection and can still be made by T2 merges. No gem has “matching tier 3 but real value tier 5”; no duplicate T5 definition with a different upgrade destination is introduced. The roster panel shows merge arrows; the supply panel shows redirected spawn arrows and actual percentages. This realizes the useful part of “T5 in a T3 slot” without giving one silhouette two meanings.

If a setting targets the same tier from two supply entries, sum their integer weights for sampling and display; maintain source-entry provenance if a later rule needs it. Admit at least three distinct supplied tiers and validate opening/dead-board behavior. Do not change supply mid-resolution. Between-room settings update supply atomically, with saved rules and asset preflight. Removing the setting restores its own contribution; it must not overwrite another setting's configuration.

**Prototype foundation:** explicit supply target/weight data, default mapping only. The high-tier redirection and its UI are expansion work. Ascending tier progression remains fixed; arbitrary cyclic merge graphs are unnecessary.

## 4. Readability under any admitted collection

### Do not solve the green-gem problem with color alone

Fluorite, green tourmaline and emerald can all be green in one roster. Reserving unique mineral body colors for eight tiers would restrict both mineral honesty and long-term drafting. Keep real-looking color, make tier shape and a fixed tier badge sufficient for matching, and treat roster color optimization as a secondary improvement.

Required visual channels:

| Channel | Carries | Constraint |
|---|---|---|
| Outer silhouette | Appraisal tier / match class | Stable through rest, selection and readable upgrade poses |
| Tier badge | Exact tier | Always available; on by default in the prototype; fixed position outside the stone |
| Body color/pattern | Gem material | Never the only match cue; no arbitrary hue cycling |
| Family emblem | Family/build information | Separate position; strongest emphasis on inspection and reaction |
| Enhancement mark | Cut technique or persistent ability | Small independent marker, not a replacement for the tier badge |
| Cell border/texture | Hazard and interaction state | Distinguish occupancy, lock and floor overlay |

The rank silhouettes in [the art review](GEM_ART_REVIEW.md#proposed-visual-grammar) remain the first test set. Strengthen round versus oval, square versus lozenge, and narrow marquise coverage. Test silhouette masks without color or facets. The eight shapes are learned symbols, not an innate value ordering.

### Four levels of disambiguation

1. **Authoring:** preserve body-color regions, avoid clipping everything white, normalize readable occupied area, strengthen outline contrast and simplify low-tier facet noise. Test adjacent tiers and actual roster mixtures at 112px and 80px.
2. **Semantic UI:** fixed tier numeral and optional tier-specific backing motif. A high-contrast accessibility mode can display a clean tier-shaped backing behind the real gem, with a numeral. It is a game symbol, not a claim that the mineral has changed color.
3. **Admitted appearance variants:** where mineral identity permits it, choose among explicitly authored natural-looking variants. A differently colored tourmaline definition may be appropriate; silently turning emerald orange is not. If a color change names a different variety or carries a different signature, it is a gameplay definition change, not a skin.
4. **Collection admission:** a review tool evaluates all concurrently reachable tier pairs, including promotions and reward previews, on still and motion sheets. Color-distance/alpha-shape measurements flag pairs for human review; they do not prove recognition. Reject an unreadable asset/skin combination or use the admitted semantic backing mode. Do not offer a reward and then forbid equipping it because its colors clash.

“Football jerseys” work best as **optional UI surrounds**, with fixed per-tier colors/patterns, rather than runtime recoloring of gemstones. Assignments stay constant across the expedition, carryover, reload and reward previews. No per-room palette reshuffle, automatic hue rotation or per-instance skin randomization. The same gem in two tiers uses the two tier silhouettes/badges; the same-tier gems always match regardless of cosmetic skin.

For the current two-options-per-tier catalog there are only 256 full rosters, but pair review is more economical: 28 tier pairs × 4 variant pairs = 112 cross-tier comparisons. Nine-gem prototype coverage is 35 such comparisons. These are coverage counts, not test results. Add dense-board and motion tests because pairwise readability alone does not establish board readability.

## 5. Cuts: appearance, technique and shape

Do not make every named cut a power. Separate **outline** (the matching symbol), **facet design** (the gem's appearance) and **technique** (an explicit gameplay enhancement). Real cut names can combine shape and facet conventions; catalog entries must identify the actual authored geometry rather than applying a fashionable name to any program. GIA distinguishes named shapes/cuts such as princess, oval, marquise and pear. [GIA diamond quality factors](https://www.gia.edu/diamond-quality-factor).

| Content use | Example | Rule |
|---|---|---|
| Cosmetic cut profile | Cushion-like versus princess-like square T2 | Both must stay within the admitted upright-square envelope; no power difference |
| Cosmetic faceting | Brilliant-style versus mixed faceting on a T4 oval | Preserve outline, pose and tier legibility |
| Collection technique | **Cleaving cut:** first line-4+ match each turn sends one obstacle pulse in the line's axis | Explicit ability marker and text; compatible art profile optional, not sufficient to grant it |
| Collection technique | **Cushioned setting:** first adjacent pressure hit each room is prevented | A mounting enhancement, not a claim that cushion-cut minerals are inherently tough |
| Incompatible skin | Round T6 gem without the T6 rectangle grammar | Reject in the normal skin set; reserve for a separately tested alternate-symbol mode |

For the first expansion, a technique attaches to a **collection tier entry**, so every tile of that entry has the same rule. It is replaced only between rooms and does not propagate into the next tier unless that destination entry also has it. This avoids tracking unique enchanted specimens before the core game proves that it needs them. One technique per entry; an enhancement reward replaces the previous technique explicitly.

Cushion versus princess can therefore be cosmetic choices at T2; the player can later earn an independent, clearly marked technique with either compatible appearance. Do not sell or unlock a skin that secretly changes power. If an eventual named cut is deliberately a mechanical package, label it as an enhancement, give it a locked rules ID, and show its tradeoff before selection.

Heart and star outlines break the ordinary silhouette grammar. Reserve them for exceptional pieces with explicit symbols, rather than randomly making a T2 amethyst heart-shaped in the default board mode. Decorative hearts in the inspector are possible later, but require separate asset coverage and must not silently alter board identification.

## 6. Family vocabulary and mineral relationships

Use **family** as a friendly umbrella in the game; the inspector records whether the scientific relationship is a mineral species, group, variety relationship or material category. One curated primary family drives a gem's shared reaction. More precise taxonomic tags support research and explicit reward filters; they do not each grant another copy of a reaction.

Use **affinity** for a cross-family game theme, such as Patterned, Color-change or Organic. An affinity does nothing until a trait/setting references it. It is not a new mineral family and does not change matching. A chalcedony entry can belong under Quartz and have a Patterned affinity without double-counting Quartz. Do not classify malachite as chalcedony or chrysoberyl as beryl.

Player vocabulary:

- **Reaction:** “When …, do …” ability, with its limit printed.
- **Family reaction:** shared baseline; one budget across all members of that family.
- **Signature:** optional gem-specific reaction or replacement of a baseline, explicitly authored.
- **Technique:** one enhancement on a collection entry.
- **Setting:** expedition-wide modifier; the equivalent of a roguelike relic. “Relic” may be used in explanatory copy, but do not add a second parallel equipment system called boons.
- **Charge:** a counter on a specific ability or special piece, not another general currency.

### Family expansion map

These are thematic game abilities, not properties of real minerals. Each candidate needs a useful access tier, a setup decision and a limiting condition. The first three retain the prototype rules; the others are directions to test, not automatic abilities for every current asset.

| Family | Identity basis | Gameplay tendency and candidate reaction | Room relationship / restraint |
|---|---|---|---|
| Quartz | Quartz varieties; chalcedony branches require accurate material metadata | **Preparation:** prototype first family match gives +1 Craft; later a patterned signature banks a charge on consumption for a future tool discount | Flexible baseline; shared Craft cap prevents multiple low-tier variants farming resources |
| Corundum | Ruby and sapphire | **Excavation:** prototype adjacent match damage 2 instead of 1; later line-size techniques extend reach | Rubble/seal rooms; high-tier access and positioning remain costs; hardness is inspiration, not a simulated toughness stat |
| Beryl | Aquamarine and emerald | **Cultivation:** prototype once per turn promotes the lowest eligible T1–3 neighbor of its survivor | Crowded upgrade chains and extraction setup; no eligible target means no spent charge |
| Garnet | Mineral group, curated member identity | **Aftermath:** once per normal turn, a garnet consumed by a match deals 1 obstacle damage adjacent to its former cell | Makes a consumed tile's position matter; survivor already receives promotion, so both roles have reasons to be chosen |
| Tourmaline | Mineral group; authored current green elbaite is one selection | **Relay:** once per normal turn, a tourmaline moved in the initiating swap but absent from every initial match grants +1 Craft if the other swapped gem matches | Rewards using a gem as the displaced helper; shares global Craft cap; no triggers on gravity jitter |
| Feldspar | Group including appropriate moonstone, labradorite and sunstone entries | **Routing:** once per normal turn, a family tile arriving through a portal removes one seal from itself or the first adjacent sealed cell | Good in transport rooms; no payoff without traversal, so these offers require upcoming route support |
| Chrysoberyl | Alexandrite belongs here, not Beryl | **Alternation:** a room counter tracks whether its last qualifying reaction was a match or an assisted swap; alternating event types grants +1 Craft, at most once per turn | Controlled sequencing; stable visual color, no required optical color-change cue |
| Fluorite | Its own mineral identity | **Arrival:** first refill-spawned family gem that survives settling each normal turn clears dust from its landing cell or one adjacent cell | Low-tier access supports pressure rooms; opening placement and carry deployment do not trigger it |

Quartz, beryl, corundum, garnet, tourmaline and chrysoberyl relationships are sourced in the [gem review](GEM_ART_REVIEW.md#mineral-and-value-source-notes). Feldspar group diversity is documented by [GIA sunstone](https://www.gia.edu/sunstone-description) and [GIA moonstone](https://www.gia.edu/gia-website/moonstone-description). Chalcedony's quartz/moganite composition needs more precise metadata than “any striped stone”; see [GIA chalcedony analysis](https://www.gia.edu/gems-gemology/spring-2020-gemnews-dyed-chalcedony-imitation-of-chrysocolla-in-chalcedony).

Topaz, peridot, diamond and painite need not each launch with a full family subsystem. They can initially be ordinary collection entries, then receive a signature or a setting affinity when that creates a real decision. A family with one rare member and no accessible setup is a poor launch archetype. Prefer adding a second useful access point or a cross-family support setting over inventing ten nominal families.

No family owns an event exclusively: several may react to consumption but choose different targets/costs. Each family should nevertheless have one memorable central verb. New signatures should bend that identity, not bolt on unrelated bonuses to fill a spreadsheet.

### Using mineral attributes without pretending to simulate them

| Attribute or relationship | Meaningful design use | Avoid |
|---|---|---|
| Verified family membership | Multiple access tiers share a reaction budget; replacing sapphire with aquamarine changes the build's timing | Matching every same-family gem regardless of tier |
| Species-appropriate grade and rarity context | Different admitted tier entries and reward availability; a fine specimen can extend family access later in the ladder | A second hidden value number or arbitrary tier placement justified by an effect |
| Color range, zoning and visible pattern | Cosmetic variety; a sourced Patterned affinity can support position/sequence rules through a setting | Classifying every green gem together as a mineral family, or requiring hue detection to play |
| Sourced color-change/phenomenal identity | Alternating-state or movement-themed signatures with explicit UI counters | Reading the current sprite color/brightness to decide a reaction |
| Sourced hardness/cleavage information | Fictional excavation or directional technique themes, authored as integer rules | Converting Mohs directly to obstacle damage, health or immunity; hardness is not toughness |
| Shape and facet profile | Cosmetic variants in a tier envelope; explicit optional techniques alter target patterns | More facets automatically meaning more valuable or more powerful |
| Inclusions and surface condition | Distinct specimen portraits and selected grade/treatment choices; later a named risk/reward signature if deliberately authored | Turning every inclusion into a penalty or every engine defect parameter into a gameplay stat |

These are curatorial connections: the designer chooses a readable game rule inspired by a sourced attribute. The simulator never calculates damage from refractive index or samples a texture to recognize a pattern. Hardness versus toughness is discussed by [GIA](https://www.gia.edu/gia-news-research/how-protect-diamond-chipping); the other identity/appearance sources are linked above and in the material table. Any new specific mineral claim needs its own source before admission.

Support overlap without erasing families. A future Patterned setting may grant one positional reaction to admitted chalcedony, malachite and shell entries while their primary families remain distinct. A family setting can reward two different access tiers without multiplying the baseline twice. This creates cross-family collections as well as focused builds; it does not require a threshold bonus for every possible combination.

## 7. Lifecycle events and deterministic reactions

### Facts, not scene callbacks

The simulation emits immutable **facts** about committed transitions. A reaction reads those facts and proposes typed effect intents. A resolver validates and commits intents. Rendering only explains the results. Preserve source snapshots: an amethyst match is a Quartz event even when its survivor becomes peridot.

| Fact / player wording | Exact meaning | Important distinctions |
|---|---|---|
| `TileSpawned` / On arrival | New instance created by a refill source | Opening population, carry deployment and roster conversion have separate setup causes and do not activate arrival rewards |
| `TileMoved` / On movement | Committed logical movement from one cell to another | Cause = player swap, tool swap, gravity, portal or effect; path retained; no event per animation frame or settling microstep |
| `SwapAssisted` / On assist | One swapped gem is absent from all initial match components while the other is included | Once for that helper per accepted swap; no assist if both gems match; includes displaced gem, not just drag origin |
| `MatchCommitted` / On match | One connected component committed from a pre-resolution board snapshot | Source members/IDs, tier, family, size, line lengths, intersection flag and chosen survivor; not one event per overlapping line |
| `TileConsumed` / On sacrifice | Non-survivor removed to pay for a normal promotion | Subtype of removal; source snapshot and survivor ID retained; not a destruction or extraction |
| `TilePromoted` / On becoming | Existing survivor changed from one tier/definition to the next | Old and new identity; match/tool/family cause; “on becoming sapphire” reads the new identity |
| `TileRemoved` / On removal | Instance ceased to occupy the board | Reason = merge consumption, terminal recovery, effect clearance, extraction or setup replacement; exact once per removal |
| `TileExtracted` / On delivery | Piece actually passed an admitted outlet/contract check | References the same removal ID; alone advances outlet demands; no second generic removal payout |
| `ObstacleDamaged`, `ObstacleBroken` | Applied damage, then destruction if durability reaches zero | Include source, original cell and actual damage; excess proposed damage is not another reward |
| `ActionSettled`, `RoomCompleted` | Stable boundary after the entire action; room win committed | One settlement per root action; use for counters and final evaluation, not repeated cascade rewards |

“On match 4” is a predicate on `MatchCommitted`, not an unrelated signal. Store both member count and shape: an L/T of five is one intersection event, not a 3-match plus another 3-match. Default size buckets are exactly 3, exactly 4, and 5+; an explicit intersection predicate can distinguish L/T. An ability with overlapping predicates activates once per event unless its rule explicitly says otherwise. Disjoint matches have separate component IDs, but shared turn/family budgets still apply.

Movement coalesces one uninterrupted settling journey into an origin, destination and path. A portal may appear in that path; traversal counts can be recorded, but ordinary arrival abilities trigger once per journey. If a later reaction moves the tile again, that is a distinct movement with a new parent event. Player swap movement facts are retained immediately but reaction dispatch waits until the validated initial matches commit, so a move reaction cannot erase the match that made the action legal.

### Event envelope and eligibility

Minimum event identity: monotonic `event_id`, `root_action_id`, `parent_event_id`, causal depth, phase/round/component IDs where relevant, cause enum, stable source/target instance IDs, cell/path data and immutable before/after snapshots required by the rule. Do not look up the current occupant of an old source cell to decide which family acted.

Each reaction declares: owner scope (family, collection entry, setting or instance), event kind, predicates, eligible root causes, target selector, effect kind, priority, cap scope/key and whether it requires a live source. Family scope deduplicates the members of one match component. Consumption rules use the removed source snapshot; they cannot require its still-existing TileState. Live-target effects revalidate IDs before application and never silently hit a replacement occupant.

**Prototype eligibility:** ordinary player swaps and their merge/family/refill descendants may activate the three family reactions. Tools, extraction continuation, setup, reshuffle and room transitions may still generate facts and objective progress, but activate no resource rewards or family/setting reactions. Root cause survives all descendants; a tool-generated match cannot launder itself into a normal swap reward. Carry an inherited reward-eligibility restriction as well: extraction continuation remains suppressed even when its root action was a normal swap. Scheduled hazard work is likewise suppressed; the mere presence of a normal-swap root is insufficient. Later content can explicitly opt into other causes only with its own budget and loop tests.

### Resolution order

1. Validate the root action on unchanged state; determine initial match legality. Reject without spending Work, Craft or RNG. Accept and reserve its costs/tool allowance.
2. Commit the player movement. Snapshot all initial match components and source identities in canonical cell order.
3. Build a base match batch. Resolve seal unlocking and the base merge/terminal outcomes under explicit board rules. Each consumed piece has one removal record; each promoted survivor keeps its instance ID. Freeze obstacle adjacency from the source component, not from the new gem's family.
4. Emit movement/assist/match/consumption/promotion/removal facts with fixed sequence order. Dispatch eligible reactions, ordered by phase priority, source event ID, owner scope ID and reaction ID. Core adjacent obstacle damage and Corundum's replacement amount are one damage plan, not two accidental hits.
5. Validate and apply effect intents in bounded waves. Revalidate targets at commit; log applied, skipped and capped results. Spend an activation budget only for a committed effect, unless a specific rule says its attempt consumes a charge. Check upgrade-created matches before gravity and repeat match/reaction waves.
6. Settle gravity and refill until physically stable. Emit coalesced movement and spawn facts, dispatch their admitted reactions, then check for new matches. Repeat until no work remains.
7. Evaluate stable extraction/objectives. If incomplete, process extraction continuation with suppressed reactions, then the once-per-normal-action scheduled hazard and its required settlement. Stop immediately on room completion; otherwise commit settled state/failure and one complete authoritative timeline.

Exact same-priority effect conflicts are resolved by stable intent order: the first legal commit wins; later intents skip invalid targets. Effects in one explicitly simultaneous match batch use the frozen match snapshot. There is no unspecified global simultaneous callback system. A future preventive shield belongs in a small typed damage-policy stage before damage commit, not in a generic “on removed, undo history” listener.

The timeline may group independent animations only when causal dependencies permit it. Events have one canonical chronology; animation regrouping is not event reordering in the simulation.

Presentation must not turn that chronology into a global wait after each cell
movement. P1-A schedules concurrent instance journeys while retaining complete
paths and conservative settling-wave boundaries. A projected dependency graph
must account for support, reservations and relevant empty cells before allowing
cross-wave overlap; one parent ID or endpoint overlap alone is insufficient.
Only committed matches may be presented. See the
[fluidity assessment](FLUIDITY_AND_REACTIVE_PLAY.md).

Automatic content reactions in this section are distinct from **player
interventions during a cascade**. The user authorized a
[required post-P2 trial](../plans/P2_INTERVENTION_TRIAL.md); adoption into the
main game remains optional.
If adopted, introduce an explicit resolution episode and subcommand/window
identity. Proposed trial policy shares Craft/family caps and one hazard boundary
across the episode; an intervention does not refresh tools or spend newly earned
Craft early. Preserve inherited suppression so tools/extraction cannot gain
rewards by opening a window. Decide objective/extraction and last-Work completion
at a named boundary. Current whole-action settlement and rollback remain the v1
contract; a continuation/prefix-commit variant needs new versions and tests, not
an extra UI callback within this pipeline.

### Budgets and loop prevention

- Keep the prototype's Craft capacity 6 and total normal-action Craft gain cap 3, including match-size, family and setting gains. Reserve the best-match base award as it increases during resolution; track raw eligible family gains separately and clamp the final sum, so dispatch timing cannot steal the base award. Earned Craft becomes spendable only at the next input boundary.
- Quartz and Beryl use shared family once-per-root-action budgets. Other rules need an equally explicit instance/action/room charge limit; no “once” without scope.
- Future Work recovery is unusual: first trial limit +1 per accepted normal swap and +2 per room, after the swap's -1 cost. It cannot trigger from a tool or purchase more Work after failure. This allows a satisfying extra move without indefinite survival; no Work-refund setting ships in the prototype.
- Every generated effect carries ancestry and root cause. Reward suppression is inherited. Never subscribe an unrestricted removal reward to its own tier-clear descendants.
- Reaction, cascade and settling caps are development/error guards. Exceeding one fails the transaction with a reproducible diagnostic; it is not a balance mechanism that silently truncates rewards.
- Do not keep an ever-growing event history solely to enforce limits. Store compact counters/flags in RoomState/ActionContext, save room-persistent ones, and hash all rule-relevant fields.

An authored reaction subscribes to one canonical fact kind. `TileConsumed` and `TileExtracted` reference their `TileRemoved` fact by the same removal ID; they are not two opportunities for the same reaction to earn a payout. Separate explicitly designed reactions may both respond, within their shared limits. The default is no generic removal income. Terminal T8 recovery has no promoted survivor and emits no `TilePromoted` or merge-consumption fact; handlers requiring a survivor have no eligible target.

Worked example: swap a green tourmaline with a quartz so the quartz joins two other quartz and tourmaline matches nothing. The source component commits as Quartz, two pieces are consumed and one becomes the active T2 gem. A later Tourmaline Relay signature can read `SwapAssisted` and offer +1 Craft; Quartz offers +1 Craft from `MatchCommitted`. If the turn's strongest match earns 2 base Craft, total gain is still capped at 3. The T2 result does not retroactively change the matched family's identity. A Reposition tool doing the same arrangement earns none of those reactions.

## 8. Effects and safe combinations

Use a small typed effect vocabulary. New content combines event predicates, targets and bounded amounts; a new rule primitive gets a resolver and focused tests. Do not embed arbitrary GDScript snippets or a general expression language in reward resources.

| Effect family | Useful payloads | Boundary |
|---|---|---|
| Economy | Gain Craft; discount next named tool; limited Work recovery | Integer caps; no duplicated generic removal/extraction earnings |
| Promotion | Promote selected eligible neighbor by one; Refine | Fixed next-tier roster lookup; cannot create T9; new definition supplies destination traits |
| Excavation | Damage adjacent blocker, chosen blocker, row or column obstacles | Distinguish obstacle damage from gem destruction |
| Cleansing/protection | Remove dust, break seal, prevent one named pressure hit | Typed statuses; no broad immunity to every room objective |
| Arrangement | Adjacent exchange, move into an empty legal neighbor, one-step pull | Board topology and locks apply; no coordinate teleport disguised as a fall |
| Supply | Next refill modifier; bounded weight redirection between rooms | Seeded integer draw; disclose changed distribution; no hidden adaptive draws |
| Recovery/clear | Remove explicitly selected low-tier pieces, or all of one chosen tier | Preserve investment by default; no survivor, promotion, match-size or Craft reward |
| Objectives | Open outlet, deliver a cargo, fulfill a contract | Only through objective resolver; no direct scene-driven “win” |

Candy Crush-style specials fit, but the merge game changes their cost. A row pulse should first **hit obstacles and cleanse overlays along that row while preserving gems**. A gem-clearing row power must say it destroys invested pieces and preview them. An “all T2” clear empties those pieces and triggers ordinary refill; it is not a board-wide T2 match and does not manufacture a T3 survivor. Default clear reactions are reward-suppressed. A later sacrifice build can explicitly allow one bounded payoff.

Define line geometry explicitly: row/column sweeps follow straight grid rays through active cells, stop at permanent walls/holes, ignore portals, and do not bend with gravity. A beam with different rules needs a different named targeting policy. Adjacency queries remain in BoardState. For multi-cell areas, sort/deduplicate target IDs and apply each once.

Keep the number of active mechanics readable: one family baseline, at most one signature, at most one technique per collection entry, three equipped settings. Large build power can emerge from their interaction with rooms; it does not require ten unlabelled status icons on each tile.

## 9. Rooms, hazards and route identity

Room content has four independent pieces: **topology**, **objective**, **pressure**, and **reward bias**. A room card shows all four before the player commits. Topology is permanent board structure; hazards are mutable occupants/locks/overlays. Portal connectivity for gravity does not create matching adjacency.

| Room theme | Topology and objective | Pressure / hazard | Favored tactics and universal fallback |
|---|---|---|---|
| Open seam — prototype | Regular 8×8; clear marked rubble | 2-hit rubble creates local choke points | Corundum positioning; everyone can use adjacent matches and Chisel |
| Commission bench — prototype | Two visible bottom outlets; deliver three T3+ gems | Limited Work; no new hazard required | Beryl setup, Reposition, choosing when to bank; all families can build T3 |
| Vault — prototype | Two rubble gates by outlets; one T5+ extraction | Space and action pressure | Carry investment plus excavation/positioning; no family-specific key |
| Split gallery — expansion | Asymmetric pockets and gaps; clear marked floor cells in both wings | Finite seals over some gems | Arrangement, local sacrifice, accessible spawn lanes; never isolate unreachable objective cells |
| Kiln — expansion | Narrow lanes and alternate outlet positions | Telegraphed dust every third swap | Arrival cleansing and targeted tools; ordinary matches always remove dust |
| Faultworks — expansion | Authored side/upward gravity zones, separately shown arrows | Repeated-hit deposits near turns | Movement/path effects; all topology must pass validator and visual path review |
| Sluice — expansion | Portal-fed side chamber with its own outlet | Seals around landing cells | Feldspar routing; ordinary portal transport remains enough to win |
| Inlay commission — expansion | Marked cells must be matched on twice | Floor coating tracks hits, survives gem movement | Low-tier supply, match size, location control; direct clears need an explicit coating interaction |
| Collector's case — expansion | Deliver a named tier/family contract through a chosen outlet | Few staging cells, optional dust | Specialization rewards; only offered if roster/access can satisfy it, with an alternative route |

Reward biases reinforce routes without locking them: a seam may favor excavation techniques, a sluice routing settings, a commission gem drafts. Show that bias; do not promise a specific reward before it is rolled. Difficulty budgets account for topology plus hazards plus objective, rather than independently maximizing all three. Introduce one unfamiliar rule per early room; combine familiar rules later.

### Hazard interaction grammar

| Kind | Occupancy model | Hit rule | Key event |
|---|---|---|---|
| Rubble | Solid obstacle, no gem | Adjacent committed component hits once, regardless of touching cells | Damaged / broken |
| Seal | Lock over gem | Adjacent match hits; direct match unlocks before merge | Lock removed |
| Dust | Floor overlay | Match covers cell; scheduled spread cancelled if announced target invalid | Overlay cleared / spread |
| Layered coating — later | Floor objective under gem | Match includes cell; one hit per component, damage does not depend on match member count | Objective-layer damaged |
| Deposit — later | Obstacle with a finite shell | Required number of adjacent matches or named hits | Shell stage changed, then broken |
| Cargo/catalyst — later | Special piece occupant | Explicit delivery or charge interaction, never ordinary matching by color | Cargo delivered / catalyst activated |

Hazard flags should express concrete capabilities: occupies cell, locks movement, allows matching, accepts adjacent-hit, accepts direct-hit, blocks extraction. Do not represent each hazard as an ever-growing pile of independent Boolean statuses on a gem. Use a compact typed obstacle definition/state and shared hit policies. A cell may have a floor layer and a lock, but visually cap simultaneous layers and reject unreadable combinations.

Future route generation tests objective accessibility for the actual collection and settings. Static reachability is necessary, not proof that the move budget is fair. A recommended route can favor a build without another route being unwinnable. Collect paired-fixture results for different builds and player explanations of their route choice.

## 10. T0, T9 and patterned or organic materials

### Special is a role, not a mineral's worth

Do not put every opaque material at T0 or every unusual silhouette at T9. Transparency and scientific rarity do not define gameplay value. A polished malachite, coral or tiger's-eye specimen could occupy an ordinary admitted appraisal band with the normal tier silhouette if that is its role.

Reserve the informal archive labels as follows:

- **T0 → special-piece category:** catalyst, cargo or obstruction; no appraisal tier unless it is also an explicitly appraised collectible. The UI says its role, not “worthless tier zero.” Store `piece_kind`, not `tier=0` branching throughout matching.
- **T9 → masterwork category:** a rare board artifact assembled through a separate late-run recipe. Not an appraisal band above all minerals, not the automatic result of matching T8, and not another full ladder.

A catalyst occupies space and cannot make ordinary matches. Example expansion trial: a heart-shaped coral charm gains one charge from each adjacent committed match, maximum one per root swap; at two charges it clears neighboring seals and is consumed. At most one catalyst may be present initially; acquisition is explicit, not random refill pollution. Charge, targeting and expiry appear on inspection. No healing implication or hidden health system is needed.

A masterwork should change a decision, not provide an infinite engine. Example later **Star Mount**: optional workshop recipe consumes two carried T6+ gems and equips one star-shaped special for the next room. Player deploys it into a staging cell; it does not match or promote. After two qualifying adjacent matches it can be activated once to send obstacle-only rays in four directions, then leaves the board. Activation uses the tool allowance, no Work, and grants no reaction/resource rewards; it cannot be used after room failure. Consumed recipe pieces are unavailable for the finale, which is its cost. Final numbers require testing; no masterwork in the initial prototype or required six-room slice.

Heart/star names describe shapes, not mineral species or simulated asterism. A star-cut opaque token is different from a sapphire displaying an optical star. Keep those concepts distinct in authoring and copy.

### Material-by-material fit

| Material | Correct identity context | Useful design placement | Art/engine implications |
|---|---|---|---|
| Obsidian | Natural volcanic glass, not an organic gem | Ordinary low-band specimen, or a cutting-tool catalyst with a consumed-on-use effect | Plain glass/bodycolor study is separate from fire-obsidian interference; no automatic support for the latter |
| Cinnabar | Mercury sulfide mineral; not a quartz variety | Defer as launch gem; could be a vivid specimen in a collector room or an explicitly fictional pigment-themed deposit | Requires material/provenance and its own role; do not turn its chemistry into an assumed poison mechanic |
| Pāua / abalone shell | Biogenic shell material; iridescent nacre | Patterned inlay setting, routing catalyst or collection collectible | Layer interference/diffraction is not established by current tracer admission; use a clearly authored illustration if chosen, or defer optical work |
| Coral | Biogenic gem material with organic/inorganic structure | Charm/catalyst or ordinary graded ornamental entry | Carved/opaque appearance is a separate art brief; no transparent-ruby preset relabelled coral |
| Malachite | Copper carbonate hydroxide; patterned mineral material | Patterned affinity, inlay room reward, coating-oriented signature | Accurate banded surface/body pattern requires dedicated study; not a green quartz shader renamed |
| Tiger's-eye | Quartz gem material, commonly polished as cabochons | Quartz branch with a movement/arrival signature; can remain an ordinary tier | Directional chatoyancy is not the engine's generic roughness or scattering; illustrative art or deferred qualified optics |

Identity sources: [GIA obsidian](https://www.gia.edu/gems-gemology/spring-2025-gemnews-bubble-obsidian-armenia), [Mindat cinnabar composition](https://www.mindat.org/element/Mercury), [GIA pāua context](https://www.gia.edu/gia-news-research/tropical-paradise-ocean-inspired-jewelry-gemstones), [GIA abalone optics](https://www.gia.edu/gems-gemology/summer-2021-iridescent-abalone-shell), [GIA coral research](https://www.gia.edu/mediterranean-precious-coral-reading-list), [GIA malachite](https://www.gia.edu/gems-gemology/winter-2023-colored-stones-unearthed), [GIA tiger's-eye quartz](https://my.gia.edu/gia-museum-exhibit-tigers-eye-quartz). Abilities in this table are fictional design choices.

There is room for this material diversity, but the role must lead the asset work. Use an inlay/relic icon or illustrated special piece before commissioning a new optical mechanism. A future explicitly admitted illustrated-asset path must satisfy the runtime delivery contract and be labelled as authored art; it is not a silent fallback when a required optical bake fails. Until such a producer/import path exists, use ordinary game UI icons or leave the special unshipped.

## 11. Settings as the large-scale build layer

“Settings” fits the jeweler theme and covers the role of passive relics/boons. Equipment is expedition-wide, with three slots, unique nonstacking IDs and explicit replacement at capacity. Permanent account unlocks add choices, not hidden stat advantages.

| Design dimension | Candidate | Constraint / tradeoff |
|---|---|---|
| Carry economy | Deep Pockets: one additional carry slot | Existing candidate; no automatic extraction income |
| Tool economy | Steady Hand: first Chisel costs 1 | Prototype setting; later discounts cannot take cost below a declared minimum |
| Family focus | Beryl Bridge: extend neighbor eligibility through T4 | Prototype setting; consumes the same family activation budget |
| Supply access | Elevated Mount: redirect third supply entry to T5, -3 room Work | Expansion; does not retier T5 or delete T3 from progression |
| Event conversion | Setter's Relay: first successful assist each normal turn counts for one named family support reaction | Expansion; explicitly grants that rule, not fake mineral ancestry or every family ability |
| Objective economy | Commission Seal: first qualifying extraction each room refunds 1 Work | Expansion; global room/turn refund caps and completion precedence apply |
| Spatial policy | Long Chisel: Chisel may target one cell beyond adjacent obstacles | Expansion; fixed targeting rule, walls still block |
| Grade access | Appraiser's Loupe: reward pool can offer admitted adjacent-band grade exchanges | Expansion; previews complete roster change; no floating multiplier |

Settings cannot execute arbitrary hooks or directly mutate roster arrays mid-cascade. Supply/tool-cost changes use typed configuration contributions, evaluated in stable equipped-slot order and checked for validity; reaction settings use the same event resolver. Conflicting exclusive modifiers are rejected at offer generation with a clear reason. Caps apply after contributions. A load recomputes the effective rules from base rules plus equipped IDs and verifies the saved content/rules version.

## 12. Expansion sequence and minimum architecture

The [architecture hardening](ARCHITECTURE_HARDENING.md) specifies replaceable rule
policies, neutral identifiers, typed content organization, deterministic topology
and shared map-authoring admission. The [presentation asset brief](PRESENTATION_ASSETS.md)
keeps non-gem art, sound and vocabulary similarly replaceable. These are
implementation seams; they do not add the expansion mechanics to the prototype.

| Stage | Content to test | Foundation exercised | Deliberately absent |
|---|---|---|---|
| Initial prototype | Nine gems, three existing families, rubble, three rooms, two settings, fixed grade intents | Identity/supply separation, immutable event snapshots, bounded reactions, layered obstacle state, complete saves, semantic art cues | Signatures, techniques, specials, grade exchanges, Work refunds |
| First expansion experiment | One Garnet or Tourmaline signature using existing art; one coating/assist-focused room variation | Consumption or assist facts, typed targets, route/build relevance | New optical phenomena or many families at once |
| Six-room slice | Seals/dust, more settings, admitted asymmetric layouts and small roster alternatives | Room pressure, offer filtering, stronger readability coverage | Required T9, general scripting DSL, full economy |
| Transport expansion | One routing family, gravity/portal room set | Coalesced paths, arrival causes, topology/presentation validation | Unvalidated arbitrary generated topology |
| Lapidary expansion | A few grade exchanges, compatible cut skins, one technique system | Curated appraisal variants and appearance bindings | Every grade/cut for every mineral |
| Special-material expansion | One catalyst or inlay theme, then optional masterwork | Explicit piece kinds, charge budget, authored asset producer if needed | Automatic T8→T9 ladder or unsupported physical claims |

Build the **seams**, not all their future contents. The prototype needs stable instance/definition IDs, complete state identity, collection versus supply data, immutable event facts with causes, one bounded reaction dispatcher, typed intents for its three families/tools, and obstacle/room ownership. It does not need an editor for arbitrary triggers, an unused handler for every event in this document, or a universal modifier graph.

Emit and verify the facts already produced by ordinary play: spawn/movement, match/consumption/promotion/removal and action settlement. Add assist classification from the accepted swap snapshot; it is small and avoids losing displaced-helper information. Extraction facts arrive with the room loop. Prototype handlers can remain explicit code selected by stable rule IDs. When a new effect actually arrives, add its implementation and test its cause/target/budget semantics without changing those foundations.

Expansion admission requires: accurate identity/source, one intelligible sentence of behavior, a named decision it changes, explicit event/cause/limit, at least one useful room and one limitation, readable asset coverage, deterministic replay, and a loop/duplicate-payout fixture. If an entry adds only artwork, ship it as a cosmetic choice rather than a misleading build reward.
