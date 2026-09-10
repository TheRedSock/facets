# Lapidary kernel contract (v15)

This is the CPU/GPU interface for offline workers and Atelier previews. The game
loads prebuilt assets and does not instantiate the optical renderer. Wire floats
are float32, std430; the optional crystal kernel computes fields and intersections
in float64. Stone space has the girdle at z=0, crown toward +Z, and unit
girdle radius. `size_mm` converts one stone-space unit into millimeters. The
orthographic camera looks down world −Z; instance quaternions rotate stone→world.

## Geometry and material state

A Plane is two vec4s (32B): outward normal.xyz/offset d, then zone ID/reserved/
facet-ID-bits/reserved. The facet ID occupies aux.z as an **int32 bit pattern**;
read it with `floatBitsToInt`, never a numeric float conversion.
The host interior obeys dot(n,x)<=d. Zone IDs: 0 table, 1 crown main/star,
2 upper girdle, 3 girdle, 4 pavilion main, 5 lower girdle, 6 culet, 7 step row.
They identify cut structure, not surface finish.

## Optional primary geometry companions

`GemTracer.geometry_aov(coverage_side)` runs a separate lazy compute pipeline;
it does not sample light, change film state or depend on optical SPP/seed. A
deterministic 1/2/4/8-square subpixel grid estimates primary physical coverage.
The representative covered sample nearest the pixel center supplies discrete
geometry; fields and IDs are never averaged across facet boundaries. Sampling
matches the optical tracer's `pixel + sample - 0.5` center convention.

The geometry pipeline uses existing scene buffers plus binding16 output. Its
32-byte push block contains ivec2 resolution/grid/cell_px, coverage_side and
row_origin. Each output record is 48 bytes: vec4 object-position-mm/camera-forward-
distance-mm; vec4 incident-facing object-normal/coverage; ivec4 instance/facet/
local-region/global-material. A miss has zero geometry/coverage and IDs=-1.
Analytic patch facet IDs are negative (-1 dome, -2 girdle, -3 base), disambiguated
from misses by coverage. Full int32 facet IDs survive BVH and plane packing.
`physical_boundary` skips boundaries that do not change the active medium, so
an exposed cavity wall replaces the clipped-away outer surface.

`GemGeometryAov` encodes standalone GAO1 little-endian diagnostics: uint32 magic
0x314f4147, width, height, coverage_side, raw_length, then Zstd-compressed records.
Decode bounds dimensions/payload and rejects nonfinite geometry or invalid
coverage/normal/visibility state. These are optional authoring companions, **not
automatically shipped game textures**. They describe the first visible boundary,
not refracted inclusions, internal optical contributions or a simulated grade.
The portable frame factory optionally schedules and caches these companions;
`tools/export_gem_aov.gd` also exports them independently for evaluation/stylizer work.

A Triangle is four vec4s (64B): a/b/c vertices (w reserved), then ivec4
(facet ID, reserved, reserved, local region ID). BVH Node (48B): vec4 low/high,
ivec4 left/right/first/count. Count0 is an internal node. Absolute buffer indices,
median split, four triangles per leaf, traversal stack64.

`GemMesh` validates finite coordinates, nondegeneracy, closed oriented edge
incidence and positive volume. Arbitrary global self-intersection certification
is not implemented. Convex plane→mesh conversion preserves facet IDs and welds
canonical intersections; concave lofts use procedural triangle surfaces.

Round/oval cabochons use analytic upper ellipsoid + elliptical girdle cylinder +
flat base. Stone.ranges0.y=-1 selects this host. Its Plane n_d contains x radius,
y radius, dome height, base z<0. Analytic surface IDs are -1 dome, -2 girdle,
-3 base; BVH triangle IDs are nonnegative. Other curved outlines use triangles.

