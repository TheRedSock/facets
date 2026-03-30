# Visuals System

`core/visuals/` contains the procedural gem generator and lighting code used by
`TileView` to render faceted gems directly in `_draw()`.

## File Layout

- `gem_cut_generators.gd` — public facade from `cut_id` to generated `GemCutResource`
- `gem_cut_profiles.gd` — declarative cut library; each profile is mostly parameters
- `gem_cut_builders.gd` — reusable topology builders (`radial`, `step`, `fan`, `radiant`, `rose`)
- `gem_cut_primitives.gd` — shared outline math, polygon helpers, curve sampling, normalization helpers
- `gem_renderer.gd` — pseudo-3D lighting and per-facet colour generation

## Generation Flow

1. `GemVisualRegistry` collects the `cut_id`s referenced by `data/visuals/*.tres`
2. `GemCutGenerators.generate(cut_id)` selects a profile in `gem_cut_profiles.gd`
3. A builder in `gem_cut_builders.gd` assembles facets into a `GemCutResource`
4. `GemCutBuilders.finalize_cut()` normalizes bounds and collects unique edge segments
5. `GemRenderer.compute_all_facet_colors()` shades the facets for `TileView._draw()`

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
- The only remaining non-procedural visual fallback is the coloured debug rectangle in `TileView`

## Tests

Run the focused cut suite after changing this folder:

```bash
godot --headless --script tests/test_gem_cuts.gd
```

Run the broader smoke suite when changes may affect startup or resource loading:

```bash
godot --headless --script tests/test_smoke.gd
```
