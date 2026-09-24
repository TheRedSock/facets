# Authored gem review for the game

Reviewed 2026-09-13 against the [proposed game design](GAME_DESIGN.md). This is an art-direction and content-fit review, not a new optical calibration or player recognition study. No authored resources or delivery images were edited.

## Evidence and scope

The shipping-style catalog has **16 game stones**, two per rank, under `data/lapidary/stones/`. Their tile definitions, shape/cut/material references and default presentation bindings were inspected. The latest readiness delivery report binds four chronological sheets containing all 304 requested rest/turn/flash frames. All four were visually reviewed here:

- [Gems A–P, rest/flash](../artifacts/readiness-review-2026-09-13/rig-schema-cleanup/delivery-review/1-idle_flash.png)
- [Gems P–T, rest/flash](../artifacts/readiness-review-2026-09-13/rig-schema-cleanup/delivery-review/2-idle_flash.png)
- [Gems A–P, turn](../artifacts/readiness-review-2026-09-13/rig-schema-cleanup/delivery-review/1-turn.png)
- [Gems P–T, turn](../artifacts/readiness-review-2026-09-13/rig-schema-cleanup/delivery-review/2-turn.png)
- [Original frame/manifest review record](../artifacts/readiness-review-2026-09-13/rig-schema-cleanup/delivery-review/report.json)

These sheets contain native 112px frame cells; their full-sheet display in a viewer may scale. This review uses the stored frames and source metadata, not a newly captured live board or measured color-confusion matrix. The readiness report's visual acceptance qualifies that milestone, not this new game's final aesthetics.

There are also **seven acceptance specimens and four cut-example specimens**, for 27 standalone `GemStone` resources in `data/lapidary`. They are reviewed separately below as diagnostic/authoring content. The quartz recipe and measured-material studies are not additional playable species.

## Overall judgment

The catalog is a usable prototype source, with strong silhouette variety and recognizably different color treatments. It should **not** be discarded or expanded into dozens of new gems before a native-size board test.

The biggest issues are presentation and semantic hierarchy:

- Quartz is a bright faceted round, not the archived cabochon. Its brightness and broad white facets compete with diamond rather than establishing a humble/common starting piece.
- Rank-2 squares are crisp and angular; the intended cushion distinction is weaker than the archive suggests.
- Rank-3 triangles point right in the delivered rest pose. The archived point-up description is not current.
- Rank-4 ovals have modest elongation; their shape cue is weaker than their hue cue.
- Rank-5 lozenges are horizontally broad in the displayed pose; sapphire in particular is dark blue-violet with weak dark-edge separation.
- Rank-6 step rectangles are coherent but have broad, relatively static interiors.
- Rank-7 marquises are narrow horizontal pieces, with smaller occupied area than rounds/squares. Ruby and painite are close warm-color alternatives.
- Rank-8 pears point down consistently, but blue garnet reads violet in the current board illumination. A name is not proof of an expected blue appearance.
- Full 0.4-second turns spend frames edge-on and showing backs. This interrupts shape identification during the moment of upgrade.

One-gem-per-rank drafting reduces same-rank confusion on the board. It does not remove the need to distinguish adjacent ranks, recognize upgrade results, compare reward cards or use accessible cues.

## Proposed visual grammar

**Shape = rank. Color and name = gem. Icon = mineral family. Overlay = gameplay status.** No layer must rely on another layer's accidental optical appearance.

| Rank | Recommended silhouette | Presentation test |
|---|---|---|
| 1 | Round, simple face | Compare existing brilliant against one restrained low-facet round and one cabochon candidate; no assumption that cabochon means cheap |
| 2 | Upright cushion/square | Broader corner rounding or a less pointed cushion program, without becoming circular |
| 3 | Triangle | Trial point-up orientation for both gems through presentation; verify with the current right-facing baseline |
| 4 | Oval | Trial stronger 1.4–1.5 aspect ratio, with long axis consistent across its variants |
| 5 | Lozenge/rhombus | Trial taller presentation/proportions; maintain clear distinction from upright rank-2 square |
| 6 | Cropped rectangle | Retain horizontal step rectangle; keep clear corners and a visible step structure |
| 7 | Marquise | Retain two-point silhouette, test slightly fuller shoulders and sufficient screen area |
| 8 | Pear | Retain downward point and fixed centered rest presentation |

