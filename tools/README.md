# Engine tools

Run `tools/check_engine.ps1 -Gpu` for source parsing, CPU contracts and windowed
GPU acceptance checks. GPU scripts require a local RenderingDevice; headless
execution is supported only for CPU planning, validation and packaging.

`tools/build_gem_assets.ps1` prepares explicit frame jobs, renders missing masters,
prints and packs referenced assets, then collects unneeded factory cache entries.
`-PlanOnly` writes jobs without rendering. The game loads the generated library;
it does not bake assets at runtime.

The standalone stages are `prepare_gem_jobs.gd`, `gem_frame_worker.gd`, and
`pack_gem_library.gd`. `maintain_gem_store.gd` defaults to a dry run and refuses
collection while workers or publishers hold activity guards. See the tracked
factory and kernel contracts for storage and transport interfaces.

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
angular/millimeter tolerances. Run windowed `tools/optimize_cut.gd -- --stone=quartz`
(or `--quick`) for a bounded pavilion/table/crown search. It writes exact candidate
resources, training and held-out metrics, and comparison images under artifacts/.
The brightness objective is not a cut grade; no candidate is promoted automatically.

Explicit fractures use `GemFractureProfile`: a correlated aperture and shared
rough mid-surface, clipped into closed material regions. Wall closure creates
host contact patches and separated pockets. Dimensions are millimeters. These
are authored statistics, not a fracture-mechanics or healed-inclusion model.
`condition_showcase.gd -- --high --fracture-only` compares open and contacting
walls at 256 samples; outputs stay in `artifacts/conditions/aperture/`.
Automatic fracture grading remains disabled: topology validation alone does not
establish convincing appearance or acceptable render cost. Meshing regularizes
near-node sliver contours; admission rejects unresolved degenerate geometry.

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
