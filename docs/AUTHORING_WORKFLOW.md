# Gem authoring workflow

These are the implemented engine paths. See the [readiness report](ENGINE_READINESS_REPORT.md)
for validated cases, measured budgets and limitations. New authored content needs
its own appearance review before being treated as accepted game content.

## Create and tune a specimen

Open `scenes/design/gem_atelier.tscn` in the Godot project, or enter Gem Atelier
from the development menu. GPU preview needs a windowed Godot process.

1. **Open** an existing stone or asset request. **New from current** creates an
   untitled detached request; it does not change the original resource.
2. Set a deliberate `asset_id` and specimen `stone_id`. These identify authored
   content; the game tile binding is a separate delivery resource.
3. Edit the resource tree. Use **Compare changes**, **Undo** and **Redo** while
   tuning. Keep the specimen seed fixed when comparing physical changes.
4. Use **Preview**, the clip/frame scrubber, black/white/game backgrounds and
   **Output at native size**. The enlarged view alone is insufficient to judge
   a shipping sprite. **House print** is the saved display treatment;
   **Display preview** is a diagnostic view.
5. **Save As**, reopen the saved request, then **Estimate** or **Build asset**.
   Estimate describes requested work and deduplication; it is not a promised
   render duration. Build returns an admitted delivery library in the session
   output. Cancel retains usable estimator checkpoints.

The inspector can load or save selected reusable resources. Keep saved requests
with authored content, and use `data/lapidary/batches/` for explicit lists of
requests. Generated jobs, checkpoints and session outputs belong under
`generated/`, not beside source resources. The catalog generator produces a
candidate tree and diff; it never overwrites hand-authored data.

| Change | Resource/field that owns it |
|---|---|
| Absorption/color | `GemMaterial.absorbers`: spectra, explicit amounts and units |
| Host mineral indices | `GemSpecies` and its index curves |
| Homogeneous cloud | `GemMaterial.scatter_per_mm` and HG anisotropy |
| Localized material variation | `GemCondition.volume_fields` and explicit banding |
| Resolved regions/finish | `GemCondition` defects, surfaces and workmanship |
| Physical scale | `GemStone.size_mm`, a unit-radius scale; inspect actual dimensions |
| Nominal cut | `GemCutTemplate` facet program and parameter values |
| Orientation/framing/pivot | `GemPresentation` |
| Lighting | `GemLightRig` |
| Display treatment | `GemPrint`, then optional `GemStyle` |
| Numerical work | Request rung, samples, dimensions and admitted policy overrides |

Grade labels do not change optics. A named condition preset is an explicit
authored state, not a measured mineral grading law. Support/admission and
appearance acceptance are separate decisions.

## Make a cut or motion

Start from `data/lapidary/cut_examples/` for a pointed/flat, independent-pavilion,
mixed-row or custom-girdle example. Edit named direction sets, groups, parameters
and meet expressions; **Inspect cut** shows the compiled facets, dimensions and
sections. Unsupported constraints fail admission. See the
[cut language](../core/lapidary/cut/CONTRACT.md) for exact units and limitations.

A `GemClip` contains explicit orientation keys, plus optional orientation time,
rig-motion, light-power and exposure curves. Use `tilt_return.tres` as a small
looping tilt example and `turn.tres` for a full turn. Add intermediate keys for
large rotations; each interval follows the shortest quaternion arc. Loops must
close their orientation, rig and envelope endpoints. See the
[clip contract](../core/lapidary/clips/CONTRACT.md).

Keep board translations, swap movement, convergence, scale pulses and removal
in the game renderer. Bake optical motion when the changed pose or lighting is
part of the desired appearance. The final game animation catalog remains a
content-design decision.

## Choose numerical quality

The diagnostic profile names are labels for complete settings, not additional
`GemRung` names. Apply them through the existing asset request fields:

| Diagnostic profile | Request `rung` | `samples` | `policy_overrides.max_bounces` | `policy_overrides.denoise_passes` |
|---|---|---:|---:|---:|
| draft | `clip_bake` | 128 | 128 | 3 |
| detail | `hero` | 512 | 256 | 0 |
| refined | `hero` | 1024 | 256 | 1 |

Set `policy_overrides.batch = 16` to match the corpus work-unit size. These are
the profile settings in `data/lapidary/acceptance/corpus.json`. The reviewed
choice depends on the specimen; more samples alone do not select a different
transport model. Use the recorded appearance decision, then review new content
at its actual shipping size rather than assuming that diagnostic acceptance
transfers to every material, condition or motion.

The corpus uses request `resolution = Vector2i(224, 224)` for 112px output and
`Vector2i(512, 512)` for 256px or 512px output. Set `output_size` independently.
The 512px corpus outputs reuse the 256px optical masters; their measured work is
reprinting, not a second optical render. Keep specimen seeds fixed when comparing
physical edits and use independent sample streams when estimating noise.

## Build and bind game assets

Use a saved `GemAssetBatch` for explicit specimens, variants, clips and policies:

```powershell
./tools/build_gem_assets.ps1 -Batch res://data/lapidary/batches/quartz_quality_lighting.tres -PlanOnly
./tools/build_gem_assets.ps1 -Batch res://data/lapidary/batches/quartz_quality_lighting.tres
```

That example is a condition/lighting study, not a complete game catalog. A game
batch must include every asset and clip referenced by its presentation catalog.
`data/presentation/default.tres` maps logical tile IDs to asset IDs and semantic
`rest`/`upgrade` roles. Rest must be a still or loop; upgrade must be a oneshot.
Missing required assets fail loading explicitly. Tier colors are not a delivery
substitute.

After building a complete catalog, `build_game_package.ps1 -AssetPack
generated/gem-assets.pck -Probe -FrameBudgetMs 16.7` creates and audits a clean
desktop package. Actual release UI and native frame capture are separate gates;
see the [delivery contract](../core/delivery/CONTRACT.md). Do not treat a fixture
package, a successful bake, or a partial image study as final content acceptance.