Region0 is the host; up to127 additional closed priority regions are clipped to
it. The highest active region chooses the medium. A uvec4 tracks active regions.
Binding13 contains int32 region→material indices at Stone.ranges1.w+region:
-1 air, otherwise a shared Stones index. Host materials are first in that array,
then nested materials. Overlapping cavities subtract their union; higher filled
regions override lower ones. Exact coincident boundaries are unsupported: use a
finite gap or overlap. Mathematical boundaries with unchanged medium are skipped
for visibility, but transport processes their segments to preserve optical length.

## Stone (160B)

| vec4 | Contents |
|---|---|
| 0 | Sellmeier B.xyz, size_mm |
| 1 | ordinary Sellmeier C.xyz in µm², sampled visible maximum |n_e-n_o| |
| 2 | scattering σ_s/mm, HG g, zoning frequency, zoning contrast |
| 3 | zoning axis.xyz, phase |
| 4 | optic axis.xyz, fluorescence strength (disabled) |
| 5 | fluorescence nm (disabled), absorb_scale, nested_volume_present, rough_present |
| ivec4 6 | plane_offset, plane_count, volume_field_offset, volume_field_count |
| ivec4 7 | absorb_offset, flags, bvh_root_plus_one, region_offset |
| 8 | extraordinary Sellmeier B.xyz, ordinary index offset |
| 9 | extraordinary Sellmeier C.xyz in µm², extraordinary index offset |

Flags: bit0 has_eray, bit1 dispersion_strong. BVH selector0 is convex planes,
-1 analytic host without mesh, positive root+1 supports triangle host/defects.
Absorption concatenates 401-sample Napierian α/mm blocks, 380..780 nm at1nm. An e-ray
block follows its o-ray block directly (offset+401). Source resources may use
a different uniform grid, but must cover the transport interval. No implicit
extrapolation or normalization of material absorption is allowed. Concentration is already applied.

Current anisotropy is an approximation: α_k=cos²φ α_o+sin²φ α_e; the unpolarized
segment uses (T_o+T_k)/2. Optional o/e fork occurs above the sampled visible
maximum |Δn|=.015, with effective
index 1/n_e(φ)²=cos²φ/n_o²+sin²φ/n_e². This scalar path has no persistent polarization frame,
full anisotropic interface solver or biaxial transport (the optional isotropic
polarized variant is described below). REFERENCE does not fix
these limitations. Fluorescence has no enabled transport implementation.

## Boundary finish (32B, binding14)

One record per region, same offset as binding13: vec4(alpha_u,alpha_v,0,0),
vec4(object-space polish direction.xyz,0). Direction projects onto the tangent
plane at each hit. Zero slopes select an exact specular dielectric interface.

Rough dielectric uses visible-normal GGX, correlated Smith masking and consistent
G2/G1 proposal weights, including incident/transmitted index squared for radiance.
Macroscopic hemisphere tests reject invalid proposals. Index-matched boundaries
ignore finish. The single-scattering microfacet model loses unresolved energy at
strong roughness: only light polish has passed acceptance. Strong frosting and
automatic grade.surface recipes remain disabled. `tools/surface_check.gd` checks
furnace response and directional polish. The old fake inclusion primitives are
removed; explicit closed geometry and material regions are the defect backend.

## Compiled lighting and colorimetry

`GemRigCompiler.compile(rig)` returns one `GemLighting`: packed lights, deduplicated
spectra, background, and white_xyz. No independently packed environment can carry
stale spectral offsets. A Light is two vec4s (32B): direction toward light.xyz,
cos outer angle; spectrum offset, radiance power, cos inner angle, role ID.
Roles0..4 are key/fill/rim/bounce/blocker. Per-instance multipliers address roles.
At most8 lights; a background-only rig has count0 and a dummy buffer allocation.

