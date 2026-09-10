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

Optional independent polarization validation uses an isolated Python environment
with `tools/reference-requirements.txt`. Pass its Python executable as
`-ReferencePython <path>` to `check_engine.ps1`; add `-Gpu` to include actual GPU
interface products. Mitsuba is a validation dependency only. Keep environments,
comparison JSON and rendered reference images under ignored `artifacts/`.

`crystal_gpu_check.gd -- --stress` exposes known float32 critical-angle failures;
it is a diagnostic, not a passing production acceptance profile. Add `--fp64`
for the double-precision mathematical reference (requires GPU shaderFloat64).
`check_engine.ps1 -CrystalPrecision` includes that explicit reference check.
Crystal modes and coherent packets are still isolated from the production tracer.
The isotropic-real-index polarized variant does support persistent axial weak-loss
absorption. `polarization_lookdev.gd -- --dichroic` renders a labeled synthetic
two-band diagnostic under `artifacts/polarization/dichroic/`; its coefficients
must not be treated as measured fluorite data.

Cut design uses explicit template proportions and `GemCondition.workmanship`
angular/millimeter tolerances. Run windowed `tools/optimize_cut.gd -- --stone=quartz`
(or `--quick`) for a bounded pavilion/table/crown search. It writes exact candidate
resources, training and held-out metrics, and comparison images under artifacts/.
The brightness objective is not a cut grade; no candidate is promoted automatically.

Completed farm output stores can be consolidated headlessly with
`merge_gem_results.gd -- --source=... --destination=... --manifest=...` (repeat
source for multiple shards). Inspect its dry-run report before `--apply=true`.
Use `--initialize-destination=true` for a new empty store. Conflicting payloads
are refused by default; source precedence must be chosen explicitly.
