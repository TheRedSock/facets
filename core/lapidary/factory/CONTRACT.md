# Asset factory and delivery contract

The game is a consumer of a prebuilt library. Optical tracing belongs to authoring
and offline jobs. A specimen, requested animation, rig and quality profile expand
into explicit frame jobs; there is no implicit rotation×cell×lighting lattice.
Equivalent poses reuse one optical master, and exposure/output-size changes reprint
that master. Artist style belongs after linear optical output.

`GemFrameJob` contains all authored inputs and render policy. `GemFramePlan` hashes
physical resources, optical source, packed lighting, canonical pose, framing,
resolution, sample seed/count and estimator policy. Display identity also hashes
print, exposure, output dimensions and spectral neutral. Scheduling batch size and
worker hardware are not optical identity. Hardware/driver provenance is recorded.
Catalog names and grade labels are also excluded from optical identity; editing
them retains expensive masters. `GemStone.fingerprint()` still tracks the complete
authored record. Physical input changes retire masters through `transport_inputs()`.
Pose quantization is explicit and the renderer uses the same canonical pose.

`GemArtifactStore` has a store.json marker, atomic recipe JSON and SHA256-addressed
immutable blobs. Linear masters are associated CIE XYZ+coverage RGBAF compressed
losslessly with ZSTD. Checkpoints contain raw estimator buffers and global sample
count; prints are lossless WebP. A worker resumes missing samples or reprints from
an available master. Stored masters include the requested reconstruction; raw
REFERENCE jobs remain available for evaluation. Payload checksums are verified.

`GemJobBundle` creates a minimal independent Godot project and ZIP, with bundled
binary resources, raw shaders, standard tables and source/job checksums. Rendering
requires windowed Vulkan/RenderingDevice, including on a farm. Shards group jobs by
master, so exposure variants stay together. Farm workers should use isolated output
stores per attempt; shared stores permit independent jobs but do not deduplicate
simultaneous executions of the same job. Completed stores can be merged through
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
mid-operation may leave a token: inspect `.active/` or `.maintenance/owner.json`,
confirm its worker is stopped, then remove that token before collection. No timer
steals a slow worker's ownership. This protocol assumes normal local filesystem
atomic creation/rename semantics; distributed object storage needs a coordinator.

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
are excluded. The optical source digest and geometry plan/worker source hashes are
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