Binding15 concatenates 401-float emission SPDs, 380..780 nm at1nm, linearly
interpolated. Light slot4 and background.w address the start of a block. Emission
recipes are equal-energy, blackbody, CIE D65, or sampled radiance. Normalization is
explicit: preserve scale, normalize at560nm, or match unit equal-energy luminance.
Power remains separate. Finer-than1nm structure is not represented by this ABI.

Binding4 is 401 vec4s: CIE1931 2° xbar/ybar/zbar and relative D65 at1nm. Original
CIE tables plus publisher metadata reside in data/lapidary/standards (CC BY-SA4.0;
DOIs10.25039/CIE.DS.xvudnb9b and10.25039/CIE.DS.hjfjmt59). SHA256 is verified and
included in optical identity. Worker bundles carry the original files. No network
is needed to render. Tables replace the earlier Gaussian observer fit.

Background is a zenith/horizon/below gradient multiplied by its SPD. Light cones
have smooth inner/outer edges, widened by the path footprint using the existing
solid-angle flux compensation. Blockers multiply radiance by1−power*weight.

White balance is independent of optical transport: integrate the explicit neutral
SPD to XYZ, normalize Y, then Bradford-adapt to D65 before linear sRGB. Null neutral
means no adaptation. White-only changes preserve optical masters and accumulation.
The house print applies exposure, tonescale and chroma control, then sRGB encoding.
Coverage-associated XYZ is area-resolved before division by coverage and nonlinear
printing. Output is straight-alpha RGBA8. Raw masters remain associated XYZ+coverage.

## Instance (64B)

vec4 quaternion; vec4(rig yaw radians, ortho half-width, key mult, fill mult);
vec4(rim mult, bounce mult, camera distance,0); ivec4(stone index,0,0,0).
Camera distance encloses all host/defect geometry under rotation. Framing is
separate. An equal-cell grid maps pixels to instances; 1×1 is a single specimen.

## Bindings and push constants

Shared set0: 0 planes,1 lights,2 absorption,3 accumulated XYZ+coverage,4 standards,
5 Stones,6 Instances,7 spatial volume fields,15 emission spectra.
Trace also uses8 guides (normal/depth sums, residual Y²/Y sum/min/max facet IDs),
9 zero-scatter sums,10 residual sums,11 triangles,12 BVH nodes,13 region materials,
14 boundary finishes. Guide stride32B; other film buffers16B/pixel.

Trace push80B: resolution, sample_base, spp, seed, max_bounces, flags, light_count,
grid, cell_px, background zenith/horizon/below, spectral_norm, rad_clamp,
row_origin, background SPD offset, throughput_epsilon. Flags bit0 dispersion,
bit1 approximate birefringence, bit2 volume, bit4 reserved,
bit5 full four-wavelength geometry. The rejected SH prepass has been removed.

Print push112B: output size,inv_samples,exposure,raw,white_point,contrast,
black_point,chroma_ceiling,chroma_soft,highlight_desat,pad; XYZ→linear-sRGB matrix
as three vec4 columns; source size and padding. Reconstruction push32B:
resolution,step,sample_count,phi,normal_exponent,padding2; bindings0 input,
1 guides,2 output,3 zero-scatter sums.

## Estimator and reconstruction

QMC/PCG derives random samples from global sample index; dispatch partitioning
does not restart sequences. Smooth convex hosts use deterministic Fresnel escape
splitting. General boundaries split only after the escape branch is proven to
reach the environment; coupled internal branches use roulette. TIR continues.
Homogeneous volume uses repeated HG scattering and analytic free-flight distance.
Absorption integrates the sinusoidal concentration field analytically along each
segment using its midpoint phase and sinc of its half-phase span. Subdividing a
straight path preserves its optical depth, including the parallel-band limit.
This does not fix the separate absence of persistent polarization.

Production volume reconstruction filters the stochastic residual with positive,
variance/normal-guided à-trous weights, keeping smooth zero-scatter light intact.
Rough interfaces reconstruct the whole stochastic signal. Coverage stays unchanged.
This is a biased optional filter. Raw accumulation and unfiltered REFERENCE remain
available. No claim of independent physical calibration follows from self-tests.

