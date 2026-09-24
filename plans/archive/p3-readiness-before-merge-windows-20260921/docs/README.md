# Current documentation

**Current phase work, 2026-09-21:** P2 engineering checks and the isolated trial are complete, with one optional review build/form delivered. Follow [the closeout journal](../plans/P2_CLOSEOUT_JOURNAL.md) for results and [P3 preparation](../plans/P3_IMPLEMENTATION_PLAN.md) for the specified next phase. P3 activation awaits the explicit CPU disposition; the 5 ms target still fails. The user is the sole reviewer, with broader human testing deferred, potentially until after P5. The design package below mixes intended later systems with dated reviews; source contracts and current handoffs distinguish what exists.

The [engine readiness report](ENGINE_READINESS_REPORT.md) records P0–P5 implementation,
validation evidence, supported limits and the next content workflow. The completed
working plan and journal are preserved in the ignored archive.

Use the [gem authoring workflow](AUTHORING_WORKFLOW.md) for creating/tuning
specimens, cuts and clips, then building and binding delivered assets.

## Proposed game direction

The following design package (reviewed 2026-09-13, expanded 2026-09-14) evaluates the current implementation and
the six historical concepts under `plans/archive/`. It proposes future gameplay;
it does not change the accepted engine milestone or claim those systems exist.

- [Game design](GAME_DESIGN.md): collection drafting, family builds, tactical
  objectives, merge rules, tools, persistence and the initial expedition.
- [Content systems and expansion](CONTENT_SYSTEMS.md): appraisal/grade, lifecycle
  reactions, families, cut variants, readability, room themes and special pieces.
- [Gameplay rewrite review](GAMEPLAY_REWRITE_REVIEW.md): verified source findings,
  what to preserve/repair/replace, and validation limits.
- [Engine integration](GAME_ENGINE_INTEGRATION.md): authoring/delivery ownership,
  content identity, clips, budgets, loading and clean packaging.
- [Gem art review](GEM_ART_REVIEW.md): all 16 game stones, diagnostic content,
  silhouette/color/style recommendations and recognition acceptance.
- [Prototype build plan](PROTOTYPE_BUILD_PLAN.md): dependencies, playable
  milestones, exit criteria and the first implementation batch.
- [Architecture hardening](ARCHITECTURE_HARDENING.md): pivot costs, workspace
  boundaries, exact replay, topology, efficiency and future map-editor seams.
- [Non-gem presentation production](PRESENTATION_ASSETS.md): specified UI/icon,
  background, audio/VFX assets, generation methods and phase acceptance.
- [P0 completed baseline](P0_BASELINE.md): frozen `facets.prototype.v1` decisions,
  source/asset snapshot, controlled fixtures and the ordered P1 handoff.
- [Fluidity and reactive play](FLUIDITY_AND_REACTIVE_PLAY.md): verified P1 motion
  regression, CPU diagnostic, concurrent presentation and optional intervention
  design. The [P1-A amendment](../plans/P1_FLUIDITY_AMENDMENT.md) specifies the
  proposed repair batches and reopened acceptance gates.
  The [P1-A handoff](../plans/P1A_HANDOFF.md) now records implemented concurrent
  motion, release recordings/checks and the remaining CPU acceptance gap.
- [P1 implementation handoff](../plans/P1_HANDOFF.md): completed functional
  baseline and original measurements; this does not establish fluidity acceptance.
- [P2 implementation plan](../plans/P2_IMPLEMENTATION_PLAN.md): source-grounded
  batches for the rubble room, Craft/tools, recovery, protocol migration,
  functional presentation and acceptance; includes the required trial handoff.
- [P2 implementation handoff](../plans/P2_HANDOFF.md): playable room, accepted audio, checkpoint commits, release evidence and remaining player/trial gates.
- [P2 finalization and P3 preparation](../plans/P2_FINALIZATION_AND_P3_PREPARATION.md):
  current closeout execution order, Step 0 evidence/reconciliation audit, correction
  and acceptance gates, required trial, and concrete P3 contract/batch preparation.
  This is a plan, not a new phase-completion or gameplay-test claim.
- [Post-P2 intervention trial](../plans/P2_INTERVENTION_TRIAL.md): required paused
  and timed experiment, replay/accounting checks and an explicit adoption decision.

These documents follow the repository's existing local, gitignored docs policy.
The [review manifest](../artifacts/game-design-review/review-manifest.json)
records document/catalog inventories, source and reviewed-sheet checksums, and
local-link validation. The [diagnostic probe](../artifacts/game-design-review/probe.json)
records reproduced gameplay gaps; it is not a new engine acceptance suite.

The [agent routing guide](../AGENTS.md) covers collaboration, navigation and
durable engineering principles. Detailed contracts live beside the code:

- [Factory, jobs, storage and delivery](../core/lapidary/factory/CONTRACT.md)
- [Runtime presentation and desktop packaging](../core/delivery/CONTRACT.md)
- [GPU buffer and transport contract](../core/lapidary/tracer/KERNEL_CONTRACT.md)
- [Tool entry points](../tools/README.md)

`docs/archive/` is gitignored historical evidence, not current instructions. The [archive manifest](archive/2026-09-13/manifest.json) preserves original paths and SHA-256 checksums for superseded documents, including the original audit and implementation report. Preserve archived bytes; update active links when archiving a superseded document. Keep current results here rather than adding new historical snapshots at this directory's top level.

Optical-source provenance is stored with the actual `GemIndexCurve`, `GemChromophore` and `GemOpticalEvidence` inputs under `data/lapidary/`. The older spectra narrative is archived because its implementation assumptions are obsolete; its references remain available there.

The prior game-design revision is preserved with verified checksums in the
[game-design archive manifest](archive/game-design-2026-09-13/manifest.json).
The expanded design remains a proposal beyond the implemented P1 subset. P1's
functional foundation and P1-A concurrent playback are verified. The CPU target
and player feel acceptance remain open. The optical engine milestones above are
a separate workstream. The original fluidity review changed documentation only;
P1-A subsequently changed runtime playback and implementation efficiency without
changing canonical rules. Superseded active documents are preserved in the
[fluidity review archive](archive/fluidity-review-2026-09-14/manifest.json).
