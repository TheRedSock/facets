# Engine tools

## Runtime delivery and desktop export

`validate_gem_delivery.gd -- --library=... --catalog=...` checks every logical tile
and declared semantic role without optical work. `create_delivery_test_pack.gd`
creates explicit synthetic integration assets under `artifacts/export-audit/fixture`.
Neither changes the production asset catalog.

`fetch_export_templates.ps1` provisions and verifies pinned official Windows
templates. `build_game_package.ps1 -AssetPack generated/gem-assets.pck -Probe`
stages only runtime sources, exports into a new directory, and audits the exact
PCKs. `-Output` selects an empty destination. Every shipped file and staged source
is hashed; build evidence remains outside the shipped directory. See
`core/delivery/CONTRACT.md` for memory, playback and package contracts.

The package audit and optional playback probe use an external script with the
editor binary's `--main-pack` support, from the clean output working directory.
They reject visible source files and omitted/dead global classes. Standard export
templates disable script overrides. Actual release-executable UI and uncontended
performance must be validated separately; the probe labels its executable.

## Durable authoring and source candidates

Facet programs and examples are documented in `core/lapidary/cut/CONTRACT.md`.
Headless `inspect_cut.gd` writes facet/meet overlays, dimensions and sections from
the compiled geometry; its default is the pointed-crown/flat-bottom example.

The public editing workflow is `GemAuthoringDocument`; its save, undo, provenance,
admission and cache rules are in `core/lapidary/authoring/CONTRACT.md`.
`godot --headless --path . --script res://tools/generate_lapidary_data.gd`
writes a fresh candidate tree and property diff under `generated/catalog-candidates/`.
It never overwrites authored catalog data. GPU `authoring_workflow_check.gd`
validates saved/reopened input through the actual planner and worker.

Check stages require completion markers and have process timeouts (300s CPU,
1800s GPU/reference; a registry entry can override `timeout_seconds`). Timeouts
terminate the launched process tree and fail the stage. The process/result gates
are `tests/test_check_process.ps1` and `tests/test_check_result.ps1`.

## Catalog inspection

`inspect_gems.gd` saves a normal asset batch, renders paired independent sample
streams through the production planner/worker, and writes a labeled sheet, PNG
hashes, cache identities, full frame wall times and opaque-pixel RGB noise metrics.
It replaces the former catalog ladder/grain/noise and aggregate evaluation tools.
The speculative board-live microbenchmark and unused policy have been removed;
gameplay acceptance measures delivered assets. Inspection does not claim a universal
noise threshold or physical calibration. A fresh render requires a windowed GPU;
`--plan-only` and completed-cache replay work headlessly.

`godot --path . --script res://tools/inspect_gems.gd -- --stones=quartz,ruby
--size=112 --samples=128 --output=res://artifacts/inspection`

Clip sampling uses `GemClipSampler`; all deliverable frames use planner/worker
jobs. Reference transport checks remain direct numerical experiments.

## Rotation inspection

`turn_gifs.gd` uses `GemAssetPlanner` and `GemFrameWorker`, the same admission,
optical policy, reconstruction, house print and content cache as asset builds.
It requests a linear 360-degree turn around local Y with a -12-degree rest tilt,
a fixed gameplay studio rig, and **no game stylizer**. The loop excludes its
duplicate endpoint. Shape-default presentation points pears down and centers
the manufactured silhouette bounds at the initial pose; rotation uses that rest
frame center. A request's `GemPresentation` independently controls orientation,
centering and pivot (including native origin or custom coordinates). Catalog discovery includes every authored stone resource.

```powershell
& 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe' --path . `
  --log-file C:/GIT/facets/artifacts/rotation-render.log `
  --script res://tools/turn_gifs.gd -- `
  --res=256 --frames=120 --fps=30 --rung=hero --spp=256 `
  --output=res://artifacts/lookdev/rotation-256
```

