# Lapidary readiness review and implementation plan

Reviewed 13 September 2026 against commit `2dc22c7`. This is a recommendation and implementation plan, not an engine implementation. Production source and authored assets were not changed.

**Recommendation**

Complete a bounded engine-readiness milestone before substantial gem authoring or game integration. The largest immediate gaps are trustworthy authoring, coherent public contracts, image/animation acceptance and exported delivery. The existing transport and factory justify continued use; they do not justify preserving every surrounding tool, schema or consumer.

Do not make completion of all optical research a prerequisite for working on the game. Preserve the scalar, Mueller and uniaxial backends where they have explicit supported cases and numerical gates. Preserve convex and general geometry as complementary active implementations. Replace inadequate authoring and integration paths aggressively. An implementation's age is a reason to investigate it, not sufficient evidence either to retain or delete it.

The proposed readiness milestone comprises P0–P5 below. It establishes the tools needed to decide animations, organize gems, tune materials and design cuts. The final content catalog, aesthetic and animation set should then be developed through a small playable slice. A full collaborative asset-management product is unnecessary.

**Evidence and limits**

Inputs: [original audit](C:/GIT/facets/docs/archive/2026-09-13/lapidary-audit-2026-09-10.md), [implementation journal](C:/GIT/facets/artifacts/ENGINE_PROGRESS.md), and [final report including presentation addendum](C:/GIT/facets/docs/archive/2026-09-13/gemstone-engine-implementation-report-2026-09-11.md). Later journal entries supersede earlier intermediate failures and pending builds. The report's A1–A15 remain the outstanding-audit accounting system.

Inspected current authoring, resource schemas, compilation, policies, clip sampling, planning, delivery, print, diagnostics and check registration. Also inspected two corrected rotation contact sheets and the softened-polish comparison sheet. These saved images support prioritizing actual-size and motion review; they do not establish physical calibration or prove temporal convergence. Several stones become much darker or narrower in side/back views, so a full inspection rotation should not automatically become the game's upgrade animation.

Fresh Godot 4.6.1 checks: 288 scripts parsed with zero reported parse failures; asset planner 23/23, clip CPU checks 26/26, presentation CPU checks 109/109. GPU portions of the clip test were skipped in headless mode. All processes exited 0, but all also printed `ERROR: Failed to read the root certificate store`; these are targeted functional results, not a clean integrated-run claim. No full optical suite, new GPU benchmark or exported game was run for this review. Logs and an isolated CPU probe are in [review evidence](C:/GIT/facets/artifacts/readiness-review-2026-09-13/probe.log).

**Current findings that affect the next stage**

