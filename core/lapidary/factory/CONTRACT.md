# Asset factory and delivery contract

## Presentation, framing and rotation pivots

`GemAssetRequest.presentation` defaults to `GemPresentation`: built-in pears
point down, projected rest-pose bounds are centered, and the rest-frame center
is the rotation pivot. Shape-default orientation rotates the native pear apex
from +X toward screen down before the clip motion/rest tilt. All physical cut,
culet, inclusion and crystal-frame coordinates remain unchanged. A newly authored
pear receives the same default without a stone-ID special case.

Orientation may instead remain native or use custom Euler angles. Camera centering
may use rest bounds, native origin or a custom camera-plane point. The pivot is
independent: rest-frame center, native origin, 3D body-bounds center, or a custom
stone-space point. Coordinates are normalized stone units; they are not millimeters
or pixel offsets. Null presentation on a request explicitly retains native jobs.

Rest bounds come from the manufactured host after workmanship and rounding, via
exact vertex extrema or analytic support functions. They deliberately do not
follow illumination, optical opacity, internal features or removed chips. This
is stable nominal-shape framing, not a claim that arbitrary damaged CSG silhouettes
are recentered by their surviving pixels. Custom centering handles an intentionally
asymmetric damaged specimen. No per-frame bounding-box fitting or brightness
centroid is performed; pivot motion can naturally change the occupied bounds.

The compiler resolves Q(t)=Qclip(t)*Qbase, a rest camera center C and native pivot p.
The camera XY offset is C + (Q(t)*p - Q(0)*p).
Pivot compensation is projected into camera XY; AOV depth remains the distance
from the renderer's outside-bound camera plane. This rotates around the chosen pivot
while holding the rest framing fixed. Centered jobs add (+half/width,-half/height)
to align with the renderer's existing integer-centered sample grid and the image
center ((width-1)/2,(height-1)/2). Native-origin mode adds no pixel correction.
Bounds are geometric, so raster extrema may differ by at most a boundary pixel.

`GemPresentationCompiler` retains one manufactured geometry and up to 64 prepared
bounds, avoiding recompilation during pose edits. Factory jobs serialize only the
resolved orientation and `camera_offset`; those values drive both optical rays
and primary AOVs and enter their independent cache keys. Presentation resources
and compilation are authoring-only dependencies. Low-level numerical fixtures
can keep native identity quaternions/zero offsets. Atelier and factory clip
baking apply the same default presentation as the asset planner.

