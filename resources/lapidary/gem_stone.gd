class_name GemStone
extends Resource
## The instance format. This is what a tile references and what BOTH board
## consumers (sprite clips, live 3D) are fed. Everything else is derived.

@export var stone_id: StringName        # == tile_id (t1_quartz ... t8_diamond)
@export var species: GemSpecies
@export var chromophore: GemChromophore # null = colorless
@export var cut: Resource               # GemCutTemplate (owned by core/lapidary/cut/)
## Silhouette from the gameplay taxonomy (round/oval/square/triangle/diamond/
## rectangle/marquise/pear). Tile readability language, unchanged.
@export var silhouette: StringName = &"round"
@export var grade: GemGrade
## Deterministic seed: inclusions, wear and jitter are stable across
## preview, bake and replays.
@export var seed := 1
## Stone-space-unit -> millimeter scale (stone space has girdle RADIUS = 1),
## i.e. size_mm 5.0 = 10 mm girdle diameter. Beer-Lambert paths use it directly;
## authored absorption curves are co-tuned with these sizes.
@export var size_mm := 4.0


## Stable identity for cache keys. Any visual-affecting change lands here.
func fingerprint() -> String:
	var parts := [
		stone_id,
		species.species_id if species else &"none",
		chromophore.chromophore_id if chromophore else &"none",
		str(cut.get("cut_id")) if cut else "none",
		silhouette,
		"%.3f_%.3f_%.3f_%.3f" % [grade.cut, grade.clarity, grade.surface, grade.crystal] if grade else "g1",
		str(seed),
		"%.2f" % size_mm,
	]
	return "|".join(PackedStringArray(parts)).md5_text().substr(0, 16)
