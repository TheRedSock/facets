# Facets

Facets is the working codename for a gemstone match-3 merge roguelike, built with Godot and
GDScript. The intended game combines an evolving collection of real gems with tactical
board objectives and branching runs. The codename does not constrain the game's
story, aesthetic or final title; those should follow the chosen experience.

## What is here

The repository contains an offline gem-authoring/rendering pipeline, runtime
asset delivery, and a playable P3 expedition with families, four authored rooms,
rewards, carryover and disk Continue under the [P3 contract](core/run/P3_PREPARATION.md).
The [merge-window successor](core/run/MERGE_WINDOW_PREPARATION.md) provides repeated
paid interventions and incremental resolution. [P3 engineering verification](tests/game/P3_FINAL_VERIFICATION.md)
passes on the declared current-machine profile and links the tested build and
optional review form. [Implementation checkpoints](tests/game/P3_IMPLEMENTATION_STATUS.md)
map requirements to behavioral coverage. Atomic P2 and the earlier isolated
comparison remain controls; their whole-action CPU target remains open.
Player learning, difficulty and feel remain unmeasured; the user is the sole
reviewer during this stage, with broader testing deferred.

Start with the [documentation index](docs/README.md), then
[current state](docs/current/STATE.md), [game vision](docs/design/VISION.md) and
[remaining prototype plan](plans/prototype/README.md). The next planned work is
to explore and prove the presentation direction before full production. Historical
plans and frozen evidence are reached through the [history index](docs/history/README.md).

## Run and develop

Start with the [fresh-machine build guide](docs/BUILDING.md) for pinned tools,
source-only setup, the complete gem bake and Windows packaging. The tested editor
is Godot 4.6.1 standard (GDScript). The project menu provides the tactical room and
Gem Atelier; gameplay requires the generated gem pack before launch.

Gameplay uses prebuilt gem assets. Follow the [tools guide](tools/README.md) for
asset generation, delivery validation and desktop packaging, and the
[authoring workflow](docs/AUTHORING_WORKFLOW.md) for editing specimens. Rendering
and GPU checks need a windowed GPU environment; headless checks cover their
explicit CPU/data scope.

Use the [tests guide](tests/README.md) for simulation tests and registered engine
checks. Existing test success does not establish the proposed game's balance,
readability or completeness.

## Navigate the project

| Area | Purpose |
|---|---|
| `core/board/`, `core/run/`, `core/rules/` | Board simulation and run/rule orchestration |
| `core/lapidary/` | Offline gem pipeline; detailed contracts live with each subsystem |
| `core/delivery/` | Runtime asset loading and presentation contract |
| `resources/`, `data/` | Schemas, authored content and presentation mappings |
| `scenes/` | Gameplay views, application UI and authoring tools |
| `tools/`, `tests/` | Build, validation and test entry points |

Use [engineering boundaries](docs/engineering/BOUNDARIES.md) for subsystem
ownership, [the presentation brief](docs/design/PRESENTATION.md) for design work,
and [production guidance](docs/production/README.md) for assets and integration.
[AGENTS.md](AGENTS.md) is the agent routing and collaboration guide.

Design documentation, user anchors, plans, authored inputs and accepted runtime
UI/audio assets are versioned. Generated gem packs, caches, tool binaries and raw
review artifacts stay ignored. The [build guide](docs/BUILDING.md#what-travels-with-git)
explains what to regenerate or transfer. Archived documents are historical references.
