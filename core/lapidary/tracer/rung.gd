class_name GemRung
extends RefCounted
## Policies select numerical work, not specimen properties. Production uses
## repeated scattering with optional variance-guided residual reconstruction.
## The zero-scatter light remains sharp. SH continuation is disabled after
## failing error/cost comparisons. REFERENCE keeps the unfiltered estimator.
## Anisotropic transport remains approximate, including in REFERENCE.
enum { INTERACT, PREVIEW, BOARD_LIVE, CLIP_BAKE, HERO, REFERENCE }

const TABLE := {
	INTERACT: {
		"res": 128, "out": 128, "spp": 16, "batch": 1, "max_bounces": 64,
		"dispersion": false, "spectral_geometry": "selective",
		"birefringence": false, "volume": true, "rad_clamp": 100000.0,
		"env_filter_rad": 0.0, "field_exits": 0,
		"denoise_passes": 3, "denoise_phi": 2.0,
	},
	PREVIEW: {
		"res": 256, "out": 256, "spp": 128, "batch": 8, "max_bounces": 128,
		"dispersion": true, "spectral_geometry": "full",
		"birefringence": true, "volume": true, "rad_clamp": 100000.0,
		"env_filter_rad": 0.0, "field_exits": 0,
		"denoise_passes": 3, "denoise_phi": 2.0,
	},
	BOARD_LIVE: {
		"res": 112, "out": 112, "spp": 16, "batch": 1, "max_bounces": 64,
		"dispersion": false, "spectral_geometry": "selective",
		"birefringence": false, "volume": true, "rad_clamp": 100000.0,
		"env_filter_rad": 0.0, "field_exits": 0,
		"denoise_passes": 3, "denoise_phi": 2.0,
	},
	CLIP_BAKE: {
		"res": 224, "out": 112, "spp": 128, "batch": 16, "max_bounces": 128,
		"dispersion": true, "spectral_geometry": "full",
		"birefringence": true, "volume": true, "rad_clamp": 100000.0,
		"env_filter_rad": 0.0, "field_exits": 0,
		"denoise_passes": 3, "denoise_phi": 2.0,
	},
	HERO: {
		"res": 768, "out": 768, "spp": 256, "batch": 8, "max_bounces": 256,
		"dispersion": true, "spectral_geometry": "full",
		"birefringence": true, "volume": true, "rad_clamp": 100000.0,
		"env_filter_rad": 0.0, "field_exits": 0,
		"denoise_passes": 3, "denoise_phi": 2.0,
	},
	REFERENCE: {
		"throughput_epsilon": 0.000001,
		"res": 512, "out": 512, "spp": 4096, "batch": 16, "max_bounces": 1024,
		"dispersion": true, "spectral_geometry": "full",
		"birefringence": true, "volume": true, "rad_clamp": 1.0e20,
		"env_filter_rad": 0.0, "field_exits": 0,
		"denoise_passes": 0, "denoise_phi": 2.0,
	},
}

static func policy(rung: int) -> Dictionary:
	return TABLE[rung].duplicate()

static func rung_name(rung: int) -> String:
	return ["interact", "preview", "board_live", "clip_bake", "hero", "reference"][rung]
