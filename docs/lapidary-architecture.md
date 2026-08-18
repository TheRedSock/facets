# Lapidary — GPU Gem Pipeline Architecture

Replaces the CPU Embree tracer, `GemVisualResource`, the lighting-grid atlas bake, and stylizer v7.
This document describes the new system only. Status: v1, being built.

---

## 0. Decisions up front

| Question | Decision | Why |
|---|---|---|
| GPU strategy | GLSL compute shader on Godot `RenderingDevice` (Vulkan primary; RD also abstracts D3D12/Metal) | Godot 4.6 has **no** hardware-RT API in RD (that is 4.7-dev, PR #99119). Gem scenes are one convex stone + a few dozen analytic inclusions — hardware BVH would be wasted. Compute is portable across every Vulkan-class GPU, no NVIDIA lock-in. |
| Stone representation | **Convex plane set** (intersection of tagged half-spaces), not a triangle mesh | Every T1–T8 cut (round, oval, square, rectangle, triangle, diamond, marquise, pear × brilliant/step/rose/princess/radiant) is a convex polyhedron. Ray–hull = one branchless loop over ≤128 planes: exact, watertight by construction, no BVH, no mesh validation class. Facet-meeting error (low cut grade) = per-plane jitter — the hull *stays* watertight. Edge rounding is shading, not geometry. |
| Inclusions | Analytic primitives (capsule, disc, ellipsoid, cloud) inside the hull, not merged mesh geometry | Exact GPU intersection, zero mesh plumbing, deterministic placement from stone seed, cheap enough to keep at every rung (grade honesty at Interact). |
| Transport | Spectral path tracing with **deterministic Fresnel splitting**: at every interior hit the transmitted branch exits and immediately evaluates the analytic environment; the reflected/TIR branch continues | The environment (light cards + gradient) is analytic and smooth, so the transmitted lobe needs no stochastic sampling. Variance collapses; gems converge at single-digit spp. This is what makes Interact real-time and Board-live worth measuring. |
| Wavelengths | 4 hero wavelengths sharing one geometric path (refraction uses n(λ₀)); when the rung enables dispersion, 1 wavelength per path (pure spectral, natural fire) | Hero-sharing is exact enough for low-dispersion minerals; per-λ paths are coherent (no divergence) and give real fire for diamond. |
| Denoise | None as architecture. Progressive accumulation for interactive rungs; optional tiny edge-aware à-trous as **rung policy** for scatter-heavy stones | Deterministic splitting removes the chromatic noise OIDN existed for. OIDN, Embree, TBB are deleted. |
| Color pipeline | Spectral → CIE XYZ (2° CMFs) → linear sRGB (D65) → **house print** (custom sprite tonescale + chroma governor) → sRGB8 | ACES was built for HDR film scenes, skews hues and crushes sprite mids. The print is our own curve, versioned, applied identically to baked clips and live draws. Raw view = same pipeline with print bypassed (still tone-mapped for display, labeled). |
| Delivery | **Authored clips** baked by the same kernel are the shipping hypothesis; live 3D stays a packaging switch on the same compiled stone. Both consume the identical `StoneInstance` + rig + rung + print | Brief §2.F. The rotation×lighting lattice is dead. Measured numbers (1/16/64 gems) decide the board consumer. |
| Headless | GPU tools run **windowed** CLI (`godot --path . --script …`); `--headless` has no RenderingDevice (verified on this machine). Pure-CPU stages (cut compile, data model, solver) remain headless-testable | Engine constraint, not a choice. Bake/launcher run inside the game process anyway. |
| Determinism | Per-stone integer seed → PCG; bit-stable per (GPU family, driver). Cache keys carry `look_version`; a different GPU regenerates rather than diffing | GPUs do not promise cross-vendor bit equality; pretending otherwise is a lie. Visual stability is asserted by physics tests with tolerances instead. |

---

## 1. Layered authoring model

Five thin layers. A shipping stone touches ~8 fields, not ~100.

```
GemSpecies      lattice physics of the mineral      data/lapidary/species/corundum.tres
GemChromophore  why ruby ≠ sapphire                 data/lapidary/chromophores/chromium_corundum.tres
GemCutTemplate  facet program in the cut language   data/lapidary/cuts/brilliant.tres
GemGrade        4 quality axes + recipes            data/lapidary/grades/t1_humble.tres … t8_exceptional.tres
GemStone        the instance a tile references      data/lapidary/stones/t7_ruby.tres
```

### GemSpecies (`resources/lapidary/gem_species.gd`)
- `sellmeier_b: Vector3`, `sellmeier_c_um2: Vector3` — 3-term Sellmeier, ordinary ray, λ in µm. Values verified against published data (refractiveindex.info / Malitson etc.); minerals without published Sellmeier get a 2-term fit from n_D + (B–G) dispersion, and the fit source is recorded in the resource.
- `birefringence: float` (Δn at 589 nm), `uniaxial_positive: bool` — optic axis fixed in stone space.
- `base_scatter: float` — σ_s of the *pure* crystal (near zero for most).
- `fluorescence_emission_nm / strength` — e.g. ruby 693 nm.
- `hardness_mohs: float` — drives wear statistics (soft stones scratch broad and shallow, hard stones pit).
- `inclusion_vocabulary: Array[GemInclusionArchetype]` — species-typical forms with placement statistics: corundum silk (oriented needle sets at 60°), beryl jardin (veil sheets + droplets), quartz milky veils (cloud banks), olivine lily pads (disc + halo). Grade picks *how much*; species defines *what dirty looks like*.
- `structure_zoning` — species-typical growth zoning (amethyst sector zoning etc.) as a small parametric field spec.

### GemChromophore
- `absorption_mm: PackedFloat32Array` — α(λ) per mm at reference concentration, 81 samples 380–780 nm @ 5 nm.
- `concentration: float` — scale.
- `pleochroic_absorption_mm` (optional second curve) + mixing by ray ∠ optic axis.
- Color change (alexandrite-class) is *not a flag*: it falls out of an absorption curve with two transmission windows plus the dual-illuminant view in the evaluation rig.
- `ui_color: Color` — UI chrome only. Never enters transport.

### GemCutTemplate — the cut language
A cut is compiled, never hand-meshed:

- **Silhouette**: parametric star-convex closed curve — `circle`, `ellipse(a,b)`, `superellipse(n)`, `polygon(k, corner_r)`, `marquise`, `pear`, `heart(deferred, needs CSG)`. Supplies `radius(θ)` and a symmetry sector count. Tier→silhouette taxonomy is unchanged game language.
- **Girdle**: plane ring sampled from the silhouette (16–64 planes by silhouette curvature), band height parameter.
- **Crown program**: ordered rows girdle→table. Row grammar: `break_row(count, alternation, angle)`, `step_row(angle)`, `star_row(...)`, terminated by `table(ratio)` or `point`. A row emits planes; it does not own a mesh builder.
- **Pavilion program**: `solved(mains, lower_halves)` or `step_rows(n)` — depth/angle from the **IOR solver**, not authored numbers. Authored override = explicit opt-out field, logged by the compiler.
- **IOR pavilion solver**: critical angle θ_c = asin(1/n_d); target main angle places face-up rays into double TIR (validated against published ideals: diamond ≈ 40.8°, corundum ≈ 42°, quartz ≈ 43°). `cut_grade` lerps solved→windowed/lumpy (below θ_c the stone *actually* windows — no image-space fakery).
- Family names (brilliant, step, rose, princess, radiant) are **templates expanding into the row grammar**. A trillion = `polygon(3)` silhouette + existing rows. No `_build_fan_crown` forks.

Compiler output — `GemHull` (RefCounted, never saved): plane array (normal, offset, zone tag: TABLE/STAR/BEZEL/UPPER_GIRDLE/GIRDLE/LOWER_GIRDLE/PAVILION_MAIN/CULET, facet-local UV basis), plus the projected 2D outline for sprites/tiles. Validation: every plane contributes a face; no windowed-by-accident geometry unless grade asked for it; hull closed (bounded) by construction check.

### GemGrade — one system, four axes, all physical
| Axis | Mechanism it drives |
|---|---|
| `cut` | Pavilion angle error vs solved (→ real windowing), crown height/table error, per-plane meeting jitter, edge rounding radius (shading), girdle unevenness |
| `clarity` | Inclusion count/size/depth distribution drawn from the **species vocabulary**, seeded |
| `surface` | Polish roughness base, scratch field density/anisotropy, abrasion patches, dirt film (surface absorption + diffuse lobe). Statistics shaped by species hardness |
| `crystal` | Volumetric milkiness σ_s multiplier, growth-zoning strength |

Grades ship as recipes `t1_humble` … `t8_exceptional`, but any stone can carry a custom grade. There is **no** haze slider, no `stylize_visual_quality`, no damage profile resource forest. A T1 quartz windows, wears, includes and hazes because the physics inputs say so, at every rung.

### GemStone (the instance format — both consumers eat this)
```
stone_id      &"t7_ruby"           (== tile_id)
species       corundum.tres
chromophore   chromium_corundum.tres
cut           brilliant.tres
silhouette    from tier taxonomy
grade         t7 recipe (or inline axes)
seed          int (stable inclusions/wear across preview & bake)
size_mm       float (Beer–Lambert path scale)
```
Compiled form: `StoneInstance` = GemHull + media params + inclusion primitive list + wear field params + optics tables (IOR per hero λ, α(λ) table). One buffer upload; consumed identically by clip baker, designer preview, and live board draws.

---

## 2. GPU kernel

**Files**: `core/lapidary/tracer/gem_tracer.gd` (host), `shaders/gem_pathtrace.glsl`, `shaders/gem_print.glsl`.

Host API (GDScript):
```
setup(rd: RenderingDevice)                        # local RD for bakes; main RD + Texture2DRD for live
load_stone(instance: StoneInstance) -> StoneSlot
render(slot, rig: RigState, rung: Rung, sample: ClipSample, accum: bool) -> void
read_image(slot) -> Image                          # bake path
texture_rd(slot) -> Texture2DRD                    # live path
profile() -> Dictionary                            # ms, paths/s, per-feature toggle costs
```
`ClipSample` = time, stone orientation, rig orientation, per-role power envelope values, camera. The designer scrubs by sending samples; the baker steps them; live sends the board's fixed sample.

Path per sample:
1. Camera ray (ortho for board/sprites) → hull test. Miss → transparent (alpha accumulates coverage).
2. Entry: Fresnel R(θ,λ). Add `R × env(reflect)` (surface sparkle), refract in with weight T. Microfacet (GGX) normal perturbation from polish/wear field at the facet-local UV.
3. Interior loop (≤ rung.max_bounces): march segment; Beer–Lambert with α(λ)·zoning; stochastic scatter event vs σ_s (HG); test analytic inclusion list — on hit, archetype-specific interaction (needle: aligned spec + scatter; veil/cloud: dense local scatter; crystal: tinted refract-scatter). At hull exit hit: **deterministic split** — add `T × env(refract_dir) × throughput`, continue with `throughput × R` along reflection; TIR continues at full weight. Kill at ε throughput.
4. Accumulate XYZ via CMF weights into float32 buffer.

Second dispatch (print pass): XYZ→sRGB linear→exposure→tonescale→chroma governor→optional micro-bloom→sRGB8 + AA alpha. `raw` flag bypasses print (display transform only).

Birefringence: entry splits o/e rays weighted by polarization when `Δn × rung policy` says so (peridot Δn≈0.036 doubles visibly; corundum 0.008 does not at 112 px). Fluorescence: pump-band absorption tally → narrow emission added (PREVIEW+).

---

## 3. Lighting language

`data/lapidary/rigs/*.tres` — a rig is ≤6 roles, not 18 environment clones:

| Role | Params |
|---|---|
| KEY / FILL / RIM / BOUNCE | direction (az/el), angular radius, kelvin → spectrum, power |
| BLOCKER | solid-angle darkener (dark-field contrast for step cuts) |
| BACKGROUND | zenith/horizon/nadir gradient + exposure |

Two shipped rigs:
- `reference_daylight.tres` — honest D65-class key, flat fill. Spectra debugging happens here first (the old A/B policy, now a tool: the evaluation harness renders both rigs side by side).
- `gameplay_studio.tres` — sprite-oriented: warm key upper-left with broad angular size (facet gradients), small cool rim (edge sparkle), blocker for dark-facet contrast, background tuned for board readability.

Rig rotation and per-role power envelopes are **clip tracks / render parameters**, never file forks. Dual illuminant is an evaluation view (and a phenomenon showcase for color-change stones), not a rig field on every file.

---

## 4. Quality rungs (one kernel, policy objects)

| Rung | Res | SPP | Policy |
|---|---|---|---|
| INTERACT | 128 | 1/frame progressive | hero-shared λ, no birefringence, single forced scatter, inclusions on (grade honesty), bounces 8 |
| PREVIEW | 256 | accumulate → 32 | dispersion for high-dispersion species, birefringence if Δn ≥ 0.02, full volume, bounces 12 |
| BOARD_LIVE | 112 | measured budget | minimal-but-grade-honest; exists to be measured at 1/16/64 gems |
| CLIP_BAKE | 224 → 112 | 128–256 | all species features, supersampled to sprite size |
| HERO | 768 | 512 | everything |

Feature flags live on the rung (+species hints like "scatter-noisy"), never on stones. A T1 must look included and windowed at INTERACT.

---

## 5. Mastering (house print)

`data/lapidary/print/house_print.tres`, versioned (`print_version` in every cache key):
- Global: sprite tonescale (toe/shoulder), black point for board, chroma governor (OKLCh ceiling with soft rolloff), highlight desaturation rolloff, micro-bloom as *print*.
- House policies that reach back into the tracer (key angular floor, sprite roughness floor, card power clamp) are named fields here, applied by the rig/rung assembler — visible, versioned, not per-gem knobs.
- Exceptions: array of `{selector, deltas, reason:String}` — reason is required; empty reason fails validation.
- Forbidden by construction: no per-stone haze, no brilliance punch, no per-gem CDL. Grade cues (windowing, silk, jardin, frost) must survive the print; the evaluation harness A/Bs raw vs print on every sheet.

---

## 6. Delivery: clips, launcher, board policy

### Clip schema (`data/lapidary/clips/*.tres`)
```
clip_id, duration_s, fps, loop
stone_track   STILL | TURNTABLE(axis, degrees, easing) | keyframes
rig_track     rig rotation over time + per-role power envelopes
camera_track  fixed board framing (default) | showroom orbit
effect_track  named print/tracer envelopes (exposure_pulse, rim_boost)
```
A still is a 1-frame clip. Baker: `clip × stone × rung × print_version → frame strip (WebP) + sidecar json`. v1 catalog: `idle` (still or 2 s micro-shimmer loop), `turn` (lighting-relative 90° turntable — the stone turns *under the rig*), `flash` (match effect via effect_track). No rotation×lighting lattice exists anywhere.

### Launcher / manifest / cache
- `data/lapidary/manifest.tres`: exact (stone × clip × rung) list with priority classes: REQUIRED_NOW (idles for the run's tile set) → SOON (turn, flash) → LATER.
- Cache: `user://gemcache/<look_version>/<stone>_<seed>/<clip>@<rung>.webp`, key = hash(look_version, print_version, rung, clip fingerprint, stone fingerprint). One gem changing invalidates one gem.
- `GemForge` autoload (lazy): serves clips; missing REQUIRED_NOW entries render an INTERACT still synchronously (few ms) as placeholder, bake CLIP_BAKE frames incrementally in the background, hot-swap when landed. Cold required-now budget: seconds — measured and reported by the harness.
- Dev fast path: `tools/package_clips.gd` bakes the full catalog into `res://generated/gemcache/` (committed/artifacted); launcher checks user:// then res://generated.

### Board lighting policy (decided, revisable by measurement)
Ship **instanced/shared look**: all stones of one identity play the same clip. Positional per-cell lighting is a rejected default (it is what forced the old 5×5 lighting-grid bake); if measurement shows BOARD_LIVE at 64 gems is cheap, positional lighting returns as a live-consumer option, not as a sprite lattice.

---

## 7. Evaluation harness (`tools/render_eval_sheets.gd` → `artifacts/lookdev/`)
- Contact sheet: 8 ladder stones, face-up, gameplay rig, sprite rung, raw|print.
- Grade sheet: one mineral at 4 grade stops, same cut.
- Lighting sheet: same stone, reference vs gameplay vs dual illuminant.
- Rung sheet: INTERACT/PREVIEW/CLIP_BAKE/HERO, same seed.
- Clip sheet: idle + turn + flash frame strips, raw|print.
- Timing: ms/frame INTERACT; BOARD_LIVE at 1/16/64 (shared vs positional); per-clip bake time; cold required-now launcher time.
- Physics tests (windowed GPU): energy ≤ 1, Fresnel vs analytic at three angles, TIR window vs cut grade, Beer–Lambert vs closed form on ruby's α, Sellmeier n(589) vs published per species.

## 8. What is deleted
DELETED (2026-08): `native/` (Embree, TBB, OIDN, SCons), `core/visuals/`, `resources/visuals/`, `data/visuals/`, `data/minerals/` + `data/environments/` (values salvaged into `data/lapidary/`), `autoloads/gem_visual_registry.gd`, the old `scenes/design/` workbench + designer, blend shader + procedural TileView paths, old bake CLIs + `config/bake_profiles/`, `generated/traced_bakes/`, visual-pipeline tests (rewritten under `tests/lapidary/`). Simulation (`core/board`, `core/run`, `core/rules`) untouched.