| Priority | Verified finding | Practical consequence |
|---|---|---|
| High | Atelier keeps detached edits only in memory and exports PNGs. It offers volume, size, seed, pose and rig controls, but no resource save workflow, material-mixture editor, cut editor, preset/batch editor or presentation-mode controls. [Source](C:/GIT/facets/scenes/design/gem_atelier.gd:331) | It is an inspection harness, not yet the working tool for maintaining a growing gem catalog. |
| High | Atelier directly compiles/configures the tracer and ignores the boolean result of `configure_stone`; it sets `_configured = true` regardless. Its status names a rung from accumulated sample count despite configuring PREVIEW throughout. [Source](C:/GIT/facets/scenes/design/gem_atelier.gd:260) | Validation failures and actual preview policy can be misrepresented. Adding more controls to this path would amplify the problem. |
| High | Species and chromophores still expose inactive fluorescence controls. The compiler emits an empty fluorescence dictionary. The CPU probe changed fluorescence strength: transport-input identity changed, compiled absorption and fluorescence did not. [Species](C:/GIT/facets/resources/lapidary/gem_species.gd:26), [compiler](C:/GIT/facets/core/lapidary/stone_compiler.gd:42) | Nonfunctional knobs can invalidate expensive work and mislead authors. Removing fake emission did not finish removal of its public contract. |
| High | `ladder_check.gd` and `noise_spp_check.gd` index `strength` in that empty dictionary. The noise tool also interprets compiled absorption using a 5 nm/81-sample convention; the probe confirms current output has 401 samples. [Ladder](C:/GIT/facets/tools/ladder_check.gd:28), [noise](C:/GIT/facets/tools/noise_spp_check.gd:148) | These surviving diagnostics contain invalid accesses and incorrect spectral reporting. Source parsing does not exercise them. Their full GPU execution was not attempted here. |
| High | The cut compiler always constructs a table and a culet; pavilion choices are fan or step. Custom polygon outlines are rejected for faceted jobs. [Compiler](C:/GIT/facets/core/lapidary/cut/cut_compiler.gd:47), [admission](C:/GIT/facets/core/lapidary/factory/job_validator.gd:121) | General transport does not yet provide a general faceted-cut authoring language. Rose/pointed/mixed designs still require compiler changes. |
| High | `raw` print is Reinhard-tonemapped, and negative linear RGB is clipped before display mapping. [Shader](C:/GIT/facets/core/lapidary/tracer/shaders/gem_print.glsl:117) | Final material tuning could compensate for a display-transform issue. Resolve naming and evaluate gamut behavior before locking the palette. |
| High | The batch planner supports independent `asset_id`, but TileView requests `tile_id/clip_id` directly; tile definitions contain no visual binding. [Planner](C:/GIT/facets/core/lapidary/factory/asset_planner.gd:60), [TileView](C:/GIT/facets/scenes/tile/tile_view.gd:105) | Multi-variant production exists, but choosing those variants in the game is not integrated. |
| Medium | `GemClip` advertises `TILT_PRESENT` and `bloom_gain`; the planner rejects both. Its sampling helper silently holds rest pose for non-turntable modes. [Schema](C:/GIT/facets/resources/lapidary/gem_clip.gd:8), [planner](C:/GIT/facets/core/lapidary/factory/asset_planner.gd:94) | Different entry points give different answers about the same authored animation. |
| Medium | `GemClipBaker.bake` is a separate synchronous rendering loop. Repository search found its bake callers in the GPU branch of `test_clips.gd`; production planning and Atelier use its sampling helpers. [Source](C:/GIT/facets/core/lapidary/clips/clip_baker.gd:21) | Tests preserve an alternate bake path instead of proving the factory path. Extract sampling and remove the duplicate executor. |
| Medium | Species still stores `GemInclusionArchetype` records describing the removed primitive system and unused polish metadata. Material scattering can still inherit species via a negative sentinel. [Species](C:/GIT/facets/resources/lapidary/gem_species.gd:19), [material compiler](C:/GIT/facets/core/lapidary/material_compiler.gd:27) | The old vocabulary and implicit material source remain. Inheritance is active behavior, so resolve values into materials before deleting it. |
| Medium | `generate_lapidary_data.gd` writes directly into canonical data paths. [Source](C:/GIT/facets/tools/generate_lapidary_data.gd:652) | A future save workflow needs explicit ownership so regeneration cannot overwrite hand-tuned catalog resources. |
| Medium | No `export_presets.cfg` exists at this checkpoint. Saved delivery evidence is a local PCK/TileView harness. | A clean exported build is still an acceptance gap, not proof that export is broken. |
| Medium | TileView still has tier-color substitution, a duplicate hardcoded palette and a rotation wrapper whose duration/turn arguments are ignored; `perf_monitor.gd` is explicitly deprecated and unregistered. | Replace these at the integration boundary, rather than adapting new content around compatibility behavior. |

**P0 — Remove obsolete contracts and make the supported tool surface executable**

Scope: schemas, generator, compiler packing, diagnostic tools, clip helpers, stale comments, test runner and architecture documentation. This is the first implementation unit.

