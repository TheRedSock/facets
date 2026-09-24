**Lapidary architecture, optics, procedural grading, and delivery audit — 10 September 2026**

This reviews the working tree, including its substantial pre-existing uncommitted changes. It is an analysis, not an implementation change. Production source and authored resources were left untouched. Isolated probes and render evidence are under [artifacts/audit-2026-09-10](C:/GIT/facets/artifacts/audit-2026-09-10).

**Recommendation**

Keep the layered authoring model, spectral transport, convex-facet fast path, and clip delivery. Rebuild the physical grading model around persistent, correlated specimen features and their optical materials. Add a general geometry backend when nonconvex damage, cabochons, carvings, or concave silhouettes become requirements. Establish a slower reference transport mode before expanding the fast approximations.

Use a hybrid of physical rendering and artistic stylization. Physical condition should determine where light travels, what it encounters, and how it scatters. Stylization should determine how clearly those results read in the game. A post-process-only grading system cannot supply the changing refraction, internal reflections, occlusion, silhouette, and lighting response of real defects.

The present implementation is a specialized clean-stone image generator. It is not yet a validated general gemstone optics engine. That distinction is chiefly about transport and representation, not a lack of procedural randomness or insufficient sample counts.

**1. Scope and evidence**

Reviewed: architecture and buffer contracts; resource schemas; species/chromophore generator and provenance notes; silhouette, cut and hull compilation; stone compilation; all three compute passes and their shared code; host scheduling and packing; lighting and print; clips, cache, manifest and GemForge; Atelier and TileView; evaluation, packaging and relevant tests.

Executed with Godot 4.6.1:

| Check | Result | Interpretation |
|---|---:|---|
| Cut compiler | 30 passed | Current template/silhouette checks pass |
| Species data | 617 passed | Authored data satisfies current numeric/schema expectations |
| Pleochroism CPU | 12 passed | Single-segment mixing and selected axis conventions pass |
| Clip delivery | 60 passed | GPU and unavailable packaged-cache paths were skipped |
| Board consumer | 11 passed | Packaged-clip serving was skipped; fallback and input contract pass |
| Existing GPU physics tool | 0 failures | Current, fairly permissive checks pass |
| Atelier parse check | **Failed** | `_c` and `_tracer` are undeclared |
| Additional CPU audit probes | Four cache gaps and a boundedness false positive reproduced | See below |
| Additional GPU audit probes | Alpha and dark-environment fluorescence defects reproduced | See below |

Initial sandboxed Godot processes crashed before test execution. Approved runs outside the sandbox completed. The GPU was an NVIDIA GeForce RTX 4060 Laptop GPU, Vulkan. GPU timings below are single-run observations, not portable performance guarantees.

Existing hero output was inspected but is labeled look v9. It is historical evidence, not proof of current look v12. Eight fresh renders were therefore generated from current source, at CLIP_BAKE policy, 224 pixels, 96 spp, the gameplay rig, and a −12° rest tilt. Rows are authored grade and all axes set to 1; columns are quartz, peridot, ruby and diamond:

![Current authored and pristine comparisons](C:/GIT/facets/artifacts/audit-2026-09-10/current_comparison.png)

These demonstrate functioning faceting, material differences, and grade-driven optical changes. They do not establish agreement with real specimens: there is no matched photograph with known shape, spectrum, lighting and exposure in this audit. Pristine here means grade axes equal 1; authored nonzero base scattering remains.

**2. Concrete findings to fix before further look development**

**A. The designer currently cannot load.** [gem_atelier.gd:52](C:/GIT/facets/scenes/design/gem_atelier.gd:52) uses `_c`, and line 56 uses `_tracer`, without member declarations. Godot's check-only invocation reports parse errors. This is a current authoring blocker, independent of the renderer's theoretical quality. The UI also exposes clarity and surface controls that trigger rebuilds although those axes currently have no optical effect. Restore parsing and make active capabilities visible.

**B. Cache identity does not represent image identity.** [GemStone.fingerprint](C:/GIT/facets/resources/lapidary/gem_stone.gd:26) hashes species/chromophore/cut IDs, not their contents. [GemClip.fingerprint](C:/GIT/facets/resources/lapidary/gem_clip.gd:46) hashes effect-envelope names but not those curves' values. [GemCache.cache_key](C:/GIT/facets/core/lapidary/clips/gem_cache.gd:26) includes neither rig nor print contents, nor the actual rung policy.

The [CPU probe](C:/GIT/facets/artifacts/audit-2026-09-10/cpu_probe.json) confirms unchanged fingerprints after doubling ruby concentration, changing Sellmeier B, changing table ratio, and changing a flash-envelope point. Smaller edits can also disappear into the fingerprint's decimal rounding. A manual look-version bump can mask this, but is not automatic dependency invalidation.

