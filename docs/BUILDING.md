# Fresh-machine setup and recovery

Windows is the supported development/package route here. Start from repository
source; no previous `.godot/`, render cache or private design package is required.
“Facets” is the project codename; current filenames keep it for continuity.

## Install tools

| Tool | Requirement / purpose |
|---|---|
| Git | Clone this repository and switch to the branch containing the current plan |
| [Godot 4.6.1 standard Windows x64](https://github.com/godotengine/godot-builds/releases/tag/4.6.1-stable) | Download/extract `Godot_v4.6.1-stable_win64.exe.zip`; use the accompanying console executable for scripts. No .NET, C++ compiler or submodule build is needed |
| [PowerShell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows) | Run the `.ps1` orchestration scripts in `pwsh`; this audit used 7.6.5 |
| [Python 3](https://www.python.org/downloads/) | Documentation and optional analysis checks; the documentation checker requires 3.9+ and this audit used 3.14. No pip packages are needed to build/play the baseline |
| GPU and driver | The project uses Godot's Mobile renderer and the offline renderer uses GPU compute. Use a Vulkan-capable GPU with current drivers and a desktop session; see [Godot requirements](https://docs.godotengine.org/en/4.6/about/system_requirements.html). Compatibility/headless mode does not substitute for the offline GPU bake |

Godot export templates are a separate, pinned download in the packaging step.
Network access is needed for initial tools/templates, not for the standard gem
bake after installation. Leave disk room for intermediate renders and caches;
full optical/reference investigations can consume tens of GB. Runtime shipping
packs are much smaller. Render time and memory depend on selected quality/GPU.

## Clone and initialize

Run in PowerShell 7. Select the branch carrying the work you intend to resume;
the documentation portability changes were made on `codex/physical-gem-engine`.

```powershell
git clone --branch codex/physical-gem-engine https://github.com/TheRedSock/facets.git
Set-Location facets
$Godot = 'C:/Godot/Godot_v4.6.1-stable_win64_console.exe' # your extracted path
& $Godot --version
python --version
./tools/check_engine.ps1 -Godot $Godot -Only @('import', 'source_check', 'test_game_rules', 'check_presentation_content')
```

Expect Godot `4.6.1.stable.official.14d19694e`. The registered runner imports the
project, checks scripts, exercises game rules and validates tracked presentation
content. Read its fresh `artifacts/checks/` report and completion results; an
exit code alone does not establish completion. This is a setup smoke check, not
the full P3/optical/performance acceptance suite. See [tests](../tests/README.md)
and [engine tools](../tools/README.md) for the appropriate task-specific checks.

## Generate the complete default gem library

Run after the initial import. The first command is optional: it prepares the
portable job bundle and reports the plan without rendering.

```powershell
./tools/build_gem_assets.ps1 -Godot $Godot -PlanOnly
./tools/build_gem_assets.ps1 -Godot $Godot
& $Godot --headless --path . --script res://tools/validate_gem_delivery.gd
```

Use the no-selector build for the current default catalog: all 16 authored
stones with `idle`, `turn` and `flash` clips, the default `clip_bake` quality,
studio rig, house print and lossless WebP pages. Single-stone, single-clip and
experimental batch examples in specialist guides do not provide the full
default catalog. Successful delivery validation must print
`CHECK_COMPLETE: validate_gem_delivery` and exit zero with no failures.

The build orchestrator checks completion for prepare, render, pack and cache
collection. The render stage opens a GPU session. Keep the machine available
until it finishes; do not add `--headless` to that stage. Logs are under
`artifacts/build-assets/`; those fixed log names are replaced on a later build,
so copy them to dated evidence when they matter.

| Generated location | Purpose |
|---|---|
| `generated/gem-job-bundle/` and `.zip` | Frozen jobs and portable input bundle |
| `generated/gemfactory/` | Resumable render/master/display cache |
| `generated/gem-library/` | Packed pages and `library.json`, used by delivery validation |
| `generated/gem-assets.pck` | Runtime asset pack mounted by the editor/game |

Rerunning the same recipe can reuse valid cache entries. Start variant studies in
an isolated checkout or explicitly chosen output workflow; the convenience build
replaces the default bundle/library/pack. Existing source and accepted assets are
not candidates to overwrite during setup. Newly baked appearance still needs
visual review; a successful bake is not artistic acceptance or a remeasurement
of historical results.

## Run and package

After the complete bake:

```powershell
& $Godot --path . --editor
```

Use Play Project (F6 runs only the current scene; F5 runs the project), or launch
directly with `& $Godot --path .`. Gameplay mounts
`generated/gem-assets.pck`; there is no synthetic fallback. The Gem Atelier is
the authoring UI. UI SVGs, themes, audio WAVs and compiled vocabulary are already
tracked and imported automatically; do not regenerate them merely to start.

To export the Windows game:

```powershell
./tools/fetch_export_templates.ps1
./tools/build_game_package.ps1 -Godot $Godot -AssetPack generated/gem-assets.pck -Probe
```

The template script downloads the official 4.6.1 archive (about 1.25 GB), verifies
its SHA-256 and extracts pinned Windows binaries into
`artifacts/toolchain/godot-4.6.1/`. For an offline transfer, provide the original
archive with `-Archive 'D:/transfer/export_templates.tpz'`; the same checks apply.
Installing unrelated global editor templates does not satisfy this script.

The package builder creates a fresh output directory (or use `-Output` with a
new/empty directory), stages/imports only runtime source, exports and audits the
exact packs. `-Probe` adds a windowed GPU playback check; without an explicit
`-FrameBudgetMs`, this proves function, not a performance target. Expect
`GAME_PACKAGE_COMPLETE`. Ship the whole output folder, including `Facets.exe`,
`Facets.pck` and adjacent `gem-assets.pck`. Package build reports stay separately
under `artifacts/package-build/`. Release gameplay and artistic quality still
need their own review.

## What travels with Git

| Versioned | Local / ignored | Recovery |
|---|---|---|
| Source, Godot project/export configuration, contracts, tests and fixtures | `.godot/`, imported translations | Initial editor import |
| `docs/`, `plans/`, user anchors and checksum-preserved archives | Raw review/measurement output in `artifacts/` | Read tracked summaries; transfer original evidence separately if needed |
| Authored `data/lapidary/`, delivery catalogs and `data/tiles/` | `generated/` bundles, optical caches, library and PCK | Complete gem build above |
| `art_source/`, accepted `assets/` UI/audio, compiled `data/localization/en.tres` | New experimental media/review candidates | Existing media comes with Git; reproduce new work from its recorded recipe/provenance |
| Build scripts and pinned tool checksums | Godot, export templates, optional Python environments, external capture tools | Install tools / run provisioning scripts |

An audit on 2026-09-24 found about 2.5 MB of documentation/plans previously
ignored, alongside about 25 GB of generated/cache/evidence data. Documentation
is now versioned; the large outputs remain ignored. There is no active native
submodule or Git LFS dependency. `docs/.gdignore` and `plans/.gdignore` prevent
historical script snapshots from entering Godot's resource scan.

For a faster transfer you may copy a known compatible `generated/gem-assets.pck`
to the same path, recording its SHA-256 and source revision. Copy the matching
`generated/gem-library/` too if running delivery validation. A PCK alone supports
play/packaging, but it does not recover authoring caches or the original bake
evidence. Do not copy `.godot/` between machines. Personal Godot `user://` saves
are outside this checkout and are not required for a new run.

Historical videos, screenshots, performance captures and exact tested packages
cannot be recreated as the same evidence by rerunning a build. Transfer those
separately with original reports/hashes when reviewing an old result. A missing
artifact link means unavailable local evidence, not that a historical result was
newly verified. Documentation checks list these separately from broken source
links. Before deleting any old machine's data, retain the evidence you need.

Future phases should commit compact decisions, recipes, provenance and accepted
runtime assets with source. If large accepted assets cannot fit normal Git,
choose a versioned delivery location with checksum and retrieval instructions
before making them a required input. An ignored local candidate must not become
an undocumented prerequisite for the next agent.

## Optional optical/reference tools

These are not baseline game/build dependencies. Independent reference analysis
uses the pinned packages in [reference requirements](../tools/reference-requirements.txt).
Create a separate compatible Python environment and install only when that task
needs it:

```powershell
python -m venv .venv-reference
./.venv-reference/Scripts/python.exe -m pip install -r tools/reference-requirements.txt
```

Pass that executable as `-ReferencePython` to `check_engine.ps1` for registered
reference stages. Package wheel/platform compatibility is an additional setup
requirement; do not change pinned versions merely to force installation. External
PresentMon capture and its permissions are documented in the tools guide and
are not needed for ordinary startup or packaging.

## Resume design work

Read [current state](current/STATE.md), [vision](design/VISION.md) and
[remaining prototype plan](../plans/prototype/README.md). User anchors travel
with Git. The next task is [P4.0 exploration](../plans/prototype/EXPLORATION.md),
not automatic adoption of historical workshop art or the codename as a theme.
Validate documentation with a new report path:

```powershell
python docs/maintenance/check_documentation.py --report artifacts/documentation/setup-check.json
```

For the latest clean-source setup evidence and limitations, see
[the portability verification record](maintenance/PORTABILITY_VERIFICATION.md).