Ratios are candidate art settings, not claims about ideal real-world cut proportions. Inspect actual compiled dimensions and rendered alpha bounds. A presentation rotation must not rotate the crystal frame or recenter each animation frame.

Rank ordering is learned from the roster and a small rank numeral/pip system. Do not promise that eight arbitrary outlines convey an innate universal value order. Give rank-7/8 a restrained frame accent/reward sound; do not make every low-rank tile gray, noisy or damaged.

## Expanded appraisal, cuts and collection policy

The 2026-09-14 [content systems revision](CONTENT_SYSTEMS.md) retains the first silhouette experiment but makes tier the single appraisal band. The per-gem rows below describe the existing source and reviewed frames; they do not certify a market grade. Treat each placement as a representative specimen intent, reviewed against adjacent bands. Do not infer price from optical brightness, facet count or the current grade file.

For the nine-gem prototype, keep one appearance per definition and tier numerals on by default. Evaluate the crowded green trio (Fluorite/Tourmaline/Emerald), violet group (Amethyst/Rhodolite/Sapphire/Blue Garnet), warm pair (Smoky Quartz/Topaz), and white pair (Quartz/Diamond). Different tiers must remain identifiable with color removed. The current fluorite/tourmaline pair is an explicit stress case, not a reason to prohibit a future player build.

A roster review can cover 112 cross-tier variant pairs for the current two-per-tier catalog, plus dense boards and motion; the nine-gem prototype has 35 pairs. These counts are combinatorial coverage, not measurements already performed. Test masks at 112px/80px, consistent badge placement, body-color coverage and unfamiliar-player errors. Color metrics only flag potential conflicts. Cosmetic variants enter the same admission process as base art.

Cushion-like and princess-like profiles can coexist as T2 cosmetic alternatives if both retain the upright-square identity. Facet patterns may vary within other tier envelopes. Mechanically meaningful cut **techniques** are explicit enhancements with their own icon/rules; a profile's name or apparent brilliance never grants power. Heart/star profiles are reserved for explicitly exceptional piece roles in the default board mode.

Prefer stable UI backing colors/patterns to arbitrary mineral recoloring. Admitted natural-looking mineral variants are optional supplements, selected consistently for a run and previewed with its collection. No dynamic “away jersey” hue changes during play. Any alternative appearance must retain the tier symbol and must not silently rename a mineral variety.

Special materials are not assigned T0 just because they are opaque. Malachite can be an ordinary appraised patterned gem; tiger's-eye can extend Quartz; pāua/coral can be inlays or charged charms. Their mechanics and delivery requirements need separate briefs. The [material table](CONTENT_SYSTEMS.md#10-t0-t9-and-patterned-or-organic-materials) identifies the current capability limits. No additional optical or visual review of those unauthored materials was performed for this revision.

## Per-gem assessment

“Keep” means suitable to continue into prototype review, not approved final art. All rows refer to the existing resource with the same ID in `data/lapidary/stones/`. Most use `cuts/brilliant.tres`; triangles use `brilliant_triangle.tres`; rank-6 rectangles use `step.tres`.

