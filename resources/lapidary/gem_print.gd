class_name GemPrint
extends Resource
## The house print: publishing/mastering transform applied to finished frames
## (baked clips AND live draws — same print). It is not the gem, not the
## grade, not the lighting. Grade cues must survive it; the evaluation
## harness A/Bs raw vs print on every sheet.
##
## Sprite readability policies (edge rounding, env filter) live on GemRung,
## not here. Bloom is not implemented — do not author bloom_* fields.

const HOUSE_PATH := "res://data/lapidary/print/house_print.tres"

@export var print_version := 1

@export_group("Tone")
@export var exposure := 1.0
## Hue-preserving sprite tonescale (max-RGB extended Reinhard): the shoulder
## rolls highlights off without bleaching absorption colour; contrast is
## applied about mid-grey. black_point is an optional board floor (0 = none;
## any lift reads as "brightness turned up in post").
@export var shoulder_strength := 0.85
@export var contrast := 1.05
@export var black_point := 0.0

@export_group("Chroma")
## OKLCh-space chroma ceiling with soft rolloff (forbidden-neon governor).
@export var chroma_ceiling := 0.34
@export var chroma_soft := 0.10
## Desaturate only where luminance clips (keeps fire from going white mush).
@export var highlight_desat := 0.35

## Authoritative house print. Hard-fails if the resource is missing.
static func load_house() -> GemPrint:
	assert(ResourceLoader.exists(HOUSE_PATH),
		"GemPrint.load_house: missing %s — author data/lapidary/print/house_print.tres" % HOUSE_PATH)
	var p := load(HOUSE_PATH) as GemPrint
	assert(p != null, "GemPrint.load_house: failed to load %s" % HOUSE_PATH)
	return p


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["exposure", "shoulder_strength", "contrast", "black_point", "chroma_ceiling", "chroma_soft", "highlight_desat"]:
		var value: float = get(key)
		if not is_finite(value) or value < 0 or value > 1e10:
			errors.append("Print %s must be finite and nonnegative" % key)
	if contrast <= 0 or chroma_soft <= 0:
		errors.append("Print contrast and chroma softness must be positive")
	if highlight_desat > 1 or black_point > 1:
		errors.append("Print highlight desaturation and black point must be in [0, 1]")
	return errors
