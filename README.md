# Facets

Facets is a gemstone match-3 merge roguelike in development, built with Godot and
GDScript. The intended game combines an evolving collection of real gems with tactical
board objectives and branching runs.

## What is here

The repository contains an offline gem-authoring/rendering pipeline, runtime
asset delivery, and playable P2 rooms with rubble, Work, Craft and tools.
The [merge-window successor](core/run/MERGE_WINDOW_PREPARATION.md) adds repeated
interventions and incremental resolution. Its [P3 readiness checks](tests/game/MERGE_FINAL_READINESS.md)
pass on the declared current-machine profile, with one verified build and optional
review form delivered. Atomic P2 and the earlier
isolated comparison remain controls; their whole-action CPU target remains open.
Family reactions, rewards, carryover and
expedition persistence are specified in the [P3 preparation contract](core/run/P3_PREPARATION.md).
Player learning, difficulty and feel remain unmeasured; the user is the sole
reviewer during this stage, with broader testing deferred.

The [documentation index](docs/README.md) routes the current design and engine
reports. The [prototype build plan](docs/PROTOTYPE_BUILD_PLAN.md) records phase
status, dependencies and acceptance criteria. Its [P0 baseline](docs/P0_BASELINE.md)
preserves the initial rules and review evidence.

## Run and develop

Open `project.godot` in Godot 4.6. The project menu provides the tactical room and Gem
Atelier. Tool scripts specify their tested Godot executable and export-template
requirements; check them when configuring another workstation.

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

For upcoming architecture and workspace changes, see the
[architecture guide](docs/ARCHITECTURE_HARDENING.md). The
[presentation specification](docs/PRESENTATION_ASSETS.md) defines UI, background,
audio and effects production. [AGENTS.md](AGENTS.md) is the agent routing and
collaboration guide.

`docs/`, `plans/`, `generated/` and review artifacts follow the repository's local,
gitignored workflow and may not exist in a fresh clone. Tracked subsystem contracts,
source and tests remain available; obtain the local design package when working
on the proposed prototype. Archived documents are historical references.
