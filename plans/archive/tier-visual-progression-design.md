# Tier Visual Progression — Design Analysis

Status: Draft design document. Not implemented.

---

## Problem Statement

The merge ladder (T1→T8) is the core progression mechanic. Each tier has a
unique silhouette (round→square→triangle→oval→diamond→rectangle→marquise→pear)
and each gem has distinct color/mineralogy. But because the pavilion generator
creates optimal proportions for each cut and the spectral tracer renders each
mineral faithfully, **all 16 gems look roughly equally "good"** — a T1 Quartz
reads as a well-cut, clear gemstone just as much as a T8 Diamond does.

In contrast, *Gems of War Treasure Hunt* (the inspiration for the merge mode)
uses bronze→silver→gold coins → money sack → brown→green→red chests → vault.
The progression from worthless to priceless is **immediately legible** because
each tier looks qualitatively different, not just chromatically different.

The goal: when a player sees the board, they should have an **intuitive
subconscious sense of tier ordering** before they've memorized which gem is
which. A T1 should look "humble." A T8 should look "precious."

---

## Available Levers by System

### A. Geometry (cut specs + pavilion generator)

**What it controls:** Silhouette shape, facet count, pavilion angles, crown
height, light return efficiency.

**Current state:** Already differentiated by silhouette per tier. Both chains
use the same shape bucket per tier (round at T1, pear at T8). Silhouette
progression goes from simple/symmetric (round) to complex/asymmetric (pear).

**Potential tier progression levers:**

1. **Intentionally sub-optimal pavilion angles for low tiers.** The pavilion
   generator currently computes angles that maximize light return for each
   mineral's IOR. For T1-T3, the pavilion could be slightly steepened or
   shallowed to reduce total internal reflection efficiency, producing a
   measurably dimmer stone with more light leakage ("windowing"). This is
   physically accurate — lower-grade gems ARE cut with less precision.

2. **Reduced facet count for low tiers.** Lower tiers could use cuts with
   fewer facets (e.g. 8-12 main facets for T1 vs 32+ for T8). The current
   simple_octagon_step for quartz already trends this way, but it could be
   made more deliberate.

3. **Crown height progression.** Shallower crowns on low tiers produce less
   fire and dispersion. Taller crowns on high tiers (especially diamond)
   maximize prismatic effects.

**Assessment:** Geometry changes are the most "honest" approach — they cause
the tracer to produce genuinely different light transport results. But they
require modifying cut specs and potentially the pavilion generator, and any
change to geometry invalidates all existing bakes. Medium-high effort.

**Recommendation:** Consider this for a second pass. The current silhouette
differentiation is already good. Pavilion de-optimization is powerful but
complex — it needs careful validation to avoid making low-tier gems look
*broken* rather than *humble*. The risk is that an intentionally bad cut
produces weird caustic patterns or total darkness rather than a controlled
"less brilliant" look.

### B. Tracer Configuration (GemVisualResource material parameters)

**What it controls:** Surface polish (roughness), volumetric haze (scattering),
physical inclusions, fluorescence, edge rounding. These are physics-level
parameters that the spectral path tracer consumes.

**Current state:** Parameters are set per-mineral for physical accuracy, not
systematically by tier. Only 4 of 16 gameplay gems have inclusion profiles.
Surface roughness varies by mineral template, not by tier.

**Potential tier progression levers:**

1. **Surface roughness ramp.** Lower tiers get higher GGX roughness
   (`surface_roughness_override`), simulating lower polish quality. This
   broadens specular highlights and reduces the "mirror-like" appearance
   of facets. A T1 Quartz with roughness 0.04 vs a T8 Diamond at 0.005
   would have visibly different specular character.

   Suggested values:
   - T1: 0.04 (satin polish)
   - T2: 0.03
   - T3: 0.025
   - T4: 0.02
   - T5: 0.015
   - T6: 0.012
   - T7: 0.008
   - T8: 0.005 (mirror polish)