## Host and authoring boundary

`create(w,h)` needs a local RenderingDevice (windowed). Configure with compiled
specimen(s), GemLighting and GemRung policy. `set_lighting()` atomically replaces
lighting and resets incompatible accumulation; a white-only
change retains it. `set_print_white()` affects only print. Per-frame orientation,
rig yaw, role multipliers, framing and seed are explicit; changing them retires
incompatible film samples. `accumulate()` reports wall time; `profile()` separates stages. Checkpoints retain
raw estimator buffers and the global sample count. Release frees GPU resources.

GemMaterial owns bulk properties, GemShape the procedural body recipe, GemCondition
realized millimeter-scale defects, manufacturing tolerances and host finish.
Cut templates carry explicit pavilion/crown/table/culet proportions: material
IOR and grade never rewrite geometry. All GemGrade axes are metadata;
homogeneous scattering and spatial banding are explicit physical inputs.
Automatic clarity and surface recipes are disabled. Explicit fractures have not passed low-SPP visual acceptance.
Recipe hashes cover physical input and optical source; producer hardware/driver
are metadata. Determinism tests use tolerances across floating-point execution.


## Measurement ingestion and evidence

`GemOpticalEvidence` scopes evidence to refraction, absorption or scattering:
authored approximation, published model, fitted targets or supplied measurement.
The catalog's absorption bands remain authored approximations. Four refraction
models use published Sellmeier coefficients; most others fit sparse targets, and
painite dispersion remains an explicit assumption. These descriptors do not claim
independent laboratory calibration. Temperature and uncertainty can be unknown.

`tools/import_absorption.gd` reads CSV wavelength_nm,ordinary[,extraordinary] plus
JSON quantity/optical_basis/citation/method. It converts Napierian or decadic
coefficients (/mm,/cm,/m), internal transmittance or decadic absorbance to α/mm
before coefficient-space interpolation. Transmission/absorbance requires path_mm
and explicit removal of interface and scattering losses. Saturated zero,
negative/nonfinite data, unordered wavelengths and incomplete spectral coverage
are rejected. Raw CSV SHA256 and interpretation metadata are retained beside the
resource and in its evidence. Importing data is not certification of its origin.
Material validation also rejects invalid concentration, visible Sellmeier poles,
unsupported model range and invalid scattering. Signed Sellmeier terms are
consistent on CPU/GPU; invalid n² is not silently repaired.

`GemSpecies.ordinary` and optional `extraordinary` are independent
`GemIndexCurve` resources with float64 B/C coefficients, explicit index offset,
valid domain and per-axis evidence. Null extraordinary means isotropic real
refraction. The offset is an authored approximation, never an inferred grade or
birefringence law. The current analytic backend accepts three Sellmeier terms;
an additive n² constant uses C=0. GPU coefficients are packed to float32.
Quartz uses Ghosh o/e curves and sapphire uses Malitson/Dodge o/e curves from
refractiveindex.info, with original formula coefficients/units retained in the
evidence. Other anisotropic catalog axes remain explicitly authored constant
offsets; the biaxial approximations are not full biaxial models.
`GemMaterialCompiler.polarization_error` checks all visible integer wavelengths,
so curves crossing at a single reference wavelength cannot bypass its gate.
This discrete policy check is not a proof for arbitrary sub-nanometer features.
The scalar o/e approximation evaluates both principal spectra at the traced
wavelengths but still ignores walk-off/mode conversion and uses ordinary Fresnel
weights. Default splitting threshold .015 still skips weak anisotropy, including
quartz/corundum. The independent Maxwell CPU/GPU probes consume their true
principal curves; accurate anisotropic production transport is not yet enabled.
`test_principal_indices.gd` checks independent published values and serialization;
`principal_indices_gpu_check.gd` probes the exact packing/GLSL at 0.25 nm spacing.