1. Inventory every documented command and public authoring field. Retain it only if an active consumer and meaningful validation exist. Register maintained tools with required inputs, execution mode and completion evidence. Delete superseded tools instead of maintaining old and new versions.
2. Remove inactive fluorescence fields/packing, the old inclusion-archetype resource and generated records, unused polish metadata, unsupported clip enum/envelope entries and the deprecated performance monitor. Preserve evidence/reasons for unsupported physics in documentation, not inert runtime properties.
3. Materialize currently inherited scattering values in every affected material, fixture and generator, then require explicit nonnegative material scattering. Verify numerical equality before and after migration. Remove the species sentinel branch in the same change.
4. Extract the active clip sampling functions into one sampling module used by preview and planning. Replace the synchronous baker tests with factory-based tests and delete `bake()`. Numerical reference tools may still call the tracer directly for their independently defined experiments; they must not become alternate asset producers.
5. Replace stale ladder/noise tooling with maintained planner-based inspection and measurement commands, or repair a tool only when it fills a distinct gap. Centralize spectral-grid access. Remove old ad hoc production policies and misleading trace-only performance claims.
6. Require positive completion evidence in the check runner, not just exit status and absence of error text. Treat timeout/incomplete stages as failures. Report environmental startup errors separately without broadly suppressing `ERROR:`. Consolidate AGENTS and current contracts; eliminate contradictory appended descriptions of removed paths.
7. Keep current documentation in `docs/` and move superseded Markdown into the explicitly gitignored `docs/archive/`. Preserve a manifest with original paths, destination paths, checksums and reasons. Repair links from current documents/source, and maintain a current documentation index. Historical audits and reports remain available as evidence but are never presented as current contracts.

Exit: no references to deleted public fields/classes; affected numerical material inputs unchanged; documented tools execute representative workloads; current tests exercise production entry points. Old schemas are migrated once and rejected afterward. No compatibility loader remains. Regenerate affected ignored jobs as needed; retain old output only as clearly historical evidence.

**P1 — Unify validation, identity and durable authoring contracts**

Depends on P0. Complete before building substantial new UI.

Use the existing GemStone, recipe, request and job model. Consolidate shared admission and diagnostics so preview, CLI and factory accept the same specimen and policy. This does not require a new renderer-independent interchange system or wholesale typed-IR rewrite.

Provide machine-readable capabilities from the same admission rules: supported/approximate/unsupported combinations, required device features and reasons. Track appearance acceptance separately and key it to the actual specimen, renderer/policy, print and evidence. A numerically supported rough surface is not automatically an accepted wear preset. Avoid creating an independent second list of validation rules.

Define one authoring workflow: open or create resource → detached edit → validate → compare changes → save/reload → freeze binary specimen/request → preview or build. Add undo/redo, dirty-state handling, Save As and explicit replace. Derived changes to measured inputs must retain parent provenance and become authored inputs, consistently with specimen realization. Editing a label or evidence note must not retrace identical optical inputs; an optical value edit must invalidate the appropriate stage. Test both directions.

Split data generation by ownership. Published-source imports and reproducible source datasets must remain reproducible. Hand-authored material, stone, cut, preset and batch resources must not be overwritten by a general regeneration command. Have generators emit a candidate result and explicit diff, or exclusively own designated source-data outputs. Keep exact binary frozen jobs; test authored save/reload behavior so the displayed preview corresponds to the saved values.

Exit: a new specimen can be saved, reopened and built through the public workflow; shared external resources remain untouched; unsupported combinations produce actionable diagnostics; renames do not cause optical work; physical edits do. A failed configuration never displays an old image as the new result.

**P2 — Replace the constrained cut program before extensive cut design**

Depends on P0/P1. This is the largest geometry-related recommendation for readiness, closing a bounded part of A5.

Introduce a single declarative facet program with named facet groups, explicit index/azimuth sets, plane angle and offset/meet constraints, independent upper/lower termination and an authored girdle boundary. Make existing brilliant and step templates data expressed through this program. Support a practical initial set of constraints with explicit rejection of unsupported programs; do not begin with a general CAD solver.