Use canonical content hashes of the resolved specimen, geometry, spectra, material features, rig, clip samples, transport policy and implementation version. Cache linear render output separately from style/print output so a print edit need not retrace. Preserve GPU/driver provenance for reproducibility; shipping pre-baked images need not be rejected merely because the player's GPU differs. Current sidecars record a device name but do not implement the documented foreign-device rejection.

**C. Straight alpha is incorrect at partially covered edges.** In [gem_print.glsl:78](C:/GIT/facets/core/lapidary/tracer/shaders/gem_print.glsl:78), XYZ includes zero-valued missed camera samples, so it already contains coverage weighting. The shader tone-maps that value and outputs coverage as straight alpha without first dividing XYZ by coverage. The compositor applies coverage again.

The [GPU probe](C:/GIT/facets/artifacts/audit-2026-09-10/optics_probe.json) feeds equal conditional radiance at coverage 1 and 0.5. Straight RGB should match. Actual encoded RGB is approximately 0.737 versus 0.612. This can darken outlines and affect apparent small-scale wear. Fix coverage handling before using edge appearance to judge geometry quality. Also replace post-print RGBA8 Lanczos resizing with an explicitly defined linear-light, alpha-aware reconstruction path; both bake paths currently resize encoded straight-alpha images.

**D. Fluorescence emits without illumination.** [gem_pathtrace.glsl:549](C:/GIT/facets/core/lapidary/tracer/shaders/gem_pathtrace.glsl:549) accumulates absorption of camera-path throughput, rather than absorbed incident light, and later adds emission directly to XYZ. With every light at zero power and a black environment, the probe gives ruby mean Y = 0 with fluorescence disabled and **0.00034718 with it enabled**. Small magnitude does not make this a physically valid mechanism.

