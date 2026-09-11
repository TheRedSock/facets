class_name GemMicrostructureRecipe
extends Resource
## Design-time realization program. Its output is a normal explicit specimen,
## so render workers need no hidden grade logic or procedural population state.
@export var populations: Array[GemInclusionPopulation] = []
@export_multiline var source_note := "Authored physical microstructure recipe; acceptance requires render review."

func validate()->PackedStringArray:
	var errors:=PackedStringArray();var ids:={};var count:=0
	if populations.size()>32:errors.append("At most 32 populations per recipe")
	for population in populations:
		if population==null:errors.append("Missing population");continue
		errors.append_array(population.validate())
		if ids.has(population.population_id):errors.append("Population IDs must be unique for stable seed channels")
		ids[population.population_id]=true;count+=population.count
	if count>127:errors.append("Resolved populations exceed the 127-region budget")
	return errors
