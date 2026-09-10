# Lapidary kernel contract (v12)

This is the CPU/GPU interface for offline workers and Atelier previews. The game
loads prebuilt assets and does not instantiate the optical renderer. All floats
are float32, std430. Stone space has the girdle at z=0, crown toward +Z, and unit
girdle radius. `size_mm` converts one stone-space unit into millimeters. The
orthographic camera looks down world −Z; instance quaternions rotate stone→world.

## Geometry and material state

A Plane is two vec4s (32B): outward normal.xyz/offset d, then zone ID/reserved3.
The host interior obeys dot(n,x)<=d. Zone IDs: 0 table, 1 crown main/star,
2 upper girdle, 3 girdle, 4 pavilion main, 5 lower girdle, 6 culet, 7 step row.
They identify cut structure, not surface finish.

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

## Stone (128B)

| vec4 | Contents |
|---|---|
| 0 | Sellmeier B.xyz, size_mm |
| 1 | Sellmeier C.xyz in µm², signed birefringence Δn |
| 2 | scattering σ_s/mm, HG g, zoning frequency, zoning contrast |
| 3 | zoning axis.xyz, phase |
| 4 | optic axis.xyz, fluorescence strength (disabled) |
| 5 | fluorescence nm (disabled), absorb_scale, nested_volume_present, rough_present |
| ivec4 6 | plane_offset, plane_count, volume_field_offset, volume_field_count |
| ivec4 7 | absorb_offset, flags, bvh_root_plus_one, region_offset |

Flags: bit0 has_eray, bit1 dispersion_strong. BVH selector0 is convex planes,
-1 analytic host without mesh, positive root+1 supports triangle host/defects.
Absorption concatenates 401-sample Napierian α/mm blocks, 380..780 nm at1nm. An e-ray
block follows its o-ray block directly (offset+401). Source resources may use
a different uniform grid, but must cover the transport interval. No implicit
extrapolation or normalization of material absorption is allowed. Concentration is already applied.

Current anisotropy is an approximation: α_k=cos²φ α_o+sin²φ α_e; the unpolarized
segment uses (T_o+T_k)/2. Optional o/e fork occurs above |Δn|=.015, with effective
index 1/n_e(φ)²=cos²φ/n_o²+sin²φ/n_e². There is no persistent polarization frame,
full anisotropic interface solver or biaxial transport. REFERENCE does not fix
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
realized millimeter-scale defects and host finish. GemGrade remains a legacy cut/
haze recipe, not a calibrated gemological grade. Automatic clarity and surface
recipes are disabled. Explicit fractures have not passed low-SPP visual acceptance.
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
consistent on CPU/GPU; invalid n² is not silently repaired on the CPU.

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