| Gem / rank | Current authored geometry and observed appearance | Fit and recommended action |
|---|---|---|
| **Quartz / 1** | Round brilliant; bright white/gray, broad facets, high occupied area; quartz host | **Reauthor candidate first.** Compare simple faceting/cabochon and a quieter rig/print while keeping readable coverage. Preserve the current bright specimen as a baseline. Quartz family is the early tool economy; it needs an appealing, calm common tile, not universal artificial dirt. |
| **Fluorite / 1** | Round brilliant; saturated emerald-like green, broad interior; fluorite host and green absorber | **Keep as later alternate, review color.** Distinct from quartz but part of a crowded green palette with tourmaline/emerald. A sourced fluorite color variant is a possible future candidate; avoid changing color solely by renaming the asset. No family ability yet means it needs a designed tradeoff before becoming a reward. |
| **Amethyst / 2** | Square brilliant, corner radius 0.12; violet/magenta with strong diagonal structure; quartz host | **Keep, tune shape.** Strong starter identity; trial a more cushion-like edge. Preserve purple chroma without clipping the face to a flat purple block. Shares Quartz behavior with rank 1. |
| **Smoky Quartz / 2** | Same square structure; amber/golden brown in the current print; quartz host | **Color/role study.** Reads warmer and more golden than its name alone suggests; compare a less amber authored derivative against references and the topaz row. Same family/rank as amethyst makes it a cosmetic replacement unless a concrete gameplay distinction is added. |
| **Peridot / 3** | Rounded triangle pointing right; yellow/olive dominant, dark interior; olivine host | **Tune pose and body readability.** Preserve yellow-green separation from deeper green gems. Trial point-up and broader light return. Do not equate an optical roughness/absorption change with a gameplay power change. Useful independent starter slot. |
| **Tourmaline / 3** | Rounded triangle, same orientation; deep green; elbaite with `verdelite_fe` absorber | **Keep as later family seed.** This is a green tourmaline, not the archived watermelon/pink-green gem. Label the specimen accurately; do not claim a bi-color feature. Future Tourmaline gameplay should earn its implementation before more variants are authored. |
| **Topaz / 4** | Oval brilliant, aspect 1.28205; orange/amber with broad central facets; topaz host | **Keep, strengthen oval.** Warm starter anchor. Trial clearer elongation and monitor separation from smoky quartz at reduced size. “Imperial” appearance remains an authored color target, not a certified specimen/market grade. |
| **Rhodolite / 4** | Same oval shape; vivid magenta/purple-red; generic garnet host | **Keep for expansion, control palette.** Distinguish from amethyst via stronger oval and redder body, without assuming precise species chemistry from the generic host. A later Garnet build can justify the draft; no behavior is currently implemented. |
| **Sapphire / 5** | Rounded diamond/lozenge, aspect 1.3; dark royal blue/violet, light gray highlights; corundum host | **Highest-priority color/light revision.** Open up body/edge readability on the board before adding contrast. Compare rig/print first, then authored absorber/size/geometry alternatives if needed. This is the first Corundum entry; its appearance should be quickly identifiable. |
| **Aquamarine / 5** | Same lozenge geometry; light cyan with strong facet contrast; beryl host | **Keep; key first alternate.** Offers a clear visual and family tradeoff against sapphire. Check highlight coverage on pale backgrounds and preserve its distinction from the white apex. This is the most useful current reward candidate for testing an earlier Beryl build. |
| **Emerald / 6** | Cropped rectangle, aspect 1.35, step cut; deep green and broad flat-looking center; beryl host | **Keep, tune lighting.** Strong rectangle identity and good family pairing with aquamarine. Test step highlights without losing the green body. Do not add fake jardin/silk or assumed clarity grading to make it “real.” |
| **Alexandrite / 6** | Same step rectangle; muted gray/teal under this rig; chrysoberyl host | **Defer as a gameplay reward until a role exists.** Preserve one stable board appearance. Compare two properly authored illuminants in the collection inspector to review color change; never simulate it with arbitrary idle hue cycling. Needs its own mechanic, not a Beryl tag. |
| **Ruby / 7** | Marquise brilliant, aspect 1.8; dark red/magenta with pale central flashes; corundum host | **Keep, improve presence.** Broaden useful face coverage and control dark tips. Ruby is a planned finale gem for the six-room slice, so a muted narrow shape may underdeliver the reward moment. Use a presentation accent, not mandatory flawless physics. |
| **Painite / 7** | Same marquise; orange/red-brown, dark ends; painite host | **Keep in catalog, defer gameplay expansion.** Similar value silhouette and warmth to ruby; use explicit name/family metadata in rewards. Rarity is not enough to justify a gameplay slot. Do not present an exact universal price hierarchy. |
| **Diamond / 8** | Downward pear brilliant, aspect 1.4; bright white/prismatic small facets; diamond host | **Keep as optional apex.** Distinct shape and detailed highlights. Make quartz calmer rather than blindly increasing diamond bloom. Test that down-point survives small-size and reduced-motion display. |
| **Blue Garnet / 8** | Same downward pear; violet/purple under board illumination; garnet host and `bluegarnet_v` absorber | **Defer reward, retain specimen.** Stable violet is usable art, but name/expected color needs a sourced multi-illuminant review before strong claims. Do not promise a visible blue↔red phenomenon from these frames. A late Garnet apex must follow a validated family design. |