Camera construction follows the standard raster-to-origin orthographic model
([PBRT](https://www.pbr-book.org/4ed/Cameras_and_Film/Projective_Camera_Models)).
`test_presentation.gd` checks pivots, physical-data isolation and cache identity;
`presentation_check.gd` measures actual catalog coverage and independent pixel
translations, and saves upright optical pear examples.

## Explicit delivery requests

`GemAssetBatch` lists `GemAssetRequest` resources, each with a unique delivery ID,
an explicit specimen or recipe/preset/seed, requested clips, rig, print, optional
style and numerical quality settings. `GemAssetPlanner.plan` validates all names
and frame counts before expansion, detaches authored inputs, realizes specimens,
and returns the existing jobs/clips representation. Invalid input returns no
partial plan. Catalog and single-specimen CLI convenience inputs use this same
planner. Only explicitly listed variants are generated; no Cartesian product is
inferred from board positions, grades, seeds or lighting bins.

Delivery IDs and clip IDs contain 1..128 ASCII letters/digits/underscore/hyphen/dot
(excluding dot and dot-dot alone). Each request has 1..256 uniquely named clips;
each batch has 1..4096 requests and a configurable job budget of 1..65,536, default
16,384. The budget counts pre-deduplication frame requests and retained prints.
Larger productions can publish separate batches into a shared artifact store.
Only explicit orientation keys, orientation time curves, linear rig orbit and
exposure/key/rim envelopes are admitted. See `core/lapidary/clips/CONTRACT.md` for
the single motion grammar and loop/timing rules. Per-frame optical policy
admission still runs after curve sampling.

The library key is `asset_id/clip_id`; it never changes GemStone identity or
transport. Equal physical jobs reuse masters/displays across delivery aliases,
and different lighting requests reuse their shared geometry companions. Optional
retained unstyled prints are offline jobs with no shipping clip references.
`-Batch` carries its own request settings; conflicting convenience CLI overrides
are rejected. Geometry coverage can be overridden explicitly. Batch/planner
sources affect worker provenance but are excluded from optical result domains.

## Procedural specimen realization

`GemSpecimenFactory.realize(recipe, preset_id, seed, source_override)` is a CPU
authoring boundary. It deep-copies a base GemStone, replaces its full condition
and quality labels, optionally selects a nominal cut, applies bounded physical
variations and realizes a microstructure population. It validates the resulting
material and boundary before returning the ordinary explicit GemStone. No camera,
light, resolution or style enters this operation. No partial stone is returned on
failure. Species restrictions are opt-in per preset and enforced when present.

`GemConditionVariation` has a fixed target vocabulary: finish slope widths,
rounding/cleavage millimeters, workmanship errors, pavilion angle/table ratio,
bulk scattering coefficients/asymmetry and named population counts. Bounds and
logarithmic/integer rules are checked before writes. Missing physical owners fail
instead of silently constructing mechanisms. Stable named channels derive their
quantile from the specimen seed; shared channels couple quantiles, while list
ordering and unrelated channel insertion do not affect existing draws. This is
bounded authored variability, not a simulation of growth or damage history.

Changing supplied scattering parameters replaces their evidence with authored
evidence retaining the parent evidence digest. The realization report records
source, recipe, realized specimen, seed, parameter draws and realizer identity.
It travels as resource metadata through binary bundles, excluded from transport
identity. The authoring implementation changes worker provenance but does not
invalidate optics for an identical already-realized specimen. Labels never
modify transport. The opt-in quartz study is not a geological grading standard;
automatic catalog degradation and unaccepted fracture grading remain disabled.

Successful specimen admission uses a 128-entry LRU keyed by exact resource
content, schema source and polarization policy. Edits invalidate the entry;
job-specific policy, rig and output validation still runs. No specimen resources
are retained by the cache. Graph preflight rejects resource cycles, unsupported
objects, depth above 64 and expanded traversal above 262,144 nodes before hashing
or realization. Shared DAG references count each expansion, matching canonical
serialization. Packed numeric arrays are leaves; this is not a byte-size quota.

The game is a consumer of a prebuilt library. Optical tracing belongs to authoring
and offline jobs. A specimen, requested animation, rig and quality profile expand
into explicit frame jobs; there is no implicit rotation×cell×lighting lattice.
Equivalent poses reuse one optical master, and exposure/output-size changes reprint
that master. Artist style belongs after linear optical output.

`GemStyle` is optional game art direction after the mastered print has been
filtered to its requested output size. Tint and saturation operate in linear
sRGB; contrast, optional luminance bands and an inner silhouette contour operate
in encoded sRGB. The contour uses square alpha erosion, at most four pixels,
and preserves every coverage byte. It cannot reveal refracted inclusions or
simulate damage. Geometry AOVs are not interpreted as internal-defect visibility.
Null/identity styles preserve exact bytes and share the unstyled print recipe.
Nonidentity styles have an independent source digest and content identity;
changing their settings or implementation retains optics and unstyled prints.

Use `prepare_gem_jobs.gd --style=res://data/lapidary/styles/illustrative_sprite.tres`
or `build_gem_assets.ps1 -Style ...`. The example is an opt-in illustrative preset,
not a final game aesthetic. Tonal bands are off: hard thresholds can amplify
sampling noise and cause temporal popping. No automatic grade mapping is supplied.
The physical baseline remains the default for the catalog and game build.

Linear luminance weights and the independent sRGB test conversion follow the
[W3C relative-luminance definition](https://www.w3.org/WAI/WCAG21/Understanding/relative-luminance.html).
The subsequent encoded tonal-band operator is an artistic mapping, not radiometry.

Workers cache the unstyled print before styling. Cached prints can be restyled
headlessly, without tracing or GPU mastering; a missing print is regenerated from
the optical master on a GPU. The styled display's `print` key is provenance, not
a mandatory retained/transferred dependency. Add `--retain-prints=true` (build
switch `-RetainPrints`) to request unstyled frames explicitly for retention and
farm transfer. They have no clip references and therefore do not enter shipping
pages. Otherwise collection may discard these intermediate prints. This trades
small additional offline storage for continued headless art iteration.

Design-time microstructure recipes freeze into ordinary `GemStone` conditions:
closed crystal habits, physical centers, uniform scales, independent crystal
frames and material fillings. Workers never invent grade-dependent geometry.
`realize_microstructure.gd` saves the explicit specimen plus recipe/source hashes;
`prepare_gem_jobs.gd --specimen=...` and `build_gem_assets.ps1 -Specimen ...` accept
that resource without catalog edits. The included diagnostic population is
synthetic and opt-in; realization is not natural-inclusion calibration.

`GemFrameJob` contains all authored inputs and render policy. `GemFramePlan` hashes
physical resources, the selected transport pipeline, packed lighting, canonical pose, framing,
resolution, sample seed/count and estimator policy. Display identity also hashes
print, exposure, output dimensions and spectral neutral. Scheduling batch size and
worker hardware are not optical identity. Hardware/driver provenance is recorded.
Catalog names and grade labels are also excluded from optical identity; editing
them retains expensive masters. `GemStone.fingerprint()` still tracks the complete
authored record. Physical input changes retire masters through `transport_inputs()`.
Pose quantization is explicit and the renderer uses the same canonical pose.

Bulk absorption is a typed list of spectrum/amount/unit terms. Source spectra may
be coefficient/mm or cross-section/cm2; the latter retain float64 precision until
physical number-density conversion and summation produce the float32 GPU table.
Binary resource bundles retain each term, its host compatibility and provenance.
Changing composition invalidates optical masters; concentration is not a print
parameter. Spatial fields can scale the complete mixture or add explicit local absorber
terms. Their profile, physical dimensions and spectra participate in optical
identity, while geometry companions remain independent of these coefficients.

`GemRenderIdentity` separates scalar, polarized, crystal, print, style and geometry
result dependencies from `worker_digest()`, the complete renderer inventory.
Known crystal-only modules affect crystal masters; print implementation changes
affect displays; primary-AOV code affects geometry companions. Shared host,
packing and geometry code remain conservative dependencies. New files within the
inventoried source roots are shared unless explicitly classified. The dependency
policy itself, frame executor, pose planner and Godot compiler version are hashed.
Frame-executor edits conservatively retire optical/print results, including when
an edit only changes scheduling; geometry uses its separate executor digest.
This is not automatic
call-graph analysis; move code between passes only with dependency tests.

Master recipe v3 includes its transport digest. Unstyled display recipe v2 includes
the print digest and master key. Styled display v1 adds the style pipeline and
active settings; its engine combines print and style digests. Geometry includes its own pipeline and planner/worker
digests. Each result's `engine` means that result pipeline, not a worker revision.
Producer metadata retains the original `source_engine`; cache hits never relabel
old producers. Bundle-level `engine` and `source_sha256` still require an exact
worker source match. Job records additionally declare `engine`/`display_engine`, and
geometry records declare `engine`. Transfer checks these requested result engines,
so compatible completed assets can cross worker revisions. Conflicting master
pipeline declarations are rejected. Older manifests without pipeline declarations
must be rebuilt; old cache payloads are not silently relabeled or migrated.

`GemArtifactStore` has a store.json marker, atomic recipe JSON and SHA256-addressed
immutable blobs. Linear masters are associated CIE XYZ+coverage RGBAF compressed
losslessly with ZSTD. Checkpoints contain raw estimator buffers and global sample
count; prints are lossless WebP. A worker resumes missing samples or reprints from
an available master. Stored masters include the requested reconstruction; raw
REFERENCE jobs remain available for evaluation. Payload checksums are verified.
Fresh reprint workers skip specimen compilation and allocate only the associated
XYZ input buffer (16 bytes/pixel) plus print output, compiling only the print
shader. They do not require the original transport backend's GPU capabilities.
A subsequent missing master recreates a full transport device. Existing full
devices may be reused for printing; job admission still validates the complete
physical request and conservatively applies its declared full-render memory budget.

`GemJobBundle` creates a minimal independent Godot project and ZIP, with bundled
binary resources, raw shaders, standard tables and source/job checksums. Rendering
requires windowed Vulkan/RenderingDevice, including on a farm. Shards group jobs by
master, so exposure variants stay together. Isolated output stores remain suitable
for separate farm machines. Cooperative workers may also share a filesystem store:
initialize it once with the worker's `--initialize-only=true` before parallel
dispatch. Per-master claims prevent simultaneous rendering/checkpoint writes for
the same master, including its exposure variants. Geometry has independent claims.
Completed stores can be merged through
the validated transfer protocol below. Linux farm deployment is not yet validated.

## Retention and concurrency

Job bundle output is generated and owned, marked by `bundle.json`. First creation
requires an empty unlinked directory; recognized older bundle manifests can be
adopted. Rebuilding a stopped bundle removes obsolete generated code/data inside
its managed source subtrees and hash-named job resources. Unrelated notes remain.
Linked paths are rejected before writing or pruning. This prevents deleted engine
modules from contaminating the standalone source fingerprint. ZIP archives still
use only the explicit current manifest whitelist. Do not rebuild a bundle while
workers are reading it; deploy a separate immutable bundle directory per run.

`GemJobValidator.validate` is CPU-only admission shared by workers and portable
bundle creation. It checks finite physical inputs, supported optical modes,
spectral normalization, camera transforms, procedural topology, known quality
keys and film/payload bounds before GPU setup. Explicit polarization currently
requires isotropic real refraction in the host and every enabled filling.
Axial dichroic absorption requires a valid optical axis and a peak weak-loss
ratio `kappa/n <= 0.001`; spatial concentration bounds participate in admission.
Invalid jobs return a field-specific error instead of silently selecting
another transport model. Film budgets do not include all driver allocations.

Exploratory disabled defects are ignored; missing array entries are errors.
Numerical admission is not a physical calibration or visual-acceptance gate.
When constructing a variant for editing, use
`duplicate_deep(Resource.DEEP_DUPLICATE_ALL)`; `duplicate(true)` retains external
resource references and can mutate the original specimen through nested data.

`GemStoreGuard` registers render/publish/pack activity. Maintenance uses atomic mkdir
and checks activity; workers register then recheck the maintenance directory before
touching data. Maintenance cannot race cooperative workers or packaging. The marker
is released explicitly and on normal RefCounted destruction. A process killed
mid-operation may leave a token. Use the stopped-store recovery protocol below
for activity/claim tokens; an existing `.maintenance/owner.json` requires separate
stopped-owner inspection. No timer steals a slow worker's ownership. This protocol assumes normal local filesystem
atomic creation/rename semantics; distributed object storage needs a coordinator.

`GemWorkClaim` combines an activity guard with atomic `.claims/<work-key>`
directory creation. A busy worker returns `status: busy` without a GPU, checkpoint
write or publication. The command-line worker continues unrelated jobs, then exits
2 if any claimed work remains (1 is failure, 0 is success). Retry busy jobs after
their owners finish; there is no polling loop or timeout-based ownership theft.
Claims cover the complete optical/checkpoint/print operation. This is cooperative
execution exclusion, not a transactional database or a distributed lease service.

After a crash, use `recover_gem_store.gd --store=...` to inspect a content-hashed
snapshot of coordination files. Stop every worker and publisher using that store,
then supply `--snapshot=<reported hash> --workers-stopped=true`. Recovery takes the
maintenance gate, checks that exact snapshot and moves only recognized activity
tokens and claim directories into `.recovered/`, preserving an inventory. Rendered
artifacts/checkpoints are untouched. Changed snapshots, links and unknown token
layouts are refused. Recovery is resumable by inspecting remaining state after
an interrupted move; it is not an all-or-nothing transaction. An existing
maintenance lock is never stolen and requires separate stopped-owner inspection.
The assertion that all workers stopped is operational: a PID on a different farm
machine cannot establish that fact. Shared network filesystem semantics and Linux
deployment still require environment-specific validation.

`tools/maintain_gem_store.gd` defaults to dry-run and the current job manifest.
Repeat `--manifest=...` to retain multiple catalogs. Required display/master recipes
are pinned. A pending checkpoint survives until a checksum-valid master exists.
Spare `--budget-mib` retains newest optional optical masters; unneeded display
recipes and completed checkpoints are disposable. Pinned jobs can exceed budget;
the report states that excess instead of deleting required work.

Collection hashes payloads, checks the store marker, rejects linked paths, and
deletes only an explicit inventory of cache-owned recipe/blob/temporary filenames.
Shared objects remain while any retained recipe references them. Unrelated files
are ignored. `--apply=true` applies collection under the same exclusive lock;
the complete inventory report is written under artifacts/. Malformed recipe JSON
must be repaired before collection. Rendering can regenerate missing/corrupt cache
entries. Neither masters, checkpoints nor cache indexes are shipped in the game.

## Delivery

`GemPagePacker` groups frames by specimen, deduplicates pixels, trims transparent
margins and restores logical size/offset in metadata. Bounded pages use padding and
transparent RGB bleed. Resolution variants reuse masters; mipmaps are absent to
avoid atlas cross-frame bleeding. Lossless WebP is the default disk encoding.
BC7/ASTC4×4 are available with device checks and per-frame RGB/alpha error gates;
the current gemstone catalog has not passed the BC7 acceptance gate.

Library metadata validates sizes, offsets, rectangles, formats and SHA before
allocating textures. Pages load lazily under an LRU ownership budget; displayed
AtlasTextures may retain pages beyond that cache budget. PCK packaging includes
only referenced pages and the published manifest. GemForge reads this library;
TileView uses frame metadata and never invokes the optical renderer.

`tools/build_gem_assets.ps1` prepares jobs, runs resumable rendering and publishes
generated/gem-assets.pck. Copy that pack beside an exported game executable, or set
the explicit delivery path. Build artifacts, evaluation bakes and reports are
ignored by source control; contracts, generation tools and authored inputs remain.


## Farm result consolidation

Give each farm attempt an isolated output store. After its worker exits, run
`tools/merge_gem_results.gd` headlessly with repeated `--source=...`, a local
`--destination=...`, and the original `--manifest=...`. The default is dry-run;
`--apply=true` publishes validated recipes. For a new empty destination, explicitly
pass `--initialize-destination=true`. Initialization refuses existing unrelated files.

Consolidation takes nonblocking exclusive locks on all stores, verifies marked
unlinked paths, checks every requested checksum and decoded image format/dimension,
and admits only manifest-listed completed displays, optical masters and geometry
companions. Geometry validates the decoded GAO1 dimensions, coverage and finite
typed records as well as its checksum.
Source JSON cannot supply executable resources or arbitrary destination paths.
Missing results are reported so incomplete shards can be retried. Checkpoints and
unrequested recipes remain in their original attempt store.

The entire inventory is validated before importing. Different payloads for the
same recipe fail by default, with hashes and source paths in the transfer report.
Floating-point differences across hardware can legitimately create such conflicts;
checksums establish integrity, not cross-device bit identity or trusted provenance.
`--conflict=keep_existing` explicitly prefers the destination, then source argument
order. Review conflicts before choosing that policy. Imports are atomic per recipe,
not one filesystem transaction: an I/O failure may leave a valid partial import,
and retry is idempotent. Only one payload is loaded at a time during copying.

Distributed duplicate-work scheduling and expiring leases require an external
coordinator; the local protocol never steals a slow or interrupted process's lock.

## Optional primary geometry companions

`GemJobBundle.write(..., geometry_coverage_side)` accepts 0 (off), 1, 2, 4 or 8.
The additive `geometry` manifest table contains independent recipe keys, dimensions,
coverage and a checksum-verified binary job input. Each optical job's optional
`geometry` reference points into that table. Missing references are rejected before
generation, retention or transfer. JSON integer-valued numbers are normalized only
after validation. Workers can select `--outputs=all|optical|geometry`.

`GemGeometryPlan` identities include shape, cut, size, workmanship, ordered enabled
defect geometry, filled-region presence, canonical camera pose, framing, dimensions
and coverage. Lighting, optical coefficients, grade labels, sample count and print
are excluded. The geometry pipeline digest and geometry plan/worker source hashes are
included so changes to shared intersections or companion generation retire them.
Geometry records are independently
sharded by their key; duplicate simultaneous work is still not coordinated.

`GemGeometryWorker` generates GAO1 companions with no optical samples, validates
cached payloads before use, and can serve cache hits without a RenderingDevice.
Requested companions are pinned by retention; unrequested companions are disposable.
They carry object-space normals/positions, millimeter depth, coverage and discrete
IDs for the primary visible physical boundary. They do not describe refracted
inclusion visibility or separate optical contributions. A future stylizer must use
the optical master for those appearances rather than painting internal defects from
primary-surface IDs. Companions are authoring data and never automatically ship.

## Optional crystal transport jobs

Quality policy `crystal_transport=true` selects the float64 uniaxial Maxwell
backend and therefore changes optical master identity. It is mutually exclusive
with the isotropic `polarization` policy. CPU admission requires smooth host and
defect boundaries, zero homogeneous/spatial scattering, and weak absorption.
Workers report device/shader configuration failures rather than silently changing
the requested model. Invalid interface diagnostics stop publication. Masters retain
precision, failure and bounce-limit counts; checkpoints retain the same counters
and reject failed state. A bounce-limit count reports finite-depth truncation,
not necessarily an invalid interface. Reference convergence remains the caller's
responsibility. The source bundle includes the shader generator and both shared
GLSL modules; game delivery still contains only the selected baked asset pages.

Explicit `GemSurface.multiple_scattering` belongs to physical specimen identity.
Its Smith walk forces independent wavelength paths and is supported by scalar
and Mueller transport; crystal admission remains smooth-only. Masters retain
`surface_transport` counters. Invalid walks or a256-event micro-walk truncation
block publication. Checkpoint version2 retains48B of surface/crystal diagnostics
in addition to80B/pixel estimator buffers; failed or old-version state is rejected.
Reprints do not rerun the surface model. No grade label enables this option.


## Explicit convex junction rounding

`GemCondition.rounding` / `GemRounding` specify a physical radius in millimeters
and a maximum removed-volume fraction. Zero radius is inactive. This is a uniform
spherical opening of a convex faceted host: inset its half-spaces by the radius,
then offset that inset solid outward by the same sphere. `GemRoundedSolid`
produces continuous planar face patches, cylindrical junction bands and spherical
corner patches. These enter the mixed primitive BVH directly, with actual normals,
refraction and silhouettes. Dihedral angles determine each band's width.

The exact convex parallel-body volume formula supplies the retained-volume report
for the encoded inset core. Collapsed cores and excessive removal are rejected.
Floating-point support planes, clip tolerances and unresolved tiny volume changes
remain explicit numerical limits. `GemRoundingReference` can build an inscribed
triangle approximation for comparison and cap-volume estimates; its angular step
is a tool parameter, not physical authoring or optical-host state.

Rounding precedes authored cleavage and other defect boundaries. Both condition
reports survive composition. It affects optical and primary-geometry cache keys
and survives portable binary jobs. The global finish still controls the rounded
surface; this phase does not infer abrasion pits, polish roughness, hardness,
contact pressure or elapsed wear from the radius. Intentional edge rounding is
also possible. `rounded_polish.tres` is an explicit 30 micrometer example; no
catalog grade or default specimen enables it. Automatic wear grading remains off.

Construction background: [CGAL Minkowski-sum definition](https://doc.cgal.org/latest/Minkowski_sum_3/index.html).
The distinction between rounded junctions, polish quality and intentional girdle
rounding is discussed by [GIA](https://www.gia.edu/gia-news-research-colored-stone-cut-quality-what-to-look-for).
Neither source supplies a calibrated wear law for this operator.

The optional mesh reference is not accepted as the production optical host.
At256px/128spp, halving angular step from6 to3degrees changed opaque RGB by
3.1–5.9LSB RMS for a120um radius and11.2–15.9LSB for600um in the diagnostic
quartz views. These differences include sampling noise and are not a strict
bias bound. Subpixel positional agreement does not establish specular convergence.
Dense triangulation also incurs CPU construction/admission, BVH packing/upload
and trace cost. Continuous analytic patches are the authored production representation;
the mesh remains available as an explicitly selected comparison reference.

## Geometry setup reuse

Each `GemTracer` retains up to 64 MiB of canonical packed BVH payloads in a 16-entry
LRU. `GemPackedGeometryCache` hashes the actual mesh buffers, including semantic
facet and region IDs, rather than trusting a compiled specimen fingerprint.
Detached copies cannot poison the cache; invalid mesh mutations fail admission.
The node array is relocated for its position in each batch without rebuilding the
BVH. Triangle region IDs remain local to each specimen's material table.

The tracer also retains the currently resident GPU node and triangle buffers.
Their final packed-byte SHA256 values include batch relocation and order. A
matching buffer is reused; changed data is uploaded. Other optical inputs are
still packed and configured normally, and every configuration resets the film.
Pose-only updates through `set_clip_sample` already avoid full configuration.
No cached geometry suppresses a material, lighting, finish or field edit.

The 64 MiB bound counts retained CPU payload bytes. Temporary BVH construction,
returned detached buffers and the currently configured GPU scene are additional
memory. This is an in-process optimization, not a persistent geometry-object
format or a complete device-memory admission policy. Job CPU shape generation
and validation still run where required, including first-time cache admission.

`geometry_cache_statistics()` and `profile().geometry_cache` report cumulative
builds/hits, retained bytes, entry count and resident buffer uploads/reuses.
A 25,696-triangle procedural benchmark reduced warm configuration from roughly
3 seconds to 14–15 milliseconds (about 208x median); first configuration remained
about 2.9 seconds. This measures setup, not tracing or first-time mesh compilation.
The saved 64px/16spp films differed by at most 4.8e-7 in linear channels, consistent
with adaptive float32 accumulation grouping. Cold/warm regression scenes have
exact primary-geometry agreement across scalar, Mueller and crystal transport.
No physical estimator or tessellation-convergence claim changes with this cache.

## Continuous rounding representation

`GemRoundedSolid.compile` constructs the same convex spherical opening as the
mesh experiment, using retained float64 vertices and continuous clipped planes,
cylinders and spheres. `GemConvexCore` retains facet/edge/vertex incidence,
checks support membership and closed edge topology, and computes area, volume
and integrated mean curvature. The offset volume is
`V(K) + r*A(K) + r*r*H(K) + 4*pi*r*r*r/3`, where
`H(K) = sum(edge_length * exterior_angle)/2`. Small removed-volume differences
that are below the reporting threshold are explicitly marked unresolved.
There is no angular tessellation setting in the physical recipe.

`GemAnalyticPatch.intersect` is a float64 CPU reference. A separate closest-feature
query validates its surface against distance to the inset core. The quadratic
solver uses closest approach, retaining small radii that would disappear in
`dot(origin, origin) - radius*radius`. Clip tolerances and the minimum radius
admission gate are numerical policies, not certified error intervals.

`GemAnalyticPacking` and `gem_analytic_patch.glsl` define a 64-byte primitive
record and relative clipping planes. This representation is exercised by a
standalone GPU probe in float32 and float64 and by GemTracer; see kernel v21. Cylinder direction must be stored independently:
subtracting float32 endpoints of a very short edge caused false hits and large
normal errors, even when the subsequent arithmetic used float64.

The stress check covers 38,200 camera, feature-interior, seam and secondary rays
per arithmetic precision over eight outlines and two physical radii. After the
axis fix it found no missing or extra intersections; largest ray-parameter error
was about 4e-6 stone units and normal difference about 0.028 degrees. Adversarial
smooth-patch seam ties can choose different facet labels. These measurements use
specific scales and a 1e-6 object-space clip tolerance; they do not certify all
possible sizes, grazing conditions or semantic tie behavior.

GemTracer now supports a mixed primitive hierarchy with continuous region-zero
patches and nested triangle defects. Scalar, Mueller and crystal transport,
primary AOVs, camera bounds and packed-geometry caching use the same boundaries.
The stone compiler and authored asset jobs select these continuous boundaries.
Cleavage and ordinary defect regions preserve the host representation. The chip
placement helper samples its actual cylinder junction bands with a deterministic
exposure heuristic; it does not select artificial tessellation edges.

Cleavage support uses the continuous solid. Its cap-volume report uses a 12-degree
reference mesh and adds the whole-solid discretization gap to the removal estimate
when enforcing the requested limit. Optical paths never use this reference mesh.
The report labels the estimate and gap; these are not certified floating-point
interval bounds. Very small caps or tight budgets can be rejected, and cap volumes
exclude other defects. No adaptive reference refinement is currently performed.
Automatic grading remains disabled. Neither the continuous geometry nor the
spherical-opening radius is a calibrated abrasion, polishing or hardness law.

The volume construction follows the convex special case of the polyhedral
[Steiner formula](https://cseweb.ucsd.edu/~alchern/teaching/DDG.pdf), section 4.7,
and its [parallel-body decomposition](https://courses.cms.caltech.edu/cs177/notes_fa11/GeoMeasure.pdf).

At 256px/128spp, explicit 0.12mm and 0.6mm radii on quartz at 4mm per stone unit used
530 and 330 patches. Construction took 237/217ms, first packing 42/29ms and
repeated packing 18/12ms. Trace times were 4.30/5.69s at 0.12mm and 8.22/9.89s
at 0.6mm for two poses. The earlier 3-degree meshes took 27.9/46.5s to construct
and 9.69–15.38s / 10.39–12.07s to trace. These are historical same-machine
comparisons, not a controlled GPU clock benchmark. Large-radius traversal still
spends work in overlapping conservative full-cylinder/sphere bounds.

Continuous versus 3-degree mesh opaque RGB RMS differences were 1.62/3.80 LSB
at 0.12mm and 5.95/9.59 LSB at 0.6mm; sampling noise is included. Smooth curved
highlights are visible, but those differences do not establish undetectable
convergence, real specimen calibration or an automatic wear grade. Keep the
rounding defaults inactive pending physical calibration and grading acceptance.

Tighter clipped-patch bounds subsequently reduced the same 256px/128spp trace
times to 3.56/4.69s (0.12mm) and 4.18/4.88s (0.6mm). Coverage was identical;
maximum opaque RGB RMS change was 0.0123 LSB, with isolated differences up to
3 LSB. The ray corpus still had zero missing/extra hits. These measurements
support this acceleration change at the tested scales, not arbitrary precision
or physical-wear calibration. The bounds include clipping tolerance and retain
full-quadric enclosures for numerically unresolved configurations.


## Custom polygon cap admission

Lofts use `GemPolygon` for simple counterclockwise outlines of 3..512 unique
vertices. Exact signs for the stored binary32 coordinates decide orientation,
segment contact and ear containment. Self-touching, crossing, overlapping,
clockwise and backtracking outlines fail admission; repeated closing vertices
are not part of this implicitly closed representation. Collinear boundary
vertices remain in the triangulation to match the side-wall topology.

The algorithm follows [ear clipping](https://www.geometrictools.com/Documentation/TriangulationByEarClipping.pdf)
with a blocker matrix that accounts for every remaining vertex, including points
on a candidate diagonal. Only two candidate triangles change when an ear is
removed; other blocker counts lose that removed point. Time and temporary
blocker storage are quadratic, bounded by 512 vertices (262,144 blocker bytes).
A 16-entry LRU retains at most 64 KiB of index payloads, keyed by exact outline
content. Detached return values cannot alter the cache. Keys/container overhead
and temporary construction storage are additional.

Rational-reference tests check positive triangle areas, exact polygon-area
conservation and oriented boundary cancellation. GPU checks compare unsplit and
128-segment collinear boundaries under scalar, Mueller and crystal transport,
and check a concave dielectric furnace. This fixes a translated-square failure
at coordinates around 10,000; it does not certify arbitrarily small features
after float32 loft construction, or arbitrary translated GPU ray precision.
