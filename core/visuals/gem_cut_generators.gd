class_name GemCutGenerators
extends RefCounted

## Public facade for procedural gem cut generation.
##
## Shared geometry math lives in `GemCutPrimitives`, reusable facet topology lives
## in `GemCutBuilders`, and per-cut tuning lives in `GemCutProfiles`.

const GemCutBuilders = preload("res://core/visuals/gem_cut_builders.gd")
const GemCutProfiles = preload("res://core/visuals/gem_cut_profiles.gd")


# ===========================================================================
#  Factory
# ===========================================================================


static func generate(cut_id: StringName) -> GemCutResource:
	match cut_id:
		&"classic_round":
			return GemCutBuilders.build_radial_brilliant(GemCutProfiles.classic_round())
		&"old_european_round":
			return GemCutBuilders.build_radial_brilliant(GemCutProfiles.old_european_round())
		&"cushion":
			return GemCutBuilders.build_radial_brilliant(GemCutProfiles.cushion())
		&"heart_brilliant":
			return GemCutBuilders.build_radial_brilliant(GemCutProfiles.heart_brilliant())
		&"trillion":
			return GemCutBuilders.build_fan_cut(GemCutProfiles.trillion())
		&"straight_trillion":
			return GemCutBuilders.build_fan_cut(GemCutProfiles.straight_trillion())
		&"radiant_diamond":
			return GemCutBuilders.build_radiant_cut(GemCutProfiles.radiant_diamond())
		&"princess_square":
			return GemCutBuilders.build_radiant_cut(GemCutProfiles.princess_square())
		&"radiant_octagon":
			return GemCutBuilders.build_radiant_cut(GemCutProfiles.radiant_octagon())
		&"hex_brilliant":
			return GemCutBuilders.build_radial_brilliant(GemCutProfiles.hex_brilliant())
		&"pentagon_brilliant":
			return GemCutBuilders.build_radial_brilliant(GemCutProfiles.pentagon_brilliant())
		&"emerald_step":
			return GemCutBuilders.build_step_cut(GemCutProfiles.emerald_step())
		&"asscher_step":
			return GemCutBuilders.build_step_cut(GemCutProfiles.asscher_step())
		&"octagon_step":
			return GemCutBuilders.build_step_cut(GemCutProfiles.octagon_step())
		&"baguette_step":
			return GemCutBuilders.build_step_cut(GemCutProfiles.baguette_step())
		&"tapered_baguette_step":
			return GemCutBuilders.build_step_cut(GemCutProfiles.tapered_baguette_step())
		&"oval_brilliant":
			return GemCutBuilders.build_radial_brilliant(GemCutProfiles.oval_brilliant())
		&"marquise_brilliant":
			return GemCutBuilders.build_radial_brilliant(GemCutProfiles.marquise_brilliant())
		&"pear_brilliant":
			return GemCutBuilders.build_radial_brilliant(GemCutProfiles.pear_brilliant())
		&"rose_round":
			return GemCutBuilders.build_rose_cut(GemCutProfiles.rose_round())
		&"half_dutch_rose_hex":
			return GemCutBuilders.build_rose_cut(GemCutProfiles.half_dutch_rose_hex())
		&"double_rose":
			return GemCutBuilders.build_rose_cut(GemCutProfiles.double_rose())
		&"cross_rose":
			return GemCutBuilders.build_rose_cut(GemCutProfiles.cross_rose())
	push_warning("GemCutGenerators: Unknown cut_id '%s'" % str(cut_id))
	return null