2. **~~Scattering coefficient ramp~~ — NOT VIABLE at current bake resolution.**

   The volumetric scattering system (`scattering_coefficient_override`) does
   not produce usable haze at gameplay bake resolutions (224px draw size).
   The Henyey-Greenstein scattering requires extremely high pixel density to
   resolve into a smooth milky appearance — at 224px, individual scatter
   events produce what reads as stochastic noise, not haze. Higher SPP does
   not fix this because the problem is spatial resolution (not enough pixels
   in the gem body for the scattered light to average into a visible fog),
   not sample variance. At 1024px+ resolution there might be enough pixel
   density for the scattering to integrate into something visibly hazy, but
   that is far above the gameplay bake target.

   **The scattering system needs its own revamp** to be useful for haze at
   gameplay resolutions. Possible approaches for that separate effort:
   - Pre-filtered scattering approximation (analytical fog integral rather
     than stochastic scatter events)
   - Multi-scale scatter accumulation that doesn't depend on pixel density
   - Post-trace scattering convolution (apply volumetric fog as a 2D
     approximation using depth/path-length information from the trace)

   **For tier progression, use inclusions instead** (see next point).

3. **Inclusion-based haze and clarity grading.** The inclusion system is the
   most effective existing lever for creating genuine internal "impurity" that
   the tracer renders physically. Currently only 4 of 16 gameplay gems have
   inclusion profiles. The system should be expanded for tier progression:

   **Volumetric particle inclusions for haze.** Rather than uniform scattering
   coefficients, haze can be modeled as dense clouds of tiny volumetric
   particle inclusions (type `veil` or `clouds`). This produces non-uniform
   haziness — denser in some zones, clearer in others — which reads as more
   realistic than uniform fog. The tracer already handles inclusion geometry
   through the Embree BVH, so these particles create real Fresnel boundaries
   and scatter events that integrate correctly with the rest of the light
   transport. At low enough density the effect is subtle cloudiness; at
   higher density it approaches translucency.

   Key advantage: because inclusions are actual geometry with spatial
   distribution, the resulting haze has natural variation — pockets of
   cloudiness, clear windows, density gradients — rather than the uniform
   milkiness that a scattering coefficient produces even when it works.

   **Suggested inclusion profiles for currently-unincluded gems:**
   - T1 Quartz: `veil` type, high density (0.5-0.7), multi-scale layers
     simulating milky quartz cloudiness. Natural for low-grade quartz.
   - T1 Fluorite: `crystals` type, low-moderate density (0.15-0.25), small
     inclusions + subtle `growth_zoning` volume pattern. Natural for fluorite.
   - T2 Amethyst: `clouds` type, low density (0.08-0.12), plus color zoning
     via gradient system. Amethyst naturally has color banding.
   - T2 Smoky Quartz: already has `crystals` at 0.08 — could increase
     density slightly and add a `veil` secondary layer.
   - T3 Peridot: `plates` type, very low density (0.04-0.06), oriented
     parallel to c-axis. "Lily pad" inclusions are characteristic of
     natural peridot.
   - T3 Tourmaline: `needles` type, very low density (0.03-0.05),
     parallel to c-axis. Natural for tourmaline.
   - T4+: Existing gems with inclusions (ruby silk, emerald jardin) keep
     their current profiles. Gems without (topaz, rhodolite, sapphire,
     aquamarine, alexandrite, blue_garnet) stay clean — by T4+ the
     progression should show clarity, not cloudiness.

   **Density ramp principle:** inclusion density should be monotonically
   non-increasing with tier. T1 has the most inclusions, T8 the fewest
   (diamond's existing crystal profile is already very sparse at 0.03).

   | Tier | Target inclusion character |
   |------|--------------------------|
   | T1 | Dense veils/clouds — visibly included |
   | T2 | Moderate clouds/crystals — noticeable but not dominant |
   | T3 | Sparse characteristic inclusions — "eye-clean with loupe features" |
   | T4 | Minimal or none — clean appearance |
   | T5-T6 | None or gem-specific character inclusions (emerald jardin) |
   | T7-T8 | Very sparse or none — near-flawless |

4. **Facet edge rounding.** Lower tiers could get higher
   `facet_edge_rounding_override` values, simulating less precise cutting
   where facet junctions are slightly rounded rather than crisp.

**Assessment:** Tracer-level changes produce physically grounded results that
interact correctly with the lighting model. They require rebaking but not
geometry changes. The roughness ramp is trivial (just setting override values
per gem). The inclusion-based haze approach is more work (authoring new
profiles) but produces results that hold up at all bake resolutions and look
genuinely realistic.

**Recommendation:** Implement the surface roughness ramp as an immediate
baseline (small effort, meaningful impact on specular character). Author
inclusion profiles for T1-T3 gems that currently lack them (medium effort,
high visual impact for tier differentiation). Do NOT use the scattering
coefficient for haze until the scattering system is revamped to work at
gameplay bake resolutions.

### C. Stylizer (image-space post-processing)

**What it controls:** Color saturation, contrast, bloom, edge definition,
haze overlay — any 2D image transformation applied after tracing.

**Current state:** Parameters are per-gem but not systematically tier-scaled.
No explicit concept of "gem quality" or "tier position" exists in the stylizer.

**Potential tier progression levers:**

1. **Vibrance scaling.** Low tiers get reduced color saturation (muted,
   humble), high tiers get boosted saturation (vivid, precious). This is the
   single most powerful tier readability lever because color intensity maps
   directly to perceived value across all cultures.

2. **Specular suppression / enhancement.** Low tiers get dampened highlights
   (no punch), high tiers get enhanced specular (bright, sharp). This
   simulates the difference between a dull stone and one that "sparkles."

3. **Bloom gating.** Only T5+ gems get bloom. Low tiers have zero glow
   effect. Bloom is subconsciously read as "magical/valuable/special."

4. **Clarity haze pass (new).** An image-space fog/milkiness overlay for
   low-tier gems. Blends the gem interior toward a softened, desaturated,
   slightly lifted version of itself. Different from tracer inclusions
   (which are geometric) — this is a fast, tunable 2D approximation that
   complements inclusion-based haze from the tracer layer.

5. **Brilliance enhancement pass (new).** For high-tier gems, detect existing
   specular peaks (high-luma, low-chroma pixels) and boost their intensity
   with a slight Gaussian spread. Not bloom (which is soft and diffuse) —
   this is a sharp "glint" effect that makes the gem look alive. Can also
   add small cross-shaped artifacts at the brightest points for T7-T8.

6. **Edge definition scaling.** Higher tiers get sharper, more precisely
   defined facet edges (suggesting expert cutting). Lower tiers get slightly
   softer edges.

7. **Contrast scaling.** Higher tiers get stronger tonal contrast (reads as
   more dynamic and "alive"), lower tiers get flatter contrast (reads as
   more inert and dull).

**Assessment:** The stylizer is the cheapest place to iterate on tier
progression because changes don't require rebaking — they apply on top of
existing traced textures. The downside is that purely image-space effects
can feel "painted on" if overdone. The stylizer should amplify physical
differences, not manufacture them from nothing.

**Recommendation:** Implement a tier-quality system in the stylizer as the
primary user-facing progression lever. Combine with tracer-level roughness
and inclusion ramps for physical grounding.

### D. Surface Damage System (geometric surface imperfections)

**What it controls:** Physical surface defects — scratches, chips, pits,
flakes, abrasion zones — rendered as actual geometry that the tracer
interacts with through standard Fresnel/GGX physics.

**Current state:** Does not exist. All gem surfaces are geometrically
perfect — the mesh has clean planar facets with optional edge rounding
but no surface imperfections. This is a significant missing lever for
tier progression because surface condition is one of the most immediate
visual cues for quality in the real world.

**Concept:**

Surface damage would be implemented as additional polygonal geometry
overlaid on or cut into the existing facet mesh before trace. The tracer
would interact with damage geometry the same way it does any other facet:
Fresnel reflection/refraction at boundaries, GGX microfacet for local
roughness, Beer-Lambert absorption through the body. No new physics
needed — just new geometry and per-zone material properties.

**Types of damage:**

1. **Scratches.** Thin elongated grooves cut into facet surfaces. Modeled
   as shallow V-shaped or U-shaped channels. At trace resolution, a
   scratch breaks the specular reflection of the facet it crosses,
   creating a bright line (specular catch) or dark line (diffuse scatter)
   depending on viewing angle. Multiple scratches at random orientations
   simulate wear from handling or poor storage.

2. **Chips.** Small conchoidal fractures at facet edges (especially
   girdle and culet). Modeled as small irregular concave divots with
   rough interior surfaces. The tracer would see a sudden change in
   surface normal at the chip boundary, producing a bright glint at the
   chip edge and a dark shadow inside. Chips are the most common damage
   on real gemstones and immediately signal "lower quality."

3. **Pits / abrasion.** Clusters of tiny surface irregularities. Rather
   than individual polygons (too expensive), these could be represented
   as zones with drastically elevated `surface_roughness` — e.g., a
   patch of roughness=0.15 on an otherwise roughness=0.01 facet. The
   GGX microfacet model already handles this; the zone just needs to be
   spatially defined. Creates a visually dull, frosted patch on the
   facet surface.

4. **Flakes / spalls.** Larger surface losses where a thin layer has
   separated. Modeled as a shallow depression with a flat floor and
   sharp edges. Similar to chips but broader and shallower. Common on
   softer minerals (fluorite Mohs 4, apatite Mohs 5).

5. **Naturals.** Unpolished remnants of the original crystal surface
   left on the girdle. Modeled as patches with very high roughness
   (0.1-0.3) and potentially different surface normal orientation. These
   are not "damage" per se — they're a deliberate choice by a cutter to
   preserve weight. Common on lower-quality cuts.

**Implementation approach:**

The surface damage system would live in `core/visuals/` as a mesh
post-processor that runs after `GemMeshAssembler` produces the clean
mesh and before the mesh is passed to the tracer. It would:

1. Accept a `GemSurfaceDamageProfile` resource (analogous to
   `GemInclusionProfile`) specifying damage type, density, severity,
   and spatial distribution.
2. Procedurally generate damage geometry using seeded RNG for
   reproducibility.
3. Merge damage polygons into the existing mesh, with per-face material
   zone tags so the tracer can apply elevated roughness to damaged areas.
4. The tracer already supports per-face material properties conceptually
   (it resolves material at hit points) — this would need the material
   lookup to respect zone tags.

**Material zoning within damage:**

Each damage feature would carry its own material properties:
- **Roughness override:** Scratch interiors might be 0.08-0.15 (unpolished
  fracture surface). Chip interiors 0.1-0.2. Abrasion patches 0.05-0.15.
- **IOR continuity:** Damage does NOT create new Fresnel boundaries into
  the gem body (unlike inclusions). A scratch is a surface-only feature —
  light entering through a scratch still refracts into the same gem body.
  This means damage geometry needs to be "open" (not sealed volumes) so
  the tracer doesn't treat them as separate dielectric regions.
- **Depth:** Scratches are very shallow (0.1-0.5% of gem radius). Chips
  are deeper (0.5-2%). Flakes are broad but shallow (0.2-1%).

**Tier mapping:**

| Tier | Surface condition |
|------|------------------|
| T1 | Heavy: multiple scratches, small chips at girdle, abrasion patches |
| T2 | Moderate: some scratches, occasional chip, mild abrasion |
| T3 | Light: few fine scratches, possible natural at girdle |
| T4 | Minimal: one or two hairline scratches if any |
| T5-T6 | Clean: no damage (or single nearly-invisible natural) |
| T7-T8 | Flawless: perfect surface |

This maps to gemological reality: lower-grade stones are sold with
surface wear because re-polishing isn't worth the cost. High-grade
stones are meticulously polished and carefully handled.

**Assessment:** This is the most complex lever — it requires a new mesh
post-processing system, material zone tagging, and potentially changes to
how the tracer resolves per-face material properties. However, the payoff
is high: surface damage is *immediately* visible and *universally* read as
"lower quality" without any learned context. A chipped, scratched gem is
intuitively less valuable than a pristine one.

The key architectural question is whether damage should be:
- **Geometric** (actual mesh modification, traced physically) — most
  realistic, but requires mesh pipeline changes and increases BVH
  complexity
- **Normal-mapped** (perturbed surface normals at hit points without mesh
  changes) — cheaper, compatible with existing mesh pipeline, but less
  physically accurate (no true depth, no correct self-shadowing in
  scratches)
- **Texture-mapped** (roughness variation map applied at trace time) —
  cheapest, but only affects GGX roughness, not surface topology

The geometric approach is the most honest and would interact correctly
with the spectral tracer's existing physics. The normal-map approach is
a reasonable middle ground. The texture-map approach is the simplest
starting point and could be implemented as a per-face roughness
perturbation within the existing tracer without mesh changes.

**Recommendation:** Defer full geometric surface damage to a later phase.
As an intermediate step, consider a **per-face roughness perturbation
system** where the tracer applies spatially-varying roughness noise on
designated faces — this achieves the visual effect of abrasion/wear
without mesh pipeline changes. The full geometric scratch/chip system
would be a subsequent evolution.

**Relationship to Mohs hardness:** Surface damage severity should loosely
correlate with the mineral's real-world Mohs hardness. Fluorite (Mohs 4)
damages far more easily than diamond (Mohs 10). This gives the damage
system gemological grounding:

| Mineral | Mohs | Damage susceptibility |
|---------|------|---------------------|
| Fluorite | 4 | Very high — chips, flakes, abrasion |
| Quartz family | 7 | Moderate — scratches, minor chips |
| Tourmaline | 7-7.5 | Moderate — scratches at girdle |
| Peridot | 6.5-7 | Moderate-high — chips at facet edges |
| Topaz | 8 | Low — minor scratches only |
| Beryl (emerald, aquamarine) | 7.5-8 | Low-moderate — occasional chip |
| Corundum (ruby, sapphire) | 9 | Very low — hairline scratches |
| Diamond | 10 | Negligible — pristine |

This naturally reinforces the tier progression because the merge ladder
roughly follows a real-value/hardness correlation (with exceptions like
emerald, which is valuable despite moderate hardness).

---

## Recommended Implementation Strategy

The approach is **layered**: physical parameters provide the baseline, the
stylizer amplifies and completes the perceptual effect.

### Layer 1: Tracer Config (physical baseline)

Set per-gem `surface_roughness_override` values to create a measurable polish
quality ramp. Author inclusion profiles for T1-T3 gems that lack them,
using volumetric particle inclusions (veils, clouds) to create non-uniform
haze at low tiers.

Do NOT use `scattering_coefficient_override` for haze — the volumetric
scattering system does not produce usable results at gameplay bake resolutions
(224px). See section B.2 for details.

This layer is conservative and physically correct:
- Players looking closely will see that T1 gems have broader specular highlights
  (roughness ramp) and visible internal inclusions (inclusion profiles)
- T4+ gems are clean and precisely polished
- The effect is subtle enough to not break the "these are all real gemstones"
  aesthetic
- It provides genuine input variation for the stylizer to amplify

### Layer 2: Stylizer (perceptual amplification)

Three new concepts in the stylizer v7:

**A. `stylize_visual_quality` parameter (0.0-1.0)**

A master "perceived gem quality" knob, defaulting by tier position. This
modulates several existing stylizer passes:

| Pass | Low quality (0.0) | High quality (1.0) |
|------|-------------------|--------------------|
| Vibrance | ×0.5 (muted) | ×1.25 (vivid) |
| Specular punch | ×0.15 (dull) | ×1.0 (brilliant) |
| Bloom gain | ×0.0 (no glow) | ×1.0 (full bloom) |
| Clarity | ×0.6 (softer) | ×1.0 (full sharpness) |
| Edge definition | ×0.5 (soft edges) | ×1.0 (crisp facets) |
| Contrast | ×0.7 (flatter) | ×1.0 (full contrast) |

Suggested defaults per tier:

| Tier | visual_quality | Perceptual target |
|------|---------------|-------------------|
| T1 | 0.12 | Humble, slightly cloudy, muted |
| T2 | 0.25 | Modest, clearing, hint of color |
| T3 | 0.40 | Decent, good color, some life |
| T4 | 0.55 | Good, clear, sparkling |
| T5 | 0.70 | Excellent, vivid, bright |
| T6 | 0.80 | Exceptional, rich, dynamic |
| T7 | 0.90 | Superb, deep, brilliant |
| T8 | 1.00 | Flawless, dazzling, transcendent |

This is NOT a linear ramp. The curve accelerates at the top because players
spend more time at T1-T4 (common merges) and the T7-T8 "wow factor" needs to
be significantly above T5-T6 to feel rewarding.

**B. `stylize_haze` parameter (0.0-0.5, default 0.0)**

A new image-space pass that simulates reduced optical clarity without requiring
tracer changes. Implementation:

```
# Build haze color: softened, desaturated, lifted version of the pixel
haze_base = gaussian_blur(image, radius=image_size*0.04)
haze_color = desaturate(haze_base, 0.6) * 0.85 + 0.15  # milky lift

# Apply in interior, fade at edges (where silhouette reads)
haze_mask = interior_mask * alpha * haze_amount
result = lerp(pixel, haze_color, haze_mask)
```

Suggested defaults:

| Tier | stylize_haze |
|------|-------------|
| T1 | 0.22 |
| T2 | 0.12 |
| T3 | 0.05 |
| T4 | 0.02 |
| T5-T8 | 0.0 |

This is purely cosmetic and cheap. It doesn't interact with the tracer at all.
The haze is strongest in the gem interior and fades toward edges, so the
silhouette (which is the primary tier identifier) remains crisp.

**C. `stylize_brilliance` parameter (0.0-1.0, default 0.0)**

A new pass that enhances the "life" of high-tier gems by boosting existing
specular peaks. Implementation:

```
# Detect specular peaks: bright, relatively unsaturated pixels
peak_mask = smoothstep(0.7, 0.95, luma) * smoothstep(0.3, 0.0, chroma)
peak_mask *= alpha  # respect silhouette

# Boost intensity at peaks (multiplicative, color-preserving)
boost = 1.0 + brilliance_amount * 0.6 * peak_mask
result = pixel * boost

# Optional: add small Gaussian spread around peaks (micro-bloom)
if brilliance_amount > 0.3:
    peak_glow = gaussian_blur(pixel * peak_mask, radius=2)
    result += peak_glow * brilliance_amount * 0.3
```

Suggested defaults:

| Tier | stylize_brilliance |
|------|-------------------|
| T1-T3 | 0.0 |
| T4 | 0.05 |
| T5 | 0.15 |
| T6 | 0.25 |
| T7 | 0.40 |
| T8 | 0.60 |

At T7-T8, the brilliance pass creates visible "life" in the gem — specular
flashes are brighter and slightly spread, making the gem look like it's
catching the light dynamically.

### Layer 3: Geometry & Surface (future, phased)

Geometric levers for tier progression, ordered by implementation feasibility:

**Phase 3a: Per-face roughness perturbation (intermediate step)**

Before building a full geometric damage system, implement spatially-varying
roughness noise within the existing tracer. The tracer would accept a
per-face or UV-mapped roughness perturbation that adds "wear zones" —
patches of elevated roughness on designated facets (especially girdle and
table edges). No mesh changes needed; the GGX roughness at the hit point
is simply modulated by a procedural noise function seeded by face index.

This achieves the visual effect of surface wear (dull patches, uneven
polish) at low implementation cost and directly reinforces the roughness
ramp from Layer 1.

**Phase 3b: Geometric surface damage system**

Full implementation of the surface damage system described in section D:
`GemSurfaceDamageProfile` resources, procedural damage mesh generation,
per-zone material tagging, and integration with the Embree BVH. This
produces physically correct scratches, chips, and flakes that the tracer
renders with proper self-shadowing and specular interaction.

Suggested implementation order:
1. Scratches (simplest geometry: V-grooves on facets)
2. Abrasion zones (roughness patches, mostly a material-zone feature)
3. Chips (conchoidal divots at edges, requires mesh boolean-like ops)
4. Flakes/naturals (shallow depressions, complex geometry)

**Phase 3c: Pavilion + crown modifications**

1. **Pavilion efficiency curve.** The pavilion generator could accept a
   `cut_quality` parameter (0.0-1.0) that biases pavilion angles away from
   the optimal TIR angle. At quality=0.5, the pavilion is slightly too
   steep, reducing total internal reflection and creating "windowing" (dark
   patches visible through the table). This is physically correct and would
   be visible in the trace without any stylizer intervention.

2. **Facet count reduction.** T1-T2 could use cuts with 8-16 main facets
   (already partially true with simple_octagon_step), while T7-T8 use
   32+ facets. More facets = more scintillation = more perceived life.

3. **Crown height scaling.** Lower crowns on T1-T3, standard/tall crowns
   on T5-T8. Crown height directly affects dispersion spread — taller crowns
   produce more fire. This could be a per-cut-spec parameter or a pavilion
   generator parameter.

Phases 3b and 3c are deferred because they require significant geometry
pipeline work and full rebake cycles. The tracer config + stylizer approach
(Layers 1-2) achieves the perceptual goal faster and more tunably. Phase 3a
is a reasonable intermediate step that adds surface-quality differentiation
without mesh pipeline changes.

---

## Risk Assessment

### Risk: Low-tier gems look "bad" rather than "humble"

**Mitigation:** The quality gradient should be subtle. Even at T1, the gem
should still look like a real gemstone — just a less impressive one. The
target is "nice piece of quartz" not "broken glass." Keep all quality
floor values above the threshold where the gem stops reading as a gem.
The haze amount should stay below 0.25, and vibrance should never go
below 50% of the authored value.

### Risk: Players perceive quality as a rendering bug

**Mitigation:** The progression should feel *natural* — the way people
intuitively expect less valuable stones to look. Real quartz IS cloudier
and less saturated than real diamonds. By grounding the progression in
gemological reality, it feels intentional rather than broken. Players who
know gemstones will find it satisfying; players who don't will process
it subconsciously.

### Risk: Two chains (A and B) diverge in perceived quality at same tier

**Mitigation:** The visual_quality default should be set by tier, not per-gem.
Both T1 gems (quartz + fluorite) get the same visual_quality=0.12. Per-gem
fine-tuning (via existing parameters like vibrance, contrast) adjusts the
character but not the quality level.

### Risk: Overshoot makes the game look ugly

**Mitigation:** The master `stylize_mix` parameter still controls the total
stylizer contribution. If the quality gradient is too aggressive, pulling
stylize_mix down reduces everything proportionally. And `stylize_visual_quality`
is an independent knob that can be dialed back to 0.5 for all gems to reduce
the tier spread.

---

## Design Principles

1. **Grade, don't break.** Low-tier gems should look like lower-grade versions
   of real gemstones, not like damaged or incorrectly rendered stones.

2. **Amplify what exists.** The stylizer should amplify physical differences
   that already exist in the tracer output (broader specular from roughness,
   inclusion-based cloudiness, surface wear), not manufacture entirely
   synthetic effects that contradict the physics.

3. **Preserve silhouette primacy.** The silhouette is the primary tier
   identifier (and the only one that works at the smallest screen sizes).
   No quality effect should compromise silhouette readability. Haze fades
   at edges. Edge definition never goes to zero.

4. **Monotonic progression.** Every quality-correlated attribute should be
   monotonically non-decreasing from T1→T8. No tier should look "better"
   than a higher tier on any single visual axis. The player should never
   be confused about which direction is "up."

5. **Both chains equivalent.** At a given tier, both chain-A and chain-B
   gems should have similar overall visual impact, even though they have
   different colors and cuts.

---

## Summary of Changes Per System

| System | Change | Effort | Priority |
|--------|--------|--------|----------|
| **Stylizer** | Add `stylize_visual_quality` with tier-aware modulation | Medium | High |
| **Stylizer** | Add `stylize_haze` clarity haze pass | Small | High |
| **Stylizer** | Add `stylize_brilliance` specular enhancement pass | Medium | High |
| **Tracer config** | Set `surface_roughness_override` tier ramp on all 16 gems | Small | High |
| **Tracer config** | Author inclusion profiles (veil/cloud) for T1-T3 gems | Medium | High |
| **Tracer config** | ~~Scattering coefficient ramp~~ — not viable at 224px | — | Blocked |
| **Tracer** | Revamp scattering system for low-res usability | High | Deferred |
| **Tracer** | Per-face roughness perturbation (wear zones) | Medium | Medium |
| **Geometry** | Surface damage system (`GemSurfaceDamageProfile`) | High | Deferred |
| **Geometry** | Pavilion efficiency curve parameter | High | Deferred |
| **Geometry** | Crown height scaling per tier | High | Deferred |