The implementation also lacks excitation spectra, quantum yield, emitted-light transport and reabsorption. A future physical implementation needs wavelength conversion driven by incident excitation, with energy accounting. A useful research reference is [Abdellah et al., fluorescent participating-media rendering](https://arxiv.org/abs/1706.03024). Treat the current effect as an artistic glow or disable it in reference mode until replaced.

There is also a portability defect: the fluorescence pump calls `smoothstep(620, 480, wavelength)`. Reversed edges have undefined results under the [GLSL specification](https://registry.khronos.org/OpenGL/specs/gl/GLSLangSpec.1.20.pdf). The disabled veil code has the same pattern. Use `1 - smoothstep(low, high, x)` for the intended descending transition.

**E. The hull boundedness check is a heuristic.** [hull_validator.gd:25](C:/GIT/facets/core/lapidary/cut/hull_validator.gd:25) tests 26 directions. The audit constructs an open cone whose normals all have negative dot product with a known escape direction; the checker nevertheless accepts it. This does not show that shipped cuts are unbounded. It does disprove the check as a guarantee for arbitrary procedural cuts.

Add a robust boundedness/nonemptiness test, finite/normalized-plane checks, positive volume, and geometric topology validation. Face clipping is valuable but not literally exact arithmetic: finite seed extent, margins and minimum area intentionally introduce tolerances. Revalidate after pruning, retain diagnostics, and distinguish intentionally vanished facets from a generator error. The stone compiler currently discards most cut diagnostics.

**F. Reported rendering time omits the dominant work.** [GemTracer.accumulate](C:/GIT/facets/core/lapidary/tracer/gem_tracer.gd:451) builds the scatter field before starting its timer. Callers aggregate that returned time under names such as `gpu_ms`. On this machine:

| Current authored stone | Returned trace time | Field build | Accumulation + print/readback wall time |
|---|---:|---:|---:|
| Quartz | 79 ms | 1,125 ms | 1,206 ms |
| Peridot | 60 ms | 605 ms | 667 ms |
| Ruby | 62 ms | 1,127 ms | 1,190 ms |
| Diamond | 180 ms | 1,167 ms | 1,348 ms |

These measurements exclude shader creation, stone compilation/upload, encoding and disk writes. See [full results](C:/GIT/facets/artifacts/audit-2026-09-10/gpu_probe.json). The timers themselves are CPU wall clocks around synchronous GPU work, not GPU timestamp queries.

`board_grid_check.gd` warms the field and then times unchanged poses, excluding both field reconstruction and print/readback. That is a valid warm-state trace measurement, but cannot decide moving-board feasibility by itself. Measure cold startup, changed orientation, changed illumination, unchanged pose, complete presentation, memory and frame-time percentiles separately.

**G. A cache can prevent its own repair.** `GemCache.has()` checks only sidecar validity, while `read()` can subsequently fail because the strip is missing or corrupt. `GemForge.ensure_required()` skips the entry if `has()` succeeds, so that failure need not queue a replacement bake. Validate artifact existence and relevant metadata, or make a failed decode invalidate/requeue the entry. Use atomic artifact publication and schema validation. The generated root is explicitly a development fast path excluded from importing; exported-build packaging remains an acceptance gap.

**3. Architecture: preserve the separation, broaden the contracts**

The strongest existing decisions are the separation of material/species, absorber, shape, condition, lighting, print and delivery; deterministic specimen generation; headless CPU compilation; explicit quality policy; shared preview/bake transport; and persistent lightweight TileViews. These are suitable foundations for a procedural asset system. Visual randomness is separate from gameplay RNG, as it should be.

The central design weakness is that broad promises are represented by narrow implementation contracts. A `StoneInstance` dictionary assumes one convex host, one main absorber with an optional second curve, one homogeneous scattering coefficient, sinusoidal zoning and fixed analytic primitives. That makes the current implementation compact, but every new material mechanism becomes another special branch in a large kernel.

Introduce a validated intermediate representation with explicit units, bounds, capability flags, material/medium IDs, stable facet IDs, feature IDs and diagnostics. Separate these concepts:

| Description | Owns |
|---|---|
| Mineral/material | Optical tensors or isotropic indices, absorber spectra, density, durability metadata |
| Specimen | Growth structure, composition fields, inclusions, fractures, treatments, crystal frame |
| Cut and manufacture | Facet program, proportions, cutter frame, cutting and polishing errors |
| Condition history | Abrasion, impact, cleaning, film/deposit state |
| Render policy | Estimator, numerical accuracy, sampling and approximation budget |
| Presentation | Lighting, framing, stylization and output transform |
| Game recipe | Which specimen/condition distribution a tier requests |

The proposed specimen representation should outlive any one renderer. A reference integrator and a fast integrator can consume it without duplicating geology or hand-authoring a second version of every gem.

Introduce a full crystal-to-cut transform, not only an optic-axis vector. Optical axes, growth planes, cleavage planes and inclusion orientation families must move together. Today `optic_axis_override` affects optics without providing a corresponding common transform for inclusion vocabulary and zoning.

**4. What physical grading should mean**

The current four sliders are convenient recipe controls, not measurements of gemstone quality. `cut` changes real planes; `crystal` changes bulk scattering and zoning; clarity emits nothing behind `INCLUSIONS_ENABLED = false`; surface is ignored. The resource comments claiming four active physical mechanisms are stale.

More fundamentally, species, condition and value should not collapse into one cleanliness hierarchy. Fine inclusions can create desirable sapphire appearance; star stones depend on oriented inclusions. [GIA's sapphire quality discussion](https://www.gia.edu/sapphire-quality-factor?title=GIA) explicitly describes both benefits and penalties from inclusions. “Remove all structure at grade 1” is therefore unsuitable as a universal definition of excellence. Nor is all impurity degradation: chromophores are how many desired colors arise.

Keep the four sliders if they are useful, but resolve them through named recipes into physical parameters. Distinguish cut proportions from cutting precision, transparency from desirable texture, and surface condition from intrinsic mineral properties. Keep tier ordering in game data. A low-tier quartz may be pristine, and a diamond can be chipped; the asset engine should support both.

**Why the disabled inclusion system reads as lines and circles**

The objection is supported by the code, but the cause is not analytic geometry itself. A capsule can be a valid representation of a needle. The failures are the distributions, optical response, and scale policy:

- Independent weighted placement has little growth history, clustering, zoning association or fracture connectivity.
- Only the inclusion center is tested inside the host. Primitive extent and offset children are not checked against every host plane. Surface-reaching features are neither explicitly classified nor handled as boundary changes.
- The primitive record reserves an IOR delta, but the placer writes zero and the tracer does not model nested inclusion media. Refraction and contrast between host and inclusion are missing.
- Surface response uses arbitrary density-derived reflection probabilities, fixed roughness values and three RGB-to-wavelength buckets.
- Crystal “sparkle” directly samples the outside environment from inside the gem, adds a fixed 0.18 contribution, and does not subtract the corresponding reflected energy. The host's remaining exit path is bypassed.
- Lily pads are forced annuli; veils are overlapping irregular discs; fingerprints become a ring of cloud ellipsoids. Their names exceed the causal detail in the generators.
- The needle-radius floor and cloud/crystal caps are specified in stone units to force sprite readability. They alter physical size rather than representation accuracy.
- Feature expansion can exceed the nominal placement budget; only eight intersecting cloud spans are collected, in primitive order.
- Disc detail depends on the sampling seed `pc.seed`. Changing a noise-test seed can therefore change specimen detail when inclusions are restored. Later random decisions also depend on dispatch partitioning. Geometry identity and sampling identity need separate seeds.

Real inclusions can align with crystallography, color zones and healed fractures, and can be solids or fluid/gas cavities; this is documented in [GIA's inclusion overview](https://www.gia.edu/gems-gemology/summer-2022-colored-stones-unearthed). Those relationships are a better procedural vocabulary than independent primitives.

**A feasible replacement: procedural process recipes**

Generate a small number of parent structures, then condition fine detail on them. These are proposed controllable approximations to formation and wear, not a claim to simulate geological time or predict fracture mechanics from first principles.

1. **Growth model:** choose growth center, crystal frame, sectors, bands and composition changes. Store smooth or piecewise concentration fields in physical coordinates.
2. **Inclusion populations:** choose domains tied to growth sectors; distribute sizes and spacing within them; generate oriented needle bundles, actual mineral microcrystals or fluid cavities with material identities.
3. **Fracture model:** generate connected bounded sheets with orientation preference, branching, variable aperture, contact patches and roughness. Generate healing as partial closure plus fluid-pocket trails on the same sheet.
4. **Cut interaction:** intersect that specimen with the cut. Preserve which features are fully internal, exposed at a facet, removed, or opened by cutting.
5. **Manufacturing history:** apply correlated indexing errors, overcuts, table/culet displacement and polishing direction per facet family.
6. **Wear history:** place impacts and abrasion using exposure, edges, corners, prior cracks and material resistance. Produce modified boundaries and local material fields.

A lily-pad recipe, for example, can start with a parent inclusion and an associated curved fracture with variable aperture. Its circular tendency need not be banned: GIA describes [reflective disk-shaped fractures in peridot](https://www.gia.edu/gia-website/peridot-quality-factor). The improvement is modeling the fracture and its interfaces, not merely distorting a drawn circle.

An emerald healed-fracture recipe can use one connected parent sheet and trails of irregular cavities, instead of unrelated discs. A silk recipe can use several crystallographic orientation families within domains, with realistic diameters, population density and an effective directional scattering response below resolution. These recipes remain seeded, reproducible and tunable.

**Surface grading is feasible without meshing every scratch**

Use three scales:

| Scale | Representation | Changes the actual boundary? |
|---|---|---|
| Microscopic polish | Spatially varying anisotropic dielectric BSDF/BTDF | Statistical microgeometry |
| Resolved scratch or facet waviness | Finite groove/displacement or validated procedural patch | When optically/silhouette relevant |
| Chips, pits, broken tips, rounded edges | Explicit geometry or exact geometric construction | Yes |

Microfacet theory represents unresolved geometry statistically. It is physical modeling, not a post-process trick. But rough transmission must use a consistent dielectric model and sampling weights; random normal perturbations plus environment blur are not an equivalent replacement. [Walter et al.](https://www.cs.cornell.edu/~srm/publications/EGSR07-btdf.html) compare rough-transmission models with measured surfaces; [PBRT's dielectric model](https://pbr-book.org/4ed/Reflection_Models/Dielectric_BSDF) provides an implementation reference.

Add facet-local polishing direction, roughness distributions, defect coverage, real groove dimensions, and boundary/material distinctions. A film should have optical properties and thickness or a justified effective coating model. Avoid a universal roughness floor derived from Mohs hardness alone. Hardness, resistance to chipping, cleavage and stability are different properties; [GIA's durability explanation](https://www.gia.edu/gia-news-research/how-protect-diamond-chipping) supports keeping them distinct.

Full finite-element fracture or atomistic damage simulation would be a separate engineering project with difficult material calibration. It is unnecessary for convincing asset generation. Correlated physically plausible geometry with correct light transport is the practical target.

**Volume grading needs heterogeneous media and real interfaces**

Use spatial absorption and scattering fields, wavelength-dependent behavior where justified, and directional scattering for oriented populations. Keep resolved crystals, cavities and open fractures as interfaces with explicit host/inclusion indices, absorption and medium membership. Handle nested regions robustly; index-matched inclusions should disappear optically when all other properties also match.

Avoid counting the same particle population both as explicit scatterers and as bulk haze. Transfer unresolved populations to an effective medium using optical depth and angular scattering behavior, with a documented transition. “More primitive count” is not a sufficient physical model of lower clarity.

**5. Geometry: what the current representation can and cannot do**

Convex half-spaces are worth keeping for planar convex gems. They give compact geometry, watertight shared intersections and uncomplicated internal ray exits. Moving planes already produces genuine geometry changes. More coherent plane errors can improve poor cutting without a mesh rewrite.

The “IOR solver” at [stone_compiler.gd:107](C:/GIT/facets/core/lapidary/stone_compiler.gd:107) is an empirical formula, `45 - 3(n - 1)`, interpolated toward a shallow pavilion. It does not optimize the complete cut. Its diamond result, about 40.75°, being plausible does not validate every material/shape. Crown, pavilion, table and other facets interact; GIA's [cut research](https://www.gia.edu/gems-gemology/fall-2004-grading-cut-quality-brilliant-diamond-moses) evaluates several appearance and craftsmanship components.

Keep it as a named heuristic starting point. Add authored proportions and a design-time optimizer that evaluates ensembles of light/view directions, brightness, leakage, contrast, spectral separation, scintillation and yield constraints. Do not optimize only one flattering camera-axis rig. Model both overly shallow and overly deep cuts, symmetry errors and miscuts; present grading mainly collapses toward one shallow failure mode.

The library currently has eight fixed silhouette presets and two authored cut templates. Aspect ratios, rounding and sector choices are hardcoded in `silhouettes.gd`. Every cut receives a table and a culet trim. Rose/pointed crowns, free-form girdles and arbitrary cutting programs are not implemented just because comments mention family names. Parameterize outlines and top/bottom termination; add explicit meets, independent facet indices, mixed programs, and stable facet identities.

| Target | Best first representation | Scale of change |
|---|---|---|
| Different convex faceted cuts | Existing half-spaces with a richer cut program | Incremental |
| Cutting errors, clipped tips, planar chamfers | Coherent plane edits/additions | Incremental |
| Polishing roughness | Dielectric material model | Moderate transport work |
| Internal crystals/cavities | Analytic or small mesh boundaries plus media | Moderate to substantial |
| True edge curvature, pits, concave chips | Tessellated/analytic geometry with robust intersection | Substantial |
| Cabochons, carved or concave fantasy shapes | Watertight meshes/analytic surfaces plus BVH | Substantial |
| Nonconvex heart/star outlines | General geometry path | Substantial |
| Opal/feldspar-like structural optical effects | Additional material models | Separate specialized development |

A triangle mesh is still fully procedural when generated from a cut/specimen program. Procedural authoring does not require analytic-only tracing. Use a backend-independent hit record containing position, geometric/shading normals, facet/feature ID, and incident/transmitted media. Keep the half-space implementation as one backend and add a mesh/BVH backend alongside it.

Crucially, adding a BVH alone is insufficient: the current integrator assumes transmission through the host boundary reaches the environment immediately. A concave gem can be hit again after an exit; cavities and nearby components create further intersections. The general transport path must continue tracing outside the host until it actually reaches a light or environment.

Be cautious with SDF ray marching as the universal replacement. It is attractive for carving and booleans, but thin fractures, tiny facets, sharp normals and grazing/TIR paths require precise intersections. Benchmark error and cost against a watertight mesh, not only visual convenience.

**6. Optical accuracy and reference mode**

**Clean isotropic transport:** spectral absorption, wavelength-dependent indices, dielectric Fresnel and TIR are the right starting components. Deterministic splitting is particularly suitable for a convex isolated stone under an environment: exiting branches can be evaluated immediately while the reflected branch continues. Retain this optimization where its assumptions hold.

**Scattering:** [the main shader](C:/GIT/facets/core/lapidary/tracer/shaders/gem_pathtrace.glsl:516) permits only the first volume event. The field then supplies a continuation with absorption but no further scattering; disabling the field also leaves only one sampled event. This is not a multiple-scattering solution of the radiative transfer equation. Conserving an energy total would not restore the missing path-length and angular distributions. A standard repeated-scattering reference is described by [PBRT's volume integrators](https://www.pbr-book.org/4ed/Light_Transport_II_Volume_Rendering/Volume_Scattering_Integrators).

The current quartz recipe has scattering optical depth about 0.659 across its 9 mm diameter, before considering longer internally reflected paths. Multiple scattering cannot simply be assumed irrelevant throughout the grading range. At strongly degraded grades it becomes a central part of appearance.

The SH field is also coarse in position, direction and spectrum: degree 3, 25 nm spectral bands, ordinary-ray absorption and 560 nm geometry. It ignores zoning, inclusion occlusion and anisotropic transport in the pre-pass. These are bias sources that more camera samples cannot remove. The common 0.25-radian post-scatter environment filter further changes the target light field. Evaluate it against both the unfiltered physical reference and the intentionally filtered production target.

The existing physics run measured field/reference mean = 0.940 and two-seed noise = 2.5% versus 7.3%. That demonstrates useful variance reduction within its test tolerance. It does not validate the missing higher-order scattering or excluded material features. A future field could be a guide/control variate with a residual estimator, or an explicitly calibrated production approximation; it should not be the only definition of physical truth.

**Birefringence:** the code represents every anisotropic species with one axis and one signed delta-n. Some resources explicitly document a biaxial-to-uniaxial approximation. The extraordinary index is computed from the incoming air-ray direction once; subsequent internal direction changes do not recompute it. Surface Fresnel weights still use ordinary indices. This is an approximation to image doubling, not a general anisotropic interface solution. A relevant complete uniaxial derivation is [Weidlich and Wilkie](https://www.cg.tuwien.ac.at/research/publications/2008/weidlich_2007_rrbuc/weidlich_2007_rrbuc-paper.pdf).

**Pleochroism:** the GIA-inspired single-segment transmission blend has a legitimate basis in [uniaxial color calculation](https://www.gia.edu/gems-gemology/spring-2021-how-to-calculate-color-from-spectra-of-uniaxial-gemstones). However, multiplying fresh unpolarized averages at every segment loses the evolving polarization mixture. Even for two same-direction lengths, `average(T1) × average(T2)` generally differs from `average(T1 × T2)`. Track the polarization components through the path, with frame changes and interface behavior appropriate to the chosen fidelity level. The current CPU tests exercise a local formula, not this multi-segment behavior.

**Dispersion:** the `dispersion_bg()` function actually measures F–C, and the tests knowingly expect only diamond to cross its 0.025 threshold. Thus HERO still does not split wavelengths geometrically for most species. This is a production cost choice, not “all optics” reference quality. Give reference mode per-wavelength paths for all dispersive materials; choose production approximation by measured error, angle, image scale and material, not merely one global threshold. Shared geometry with wavelength-dependent Fresnel can disagree about critical-angle behavior near TIR.

**Spectra:** authored curves are primarily Gaussian reconstructions with literature-informed band positions and appearance-tuned strengths, not a database of measured absorption coefficients. Two-point Sellmeier fits likewise should retain explicit uncertainty and valid wavelength ranges. Preserve these assets as artistic approximations, but label provenance: measured, fitted, literature-shaped, or artistic.

A particularly actionable upgrade is corundum: the [GIA quantitative chromophore study](https://origin.prod.gia.edu/gems-gemology/spring-2020-corundum-chromophores) supplies downloadable polarization-dependent absorption cross-section data. Build unit-checked concentration-to-absorption conversion and support mixtures. Verify sample thickness, orientation and spectral normalization before tuning colors by eye. The current radius convention is now explicit in `GemStone`, but documentation still contains outdated diameter/fluorescence caveats.

**Illumination/color:** keep the controlled studio rig, but do not use it as the sole physical calibration. The current reference rig mixes blackbodies and a spectrally flat background; it is not the CIE D65 spectrum. Use the [published D65 dataset](https://www.cie.co.at/datatable/cie-standard-illuminant-d65), illuminant A and measured-source spectra where relevant. White balance can adapt a white point; it cannot make different source spectra equivalent for every gemstone.

**Print:** `raw` is a tone-mapped display view, not raw linear radiometry. `read_xyz()` is the present numeric escape hatch. Preserve HDR linear output and a documented display transform. The print clips negative RGB before gamut mapping and clamps before its OKLab operation, so full hue preservation is not guaranteed. The house print already performs artistic mastering; keep that separate from validation and future style decisions.

**Any gemstone:** a geometric-optics dielectric engine cannot automatically produce every structural-color phenomenon by adding another Sellmeier curve. Opal's play of color involves diffraction from ordered microstructure; GIA's [review of phenomenal gems](https://origin.prod.gia.edu/gems-gemology/summer-2025-phenomenal-gemstones) explains why distinct material mechanisms are needed. Add targeted effective optical models for such materials rather than promising a universal atomistic simulation.

**7. Optimization priorities**

1. **Measure total cost accurately.** Report geometry compilation, shader startup, uploads, field work, tracing, printing, readback, resampling, encoding and upload-to-display separately. Distinguish warm and changed-scene timings and use GPU timestamps where appropriate.
2. **Avoid paying the dense field cost for negligible scattering.** Current diamond still builds the same 6.75 MiB field at CLIP_BAKE, despite sigma-s = 0.0005/mm. Skip the field exactly when no scattering is possible; for rare scattering, use a cheaper unbiased continuation or a validated approximation policy. Do not silently remove scattering solely for speed.
3. **Reuse according to actual dependencies.** Framing and print changes should not rebuild incident volume illumination. Do not dirty unchanged poses. Reuse fields among truly identical specimen/pose/rig states; keep per-instance transforms separate from shared stone/material data. Flash exposure-only frames can reuse linear radiance. Rig-role variations might use linear basis fields where blockers and all other dependencies permit it; benchmark the memory tradeoff.
4. **Make jobs genuinely interruptible.** GemForge yields between accumulation batches, but the first batch synchronously builds the complete field. Hundreds of short GPU submissions can still create a long main-thread stall. The 120 ms dispatch target protects the watchdog, not frame rate. Use a bounded scheduler/worker ownership model, cancellation and stale-result rejection; perform only necessary presentation work on the main thread.
5. **Keep live output on the GPU if live rendering becomes a goal.** Current print always reads back to an `Image`, followed by `ImageTexture` upload in consumers. The optional external RD argument does not make the host compatible with the main rendering device: it unconditionally calls `submit()`/`sync()`, which [Godot 4.6 documents as local-device-only](https://docs.godotengine.org/en/4.6/classes/class_renderingdevice.html#class-renderingdevice-method-submit). Implement a real main-device presentation path separately.
6. **Enforce device limits and report quality changes.** The field has hardcoded dimension assumptions, stacks instances in texture X, and silently coarsens under a memory budget. Query actual limits, validate every dimension and allocation, and expose effective policy. Otherwise identical materials can change appearance with batch size.
7. **Optimize the remaining kernel after profiling.** Precompute spectral light/IOR lookup tables where error is controlled; specialize clean/no-inclusion paths; replace 20-step free-flight bisection with direct homogeneous sampling when no clouds are present. Cache compiled geometry/material buffers and avoid unnecessary reuploads. The initial wins are likely outside the hull intersection loop.
8. **Add acceleration when feature counts justify it.** A few dozen planes may favor direct intersection; thousands of fracture facets or inclusions justify a BVH or other hierarchy. Benchmark traversal, occupancy, register pressure and divergence on the target GPU. A wavefront rewrite or custom native backend is an option after evidence, not a prerequisite to fix the current dominant costs.

The current no-denoiser policy is an engineering choice that should be reassessed if rough surfaces and richer volumes substantially increase variance. Keep numerical reference outputs unfiltered. For production, compare additional sampling, better importance sampling and optional temporally stable denoising at equal total cost. A denoiser can erase thin inclusions or invent stability, so validate feature preservation; it cannot correct biased transport. Changing this policy would require updating the architecture document, not silently adding a filter.

For the game, baked clips remain the sensible default given these measurements. Ship validated required assets and a cheap fallback; do not make runtime optical compilation essential to launching a level. Keep the board consumer insulated from richer offline grading costs.

**8. How physical grading and stylization should cooperate**

The physical layer should produce the specimen's silhouette, actual surface/volume interactions, colored attenuation, internal feature visibility and view-dependent flashes. The style layer can control palette, contrast, outline treatment, highlight shapes, bloom, temporal accents and game-tier emphasis.

Render linear beauty plus useful auxiliary outputs: coverage, depth, geometric normal, stable facet/material IDs, surface reflection, through-body contribution, volume scattering and defect contributions. For internal defects, first-surface masks are insufficient: accumulate path-weighted contributions or IDs along refracted/reflected paths. Document what each pass means; a stylizer must not mistake a projected front-face normal for the visible internal surface.

Use these outputs to amplify a physically rendered fracture or abrasion cue at 112 px, rather than placing a new screen-space scratch that does not follow the light path. A deliberately painterly game may choose the latter, but that is a different deliverable from the requested reusable optical foundation.

Plan the physical/style resolution boundary explicitly. At a roughly 10 mm stone width occupying order 100 pixels, many real structures are subpixel. Increasing their physical diameter until they become obvious changes the material. Preserve resolved structures geometrically, represent unresolved populations statistically, and use a separate, named readability gain in the style layer if necessary. Filter the underlying signals over the pixel footprint and check temporal stability during rotation.

Preserve reusable HDR artifacts before mastering. Full spectra are only needed if later spectral operations require them; XYZ/linear color supports reprinting but cannot generally recover arbitrary spectral relighting. A set of 2D auxiliary images also does not make a baked stone fully relightable. Keep the specimen definition and renderer available for that.

**9. Alternatives and recommended development sequence**

| Approach | Advantage | Principal limitation | Assessment |
|---|---|---|---|
| Current clean renderer + all grading in post | Shortest route to a fixed game aesthetic | Condition lacks real optical response and generalizes poorly to new views | Viable only if the physical-foundation objective is dropped |
| Extend current half-space renderer only | Reuses nearly everything; handles good facets and modest condition | Nonconvex geometry and nested optics eventually become awkward | Useful first stage, not universal endpoint |
| Shared specimen model + fast convex and general reference paths | Preserves existing assets, gives accuracy targets and a migration path | Requires careful shared contracts and validation | **Recommended** |
| Replace the transport backend with an established spectral renderer | Reuses mature sampling, media and mesh support | Integration, asset authoring and mineral-specific physics still require work | Benchmark as a reference before committing |
| Full custom physical-optics/geomechanics rewrite | Maximum theoretical scope | Large research and calibration burden | Poor first investment for this game |

Mitsuba is a candidate for independent spectral/polarized comparison, based on its [documented rendering modes](https://mitsuba.readthedocs.io/en/stable/src/key_topics/polarization.html). That is not a claim that it already models every gemstone's anisotropic interfaces or special phenomena. Export matched geometry/material test cases and verify supported mechanisms before using any renderer as ground truth.

Recommended order, with concrete exit criteria:

1. **Restore trustworthy iteration.** Fix Atelier parsing, cache identity/repair, alpha and resampling, dark-environment fluorescence and undefined shader expressions. Correct timing reports and stale capability descriptions. Exit: relevant edits invalidate outputs; partial-coverage tests and dark-scene tests pass; current authoring scene loads.
2. **Establish a physical reference mode.** Add strict slab/Fresnel/TIR tests, persistent polarization behavior at the chosen fidelity, full repeated volume scattering, and spectral-path convergence. Keep fast mode separate and measure its bias. Exit: analytically tractable cases pass meaningful bounds, and independent comparisons agree for shared capabilities.
3. **Implement one convincing condition slice.** Use one material/shape and one mechanism at a time: variable facet polish, then a connected fracture with actual internal optical material, then a correlated silk/cloud population. Exit: convincing behavior under rotation and multiple lights, in unstyled output, at hero and sprite sizes.
4. **Broaden geometry.** Add a parameterized cut language, robust validation and a general mesh backend; preserve stable features through cutting and damage. Exit: a cabochon, concave outline and chipped faceted stone render through correct medium transitions and outside reintersection.
5. **Calibrate recipes and spectra.** Add measured-source assets, specimen-scale tests and species-specific feature distributions. Exit: clear separation between measured physics, plausible procedural morphology and artistic choices.
6. **Add game stylization and delivery optimization.** Define the intended aesthetic, develop style against linear output/auxiliary passes, and tune temporal/readability behavior at shipping size. Exit: grade recognition in controlled comparisons without forcing all materials into one monotonic haze/scratch ramp.

Do not implement all phenomena at once. A physically convincing polished-to-abraded facet and one real internal fracture will provide more information than six newly randomized inclusion families.

**10. Validation that would substantiate the engine's claims**

Current tests are useful smoke and regression checks, but several assert the implementation's own policy. The Fresnel check prints an expected 4% while accepting a broad luminance range under a nontrivial rig; the Beer check does not isolate a known transmitted slab path; the energy check is a loose mean threshold. The scatter comparison shares the same one-event approximation on both sides.

Build these acceptance families:

- **Optical primitives:** exact normal-incidence and angular Fresnel, TIR transition, refracted direction, known slab thickness with interface losses accounted for, energy/reciprocity tests appropriate to the model, zero illumination producing zero radiance.
- **Media:** homogeneous and heterogeneous attenuation, zero/equal-index invisible boundaries, repeated scattering versus reference, extinction/albedo separation, nested cavity exit/entry and thin-feature robustness.
- **Anisotropy:** along/across-axis cases, multiple segment transmission, per-interface polarization handling, uniaxial reference slabs; biaxial cases only when actually implemented.
- **Spectra and color:** known spectra under D65/A, thickness and concentration sweeps, white-point checks, measured material examples, fluorescence linearity with excitation and emitted-energy bounds.
- **Geometry:** bounds, nonempty volume, topology, winding, inside/outside consistency, plane/mesh parity, expected facet meets, silhouette across a turn, seed reproducibility and deformation extremes.
- **Image formation:** alpha on black/white/colored backgrounds, HDR-to-display behavior, alpha-aware filtering, spectral and angular convergence, temporal error during clip motion.
- **Procedural quality:** population statistics, physical size limits, crystal-frame alignment, feature connectivity, optical material identity and stable feature IDs under small parameter changes.
- **Production:** content invalidation, interrupted/corrupt cache recovery, cold-start latency, changing-pose cost, GPU memory, actual exported asset availability, and visual inspection at shipping scale.

Test sampling error and model error separately. More samples can suppress grain while leaving the wrong optical model perfectly stable.

The target should be a reproducible procedural specimen generator with validated optical transport and an explicitly artistic presentation stage. The repository already has useful separation and delivery infrastructure for that target. Its largest required changes are a trustworthy reference model, physically meaningful condition features, and geometry/medium contracts broad enough to support them.

For later reproduction, [source_hashes.json](C:/GIT/facets/artifacts/audit-2026-09-10/source_hashes.json) records SHA-256 hashes of the inspected source/data areas. The three isolated probe scripts are retained beside their JSON results. The comparison render intentionally bypasses the asset cache.