Compile admitted convex programs to the current efficient half-space representation. Route supported closed nonconvex construction to the existing mesh/analytic infrastructure. General rendering capability alone is not permission to accept a faceted program whose topology the authoring compiler cannot construct. Stable group/facet identifiers must survive pruning where features survive, with diagnostics for vanished/ambiguous meets. Keep workmanship separate from nominal design and material.

Required demonstrations: current catalog cuts; a table-free pointed crown/flat-bottom design; a design with independent pavilion indices; a mixed row program; and one admitted custom convex girdle. Add shape-specific examples only as data. Provide facet/meet overlay, dimensions and section inspection for debugging authoring.

Migrate the catalog and remove the old table/culet/fan/step compiler branches after equivalence checks. Preserve expected existing geometry where migration intends equivalence; compare selected renders and all catalog admissions. Do not silently keep two grammars.

Exit: those examples require no compiler edits; invalid meets/topology fail clearly; stable IDs and deterministic manufacture pass; supported transport backends agree on the new geometry within existing tolerances. Arbitrary carved geometry and certified cut grading remain outside this milestone.

**P3 — Establish color, temporal and feature-preservation acceptance**

Depends on P1; use P2 examples when available. Complete before locking catalog colors or batch quality settings. Addresses the immediate parts of A9/A12 and prepares A8.

Give diagnostic views truthful names: linear XYZ data, exposure-adjusted display preview and house print. Evaluate saturated spectral inputs before clipping negative RGB and choose a documented gamut-mapping policy using hue/chroma behavior and neutral/alpha checks. Update both GPU and offline print implementations and their identities together. Reprint retained masters; do not retrace unless optical inputs changed.

Create a small acceptance corpus using existing supported mechanisms: clear faceted, strongly absorbing, rounded, rough, localized volume, resolved inclusion and thin boundary examples. Inspect stills and short motions at 112, 256 and 512 pixels under at least two controlled rigs and black/white/game backgrounds. Include fixed-pose independent streams and high-sample references for moving cases. Freeze specimen seeds while changing sample streams.

Measure spatial error, mean bias, temporal residual error against the corresponding reference motion, loop seams, feature visibility and total cost. Use geometry correspondence only where it applies; first-surface motion is not internal refracted-feature correspondence. Whole-image temporal smoothness must not reward blurring real flashes or removing thin inclusions. Use feature masks/crops and unfiltered references.

Select production quality from these measurements. Initially prefer explicit tested profiles to a universal adaptive controller. Add automatic sampling/reconstruction decisions only when their error estimator is validated. Record any failing specimen rather than silently coarsening it. Derive numerical thresholds from accepted reference comparisons before claiming a universal visual limit.

Exit: a reproducible pass/fail report for the corpus, including temporally changing signals and retained thin features; honest view names; accepted display mapping; a measured cost table for the chosen quality profiles. Existing still-noise numbers alone do not satisfy this gate.

**P4 — Replace the Atelier execution loop and expose the minimum complete workflow**

Depends on P1, with P2/P3 controls added as those contracts settle. Addresses practical A13 and enables actual tuning.