### Priority order

1. Shared presentation grammar and short tilt: benefits every gem and is cheaper than 16 physical rewrites.
2. Quartz and sapphire: largest common/apex hierarchy and dark-body problems.
3. Oval elongation and square/lozenge separation: protects rank recognition across drafts.
4. Marquise occupied area and ruby reward presence.
5. Smoky quartz and special color-change specimen calibration, after the initial playable slice.

The **starter eight plus Aquamarine** are enough for the first family-versus-route experiment. The remaining seven game stones remain usable source content and later roster candidates. Do not invent an untested trait just to ship every image.

## Diagnostic and other authored content

These specimens are not silently promoted into playable gems. Their role was reviewed against the game direction; their appearance qualification remains the existing engine corpus/cut evidence, not a new per-specimen optical review in this task.

| Resource | Game relevance and decision |
|---|---|
| `acceptance/clear_faceted.tres` | Baseline transport/facet control; retain regression fixture, not a generic game gem |
| `acceptance/strong_absorption.tres` | Useful stress comparison for dark bodies; does not certify sapphire or any mineral color |
| `acceptance/rough.tres` | Demonstrates admitted rough-surface behavior; optional future named specimen study, not a rank-1 default |
| `acceptance/rounded.tres` | Supports a soft-edge/cushion study; preserve accepted fixture and author a separate game candidate |
| `acceptance/localized_volume.tres` | Local material-field example; not an automatic quality/haze grade |
| `acceptance/resolved_inclusion.tres` | Internal feature control; does not imply natural inclusion morphology/calibration |
| `acceptance/thin_boundary.tres` | Thin-boundary transport stress; not proof of healed-fracture/jardin morphology or visible gap resolution at 112px |
| `cut_examples/pointed_flat.tres` | Pointed crown/flat-bottom grammar example; possible simple-cut inspiration, no required game role |
| `cut_examples/independent_pavilion.tres` | Proves independent construction indices; retain authoring example |
| `cut_examples/mixed_rows.tres` | Rectangle/mixed facet program; possible rank-6 alternative if the step center stays visually static |
| `cut_examples/custom_girdle.tres` | Custom outline example; possible future special silhouette only after rank grammar is tested |
| `recipes/quartz_condition_study.tres` and `batches/quartz_quality_lighting.tres` | Detached condition/lighting exploration with explicit provenance; useful controlled study, not a whole game catalog or geological grading law |
| `materials/measured_corundum/` | Evidence-bearing material studies; usable references for future corundum derivatives, not automatically interchangeable with the catalog's artist-authored coefficients |

## Stylizing without confusing material and gameplay

Use the existing optional illustrative preset as one comparison, not the chosen final style. It currently sets saturation 1.08, contrast 1.04, a one-pixel inner contour at 0.22 opacity and no tonal bands. Compare it to the unstyled house print on actual board backgrounds, especially the already-dark sapphire, ruby and emerald.

Recommended first treatment: common neutral rig, consistent print, subtle optional inner contour, stable hues and crisp alpha. Highlights can be expressive, but entire faces should not turn into flat clipped color. Keep inclusion/roughness/absorption changes specimen-specific and evidence-labeled.

