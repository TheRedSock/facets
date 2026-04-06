# Visuals System

`core/visuals/` contains the canonical gem geometry compiler plus the lighting
code used by both `TileView._draw()` and the offline-traced bake pipeline.

## File Layout

- `gem_cut_spec_library.gd` — loads `GemCutSpecResource` assets from `data/visuals/cut_specs/`
- `gem_topology_builders_3d.gd` — family-based 3D topology builders (`radial`, `step`, `fan`, `radiant`, `rose`, `princess`, `fan_step`) plus named-loop patch support
- `gem_cut_compiler_3d.gd` — compiles a spec into a canonical `GemCutModelResource` and runs validation/normalization
- `gem_cut_projector.gd` — projects compiled models into `GemProjectedCutResource` for procedural fallback rendering
- `gem_mesh_generators.gd` / `gem_mesh_assembler.gd` — traced-bake mesh generation from compiled model data
- `gem_optics_tracer.gd` — **fallback only** GDScript CPU tracer; kept as a readable reference implementation. The primary tracer is the native C++ `GemTraceKernel` in `native/`
- `gem_material_sampler.gd` — procedural material sampling used by the 2D renderer (`GemRenderer`). Also serves as the reference implementation for the C++ port in `native/src/gem_trace_material.cpp`
- `gem_cut_primitives.gd` — shared outline math, polygon helpers, curve sampling, normalization helpers, and winding-safe polygon clipping
- `gem_renderer.gd` — pseudo-3D lighting, per-facet colour generation, and pavilion extinction overlay colouring
- `gem_geometry_validator.gd` — compile-time geometry validation for degeneracy, closure, edge sharing, and symmetry quality checks

## Generation Flow

1. `GemVisualResource.resolve_cut_spec()` resolves the referenced `GemCutSpecResource` plus any per-visual overrides
2. `GemCutCompiler3D.compile_spec()` builds a canonical `GemCutModelResource` through `gem_topology_builders_3d.gd`
3. `GemGeometryNormalizer` centers/scales the model and `GemGeometryValidator` checks geometry quality
4. `GemCutProjector.project()` derives a `GemProjectedCutResource` for procedural fallback rendering
5. `GemMeshAssembler.assemble()` derives a `GemMeshResource` for offline tracing
6. `GemRenderer.compute_all_facet_colors()` shades projected crown facets for shared render bundles
7. `GemRenderer.compute_pavilion_colors()` computes semi-transparent dark colours for the pavilion overlay

At runtime, `GemVisualRegistry` reuses those render bundles in two ways:
- `TileView._draw()` for direct procedural rendering and fallback paths
- offline-traced manifest textures for gameplay `TileView`s

The active gameplay bake path is offline traced. It uses the native C++ `GemTraceKernel` (in `native/`) as its primary tracer, with `gem_optics_tracer.gd` as an internal GDScript fallback. There is no longer a public runtime bake-backend switch. See [AGENTS.md](../../AGENTS.md) for the full native tracer architecture, build instructions, and CLI bake reference.

### Pavilion Extinction Overlay

`GemCutProjector.project()` carries pavilion extinction data forward from the compiled model:
1. The compiled model retains zone, facet, and pavilion metadata from the source spec
2. Projection derives clipped pavilion fragments and keeps source/target facet mappings
3. `GemRenderer` shades those fragments separately from the crown facets
4. The shared render bundle exposes them for both `TileView._draw()` and traced-texture preview paths

The rotation offset ensures pavilion edges cross through crown facets at angles, creating the characteristic angular dark zones seen inside real gems. The `extinction` property on `GemVisualResource` now controls only overlay opacity and no longer darkens crown facets a second time.

## Builder Families

- `radial_brilliant` for round, oval, pear, marquise, heart, and polygon brilliants
- `step` for emerald, asscher, octagon, baguette, and tapered baguette style cuts
- `fan` for triangular cuts such as curved and straight trillion variants
- `radiant` for stylized or square/clipped-corner radiant-like cuts
- `rose` for rose-family cuts that do not use a flat table
- `princess` and `fan_step` for the remaining bespoke-but-still-generic families

## Adding A New Cut

If the cut is just a new silhouette or proportion variant:

1. Add or update a `GemCutSpecResource` in `data/visuals/cut_specs/`
2. Extend `gem_cut_primitives.gd` only if an existing sampler is insufficient
3. Reuse an existing family in `gem_topology_builders_3d.gd`
4. Add regression coverage in `tests/test_gem_cut_models.gd` and `tests/test_gem_cuts.gd`

If the cut needs a different topology family:

1. Add a new family builder to `gem_topology_builders_3d.gd`
2. Keep the spec declarative where possible
3. Preserve the canonical compile pipeline so projection, mesh assembly, and validation keep working

## Design Rules

- Keep all geometry in normalized unit space centered on `(0.5, 0.5)`
- Express shape using ratios, angles, and curve parameters rather than pixel-like constants
- Prefer adding a spec asset over adding bespoke cut-specific assembly code
- Keep `GemCutCompiler3D` + projection/mesh assembly as the stable geometry pipeline for the rest of the project
- Keep pavilion behavior cut-specific by storing metadata on the spec/model path, not by inferring from broad shape categories
- Gameplay uses offline-traced textures derived from the same canonical model; the only non-gem fallback is the coloured debug rectangle in `TileView`
- New visual properties should be added to `GemVisualResource` with zero-value defaults so existing `.tres` files render identically
- The active gem tooling surface is `scenes/design/gem_bake_workbench.tscn`; legacy designer scenes are reference-only

## Tests

Run the focused cut suite after changing this folder:

```bash
godot --headless --script tests/test_gem_cuts.gd
```

This suite now also checks pavilion fragment integrity, pavilion symmetry metadata, and winding-independent clipping.

Run mesh and traced-bake coverage when touching traced geometry or optics:

```bash
godot --headless --script tests/test_gem_meshes.gd
godot --headless --script tests/test_gem_optics_tracer.gd
godot --headless --script tests/test_native_trace_kernel.gd
godot --headless --script tests/test_gameplay_bake_backends.gd
godot --headless --script tests/test_gameplay_variant_math.gd
```

Run the broader smoke suite when changes may affect startup or resource loading:

```bash
godot --headless --script tests/test_smoke.gd
```
