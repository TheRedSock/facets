# Current documentation

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
- [P0 completed baseline](P0_BASELINE.md): frozen `facets.prototype.v1` decisions,
  source/asset snapshot, controlled fixtures and the ordered P1 handoff.

These documents follow the repository's existing local, gitignored docs policy.
The [review manifest](../artifacts/game-design-review/review-manifest.json)
records document/catalog inventories, source and reviewed-sheet checksums, and
local-link validation. The [diagnostic probe](../artifacts/game-design-review/probe.json)
records reproduced gameplay gaps; it is not a new engine acceptance suite.

Current contracts live beside the code:

- [Agent/project invariants](../AGENTS.md)
- [Factory, jobs, storage and delivery](../core/lapidary/factory/CONTRACT.md)
- [Runtime presentation and desktop packaging](../core/delivery/CONTRACT.md)
- [GPU buffer and transport contract](../core/lapidary/tracer/KERNEL_CONTRACT.md)
- [Tool entry points](../tools/README.md)

`docs/archive/` is gitignored historical evidence, not current instructions. The [archive manifest](archive/2026-09-13/manifest.json) preserves original paths and SHA-256 checksums for superseded documents, including the original audit and implementation report. Preserve archived bytes; update active links when archiving a superseded document. Keep current results here rather than adding new historical snapshots at this directory's top level.

Optical-source provenance is stored with the actual `GemIndexCurve`, `GemChromophore` and `GemOpticalEvidence` inputs under `data/lapidary/`. The older spectra narrative is archived because its implementation assumptions are obsolete; its references remain available there.

The prior game-design revision is preserved with verified checksums in the
[game-design archive manifest](archive/game-design-2026-09-13/manifest.json).
The expanded design is a proposal; no runtime game or authored gem was changed.