Reject the archived global monotonic quality rule. Quartz need not be cloudy; diamond need not be flawless; Mohs hardness measures scratch resistance and does not make a diamond immune to chipping. Colored-stone quality/value is not a universal sequence of saturation or facet count. UI rank and reward presentation can communicate progression without pretending otherwise. [GIA durability](https://www.gia.edu/gia-news-research/how-protect-diamond-chipping), [GIA colored-stone value factors](https://www.gia.edu/gia-news-research/value-factors-design-cut-quality-colored-gemstone-value-factors).

Do not introduce fake fluorescent emission, directional silk, star effects or healed fractures as engine-backed features. A stylized family burst is allowed as a clearly separate gameplay overlay; it must not be described as simulated mineral optics.

## Acceptance protocol for game art

Make one reproducible review scene with the active eight-rank roster, mixed dense boards, rubble/seals/dust, rank/family labels and a three-card reward comparison. Preserve specimen seeds and compare one changed factor at a time.

1. Inspect 112px native deliveries and 80px/56px downscaled display stress cases on dark, light and actual game backgrounds. These are different display tests, not automatically different optical bakes.
2. Show grayscale and common color-vision-deficiency simulations. Require shape/icon/text cues to carry rules; simulation alone is not accessibility certification.
3. Test all 8 ranks and likely replacements together, not just adjacent ladder pairs. Include quartz/diamond, square/lozenge, round/oval and ruby/painite reward cards.
4. Play chronological short tilts and chained upgrades. No edge-on identity loss, silhouette clipping, framing jumps or high-contrast temporal popping. Review ordinary, fast and reduced-motion modes.
5. With 5–8 unfamiliar testers after a short tutorial, measure gem/rank selection errors, survivor prediction and ability to explain a family reward. Initial target: ≥90% rank identification at 112px and no systematic pair above 10% confusion. These are proposed gates, not results or statistically broad population claims.
6. Reject candidates that pass enlarged inspection but fail board recognition. Retain native images, request/pack hashes, test conditions, observations and decisions.

## Mineral and value source notes

Sources consulted 2026-09-13. Scientific taxonomy and appearance context below are distinct from fictional game effects. Exact prices and geological rarity probabilities are deliberately not assigned.

- [GIA Amethyst](https://www.gia.edu/amethyst): amethyst is the purple quartz variety; supports the Quartz family connection.
- [GIA Aquamarine](https://4cs.gia.edu/en-us/blog/aquamarine/): aquamarine belongs to beryl. [GIA colored-gem overview](https://4cs.gia.edu/en-us/blog/colored-gemstone-engagement-rings-buying-guide/) also distinguishes emerald/green beryl and ruby/pink sapphire.
- [GIA Ruby](https://www.gia.edu/ruby-quality-factor): cut/clarity vary by specimen; ruby can have beneficial or detrimental inclusions. No mandatory “higher rank = zero inclusions” rule follows.
- [GIA corundum](https://www.gia.edu/ruby): ruby and sapphire share the corundum mineral species, supporting their common game-family tag.
- [GIA Garnet](https://www.gia.edu/garnet) and [GIA Tourmaline](https://www.gia.edu/tourmaline): group diversity supports family identity, not one universal material or an invented common ability.
- [GIA Alexandrite](https://www.gia.edu/alexandrite): chrysoberyl identity and illumination-dependent color change support a separate taxonomic tag and inspector study. A board's fixed illumination is not a calibration of that change.
- [GIA value factors](https://www.gia.edu/gia-news-research/value-factors-design-cut-quality-colored-gemstone-value-factors): color, clarity, size, origin, cut and other interacting factors prevent treating the eight game ranks as a reliable mineral price list.

Game metadata must retain a source per mineral relationship and clearly label thematic tags separately. In particular, do not classify malachite as chalcedony merely because both can be patterned: malachite is a copper carbonate hydroxide. [GIA sedimentary gem overview](https://www.gia.edu/gems-gemology/winter-2023-colored-stones-unearthed). Do not classify chrysoberyl as beryl because of its name. Unsupported archive assertions should be verified when that content is actually proposed.