The defaults are 256 pixels, 120 frames, 30 fps and HERO's sample count. Override
`--rung=preview` or `--spp=128` for cheaper inspection; `--res` sets both render
and output size without additional resampling. Rungs retain their defined optical
limitations: even `reference` does not select exact crystal transport. Optional
`--stones=quartz,ruby` restricts the catalog; `--python=PATH` selects Python.
`--plan-only` validates and writes `request.res` / `report.json` without rendering.
The saved request is a normal `GemAssetBatch` usable by `prepare_gem_jobs.gd
--batch=...` for portable workers. Both `--name=value` and `--name value` work.

Rerun the same command to reuse verified completed frames and worker checkpoints.
Fully cached reruns can use `--headless`; missing optical work needs a windowed
RenderingDevice. Use separate output directories for studies with different
settings. The store and all source PNGs are retained for inspection and recovery;
this tool does not overwrite the game's generated library or run cache collection.
The report records exact output keys, physical specimen fingerprints, policy,
sample count, source identity, PNG hashes and per-frame end-to-end wall times.

The Python encoder needs Pillow (with WebP) and NumPy. It produces a GIF, a
lossless full-color WebP, an encoding report and an `index.html` comparison gallery.
GIF uses one shared palette and no dithering; use the WebP/PNG to distinguish
palette banding from transport noise. Straight-alpha prints are composited in
linear light onto sRGB (18,18,20) for both animations; PNGs retain original alpha.
GIF's centisecond delays alternate 30/40 ms at 30 fps, totaling exactly 4 seconds
for 120 frames; WebP uses 33/34 ms. Viewer scheduling can still vary. See the
[GIF specification](https://giflib.sourceforge.net/gifstandard/GIF89a.html) and
[Pillow animation options](https://pillow.readthedocs.io/en/stable/handbook/image-file-formats.html#gif).
`python tests/lapidary/test_turn_gifs_encode.py` checks the encoded files' timing,
frame sequence, lossless colors, stale-tail exclusion and linear compositing.

Run `tools/check_engine.ps1 -Gpu` for source parsing, CPU contracts and windowed
GPU acceptance checks. GPU scripts require a local RenderingDevice; headless
execution supports CPU planning, validation, packaging, cached results and styling
from cached unstyled prints.

`engine_checks.json` is the executable gate inventory: entry point, CPU/GPU mode
and positive completion marker. Use `check_engine.ps1 -List -Gpu` to list it or
`-Only source_check,test_asset_planner` to run selected enabled checks. An automatic
quit before the marker fails, as does an exit-zero GDScript exception. Environmental
startup errors remain failures and are separately identified in `results.json`.

Optional game art direction: `build_gem_assets.ps1 -Style
res://data/lapidary/styles/illustrative_sprite.tres -RetainPrints`. Unstyled prints
remain offline inputs; only clip-referenced styled frames ship. Omit `-Style` for
the physical baseline. The preset is illustrative, not a grading model.
`test_style.gd` checks color/coverage/cache isolation; `style_factory_check.gd`
checks an actual GPU print followed by portable headless styling and farm transfer.
`style_lookdev.gd` saves a four-species physical/mild/banded comparison and timings
under ignored `artifacts/style-lookdev`. Hard tonal bands amplify noise and remain
off in the preset.

`tools/build_gem_assets.ps1` prepares explicit frame jobs, renders missing masters,
prints and packs referenced assets, then collects unneeded factory cache entries.
`-PlanOnly` writes jobs without rendering. The game loads the generated library;
it does not bake assets at runtime.

The standalone stages are `prepare_gem_jobs.gd`, `gem_frame_worker.gd`, and
`pack_gem_library.gd`. `maintain_gem_store.gd` defaults to a dry run and refuses
collection while workers or publishers hold activity guards. See the tracked
factory and kernel contracts for storage and transport interfaces.

Named physical quality states use `GemSpecimenRecipe` and `GemQualityPreset`.
Run `realize_specimen.gd -- --recipe=res://data/lapidary/recipes/quartz_condition_study.tres
--quality=softened_polish --seed=17 --output=res://generated/specimens/quartz.res`
to save an explicit binary specimen and its provenance report. Optional `--base`
selects a different GemStone within the preset's species restrictions.
`build_gem_assets.ps1 -Recipe res://data/lapidary/recipes/quartz_condition_study.tres
-Quality softened_polish -SpecimenSeed 17` realizes and builds that state directly.
Recipe selection is mutually exclusive with `-Stone` and `-Specimen`; quality is
required with a recipe. Seeds are integers in 0..2147483647.

The quartz study supplies reference, softened polish, cut tolerance, localized
cloud and foreign-crystal states. These are authored engineering examples, not
calibrated natural grades. Presets replace the base condition completely and can
select a nominal cut and microstructure population. Explicit bounded variation
channels preserve existing draws when unrelated channels are inserted; sharing a
channel couples quantiles. Physical millimeter values do not scale with the gem.
Workers consume the frozen GemStone, not the recipe. Style remains independent.
`test_specimen_recipe.gd` checks realization and admission; `specimen_factory_check.gd`
checks standalone rendering, geometry, cached replay and packing.
`specimen_lookdev.gd` compares unstyled states under three poses and two rigs;
`--quality`, `--resolution`, `--samples`, `--seed` and `--sample-seed` select a study.
Its 112px previews use production XYZ resolve and reuse the optical master.

For multiple quality or lighting variants in one library, use an explicit
`GemAssetBatch`: `build_gem_assets.ps1 -Batch
res://data/lapidary/batches/quartz_quality_lighting.tres`. Each `GemAssetRequest`
names its own asset ID, specimen or recipe/preset/seed, clips, rig, print and
optional style. The example lists two quality states under two rigs, with idle
and turn clips (52 requested frames). No additional grade/seed/light combinations
are generated. Runtime keys are `asset_id/clip_id`, so
`quartz_softened_daylight/turn` coexists with `quartz_reference/turn`.

Request IDs do not change physical stone IDs or optical cache keys. Repeated
aliases share optical/display results; lighting changes reuse geometry outputs.
Requests may override render size, output size and samples independently. Batch
budgets count requested jobs, including retained unstyled prints, before frame
allocation. `-Batch` rejects per-specimen CLI overrides; edit the request resource
instead. `-GeometryCoverage` may explicitly override its geometry setting.
`test_asset_planner.gd` checks bounded planning and identities;
`asset_batch_check.gd` exercises standalone workers, headless reuse and selective
texture loading across quality/lighting variants and aliases.

Physical diagnostics include `foundation_gpu_check.gd`, `surface_check.gd`,
`spectra_gpu_check.gd`, and `reconstruction_check.gd`. Visual outputs and reports
belong under ignored `artifacts/`; generated delivery libraries belong under
ignored `generated/`. Use searches that include ignored paths when investigating
bakes or comparing experiments.

`export_gem_aov.gd -- --stone=quartz --resolution=512 --angle-deg=20 --coverage=4`
writes typed primary geometry, a normal preview and metadata under `artifacts/aov/`.
The pass uses no optical samples. Position/depth are millimeters; normals are in
object space; facet/region/material IDs remain discrete. These optional companions
are for grading inspection and stylizer development, not automatic game payloads.

Use `build_gem_assets.ps1 -GeometryCoverage 4` to request cached geometry alongside
the normal animation outputs (default is off). The standalone planner accepts
`--geometry-coverage=4`; workers accept `--outputs=geometry` to generate only
companions, or `--outputs=optical` to skip them. `all` is the default. Geometry
shares the artifact store, retention manifests and farm transfer protocol, but
never enters the shipping texture pages. Each display job references its companion;
equivalent shapes/poses reuse one result across lighting and optical edits.

Optional independent polarization validation uses an isolated Python environment
with `tools/reference-requirements.txt`. Pass its Python executable as
`-ReferencePython <path>` to `check_engine.ps1`; add `-Gpu` to include actual GPU
interface products. Mitsuba is a validation dependency only. Keep environments,
comparison JSON and rendered reference images under ignored `artifacts/`.

`crystal_gpu_check.gd -- --stress` exposes known float32 critical-angle failures;
it is a diagnostic, not a passing production acceptance profile. Add `--fp64`
for the double-precision mathematical reference (requires GPU shaderFloat64).
`check_engine.ps1 -CrystalPrecision` includes that explicit reference check.
Explicit `GemFrameJob.quality["crystal_transport"] = true` now connects float64
Maxwell modes and coherent packets to the renderer. It requires shaderFloat64,
smooth boundaries, no volume scattering, and weak loss. Defaults remain unchanged.
`crystal_transport_check.gd` checks actual slabs, procedural shapes, nested media,
resume equivalence and the isotropic limit against the Mueller renderer.
`crystal_lookdev.gd` renders clear quartz/ruby diagnostics under artifacts/ and
records whole-job wall time separately from the last accumulation batch profile.
This backend is expensive and still needs broader anisotropic image comparisons;
it is not the fast default or a complete biaxial/scattering implementation.
For a repeatable performance comparison, save `gem_crystal.glsl` and
`gem_crystal_path.glsl` from the baseline revision as
`artifacts/crystal-performance/baseline-math.glsl` and `baseline-path.glsl`.
Run windowed `tools/crystal_benchmark.gd`. It compares three warmed 128px/16-sample
runs of clear quartz/ruby for each version, excluding compilation, and records
source hashes, device, timings, diagnostics and maximum linear XYZ differences.
The fixture compares interface/path changes with the current shared geometry and
lighting; it is not a whole historical-engine benchmark. Baseline sources and
reports remain ignored. FP64 precision checks now include elliptical incident
fields even at interfaces whose mode basis is real.
The isotropic-real-index polarized variant does support persistent axial weak-loss
absorption. `polarization_lookdev.gd -- --dichroic` renders a labeled synthetic
two-band diagnostic under `artifacts/polarization/dichroic/`; its coefficients
must not be treated as measured fluorite data.

Cut design uses explicit template proportions and `GemCondition.workmanship`
angular/millimeter tolerances. Run windowed `tools/optimize_cut.gd -- --stone=quartz --vary=pavilion:38,42,46 --vary=table:0.48,0.64`
(or `--quick`) for a bounded pavilion/table/crown search. It writes exact candidate
resources, training and held-out metrics, and comparison images under
`artifacts/cut-search/<stone>/multi/`. `GemCutPreference` declares return weights,
relative-dark-area constraints, a contrast target and motion weight. Measurements
use associated linear XYZ before print: coverage-normalized mean return,
worst-view return, opaque-pixel luminance CV and darkness relative to that view's
mean. Primary facet IDs match mean facet returns across a 2.5-degree motion;
small/occluded facets are excluded and matched coverage is reported. A stationary
second seed exposes noise. Subtracting this from motion is a conservative utility
term, not an unbiased scintillation estimator. Soft observer masks are included
in half the scenarios. Relative darkness is **not** measured leakage.

The tool screens nondominated alternatives, confirms three at higher resolution
and samples, includes the authored baseline, repeats confirmation with independent
seeds, and evaluates held-out lighting/views without selecting on them. A changed
leader is reported explicitly; two seed pairs are not a confidence interval.
Preferences are illustrative engineering choices, not a gemological cut grade.
Fire, rough-stock yield and calibrated observer judgments remain unmeasured; no
candidate is promoted automatically. CPU `test_cut_metrics.gd` and windowed
`cut_study_gpu_check.gd` cover formulas, eligibility, furnace invariance across
all three transport modes, correspondence and failed-study rejection.

Explicit fractures use `GemFractureProfile`: a correlated aperture and shared
rough mid-surface, clipped into closed material regions. Wall closure creates
host contact patches and separated pockets. Dimensions are millimeters. These
are authored statistics, not a fracture-mechanics or healed-inclusion model.
`condition_showcase.gd -- --high --fracture-only` compares open and contacting
walls at 256 samples; outputs stay in `artifacts/conditions/aperture/`.
Automatic fracture grading remains disabled: topology validation alone does not
establish convincing appearance or acceptable render cost. Meshing regularizes
near-node sliver contours; admission rejects unresolved degenerate geometry.

Resolved microstructure is authored with `GemMicrostructureRecipe` and named
`GemInclusionPopulation` resources. Crystal habits use outward Cartesian support
planes with millimeter distances, not generic stretched hexagons or inferred
Miller indices. Uniform instance scaling preserves face angles. A filling's
optical axis is local to the defect and rotates with its geometry; host and
foreign crystal frames remain independent.

Each population samples a common C2 ellipsoidal placement density in the host
crystal frame, log-uniform sizes and declared orientation families with optional
cone spread. Stable IDs isolate seed channels. Recutting or changing grade labels
does not move inclusions. Conservative bounding-sphere separation applies within
each population; it can reject arrangements that exact elongated shapes could
fit. Failure returns no partial specimen and never shrinks features. Separate
populations retain explicit region priority. Transport clips closed regions to
the host; the report does not infer retained volume from inclusion centers.

These are statistical morphology controls, not nucleation, exsolution or healing
simulation. Grouping by crystal directions, growth zones and healed fractures
has observational support ([GIA, 2022](https://www.gia.edu/gems-gemology/summer-2022-colored-stones-unearthed));
the authored distributions here are not calibrated from that article. The cone
sampler follows [PBRT's uniform solid-angle construction](https://www.pbr-book.org/4ed/Sampling_Algorithms/Sampling_Multidimensional_Functions#SamplingWithinaCone).
Resolved populations cannot also add effective scattering through their placement
domain. Aligned silk, asterism and subwavelength scattering need other optical
models; neither HG haze nor oversized visible needles is a substitute.

Run headless `tools/realize_microstructure.gd` with optional `--stone=...`,
`--recipe=...` and `--output=...res`. It saves the explicit specimen and a provenance
JSON. Defaults use `data/lapidary/microstructures/diagnostic_crystal_layer.tres`,
an explicitly synthetic n=1.8 / neutral 10-per-mm absorption fixture. Build it
with `tools/build_gem_assets.ps1 -Specimen res://generated/microstructure/quartz.res`.
`prepare_gem_jobs.gd -- --specimen=...` also accepts any explicit GemStone;
`--specimen` and catalog `--stone` are mutually exclusive. Workers consume frozen
physical inputs and require no population program or grading decisions.

Windowed `microstructure_lookdev.gd` compares 0/6/18 members at three poses and
light rotations, preserving physical sizes in both 256px and 112px outputs.
The synthetic example remains opt-in. CPU `test_microstructure.gd`, windowed
`microstructure_gpu_check.gd` and headless `microstructure_portable_check.gd`
cover geometry, determinism, crystal frames, independent Beer attenuation,
three-mode furnace behavior and isolated worker/cache delivery.
`microstructure_noise_check.gd` compares fixed-geometry transport seeds at
64/128/512 samples and 256/112px, reporting opaque-pixel RMS, p99 and peak
differences. It does not infer invisibility from an average or certify natural
appearance. This separate lookdev study is not part of every regression run.

`GemGrade` is metadata: changing a label cannot alter transport. Author bulk
scattering with `GemMaterial.scatter_per_mm` and `scatter_g`; use
`GemCondition.banding` for physical band period, direction, phase and contrast,
and `volume_fields` for localized coefficient variations. Catalog coefficients
are explicitly labeled authored approximations. The Atelier volume controls
edit a deep working copy. Evaluation sheets vary physical coefficients rather
than promising that grade sliders simulate degradation.

Completed farm output stores can be consolidated headlessly with
`merge_gem_results.gd -- --source=... --destination=... --manifest=...` (repeat
source for multiple shards). Inspect its dry-run report before `--apply=true`.
Use `--initialize-destination=true` for a new empty store. Conflicting payloads
are refused by default; source precedence must be chosen explicitly.


Principal refraction inputs use `GemIndexCurve` independently for ordinary and
extraordinary axes. Null extraordinary means isotropic. Published quartz and
sapphire curves retain per-axis source equations/evidence; constant index offsets
in the other catalog models are labeled approximations. The GPU transport model
remains approximate for anisotropy in default policies. The explicit crystal
backend follows the admitted uniaxial model. `test_principal_indices.gd` verifies published
numbers, crossing-spectrum admission and binary job identity;
`principal_indices_gpu_check.gd` checks the actual 160B Stone wire format and
GLSL at 0.25 nm intervals. Authoring rejects coefficient quantization exceeding
1e-6 in index on the visible 1 nm grid; this is not a full transport error bound.
Evaluation sheets and the batched board diagnostic now use the actual catalog,
with no duplicate in-code gemstone material definitions.

Pipeline dependency checks: `test_render_dependencies.gd` changes detached source
inventories and verifies actual master/display/geometry keys. The windowed
`pipeline_cache_check.gd` builds an isolated worker, modifies only copied shaders,
and launches fresh processes. It checks headless scalar/geometry reuse after a
crystal edit, reprinting after a print edit, invalidation after a shared mesh edit,
cross-worker result transfer, and rejection of a stale worker source manifest.
Logs and copied projects stay under ignored `artifacts/pipeline-cache/`.

Explicit rough-surface multiple scattering uses `GemSurface.multiple_scattering`.
`microsurface_gpu_check.gd` exports directional samples under ignored
`artifacts/microsurface/`; `check_microsurface_reference.py` independently compares
them with float64 slope-CDF inversion, angular histograms and hemispherical
reciprocity. The full check runner includes both when GPU and reference Python
are supplied. `surface_check.gd` also exercises the integrated scalar/Mueller
renderer, checkpoint failures and uint32 counter carry. `microsurface_lookdev.gd`
renders a256px polished/single/multiple/multiple-plus-milk sheet:128-sample
reconstructed images above independent2048-sample raw references. Results are
numerical/model evidence; automatic surface grading remains disabled.

Spatial finish is authored with `GemSurface.fields` / `GemFinishField`, in
millimeters and object-space directions. Fields interpolate the local GGX shape
matrix; they do not paint color or change geometry. `finish_fields_gpu_check.gd`
and `check_finish_fields_reference.py` compare actual packed/shader results to a
float64 matrix reference. `finish_fields_render_check.gd` checks energy and
angle-dependent reflection; `finish_fields_lookdev.gd` anchors a thin finish
region to the generated table plane and compares unfinished/repolished states
under two poses. Outputs remain under ignored `artifacts/finish-fields/`.

Mesh admission: run `tests/lapidary/test_mesh_admission.gd` headlessly, then
`python tools/check_mesh_predicates.py` for an independent exact-rational check
of determinant signs and constructed triangle intersections. The full runner
includes this comparison when reference Python is supplied; it needs only the
standard library. `mesh_admission_benchmark.gd` measures dense fracture generation,
first admission and repeated content checks separately. Outputs stay under
ignored `artifacts/geometry/`. Topological admission does not certify that tiny
features are resolvable by a chosen GPU transport policy.

Cleavage: attach the opt-in `data/lapidary/conditions/diamond_cleavage.tres` to
`GemCondition.cleavage`, declare the host `GemStone.crystal_to_stone` frame and
choose a depth in millimeters. The source family is cubic diamond {111}; do not
silently apply it as a universal mineral fracture law. Run `test_cleavage.gd`
headlessly and `cleavage_gpu_check.gd` windowed. `cleavage_lookdev.gd` compares
pristine/.4/1.2mm cap removals on a pear-cut diamond at three view/light settings,
writing images and physical reports to ignored `artifacts/cleavage/lookdev/`.
Volume reports describe the host cap before other cavities or fillings. The
operation is explicit, persistent geometry; automatic tier/grade assignment is
not enabled. Linear master records retain the condition report for inspection.

`cleavage_portable_check.gd` builds a fresh isolated source/job bundle with an
enabled cleavage condition, launches its own worker, and verifies optical,
geometry and physical-report outputs. It is included in the GPU check runner.

Convex cleavage keeps half-space geometry and assigns the new face its own
finish slot. `cleavage_backend_check.gd` compares optimized planes against the
general boundary reference at two poses and two finishes, including optical
images and primary geometry. `convex_surface_check.gd` checks mixed plane/mesh
batches and rough scalar/Mueller furnace energy. Both run with `check_engine.ps1
-Gpu`; comparison images/timings stay in ignored `artifacts/cleavage/backends/`.

Localized reconstruction: `reconstruction_gpu_check.gd` is included in the GPU
runner. It checks that raw = sharp + residual, inactive rough fields cannot
soften facets, uniform rough first boundaries have no sharp contribution, and
checkpoint restoration preserves the decomposition. Mueller fixtures explicitly
use isotropic real refraction. For historical image/cost A/B, save the earlier
`gem_pathtrace.glsl` under ignored `artifacts/reconstruction/baseline-pathtrace.glsl`
and run `reconstruction_lookdev.gd` (or `-- --quick` for128px/512spp references).
The normal comparison is256px/128spp against an independent2048spp raw reference;
images, timings, errors and source hashes remain in that ignored directory.

Absorption recipes use `GemMaterial.absorbers`, with a `GemAbsorber` per active
coloring agent. Coefficient spectra take relative scales; cross sections take
active absorbers/cm3 or total-atom ppma with an explicit host atom density.
Independent terms add Napierian coefficients on both principal axes. This is a
dilute independent-absorber model, not a chemical equilibrium calculation. Spatial concentration fields can scale the whole mixture or add independent
absorber terms using the host lattice, atom density and crystal frame.

For the reviewed GIA2020 corundum examples, run
`python tools/extract_corundum_measurements.py <downloaded-workbook.xlsx>` followed
by headless `tools/import_corundum_measurements.gd`. The extractor pins the original
workbook SHA; the importer reads the retained CSVs and checks their hashes. Source
URLs, column mappings, uncertainty scope and unresolved source questions remain
in `data/lapidary/measurements/gia_corundum_2020/source.json` and resource evidence.
Only chromium and iron-titanium examples are active build resources. Iron's
concentration dependence and the other unreviewed curves are not generalized.

`test_absorption_mixtures.gd` checks dimensions, mixtures, source precision,
host admission and portable job serialization. `absorption_mixture_gpu_check.gd`
renders 12 source-backed slabs; `python tools/check_absorption_mixtures.py`
independently integrates raw spectra and normal-incidence reflection/transmission.
Both are included in the GPU/reference suite. `absorption_mixture_lookdev.gd`
compares scalar preview (left) and explicit crystal transport (right), with two
crystal orientations per material, under ignored `artifacts/materials/lookdev/`.
These are measured-spectrum examples, not calibrated specimen colors or updates
to the authored game catalog. Fluorescence remains disabled.

Spatial composition: `GemVolumeField.absorbers` specifies additional peak
concentrations independently of the homogeneous mixture. `PLANAR_TRANSITION`
uses a C2 concentration step across local z=-radius.z..+radius.z; reverse its
normal for the complement. Compact ellipsoid profiles remain available. These
change absorption/scattering only, with no artificial refractive surface.
`generate_composition_examples.gd` rebuilds the explicit corundum bicolor preset
and its clear host. `spatial_composition_lookdev.gd` writes384px/128spp comparisons
of homogeneous, bicolor and bicolor-plus-milk specimens at two poses.

Run `test_spatial_composition.gd` and `spatial_composition_gpu_check.gd` (included
in the full runner). Scalar boundary paths now preserve absorption polarization
across segments and nested media, avoiding a former reset at every cavity. Their
Fresnel interface weights and optional o/e ray split remain approximations;
full Mueller and crystal backends retain their separate capability gates.
`composition_portable_check.gd` exercises the measured spatial example through
an isolated binary job bundle, partial render, resumed render, geometry output
and headless cache reuse. It is also included in the GPU check suite.

Shared worker stores: initialize once with the portable worker's
`--initialize-only=true --output=...` before dispatching parallel processes.
Optical masters and geometry companions have separate work claims. The worker
continues other jobs on contention, then exits 2 for retryable busy work (1 for
failure). `test_work_claims.gd` tests eight competing processes and a killed child;
`work_claims_gpu_check.gd` verifies real portable partial/resume/contention/cache
behavior. Both are registered in the engine check runner.

For crash recovery, inspect `recover_gem_store.gd -- --store=...`, stop all workers
and publishers, then rerun with the exact `--snapshot=... --workers-stopped=true`.
It archives recognized abandoned coordination records without touching bakes or
checkpoints. No expiry timer or cross-machine PID guess releases a work claim.
An existing maintenance lock is not recovered automatically. See the factory
contract for filesystem assumptions and partial-recovery behavior.


Convex junction rounding: `GemCondition.rounding` produces continuous patches with
physical material removal before subsequent cleavage/defects. Use the explicit
`data/lapidary/conditions/rounded_polish.tres` example or author radius in mm.
`test_rounding.gd` checks topology, analytic cube volume, all faceted outlines,
units, cache isolation, admission, portable identity and operation composition.
`rounding_gpu_check.gd` compares actual hits with an analytic rounded box and
checks dielectric energy conservation. `rounding_portable_check.gd` executes an
isolated worker and verifies its physical report and cached geometry. All three
are registered in the check runner.

`rounding_lookdev.gd` renders sharp/30um/120um quartz at two poses. Add `--macro`
for sharp/120um/600um. `--mesh-reference` explicitly selects the triangle
comparison; add `--fine` to halve that reference angular step. `--conditions`
compares sharp, rounded, rounded chip and diagnostic plane separation at two poses.
Generated comparisons remain under ignored `artifacts/rounding/`. This is an
explicit geometry model, not a universal abrasion or grade simulator; performance
and physical calibration must be considered before using it in a large catalog.

Geometry setup reuse: `test_packed_geometry_cache.gd` checks byte-exact canonical
packing/relocation, mutation invalidation and bounded LRU retention.
`geometry_cache_gpu_check.gd` compares cold and reused geometry across all three
transport backends, mixed batches, nested media and material/geometry edits.
Both run through `check_engine.ps1` (the latter with `-Gpu`).

`scene_setup_benchmark.gd -- --label=NAME` records compilation, repeated setup,
trace timings and raw 64px/16spp films under ignored `artifacts/scene-cache/NAME`.
Use `python tools/compare_scene_setup.py BEFORE_DIR AFTER_DIR` to compare timings
and numeric film differences; float32 accumulation grouping can change file hashes.
The benchmark is a setup microbenchmark, not an end-to-end catalog throughput test.

Continuous rounding development checks:
- `test_rounded_solid.gd` validates the float64 construction against an independent
  rounded-box ray/volume oracle, closest-feature distances, mesh tessellation,
  all eight faceted outlines, scaling and invalid inputs.
- `analytic_patch_gpu_check.gd -- --stress` compares candidate packed primitives
  with CPU hits for camera rays, patch interiors/seams and secondary grazing rays
  in float32 and float64. `check_engine.ps1 -Gpu` includes the stress option.
  Reports remain ignored under `artifacts/rounded-solid/`.

- Add `--bvh` to the analytic patch probe to check the accelerated representation
  against the same reference rays. Reports include primitive-test counts.
- `continuous_transport_check.gd` covers mixed analytic/triangle batches, nested
  air and filled regions, cache relocation, AOVs, and scalar/Mueller/crystal
  furnace checks, including real uniaxial quartz.
- `rounding_lookdev.gd -- --macro` uses authored continuous boundaries.
- `cleavage_gpu_check.gd -- --rounded` checks combined conditions across all three
  optical solvers, primary geometry, interrupted-job resume and print reuse; it
  is included in `check_engine.ps1 -Gpu`.

These checks establish renderer admission evidence, not finished grading or
physical wear calibration. StoneCompiler and portable jobs use continuous
rounding; automatic grading and catalog defaults remain inactive.

`compare_rounding.gd -- BEFORE_DIR AFTER_DIR OUTPUT_JSON` compares matching
lookdev frames, records print-space errors and source timing reports, and states
that sampling noise is included. Comparison outputs stay in ignored artifacts.

Rounding lookdev accepts `--output=res://artifacts/NAME` to preserve comparison
runs. `test_patch_bounds.gd` checks clipped-surface extrema independently of rays.


Custom polygon checks: `test_polygon.gd` exports its encoded cap corpus to ignored
`artifacts/polygon/corpus.json`; run `python tools/check_polygon_reference.py` for
independent exact rational area and topology checks. `polygon_gpu_check.gd` checks
collinear-boundary optical equivalence in all three solvers and concave-host
energy conservation. The standard runner includes CPU/GPU checks and runs the
Python oracle when `-ReferencePython` is supplied.
