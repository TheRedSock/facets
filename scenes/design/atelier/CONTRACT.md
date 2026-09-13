# Atelier client and render owner

The Atelier edits one detached `GemAssetRequest` through `GemAuthoringDocument`. Resource controls do not mutate the catalog or shared loaded resources. Open/Save/Save As, explicit replacement, undo/redo and comparison use the same document workflow as CLI authoring. Creating from the current document starts an untitled asset. Physical validity is reported by the production planner/admission rules; invalid drafts remain editable and clear the old preview immediately.

`GemPreviewClient` owns a unique ignored session directory under `generated/atelier/sessions/`. The scene thread freezes binary request bundles and sends an atomic JSON message with its SHA-256 and a strictly increasing generation. Cancellation and the following submitted request have distinct generations: the worker may observe cancellation while a bundle is being saved. The client accepts a response only for its current generation and verifies the image filename and checksum before displaying it.

`tools/atelier_render_worker.gd` is the sole GPU owner for the session. It calls `GemAssetPlanner`, `GemJobValidator`, `GemFrameWorker` and `GemPagePacker`; it is not another baker. The selected preview is an actual planned frame. House print follows the saved request; display preview is an explicit diagnostic view. A build packs the saved request's house/style result and returns both the library path and selected frame. Inspect and estimate actions use the same admitted request without optical sampling.

Cancellation is cooperative between sample units. Partial work is a resumable estimator checkpoint, never a completed display. Close sends stop; a lost parent heartbeat also ends the worker after the current unit. The worker releases its tracer before its positive shutdown marker. Generation checks prevent late results from replacing a newer edit. GPU failures remain errors; no synthetic image substitutes for failed optics.

The worker collects older consumed `request-<generation>.res` bundles and retains
only the two newest `preview-<generation>-<sequence>.png` files. Future queued
requests remain untouched. The client reads and hashes one immutable byte buffer;
if collection overtakes a read, it retries the latest response. Session logs,
completed delivery directories and the resumable optical store are retained.

The inspector exposes stored, active resource fields and named enum values. Curves use explicit normalized-time/value/incoming-slope/outgoing-slope entries. Orientations are edited as Euler degrees and stored as unit quaternions. Named effect curves can be created and removed from their typed dictionary. Generic orientation keys and time curves use the shared clip sampler; see `core/lapidary/clips/CONTRACT.md`. Facet inspection shows the manufactured declarative hull before rounding/cleavage, with stable IDs, meets, dimensions and top/front sections. Native-size output is shown separately from the enlarged preview.

Device reports identify allocator buffer/texture ownership, relevant limits and timestamp availability. Plan/unit/elapsed times are wall-clock values. Driver internal memory is not VRAM capacity. Responsiveness and final clip controls are still under P4 acceptance; no interactive frame budget has yet been certified.

The selected desktop budget is at most 100 ms from an edit through request
submission to the next UI draw. `atelier_latency_check.gd` measures that path
and separately reports cold initialization and first-image/completion latency
for material, geometry, pose and print changes. Print changes must reuse the
optical master. Run this gate with no concurrent optical worker before accepting
its measurements; its presence alone is not responsiveness acceptance.

Atelier frame telemetry uses successive monotonic microsecond timestamps, not
Godot's potentially smoothed/clamped delta. Sampling a contended GPU session is
diagnostic evidence, not an uncontended responsiveness result.

Validation: `test_atelier_document_ui` exercises actual headless controls, nullable resources, typed arrays, named curves, durable save/reload, source isolation and the cancel-before-submit protocol. Windowed `atelier_admission_check` exercises a new saved gem/cut, invalidation/recovery, stale response rejection, cancellation after real partial sampling, checkpoint recovery, preview/build identity and close during active work. These functional checks are not a substitute for the uncontended latency benchmark.
