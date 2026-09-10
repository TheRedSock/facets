# Lapidary Kernel Contract (v3 — clean optics)

The single interface between the data model and the GPU tracer. Everything that
renders — designer preview, clip bake, live board draws, evaluation sheets —
goes through these buffers. Anything not expressible here does not exist visually.

All buffers are std430 float32 unless noted. Stone space: girdle plane at z=0,
crown toward +Z, unit girdle radius. Camera: orthographic, world space, looking
down −Z; the stone quaternion rotates stone→world.

## Plane (8 floats) — the stone body, intersection of half-spaces
| idx | field | notes |
|---|---|---|
| 0–2 | outward unit normal (stone space) | |
| 3 | d — plane offset (`dot(n,x) <= d` is inside) | |
| 4 | zone id | 0 table, 1 crown main/star, 2 upper girdle, 3 girdle, 4 pavilion main, 5 lower girdle, 6 culet, 7 step row (compiler metadata; kernel v3 treats every facet as a perfect specular dielectric) |
| 5–7 | reserved | |

The hull MUST be bounded (compiler responsibility). Facet-meeting error is
per-plane jitter — never break the half-space representation.

## Light (8 floats) — analytic rig, world space
| idx | field |
|---|---|
| 0–2 | direction TOWARD the light |
| 3 | cos(outer angular radius) |
| 4 | kelvin (Planck-relative SPD, normalized at 560 nm) |
| 5 | power (BLOCKER: darkening strength 0..1) |
| 6 | cos(inner radius) |
| 7 | role: 0 key, 1 fill, 2 rim, 3 bounce, 4 blocker |

`GemRigCompiler.pack()` is the only packer. The shader indexes per-role power
multipliers by this role field (not by buffer index).

## Inclusion primitive (16 floats) — analytic, inside the hull only
| idx | field | notes |
|---|---|---|
| 0–2 | center (stone space) | compiler guarantees inside hull |
| 3 | type | 0 needle (capsule), 1 disc (platelet or veil), 2 cloud (ellipsoid volume), 3 crystal (pinpoint) |
| 4–6 | axis (unit) | needle direction / disc normal / ellipsoid major axis |
| 7 | half-length or radius (stone units) | |
| 8 | secondary radius | capsule radius / disc half-thickness / ellipsoid minor |
| 9 | scatter density per mm | optical depth `tau = density * chord_mm`; `P = 1 - exp(-tau)` |
| 10–12 | tint RGB | broad-band approximation: R→long-λ, G→mid, B→short (documented simplification) |
| 13 | ior_delta (crystal type) | unused for v1 pinpoints |
| 14 | style | 0 lily pad (annulus / decrepitation halo), 1 veil (irregular fracture band) |
| 15 | reserved | |

Clouds have no surface: the kernel samples optical depth along the ellipsoid chord
and may HG-scatter inside it. Veil discs use a noisy outline and holey coverage.
Crystals sparkle and continue; they do not resolve as spheres.

## Stone struct (128 bytes, std430 — array `Stones`, one per distinct stone)
| vec4 | contents |
|---|---|
| 0 | sellmeier_b.xyz, size_mm |
| 1 | sellmeier_c_um2.xyz, signed birefringence Δn |
| 2 | scatter σ_s/mm, HG g, zoning frequency, zoning contrast |
| 3 | zoning axis.xyz, zoning phase |
| 4 | optic axis.xyz, fluorescence strength |
| 5 | fluorescence nm, absorb_scale, 0, 0 |
| ivec4 6 | plane_offset, plane_count, incl_offset, incl_count |
| ivec4 7 | absorb_offset, stone_flags (bit0 has_eray, bit1 dispersion_strong), 0, 0 |

There is no surface-condition (wear) model: the grade reaches the kernel only
through geometry (cut), inclusions (clarity) and media (crystal).

Absorption buffer: concatenated 81-sample blocks (α/mm, 380–780 @ 5 nm, concentration
applied). If `has_eray`, the e-ray block directly follows the o-ray block (offset+81).

Polarisation (GIA G&G Spring 2021): with `c2 = cos²(φ)` for angle φ between ray and
optic axis, `α_k = c2 α_o + (1-c2) α_e`. Unpolarised stones use `0.5 T_o + 0.5 T_k`.
Birefringent fork (rung + |Δn| > 0.015): o-pass uses α_o, e-pass uses α_k. Index of
the e-pass uses the indicatrix: `1/n_e(φ)² = c2/n_o² + (1-c2)/n_e²`.

## Instance struct (64 bytes — array `Insts`, one per grid cell)
| vec4 | contents |
|---|---|
| 0 | stone→world quaternion |
| 1 | rig_yaw (radians), ortho_half, key_mult, fill_mult |
| 2 | rim_mult, bounce_mult, 0, 0 |
| ivec4 3 | stone_index, 0, 0, 0 |

Pixels map to instances via an equal-cell grid (push constants `grid`, `cell_px`);
grid 1×1 = single stone.

## Bindings (set 0)
0 Planes, 1 Lights, 2 Absorb, 3 Accum (vec4 XYZ+coverage), 4 Prims, 5 Stones, 6 Insts,
7 scatter field (`image3D` rgba16f in the pre-pass, `sampler3D` trilinear in the kernel).

Kernel push constants (96 B): resolution, sample_base, spp, seed, max_bounces, flags
(bit0 dispersion_split, bit1 birefringence, bit2 volume, bit4 fluorescence),
light_count, grid, cell_px, bg zenith/horizon/below, spectral_norm, rad_clamp,
env_filter_rad, field_exits, field_grid, row_origin, field_insts, bg_kelvin.

