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
simultaneous executions of the same job. Linux farm deployment and a result-store
merge service are not yet validated. Do not confuse a prepared ZIP with that work.

## Retention and concurrency

`GemJobValidator.validate` is CPU-only admission shared by workers and portable
bundle creation. It checks finite physical inputs, supported optical modes,
spectral normalization, camera transforms, procedural topology, known quality
keys and film/payload bounds before GPU setup. Explicit polarization currently
requires isotropic refraction and absorption in the host and every enabled
filling. Invalid jobs return a field-specific error instead of silently selecting
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
