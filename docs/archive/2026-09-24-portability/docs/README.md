# Facets documentation

Updated 2026-09-24. This is the starting point for current project context.
Read a route, not the entire documentation tree.

## The short orientation

1. [Current state](current/STATE.md): what exists, what was verified, and what remains unknown.
2. [Game vision](design/VISION.md): the intended experience and product boundaries.
3. [Remaining prototype plan](../plans/prototype/README.md): the next work and its decision points.

These three documents are the default onboarding packet. Add specialist context
only when the assigned task needs it. The engine's completed P0–P5 and the
game prototype's P0–P5 are different workstreams.

## Choose a route

| Question or task | Read next |
|---|---|
| What does the current game do? | [Current mechanics](design/MECHANICS.md), then the linked owner contract |
| What should it feel like; what can change? | [Vision](design/VISION.md), [user anchors](design/USER_ANCHORS.md) |
| Where could the game go later? | [Possible routes](design/POSSIBLE_ROUTES.md); optional, outside the prototype queue |
| How should the UI, art, sound and interaction be redesigned? | [Presentation brief](design/PRESENTATION.md), then [exploration task](../plans/prototype/EXPLORATION.md) |
| Which architecture should survive or change? | [Engineering boundaries](engineering/BOUNDARIES.md), then source/contracts for the affected owner |
| How do we make and integrate assets? | [Production guide](production/README.md), then [gem authoring](AUTHORING_WORKFLOW.md) when needed |
| How will remaining work be accepted? | [Prototype acceptance](../plans/prototype/ACCEPTANCE.md), [tests guide](../tests/README.md), [tools guide](../tools/README.md) |
| What was previously measured or decided? | Evidence links in [current state](current/STATE.md); [history index](history/README.md) only for a specific question |

## Authority and maintenance

- Current user instructions and explicitly confirmed decisions govern intent.
  Unanswered anchor fields and agent suggestions are not user decisions.
- Source, owning contracts and regression expectations establish implemented
  behavior. Dated verification establishes results only for its recorded inputs.
  Resolve disagreements explicitly; neither code nor an old plan proves future intent.
- The remaining prototype plan owns sequence and status. Design documents own
  intent; production guides own workflow. Avoid copying their full contents into
  task prompts, journals or root guides.
- Old filename redirects exist for incoming links. They are not additional
  reading requirements. Archived proposals, recipes and completion criteria are
  historical context unless a current task explicitly adopts them.

Keep active guidance concise. Replace superseded text instead of accumulating
amendments above contradictory instructions. Preserve dated reports and frozen
baselines verbatim; put new results in new evidence. Record a consequential
decision beside its owner, with reason, scope and evidence.

`docs/`, `plans/` and review artifacts remain local and gitignored. A fresh
checkout needs this local documentation package for planned work; tracked
contracts/source/tests remain available for implemented behavior. Do not silently
infer missing plans. The reorganization and preservation checks are described in
[documentation maintenance](maintenance/README.md).