Scatter-field push constants (48 B): grid_n, field_exits, light_count, inst_count,
dirs, band_group, env_filter_rad, texel_base, bg (zenith, horizon, below, kelvin).

Print push constants (112 B): output resolution, inv_samples, exposure, raw, white_point,
contrast, black_point, chroma_ceiling, chroma_soft, highlight_desat, pad, then the
XYZ→linear-sRGB matrix as three vec4 columns (includes the rig's as-shot white
balance, see below), then source resolution (ivec2) and padding (ivec2).
The print resolves coverage-associated linear XYZ over each output pixel's source
footprint, divides XYZ by covered sample weight, then applies the display transform.
The output is straight sRGB RGBA8. `read_linear_master()` returns associated XYZ
and coverage as RGBAF without any display transform.

## Environment
`env_radiance_ex(dir, wl, rig_yaw, role_mult, fp, with_lights, bg, light_count)`
(gem_common.glsl) is the one analytic rig evaluator, shared by the kernel and the
scatter-field pre-pass. Background = zenith/horizon/below gradient; its spectrum is
Planckian at `bg.w` kelvin (flat when 0). Lights are Planck-relative cones widened by
the footprint `fp` (flux-conserving `R² / (R² + fp²)` — the same cone_omega formula
on both sides). Blockers multiply everything in their cone by `1 - power·w`.

`GemRigCompiler.environment(rig)` → `{bg: Vector4, white_kelvin}` feeds
`GemTracer.set_environment()`. `white_kelvin` is the rig's as-shot neutral: the host
builds Bradford(CAT) from that Planckian white to D65 (`core/lapidary/lighting/
colorimetry.gd`, same CIE fit as the shaders) and folds it into the print matrix, so a
colourless stone under the rig's dominant light prints white and every other light
keeps its relative warmth. Exposure is the house print's `exposure` only — tools and
bakes pass 1.0.

## Estimator (v3)
- Global sample index `n = sample_base + s` drives per-pixel Cranley-Patterson-rotated
  Halton for pixel filter, wavelength, unified free flight + medium choice, and the
  first scatter direction (field-off only). PCG covers remaining dimensions.
- Deterministic Fresnel split at every interior surface: the transmitted branch
  evaluates the environment immediately, the reflected/TIR branch continues.
  The first inclusion surface hit splits deterministically too.
- Angular footprint `fp` (radians) grows with the orthographic pixel footprint and
  the path's divergence; the environment cones are widened by it.
- Volume: repeated sampled scatter events per path (homogeneous milk + cloud primitives,
  unified free flight). With `field_exits > 0` the scattered radiance is read from
  the SH scatter field (l ≤ 3, 16 × 25 nm bands, HG convolution `g^l`), and the
  path ends: the field is the whole continuation. `field_exits = 0` keeps the
  stochastic HG continuation with a fresh exponential free flight after each event.
  The reference includes multiple scattering; the current field remains an
  approximation under evaluation. After a
  scatter, the environment footprint floor is `env_filter_rad` on both sides.
- Scatter field pre-pass (`gem_scatter_field.glsl`): per texel of a
  `field_grid³` lattice over `[-1.25, 1.25]³` stone space, `field_dirs` Fibonacci
  directions each traced through the Fresnel chain for `field_exits` hull hits with
  Beer-Lambert absorption (no extinction by σ_s: higher orders are delivered
  forward, matching the kernel). Rebuilt whenever orientation, rig, background or
  stone set changes; the host chunks it (4 bands × texel ranges) for TDR safety.

## Rung flags (engineering policy — `core/lapidary/tracer/rung.gd`)
dispersion_split (per-λ paths), birefringence fork, volume, max_bounces, spp per
dispatch (`batch`), internal resolution → output size, rad_clamp, env_filter_rad,
field_exits / field_grid / field_dirs. Denoise always off.

## Clip sample (what a render call receives)
time_norm, stone quaternion (rest ∘ motion), rig yaw (radians), per-role power
multipliers (vec4: key, fill, rim, bounce), effect values (exposure_pulse),
camera ortho half-width.

## Host API (`gem_tracer.gd`)
`create(w, h, rd=null)` → tracer (null in headless).
Full path: `configure_stone(instance, lights, policy)` /
`configure_stones(instances, lights, policy, grid)` where `instance` is
`LapidaryStoneCompiler.compile()` output and `policy` is `GemRung.policy()`.
Per-frame: `set_stone_orientation(q)`, `set_clip_sample(q, rig_yaw, role_mult,
ortho_half)`, `set_instances(states)` (batch), `set_environment(env)` (from
`GemRigCompiler.environment(rig)`), `set_seed(s)`.
Dispatch: `accumulate(spp) -> ms` (adaptive TDR-safe chunking; rebuilds the scatter
field first when dirty), `build_scatter_field() -> ms`, `reset_accumulation()`.
Output: `finalize_print(print: GemPrint, raw := false, exposure := 1.0)`
(GPU print pass; house print via `GemPrint.load_house()`), `read_xyz()` (physics tests).
`release()` frees GPU resources.

## Determinism contract
Seeded QMC + PCG from (pixel, frame, stone seed). Reproducible on the same GPU
family + driver. NOT bit-exact across vendors — cache keys carry
`look_version`; foreign caches regenerate. Physics tests assert with
tolerances, never bit equality.
