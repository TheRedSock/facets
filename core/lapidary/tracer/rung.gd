class_name GemRung
extends RefCounted
## Quality rungs: one kernel, policy objects. Feature flags live HERE
## (plus species hints), never on stones. A T1 must still look included
## and windowed at INTERACT — rungs simplify HOW, not WHETHER.

enum { INTERACT, PREVIEW, BOARD_LIVE, CLIP_BAKE, HERO }

const VOLUME_OFF := 0
const VOLUME_SINGLE := 1
const VOLUME_FULL := 2

# res: internal render size. out: delivered size. spp: total target
# (progressive rungs accumulate toward it in `batch`-sized dispatches).
const TABLE := {
	INTERACT: {
		"res": 128, "out": 128, "spp": 4, "batch": 1, "max_bounces": 16,
		"dispersion": false, "birefringence": false, "volume": VOLUME_SINGLE,
		"rad_clamp": 8.0,
	},
	PREVIEW: {
		"res": 256, "out": 256, "spp": 32, "batch": 8, "max_bounces": 24,
		"dispersion": true, "birefringence": true, "volume": VOLUME_FULL,
		"rad_clamp": 24.0,
	},
	BOARD_LIVE: {
		"res": 112, "out": 112, "spp": 8, "batch": 8, "max_bounces": 12,
		"dispersion": false, "birefringence": false, "volume": VOLUME_SINGLE,
		"rad_clamp": 8.0,
	},
	CLIP_BAKE: {
		"res": 224, "out": 112, "spp": 160, "batch": 32, "max_bounces": 32,
		"dispersion": true, "birefringence": true, "volume": VOLUME_FULL,
		"rad_clamp": 48.0,
	},
	# HERO batch stays small: a 64-spp dispatch at 768px trips the Windows GPU
	# watchdog (TDR ~2s) and device-loses Vulkan. Chunk, never bulk.
	HERO: {
		"res": 768, "out": 768, "spp": 512, "batch": 8, "max_bounces": 48,
		"dispersion": true, "birefringence": true, "volume": VOLUME_FULL,
		"rad_clamp": 100000.0,
	},
}

## Species hints may raise spp (scatter-noisy minerals), never lower physics.
## "Noisy" is compiled σ_s (T1 quartz haze ~0.25/mm), not the species base.
const SCATTER_NOISY_SIGMA := 0.12

static func scatter_noisy(instance: Dictionary) -> bool:
	var scat: Dictionary = instance.get("scatter", {})
	return float(scat.get("sigma_per_mm", 0.0)) > SCATTER_NOISY_SIGMA


static func policy(rung: int, species_scatter_noisy := false) -> Dictionary:
	var p: Dictionary = TABLE[rung].duplicate()
	if species_scatter_noisy and rung >= PREVIEW:
		# CLIP_BAKE/HERO: quartz at 160 spp is still sandy; 3x (~480) was the
		# first usable stop on the spp ladder. Preview stays a lighter 1.5x.
		var mul := 3.0 if (rung == CLIP_BAKE or rung == HERO) else 1.5
		p["spp"] = int(round(float(p["spp"]) * mul))
	return p


static func rung_name(rung: int) -> String:
	return ["interact", "preview", "board_live", "clip_bake", "hero"][rung]