Make Atelier a client of the same admitted jobs, sampling and presentation used by the factory. Use one rendering owner with detached immutable requests. Keep scene-tree/UI mutation on the UI thread; worker-process isolation is a reasonable first implementation using the existing portable machinery. Benchmark the chosen execution design before committing to threads, IPC or GPU-resident presentation. Godot documents synchronization stalls and thread restrictions in its [thread-safety guide](https://docs.godotengine.org/en/4.6/tutorials/performance/thread_safe_apis.html).

Add cancellation between bounded work units, latest-request-wins behavior, stale-result rejection, progress and explicit error states. A canceled preview must not discard valid resumable work or publish as a completed new request. Measure cold initialization, changed material/geometry/pose and print-only latency separately. Query device limits and account for allocated buffers/pages, using [RenderingDevice limits and timestamp APIs](https://docs.godotengine.org/en/4.6/classes/class_renderingdevice.html) where appropriate. A batch's wall time is not automatically GPU execution time.

Expose material/absorber amounts and units, physical size with the radius convention made explicit, condition/preset selection, cut program, crystal frame, rig, print/style, presentation and clips. Add save/reopen, comparison at shipping size, batch dry-run estimates and build selection. Show only controls backed by a supported implementation. Start with resource-oriented panels and previews; defer elaborate sculpting or node editors.

For clips, provide the minimum generic orientation keyframes/time curves needed for a small tilt/return and a presentation turn, plus existing rig/power/exposure tracks. Implement every exposed track through the shared sampler or omit it. Specify loop endpoints, return-to-rest, timing and interruption behavior. A pose must not be recentered independently every frame. Keep board translations, swaps, squash, convergence and removal choreography in the game renderer, outside optical baking.

Exit: rapid edits do not block input for the duration of a render or show stale output as current; cancel/close leaves consistent worker state; saved preview and built output agree at the same request/policy; an author can create and build one new gem and cut without editing engine code. Report latency percentiles and agree the interactive budget before declaring responsiveness accepted.

**P5 — Complete the asset/game boundary and prove a clean export**

Depends on P1/P3; finalize after P4. This is an engine-delivery bridge, not implementation of gameplay progression or the final animation catalog.

Introduce one explicit presentation catalog mapping logical game tile IDs to delivered asset IDs and semantic clip roles. Keep this outside board simulation and outside physical GemStone identity. Do not encode family/tier/preset/lighting selection by parsing asset names. Require build-time validation that every required tile/role resolves. Runtime selection reads that binding, with any visual variation chosen independently of simulation state mutation and reproducibly when required for replay presentation.

Replace TileView's ignored rotation arguments with explicit playback semantics: completion/interruption, restart and return-to-rest. Remove production tier-color substitution and the duplicate palette; incomplete required libraries fail preflight with an actionable loading error. If a debug board needs synthetic tiles, use explicit test/debug fixtures instead of a hidden alternate production visual path. Update the documented old fallback contract in AGENTS in this change; the user's current no-fallback direction supersedes it.

Add a tracked export preset and reproducible package build. Verify the actual executable in a clean directory containing only intended shipped files, without the source tree, `.godot`, master cache or build tools. Verify install paths with spaces/non-ASCII characters, required asset completeness, corrupt/missing pack rejection and reload behavior. Inspect the main game package as well as the gem PCK so optical tooling is not unintentionally shipped through resource dependencies.

Measure startup, cold page loads during a burst of animations, steady frame-time percentiles and simultaneous active texture references. Cache-owned bytes alone are insufficient. Prefetch the declared upcoming asset/clip set and show its readiness before the relevant presentation begins; do not add runtime baking. Keep selective loading and bounded page ownership.

Exit: the clean exported application displays and animates the declared test catalog; all required assets resolve; corruption fails clearly; frame-time and working-set results meet the selected desktop budget. Real Linux/cloud/network-store deployment is a separate required gate only when that production environment is chosen. Portable Windows bundles are not evidence for that environment.

**Work that should stay outside the readiness milestone**

| Audit group | Recommendation and trigger |
|---|---|
| A1 connected/healed fractures | Highest-priority later physical condition slice if visibly fractured gems are wanted. Rebuild the rejected morphology against multi-view references; reuse validated medium transport. Do not enable the current failed appearance through a preset. If no active experiment or consumer remains, remove abandoned implementation and retain its history in Git. |
| A2 directional silk/unresolved handoff | Pursue when an actual target gem needs the directional effect. Requires a matched resolved/effective response and no double counting. Existing HG clouds cannot be relabeled silk. |
| A3 resolved scratches/films | Implement only the selected feature and scale needed for an accepted asset. Statistical polish and rounded/chipped geometry are already enough to test initial condition differentiation. |
| A4 process/species priors | Expand a small set of named recipes across selected species during content work. Do not add a universal cleanliness/rarity/tier law. |
| A6 full cut optimization | Retain honest existing proxy metrics. Add meet/dimension feasibility with P2; develop fire, leakage, yield and perceptually calibrated scintillation only as a separate objective study. |
| A7 internal contribution passes | A valuable next engine addition if art direction needs physically located internal-cue emphasis. Design a partition of linear contributions that sums back to beauty, with explicit overlap semantics for defect tags, resume/reconstruction/cache identity and reference tests. Do not fabricate these masks from primary geometry or store every conceivable AOV by default. |
| A8 final style/readability | Requires actual game size, background, motion and aesthetic decisions. Run controlled recognition comparisons during the playable slice; it cannot be completed credibly as an engine-only task. |
| A9 broader physical calibration | P3 covers print correctness and diagnostic clarity. Measured multi-species condition distributions and matched real specimens remain independent evidence-gathering work. |
| A10 broader anisotropy | Keep current capability boundaries explicit. Extend only for selected material cases; increasing the REFERENCE rung does not select an exact backend or add missing physics. |
| A11 fluorescence/structural color | Retain unsupported status, remove inactive knobs, and add a complete validated mechanism only when needed. No automatic revival of the former emission code. |
| A12 adaptive controller / motion-aware reconstruction | P3 supplies temporal acceptance first. More sophisticated optimization follows demonstrated error/cost need. |
| A13 live GPU game rendering | Responsive authoring is in P4. GPU-resident live gameplay is optional; offline delivery remains the intended game path. |
| A14 farm deployment | P5 covers the desktop export. A chosen remote platform requires its own deployment, throughput, device and interrupted-work tests. |
| A15 documentation/capabilities | Address through P0/P1 and update alongside every subsequent phase. |

**Repository discipline during implementation**

Each phase must include its replacement, caller/data migration, removal list, contract updates and relevant checks. Remove superseded tests that only preserve removed behavior; retain independent references that constrain the active implementation. Do not keep adapters, schema aliases, empty feature dictionaries, silently ignored arguments or speculative public fields for hypothetical compatibility.

Keep complementary algorithms where measured correctness/cost warrants them: convex/general transport and filtered/exact predicates are active engineering choices, not legacy just because they have alternative paths. Experimental code remains only with explicit current consumers, maintained gates and accurate status. Historical reports and rejected prototypes belong in Git history or ignored evidence, not in a production fallback chain.

After transport/packing changes, run the appropriate numerical/GPU/reference gates and update identities/contracts. After authoring-only work, run relevant admission, dependency, serialization, planner and preview/factory parity checks. At final readiness, run the integrated suite and clean export; report completion markers, skips and environmental failures explicitly. Rebuild the full default delivery at that acceptance point rather than after every source-only intermediate change.

**Stopping point and first game slice**

Start substantial game work when one saved/tuned specimen, one new declarative cut, one named condition variant and one authored motion can pass the same preview → frozen job → factory → accepted images → clean exported consumer workflow, with no hand-repair or legacy substitution. That is a concrete foundation milestone; universal mineral realism is not its completion criterion.

Then build a small playable slice using a few visually different gems. Decide actual rest poses, select/upgrade motion, readability, tier/family bindings and simultaneous-animation budgets there. Use ordinary board animation for movement and merges; bake additional optical motion only where it adds a visible benefit. Expand the gem catalog and mechanisms from that evidence. Do not design hundreds of variants or commission large clip batches before this loop is usable.

Suggested commit boundaries follow P0–P5, splitting P2 and P4 into smaller independently verifiable changes as necessary. P0 and P1 should be implemented first. P2 and the test-corpus portion of P3 can proceed independently afterward. P4 consumes their settled contracts; P5 closes delivery acceptance. Calendar estimates would be speculative before the cut-grammar and scheduling prototypes; use their measured scope to estimate the remaining work.