## Spatial coefficient fields (48B, binding7)

GemCondition.volume_fields defines at most16 additive, smooth fields in physical
host-space millimeters. Each record is three vec4s: center.xyz/absorption amplitude,
ellipsoid radii.xyz/scattering amplitude per mm, unit quaternion xyzw. Density is
max(0,1−r²)^3; the value and first two derivatives vanish at its finite boundary.
There is no refractive surface there. Host priority regions still control where
material exists; a field never fills a cavity or changes silhouette.

Absorption adds the field's concentration times the host absorption spectrum.
Scattering adds the field coefficient to homogeneous σ_s, using the host HG phase
function. This is an authored effective-medium model for spatial haze and color
variation. It does not represent resolved crystals, polarized silk, stress,
crystal-growth mechanics, or a calibrated clarity grade. No catalog grade enables
these fields automatically.

Restricting a field to a ray gives a degree-six polynomial over a clipped chord.
Four-point Gauss-Legendre integrates that polynomial exactly apart from floating
point rounding, with positive weights to avoid grazing cancellation. Reference:
https://dlmf.nist.gov/3.5#v . Integrated σ_s is inverted with a safeguarded Newton/
bisection solver (32 iterations, optical-depth residual target2e-6). Homogeneous
media retain the analytic exponential inverse. Field geometry is cached per
sampled segment. Transport uses the same integrated coefficients for Beer-Lambert
and zero-scatter reconstruction. The relevant transmittance/free-flight framework
is https://pbr-book.org/4ed/Light_Transport_II_Volume_Rendering/The_Equation_of_Transfer .

`test_volume_fields.gd` compares columns to independent midpoint quadrature;
`volume_gpu_check.gd` checks the actual GLSL collision sampler against independent
CPU integrals and tests full heterogeneous transport. `volume_lookdev.gd` compares
raw/reconstructed low-SPP renders to high-SPP transport at multiple poses.

## Optional persistent polarization

Policy `polarization=true` lazily compiles a separate variant of the same boundary
transport source. It forces independent wavelength geometry. The scalar variant
compiles away the extra state. The variant currently requires isotropic **real
refraction** in every host/filling. Axial weak-loss absorption is supported with
persistent polarization; birefringent refraction remains rejected by its
precondition. Existing catalog policies remain scalar pending broader
anisotropic transport. The REFERENCE rung alone does not enable polarization.

Per-wavelength camera importance is a row of a Mueller product plus an explicit
transverse basis for physical light propagation opposite the camera ray. Every
reflection/refraction changes reference frames and retains I/Q/U/V, including TIR
phase. Index ratios for physical transmission are reversed relative to the camera
path; radiance eta-squared factors remain explicit. The shared boundary solver
still handles priority regions, cavities, GGX finish and deterministic escape.
The effective scalar HG model is explicitly treated as an ideal depolarizer; this
is not a prediction of a particle population's polarized scattering matrix.

For axial absorption, the ordinary transverse direction is perpendicular to the
optic-axis/ray plane. The other transverse component has
`alpha_k=cos(phi)^2*alpha_o+sin(phi)^2*alpha_e` for the supported isotropic real
index. Each segment applies the rotated diattenuation Mueller operator to the
existing importance state. It never resets that state to an equal mixture.
Zoning and compact absorption fields use their exact integrated optical columns.
Admission limits peak `kappa/n` to 0.001 for this dichroic approximation, including
a conservative sum of field concentrations and zoning amplitude. This bound is
an implementation policy, not a guaranteed error near all critical angles.
Complex-index interface changes and causally coupled dispersion are not modeled.

