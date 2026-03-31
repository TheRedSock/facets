# Visuals System

`core/visuals/` contains the procedural gem generator and lighting code used by
both `TileView._draw()` and the gameplay texture-bake path.

## File Layout

- `gem_cut_generators.gd` — public facade from `cut_id` to generated `GemCutResource`
- `gem_cut_profiles.gd` — declarative cut library; each profile is mostly parameters
- `gem_cut_builders.gd` — reusable topology builders (`radial`, `step`, `fan`, `radiant`, `rose`) and cut-specific pavilion overlay generation
- `gem_cut_primitives.gd` — shared outline math, polygon helpers, curve sampling, normalization helpers, and winding-safe polygon clipping
- `gem_renderer.gd` — pseudo-3D lighting, per-facet colour generation, and pavilion extinction overlay colouring

## Generation Flow

1. `GemVisualRegistry` collects the `cut_id`s referenced by `data/visuals/*.tres`
2. `GemCutGenerators.generate(cut_id)` selects a profile in `gem_cut_profiles.gd`
3. A builder in `gem_cut_builders.gd` assembles facets into a `GemCutResource`
4. `GemCutBuilders.finalize_cut()` normalizes bounds, collects unique edge segments, and generates pavilion extinction overlay fragments
5. `GemRenderer.compute_all_facet_colors()` shades the crown facets for shared render bundles
6. `GemRenderer.compute_pavilion_colors()` computes semi-transparent dark colours for the pavilion overlay

At runtime, `GemVisualRegistry` reuses those render bundles in two ways:
- `TileView._draw()` for direct procedural rendering and fallback paths
- `GameplayGemBakeView` for board-ready baked textures used by gameplay `TileView`s

### Pavilion Extinction Overlay

`generate_pavilion_overlay()` in `GemCutBuilders` creates sub-facet extinction patterns:
1. All non-table crown facets are mirrored through the gem centre (simulating the pavilion)
2. Each cut supplies pavilion metadata such as sector count, rotation fraction, scale, and normal shaping through its generated `GemCutResource`
3. Mirrored facets are transformed using that cut-specific metadata rather than guessed from broad shape categories
4. Each mirrored polygon is clipped against non-table crown facets using winding-safe Sutherland-Hodgman (`GemCutPrimitives.clip_polygon()`)
5. Degenerate intersections are discarded; valid clipped fragments become pavilion overlay entries with steep normals and source/target facet indices
6. The shared render bundle exposes them for both `TileView._draw()` and `GameplayGemBakeView`

The rotation offset ensures pavilion edges cross through crown facets at angles, creating the characteristic angular dark zones seen inside real gems. The `extinction` property on `GemVisualResource` now controls only overlay opacity and no longer darkens crown facets a second time.

## Builder Families

- `build_radial_brilliant(profile)` for round, oval, pear, marquise, heart, polygon brilliants
- `build_step_cut(profile)` for emerald, asscher, octagon, baguette, and tapered baguette style cuts
- `build_fan_cut(profile)` for triangular cuts such as curved and straight trillion variants
- `build_radiant_cut(profile)` for stylized or square/clipped-corner radiant-like cuts
- `build_rose_cut(profile)` for rose-family cuts that do not use a flat table

## Adding A New Cut

If the cut is just a new silhouette or proportion variant:

1. Add outline math to `gem_cut_primitives.gd` only if an existing sampler is insufficient
2. Add a new profile dictionary in `gem_cut_profiles.gd`
3. Wire its `cut_id` through `gem_cut_generators.gd`
4. Add regression coverage in `tests/test_gem_cuts.gd`

If the cut needs a different facet topology:

1. Add a new builder to `gem_cut_builders.gd`
2. Keep the profile declarative where possible
3. Reuse `GemCutResource.add_facet()` and `finalize_cut()` so all consumers keep working

## Design Rules

- Keep all geometry in normalized unit space centered on `(0.5, 0.5)`
- Express shape using ratios, angles, and curve parameters rather than pixel-like constants
- Prefer adding a profile over adding bespoke cut-specific assembly code
- Keep `GemCutGenerators.generate()` as the stable facade for the rest of the project
- Keep pavilion behavior cut-specific by setting metadata on the generated `GemCutResource`, not by inferring from `shape_category`
- Gameplay uses registry-baked textures generated from the same procedural source; the only non-gem fallback is the coloured debug rectangle in `TileView`
- New visual properties should be added to `GemVisualResource` with zero-value defaults so existing `.tres` files render identically
- The Gem Designer (`scenes/design/`) should expose all new visual properties for interactive tuning

## Tests

Run the focused cut suite after changing this folder:

```bash
godot --headless --script tests/test_gem_cuts.gd
```

This suite now also checks pavilion fragment integrity, pavilion symmetry metadata, and winding-independent clipping.

Run the broader smoke suite when changes may affect startup or resource loading:

```bash
godot --headless --script tests/test_smoke.gd
```
