# Facets

Godot 4.6 gemstone match-3 merge roguelike. Desktop viewport: 1920×1080.
The executable used for validation is `C:/Godot/Godot_v4.6.1-stable_win64_console.exe`.

Swap adjacent tiles to form matches. Matching tiles merge into an upgraded survivor;
the deterministic simulation produces an event timeline for visual playback.
`core/board`, `core/run` and `core/rules` contain simulation. `scenes/` owns input and
animation. See [AGENTS.md](AGENTS.md) for topology, gravity, RNG and rendering invariants.

Gem assets are generated offline from explicit material, geometry, condition,
lighting and presentation resources. The spectral GPU renderer supports convex,
mesh and analytic geometry, repeated volume scattering and optional reconstruction.
Specialized transport modes have explicit limitations. Physical grade labels never
alter optics; authored condition presets and an independent style layer control
their respective inputs. The game reads a bounded prebuilt asset library through
GemForge; it never renders missing optical assets at runtime.

Build with `tools/build_gem_assets.ps1`. Current factory contracts and available
commands are in [the tools guide](tools/README.md), [factory contract](core/lapidary/factory/CONTRACT.md)
and [kernel contract](core/lapidary/tracer/KERNEL_CONTRACT.md). Generated output is
ignored under `generated/`; desktop delivery includes the generated gem-assets.pck.

Run the project in Godot to access Play and the Gem Atelier. The
[engine readiness report](docs/ENGINE_READINESS_REPORT.md) records implemented
authoring, cut design, appearance and desktop-delivery validation.
Current documentation is indexed in [docs/README.md](docs/README.md). Superseded
documents are preserved under the gitignored `docs/archive/`.

Validation: `tools/check_engine.ps1` for CPU gates, `-Gpu` for GPU and factory gates,
`-ReferencePython <python>` for independent numerical comparisons. Use `-List -Gpu`
to inspect registered stages. GPU tools need a windowed RenderingDevice; use
`inspect_gems.gd -- --plan-only` for headless inspection planning. Simulation tests
are documented in [tests/README.md](tests/README.md).
