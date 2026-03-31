extends Node

signal visual_flags_changed

var protection_threshold := 5
var active_rule_pack := &"baseline"

## Gem rendering toggles
var _gem_silhouette_outline := true
var gem_silhouette_outline: bool:
	get:
		return _gem_silhouette_outline
	set(value):
		if _gem_silhouette_outline == value:
			return
		_gem_silhouette_outline = value
		visual_flags_changed.emit()

var _gem_low_detail_gameplay := false
var gem_low_detail_gameplay: bool:
	get:
		return _gem_low_detail_gameplay
	set(value):
		if _gem_low_detail_gameplay == value:
			return
		_gem_low_detail_gameplay = value
		visual_flags_changed.emit()

## Runtime override for outline width. Negative value means use the default runtime width.
var _gem_outline_width_override := -1.0
var gem_outline_width_override: float:
	get:
		return _gem_outline_width_override
	set(value):
		if is_equal_approx(_gem_outline_width_override, value):
			return
		_gem_outline_width_override = value
		visual_flags_changed.emit()
