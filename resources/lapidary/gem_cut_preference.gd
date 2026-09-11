class_name GemCutPreference
extends Resource
## Explicit design utility, not physical law or a gemological cut grade.
## Return ratios use the study's baseline specimen under identical scenarios.
@export var mean_return_weight:=.5
@export var worst_return_weight:=.2
@export var dark_area_weight:=.15
@export var contrast_weight:=.05
@export var modulation_weight:=.1
@export var target_contrast_cv:=.7
@export var minimum_mean_return_ratio:=.8
@export var maximum_dark_fraction:=.8
@export var relative_dark_threshold:=.2
@export_multiline var source_note:="Illustrative engineering preference; no gemological calibration."

func validate()->PackedStringArray:
	var errors:=PackedStringArray();var total:=0.0
	for weight in [mean_return_weight,worst_return_weight,dark_area_weight,contrast_weight,modulation_weight]:
		if not is_finite(weight) or weight<0:errors.append("Preference weights must be finite and nonnegative")
		total+=weight
	if not is_finite(total) or total<=0:errors.append("Preference needs positive total weight")
	if not is_finite(target_contrast_cv) or target_contrast_cv<=0:errors.append("Contrast target must be positive")
	if not is_finite(minimum_mean_return_ratio) or minimum_mean_return_ratio<0:errors.append("Return floor must be finite and nonnegative")
	if not is_finite(maximum_dark_fraction) or maximum_dark_fraction<0 or maximum_dark_fraction>1:errors.append("Dark-area limit must be in 0..1")
	if not is_finite(relative_dark_threshold) or relative_dark_threshold<=0 or relative_dark_threshold>=1:errors.append("Dark threshold must be in (0,1)")
	return errors

func describe()->Dictionary:
	return {"weights":{"mean_return":mean_return_weight,"worst_return":worst_return_weight,"dark_area":dark_area_weight,"contrast":contrast_weight,"modulation":modulation_weight},
		"target_contrast_cv":target_contrast_cv,"minimum_mean_return_ratio":minimum_mean_return_ratio,"maximum_dark_fraction":maximum_dark_fraction,
		"relative_dark_threshold":relative_dark_threshold,"source_note":source_note}
