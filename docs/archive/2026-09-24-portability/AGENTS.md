# Working in Facets

This file is a routing guide. Read the relevant source, contracts and current
plan before changing a subsystem; detailed behavior belongs beside its owner.

## Collaboration

Assess requests independently. Treat the user's proposals as directional input,
check whether they fit the project, and explain a better approach when warranted.
Prefer a short back-and-forth on consequential choices over blindly implementing
a suggestion or silently substituting your own plan. Surface tradeoffs and ask
focused questions before committing to a direction when intent or consequences
are uncertain.

## Find the relevant context

Start with [README.md](README.md) for the project and [the documentation index](docs/README.md)
for current work. Follow the route for the task; the entire archive is not required reading.

| Task | Start here |
|---|---|
| Project status, game direction or phase work | [Current state](docs/current/STATE.md), [vision](docs/design/VISION.md), [remaining prototype plan](plans/prototype/README.md) |
| Gameplay architecture or repository organization | [Engineering boundaries](docs/engineering/BOUNDARIES.md), then the linked owner contracts/source and relevant tests |
| Mechanics, triggers, families or tuning | [Current mechanics](docs/design/MECHANICS.md), then `core/run/P3_PREPARATION.md`, `core/run/MERGE_WINDOW_PREPARATION.md` and relevant content/source |
| UI, terminology, non-gem art, sound or effects | [Presentation brief](docs/design/PRESENTATION.md), [user anchors](docs/design/USER_ANCHORS.md), then the current prototype task and affected scenes |
| Gem authoring, cuts, clips or rendering | [Authoring workflow](docs/AUTHORING_WORKFLOW.md); the relevant contract in [core/lapidary](core/lapidary/) |
| Asset integration, loading or packaging | [Production guide](docs/production/README.md), [delivery contract](core/delivery/CONTRACT.md) and [tools guide](tools/README.md) |
| Validation or an existing command | [Tests guide](tests/README.md), [tools guide](tools/README.md) and the relevant registered check |
| Optional future content concepts | [Possible routes](docs/design/POSSIBLE_ROUTES.md); these are not the active prototype queue |

`docs/`, `plans/` and generated review artifacts are local and gitignored. They may
be absent in a fresh checkout. Use tracked contracts/source/tests for existing
behavior; request missing design context before inferring a planned feature.
Archived proposals are historical input, not current requirements.

## Durable engineering principles

- Keep simulation, presentation and offline gem production separate. Game rules
  must not depend on animation timing, scene callbacks, translated labels or
  rendered appearance. Names and art should be replaceable without changing rules.
- Preserve deterministic rule execution: controlled integer randomness, explicit
  ordering, board-owned topology queries and complete state identity. Revisit save,
  replay and serialization whenever rule-relevant state or ordering changes.
- Use stable semantic IDs. Version behavior, content and replay protocols when
  compatibility changes; distinguish cosmetic edits from mechanical changes.
- Keep authored inputs separate from generated candidates. Preserve provenance;
  a label, successful render or old report does not establish a physical capability
  or current acceptance. Verify material claims against supporting evidence.
- Keep proposed behavior, implemented behavior and measured results distinct.
  Resolve disagreements between docs and code explicitly instead of silently
  treating either as proof of intent.

## Tests and documentation

Run checks relevant to the change and state what they establish. Respect registered
completion criteria; an exit code alone may not prove a check finished. Separate
environmental failures, previous evidence and newly verified results.

Update the owning contract/guide and regression expectations with behavior changes.
Keep root guides focused on navigation and lasting principles, not API signatures,
tuning values or copied implementation inventories. Update the current plan when
a milestone changes; preserve frozen baselines and archive superseded local docs
with verified checksums. Do not revise historical expectations merely to fit new code.
