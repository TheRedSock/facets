class_name GemPrint
extends Resource
## The house print: publishing/mastering transform applied to finished frames
## (baked clips AND live draws — same print). It is not the gem, not the
## grade, not the lighting. Grade cues must survive it; the evaluation
## harness A/Bs raw vs print on every sheet.

@export var print_version := 1

@export_group("Tone")
@export var exposure := 1.0
## Sprite tonescale: toe lift keeps board black-point readable,
## shoulder rolls highlights off without bleaching absorption color.
@export var toe := 0.02
@export var shoulder_strength := 0.85
@export var contrast := 1.05
@export var black_point := 0.012

@export_group("Chroma")
## OKLCh-space chroma ceiling with soft rolloff (forbidden-neon governor).
@export var chroma_ceiling := 0.34
@export var chroma_soft := 0.10
## Desaturate only where luminance clips (keeps fire from going white mush).
@export var highlight_desat := 0.35

@export_group("Print bloom")
## Micro-bloom as PRINT (readability at 112px), never as fake brilliance.
@export var bloom_threshold := 0.80
@export var bloom_strength := 0.12
@export var bloom_radius_px := 2.0

@export_group("House policies (reach back into tracer config; versioned here)")
## Roughness floor at sprite rungs so polish never aliases into single-pixel fireflies.
@export var sprite_roughness_floor := 0.015
## Minimum key angular radius (deg) so facet gradients survive 112px.
@export var key_angular_floor_deg := 10.0

@export_group("Exceptions")
## Rare, justified per-family deltas: [{selector:String, deltas:Dictionary, reason:String}].
## Empty reason = validation failure. Kept as data here, never as per-stone knobs.
@export var exceptions: Array[Dictionary] = []


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for e in exceptions:
		if String(e.get("reason", "")).strip_edges().is_empty():
			errors.append("Print exception without a written reason: %s" % str(e.get("selector", "?")))
	return errors
