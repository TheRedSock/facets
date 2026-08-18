# Lapidary Kernel Contract (v1)

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
| 4 | zone id | 0 table, 1 crown main/star, 2 upper girdle, 3 girdle, 4 pavilion main, 5 lower girdle, 6 culet, 7 step row |
| 5 | roughness base for this facet | polish after grade, before wear fields |
| 6–7 | reserved | |

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
| 7 | role: 0 emitter, 1 blocker |

## Inclusion primitive (16 floats) — analytic, inside the hull only
| idx | field | notes |
|---|---|---|
| 0–2 | center (stone space) | compiler guarantees inside hull |
| 3 | type | 0 needle (capsule), 1 platelet (disc), 2 cloud (ellipsoid), 3 crystal (sphere) |
| 4–6 | axis (unit) | needle direction / disc normal / ellipsoid major axis |
| 7 | half-length or radius (stone units) | |
| 8 | secondary radius | capsule radius / disc half-thickness / ellipsoid minor |
| 9 | scatter density per mm | |
| 10–12 | tint RGB | broad-band approximation: R→long-λ, G→mid, B→short (documented simplification) |
| 13 | ior_delta (crystal type) | |
| 14–15 | reserved | |

## Stone struct (144 bytes, std430 — array `Stones`, one per distinct stone)
| vec4 | contents |
|---|---|
| 0 | sellmeier_b.xyz, size_mm |
| 1 | sellmeier_c_um2.xyz, birefringence Δn |
| 2 | scatter σ_s/mm, HG g, zoning frequency, zoning contrast |
| 3 | zoning axis.xyz, zoning phase |
| 4 | optic axis.xyz, fluorescence strength |
| 5 | wear: roughness (polish+grade boost), scratch_density, scratch_aniso, abrasion |
| 6 | wear: dirt, edge_round, fluorescence nm, absorb_scale |
| ivec4 7 | plane_offset, plane_count, incl_offset, incl_count |
| ivec4 8 | absorb_offset, stone_flags (bit0 has_eray, bit1 dispersion_strong), 0, 0 |

Absorption buffer: concatenated 81-sample blocks (α/mm, 380–780 @ 5 nm, concentration
applied). If `has_eray`, the e-ray block directly follows the o-ray block (offset+81)
and is blended by cos²(ray, optic axis).

## Instance struct (64 bytes — array `Insts`, one per grid cell)
| vec4 | contents |
|---|---|
| 0 | stone→world quaternion |
| 1 | rig_yaw (radians), ortho_half, key_mult, fill_mult |
| 2 | rim_mult, bounce_mult, 0, 0 |
| ivec4 3 | stone_index, 0, 0, 0 |

Pixels map to instances via an equal-cell grid (push constants `grid`, `cell_px`);
grid 1×1 = single stone. Per-role power multipliers map to emitter buffer INDEX
0–3 (emitters packed in role order KEY, FILL, RIM…, BOUNCE last; index ≥3 shares
the fourth multiplier). `GemRigCompiler.pack()` produces the ordering.

## Bindings (set 0)
0 Planes, 1 Lights, 2 Absorb, 3 Accum (vec4 XYZ+coverage), 4 Prims, 5 Stones, 6 Insts.
Push constants (80 B): resolution, frame, spp, seed, max_bounces, flags
(bit0 dispersion_split, bit1 birefringence, bit2–3 volume_mode, bit4 fluorescence),
light_count, grid, cell_px, bg zenith/horizon/below, spectral_norm, rad_clamp.

## Rung flags (engineering policy — `core/lapidary/tracer/rung.gd`)
dispersion_split (per-λ paths), birefringence_fork, volume_mode
(0 off / 1 single-forced-scatter / 2 full-features; both 1 and 2 allow at most
one HG event — homogeneous volume *or* cloud/fingerprint primitive — then NEE
the remaining hull; milk is σ, not bounce count. Needle/platelet silk stays
rough-specular and does not consume the HG slot), max_bounces, spp per dispatch,
internal resolution → output size, denoise (always 0; no à-trous).

## Clip sample (what a render call receives)
time_norm, stone quaternion (rest ∘ motion), rig yaw (radians), per-role power
multipliers (vec4: key, fill, rim, bounce), effect values (exposure_pulse,
bloom_gain), camera ortho half-width.

## Host API (`gem_tracer.gd`)
`create(w, h, rd=null)` → tracer (null in headless).
Full path: `configure_stone(instance, lights, policy)` /
`configure_stones(instances, lights, policy, grid)` where `instance` is
`LapidaryStoneCompiler.compile()` output and `policy` is `GemRung.policy()`.
Per-frame: `set_stone_orientation(q)`, `set_clip_sample(q, rig_yaw, role_mult,
ortho_half)`, `set_instances(states)` (batch), `set_background(bg)`, `set_seed(s)`.
Dispatch: `accumulate(spp) -> ms`, `reset_accumulation()`.
Output: `finalize_print(print: GemPrint = null, raw := false, exposure := 1.0)`
(GPU print pass), `read_xyz()` (physics tests), `finalize_image(exposure)`
(CPU compat). Compat: `configure(planes, lights, absorb, params)` wraps a
single wear-free stone. `release()` frees GPU resources.

## Determinism contract
Seeded PCG from (pixel, frame, stone seed). Reproducible on the same GPU
family + driver. NOT bit-exact across vendors — cache keys carry
`look_version`; foreign caches regenerate. Physics tests assert with
tolerances, never bit equality.
