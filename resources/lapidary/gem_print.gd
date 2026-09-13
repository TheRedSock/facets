class_name GemPrint
extends Resource
## Display mastering settings, independent of transport and grade labels.
## LINEAR XYZ is read through GemTracer.read_xyz/read_linear_master, not encoded.
enum View { HOUSE_PRINT, DISPLAY_PREVIEW }

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
## Oklab chroma ceiling before hue/lightness-preserving sRGB gamut mapping.
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
