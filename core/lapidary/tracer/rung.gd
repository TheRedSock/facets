class_name GemRung
extends RefCounted
## Quality rungs: one kernel, policy objects. Feature flags live HERE
## (plus species hints), never on stones. A T1 must still look included
## and milky at INTERACT — rungs simplify HOW, not WHETHER.

enum { INTERACT, PREVIEW, BOARD_LIVE, CLIP_BAKE, HERO }

# res: internal render size. out: delivered size. spp: total target
# (progressive rungs accumulate toward it; the tracer chunks dispatches
# adaptively for TDR safety, `batch` is the caller's accumulate granularity).
# field_exits: hull-hit budget per direction inside the per-frame SH scatter
#   field; a path ends at its scatter event and reads the field (0 = field
#   off: stochastic HG continuation, the physics check's reference).
# field_grid / field_dirs: scatter-field texels per axis / quadrature
#   directions per texel (pre-pass cost ~ grid^3 * dirs * mean chain length;
#   the field is rebuilt per orientation). Measured print-space error vs an
#   8192-direction reference on the milkiest stone (quartz): grid 32 / 2048
#   dirs 0.29 LSB, 32 / 1024 0.44, 24 / 1024 0.47, 16 / 1024 0.61, 32 / 256
#   0.84 (tools/grain_check.gd covers the residual sampling grain).
# env_filter_rad: angular footprint floor (radians) for the environment seen
#   from inside the field pre-pass (and by field-off post-scatter chains).
const TABLE := {
	INTERACT: {
		"res": 128, "out": 128, "spp": 8, "batch": 1, "max_bounces": 16,
		"dispersion": false, "birefringence": false, "volume": true,
		"rad_clamp": 64.0, "env_filter_rad": 0.25,
		"field_exits": 12, "field_grid": 12, "field_dirs": 256,
	},
	PREVIEW: {
		"res": 256, "out": 256, "spp": 48, "batch": 8, "max_bounces": 24,
		"dispersion": true, "birefringence": true, "volume": true,
		"rad_clamp": 96.0, "env_filter_rad": 0.25,
		"field_exits": 24, "field_grid": 24, "field_dirs": 512,
	},
	BOARD_LIVE: {
		"res": 112, "out": 112, "spp": 12, "batch": 8, "max_bounces": 12,
		"dispersion": false, "birefringence": false, "volume": true,
		"rad_clamp": 64.0, "env_filter_rad": 0.25,
		"field_exits": 12, "field_grid": 12, "field_dirs": 256,
	},
	CLIP_BAKE: {
		# 224→112: 2×2 supersample AA. Scattering is deterministic (scatter
		# field); residual variance is facet-edge coverage, the scatter /
		# pass-through decision and later inclusion Bernoullis only.
		"res": 224, "out": 112, "spp": 96, "batch": 16, "max_bounces": 32,
		"dispersion": true, "birefringence": true, "volume": true,
		"rad_clamp": 128.0, "env_filter_rad": 0.25,
		"field_exits": 32, "field_grid": 24, "field_dirs": 1024,
	},
	HERO: {
		"res": 768, "out": 768, "spp": 256, "batch": 8, "max_bounces": 48,
		"dispersion": true, "birefringence": true, "volume": true,
		"rad_clamp": 100000.0, "env_filter_rad": 0.25,
		"field_exits": 48, "field_grid": 32, "field_dirs": 2048,
	},
}


static func policy(rung: int) -> Dictionary:
	return TABLE[rung].duplicate()


static func rung_name(rung: int) -> String:
	return ["interact", "preview", "board_live", "clip_bake", "hero"][rung]
