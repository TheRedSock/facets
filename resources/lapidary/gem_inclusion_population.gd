class_name GemInclusionPopulation
extends Resource
## A bounded statistical population in a shared host-crystal domain. This is
## authored morphology, not inferred geology or an automatic clarity grade.
@export var population_id: StringName
@export var seed := 1
@export_range(0,127) var count := 8
## C2 ellipsoidal density in host-crystal coordinates (millimeters). A thin
## domain can describe a growth layer; isotropic scattering is not added.
@export var domain: GemVolumeField = GemVolumeField.new()
@export var habit: GemCrystalHabit = GemCrystalHabit.new()
@export var filling: GemMaterial
@export var finish: GemSurface = GemSurface.new()
## Uniform size range preserves habit face angles. Samples are log-uniform.
@export var scale_range := Vector2(.7,1.3)
## Crystal-local -> host-crystal orientation families, equally weighted.
@export var orientation_families: Array[Quaternion] = [Quaternion.IDENTITY]
@export_range(0,45) var angular_spread_deg := 2.0
## Conservative bounding-sphere gap within this population, in millimeters.
## Zero still prevents overlap. Separate populations retain authored priority.
@export var minimum_gap_mm := .01
@export_multiline var source_note := "Authored correlated population; no species or geological provenance claim."

func validate()->PackedStringArray:
	var errors:=PackedStringArray()
	if String(population_id).strip_edges().is_empty() or seed<0 or seed>0x7fffffff or count<0 or count>127:
		errors.append("Population needs a stable ID, 31-bit seed and 0..127 members")
	if domain==null:errors.append("Population domain is missing")
	else:
		errors.append_array(domain.validate())
		if domain.profile!=GemVolumeField.Profile.COMPACT_ELLIPSOID or domain.scatter_per_mm!=0 or domain.absorption_concentration!=0 or not domain.absorbers.is_empty():
			errors.append("Resolved population domains specify placement only; no simultaneous effective-medium coefficients")
	if habit==null:errors.append("Population habit is missing")
	else:errors.append_array(habit.validate())
	if filling!=null:errors.append_array(filling.validate())
	if finish!=null:errors.append_array(finish.validate())
	if not scale_range.is_finite() or scale_range.x<1e-4 or scale_range.y<scale_range.x or scale_range.y>1000:
		errors.append("Population uniform scale range must be ordered in 1e-4..1000")
	if orientation_families.is_empty() or orientation_families.size()>64:errors.append("Population needs 1..64 orientation families")
	for q in orientation_families:
		if not q.is_finite() or absf(q.length_squared()-1)>1e-5:errors.append("Population orientation families must be unit quaternions")
	if not is_finite(angular_spread_deg) or angular_spread_deg<0 or angular_spread_deg>45 or not is_finite(minimum_gap_mm) or minimum_gap_mm<0 or minimum_gap_mm>10000:
		errors.append("Invalid angular spread or physical separation")
	return errors