`GemPolarization` supplies float64 CPU reference mathematics. The optional tooling
pins Mitsuba3.9.1/DrJit1.5.0 and compares elementary and rotated matrices, plus actual
GPU products through refractive/TIR interface chains. Exact index matching is
checked against the identity law separately: Mitsuba's float32 grazing flux
conversion loses precision in that degenerate case, which the reports retain.
See https://mitsuba.readthedocs.io/en/stable/src/key_topics/polarization.html and
https://github.com/mitsuba-renderer/mitsuba3/tree/v3.9.1/include/mitsuba/render .
This validates isotropic polarization operations; it does not validate anisotropic
ray direction, birefringent retardation, biaxial materials or mineral measurements.


## Uniaxial Maxwell model and optional transport

`GemCrystalModes` solves ordinary/extraordinary wavevectors at a boundary from
conserved tangential phase and the uniaxial dispersion metric. It stores complex
E/H fields, wave-normal direction and Poynting energy direction separately.
Evanescent modes decay into the selected half-space and carry no normal flux.
`GemCrystalInterface` solves four tangential field-continuity equations for two
reflected and two transmitted amplitudes. It is a forward flux operator for
lossless smooth media. The explicit GPU backend below composes these operators
for reciprocal camera paths with unpolarized illumination and air endpoints.
`GemCrystalPacket` recombines coincident isotropic modes as complex fields and
keeps separated crystal modes distinct. Its field amplitudes and normal-flux
probabilities are different quantities; a renderer must normalize its state and
apply a sampled branch's weight once. `GemCrystalMeasure` implements curvature
of the wavevector ellipsoid and forward/camera radiance conversions from
[Lax & Nelson (1975)](https://doi.org/10.1364/JOSA.65.000668).
The camera factor reduces to `(n_current/n_next)^2` in isotropic media.
`GemCrystalLoss` derives weak-loss eigenmode attenuation from Poynting dissipation
and the principal imaginary permittivity tensor. An independent full complex
4x4 Maxwell eigenproblem checks its rate, including decreasing-loss convergence.
General biaxial media, anisotropic scattering and strong-loss interfaces remain
unsupported. These mathematical components alone do not establish full rendering
accuracy; the backend's restricted admission and validation are described below.

The modal construction is grounded in Thomson, Wilen & Wettlaufer (2009),
[Light scattering from an isotropic layer between uniaxial crystals](https://arxiv.org/abs/0901.2558),
and the rendering problem is discussed by
[Weidlich & Wilkie, Realistic Rendering of Birefringency in Uniaxial Crystals](https://cgg.mff.cuni.cz/wp-content/uploads/2021/05/weidlich_2007_rrbuc-paper.pdf).
The implementation uses dispersion tensors and a numerical complex boundary solve,
not copied closed-form Fresnel expressions. Optional NumPy checks independently
diagonalize the tangential Maxwell propagation matrix, then compare interface
elimination to LAPACK. These validate the synthetic field solver, not catalog
material measurements or a completed anisotropic gemstone renderer.


Authoring note: `scatter_zone.z` remains the normalized angular frequency divided
by PI. `GemBanding.period_mm` compiles to `2*size_mm/period_mm`; physical band
spacing therefore stays fixed when the host's normalization changes. The phase
is explicit specimen data. Grade labels and species metadata do not modulate
scattering or band contrast.

`gem_crystal.glsl` ports the mode and complex interface field solve to float32.
`tools/crystal_gpu_check.gd` compares actual GPU outputs against float64 CPU fields
for rotated boundaries, including evanescent output modes. `GemCrystalShader`
compiles the same source as float64 for the explicit crystal backend. Input
stress cases now include near-critical and optic-axis degeneracy. Comparing
arbitrary basis amplitudes there is insufficient: the probe supplies the same
incident complex field to both solvers and also checks summed boundary fields
and reflected/transmitted power. The float32 variant **fails** the current stress
gate (up to about 0.0015 side-power error and 0.0028 field-component error on the
tested device). `--stress --fp64` runs a diagnostic double-precision variant of
the same source, retaining float32 wire inputs/outputs. The expanded 1,352-case gate
includes published principal curves, phase-rotated eigenmodes and elliptical
isotropic incident packets. Both this diagnostic and crystal rendering
require shaderFloat64; prebuilt game assets do not. Selective precision and broader
transport validation must precede default promotion. Near-axis basis labels alone
are not accuracy metrics.

CPU packet tests independently differentiate the ray solid-angle map, check
modal reciprocity, and export 64 five-interface chains with elliptical input and
three oriented TIR events. `check_crystal_packet_reference.py` checks all four
Stokes components against Mitsuba, separately for raw electric fields and
normal-flux normalization. The export's circular-polarization convention is
`V=2*Im(Eu*conj(Ev))`. This catches phase loss during coherent recombination; it
does not validate a complete birefringent render or coherent interference of
spatially separated paths that later overlap.

### Explicit `crystal_transport=true` quality policy

`gem_crystal_path.glsl` launches two orthogonal Jones probes per wavelength.
Uniaxial interfaces conserve tangential wavevector, solve complex tangential E/H
continuity, and propagate along Poynting directions. Coincident isotropic modes
retain coherent complex fields; separated eigenmodes are distinct geometric paths.
All branches proven to escape into the analytic rig are evaluated immediately;
one remaining branch is sampled by its normal-flux power. No intensity or phase
is duplicated when recombining a packet. The reciprocal air-to-air construction
uses telescoping ray-measure factors; it is not an emitter-inside-crystal API.

Admission rejects homogeneous/spatial scattering, rough boundaries and peak
imaginary/real index ratios above 0.001. Weak-loss eigenmode absorption and
coherent isotropic dichroism integrate authored banding and concentration columns.
Biaxial refraction, spatially separated interference, rough microfacets and
anisotropic particle scattering are not supported. Catalog effective-uniaxial
approximations remain approximations even in this backend. Defaults remain scalar;
`polarization=true` and `crystal_transport=true` are mutually exclusive.

Wire geometry remains float32. Persistent crystal ray positions, intersections,
fields and interface elimination use float64. The geometry source is generated
from the shared mesh/analytic/region algorithms with a 1e-10 normalized intersection
epsilon and 4e-10 offsets. Primary silhouette sampling still uses the common
float32 coverage path. This fixed epsilon does not certify arbitrarily small or
coincident features. Do not silently fall back to float32 on unsupported devices.

Binding18 is a 16-byte uint diagnostics buffer: invalid-path count, bounce-limit
count, failure bits (1 missing interior boundary; 2 invalid Maxwell solve/residual;
4 interface power imbalance), and float32 bits of the largest **failed** power
imbalance. Healthy-interface maxima are not collected. Invalid paths prevent
factory publication; finite-bounce truncations are reported in master metadata.
Checkpoints retain diagnostics, and failed checkpoints cannot be resumed.

`crystal_transport_check.gd` covers lossless isotropic/uniaxial slabs, analytic
absorbing o/e slabs, faceted/analytic/mesh/nested-region furnace renders, checkpoint
restoration and a complete isotropic comparison with the Mueller renderer under
directional studio lighting. This is reference-quality, currently expensive work;
it is not a claim of general anisotropic convergence or measured catalog realism.

The fixed-size interface solve uses partial-pivot forward elimination and back
substitution. When every output mode propagates, its lossless basis fields are
real, so a real 4x4 matrix solves the two real/imaginary RHS components. Any
evanescent output uses the full complex matrix; elliptical incident polarization
is retained in both paths. Interface axes are normalized once. Continuing-branch
storage holds mode indices, combination flags and powers; only the selected
packet is normalized and retained. These are algebra/storage optimizations, not
lower precision or a changed branch estimator. Optional `crystal_benchmark.gd`
compares saved baseline sources with current code using warmed repeated renders
and complete linear-image differences. Performance remains device/scene dependent.
