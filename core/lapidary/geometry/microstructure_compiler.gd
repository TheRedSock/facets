class_name GemMicrostructureCompiler
extends RefCounted
## Realize in host-crystal coordinates before cutting. Transport clips every
## closed inclusion to the host; centers are never snapped onto visible facets.
## No camera, resolution, light, grade or renderer RNG enters this procedure.
const ATTEMPTS_PER_MEMBER := 2048

static func realize(source:GemStone, recipe:GemMicrostructureRecipe)->Dictionary:
	if source==null or recipe==null:return {"error":"Specimen and microstructure recipe are required"}
	var errors:=recipe.validate()
	if not errors.is_empty():return {"error":"; ".join(errors)}
	if not source.crystal_to_stone.is_finite() or absf(source.crystal_to_stone.length_squared()-1)>1e-5:
		return {"error":"Host crystal frame must be a unit quaternion"}
	var total:=0
	if source.condition!=null:
		for defect in source.condition.defects:
			if defect==null:return {"error":"Missing existing physical defect"}
			if defect.enabled:total+=1
		if source.condition.cleavage!=null and source.condition.cleavage.depth_mm>0:total+=1
	for population in recipe.populations:total+=population.count
	if total>=GemBoundarySet.MAX_REGIONS:return {"error":"Existing and generated defects exceed the region budget"}
	var stone:=source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GemStone
	if stone.condition==null:stone.condition=GemCondition.new()
	var report:=[]
	for population in recipe.populations:
		var template:=GemCrystalHabitCompiler.compile(population.habit)
		if not template.validate().is_empty():return {"error":"Population %s has an unbounded or unresolved habit"%population.population_id}
		var bound:=0.0
		for vertex in template.vertices:bound=maxf(bound,vertex.length())
		var seed_value:=GemContentIdentity.digest([source.seed,population.population_id,population.seed]).left(7).hex_to_int()
		var centers:Array[Vector3]=[];var radii:Array[float]=[];var attempts:=0
		# Shared prototype resources are detached from the author's graph.
		var habit:=population.habit.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GemCrystalHabit
		var filling:GemMaterial=population.filling.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) if population.filling!=null else null
		var finish:GemSurface=population.finish.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) if population.finish!=null else null
		for member in population.count:
			var scale:=exp(lerpf(log(population.scale_range.x),log(population.scale_range.y),_sample(seed_value,member,0,0)))
			var radius:=bound*scale
			var accepted:=false;var center:=Vector3.ZERO
			for attempt in ATTEMPTS_PER_MEMBER:
				attempts+=1
				var local:=Vector3(_sample(seed_value,member,attempt,1),_sample(seed_value,member,attempt,2),_sample(seed_value,member,attempt,3))*2-Vector3.ONE
				var r2:=local.length_squared()
				if r2>=1 or _sample(seed_value,member,attempt,4)>pow(1-r2,3):continue
				center=population.domain.center_mm+population.domain.orientation*(local*population.domain.radius_mm)
				accepted=true
				for j in centers.size():
					if center.distance_to(centers[j])<radius+radii[j]+population.minimum_gap_mm:accepted=false;break
				if accepted:break
			if not accepted:return {"error":"Population %s cannot place member %d at the declared sizes/separation; no partial specimen returned"%[population.population_id,member]}
			centers.append(center);radii.append(radius)
			var family:=mini(population.orientation_families.size()-1,int(_sample(seed_value,member,0,5)*population.orientation_families.size()))
			# Uniform solid-angle cone for the local c-axis, with a deterministic
			# shortest-arc tilt. No arbitrary twist is added around that axis.
			var azimuth:=TAU*_sample(seed_value,member,0,6)
			var cosine:=lerpf(1,cos(deg_to_rad(population.angular_spread_deg)),_sample(seed_value,member,0,7))
			var sine:=sqrt(maxf(0,1-cosine*cosine))
			var tilt:=Quaternion(Vector3.BACK,Vector3(sine*cos(azimuth),sine*sin(azimuth),cosine))
			var defect:=GemDefect.new()
			defect.kind="crystal";defect.crystal_habit=habit;defect.crystal_scale=scale
			defect.center_mm=source.crystal_to_stone*center
			defect.orientation=(source.crystal_to_stone*population.orientation_families[family]*tilt).normalized()
			defect.filling=filling;defect.finish=finish;defect.seed=seed_value
			defect.source_note="Population %s member %d. %s"%[population.population_id,member,population.source_note]
			stone.condition.defects.append(defect)
		report.append({"id":String(population.population_id),"members":population.count,"placement_attempts":attempts,"unscaled_bound_mm":bound,"seed_channel":seed_value})
	return {"error":"","stone":stone,"report":{"populations":report,"clipping":"Closed regions are intersected with the cut host during transport; no retained-volume or visibility estimate is inferred from center placement.","model":"Authored spatial statistics and crystal habits; not simulated nucleation, exsolution, fracture healing, or optical silk."}}

static func _sample(seed_value:int,member:int,attempt:int,channel:int)->float:
	return GemDefectCompiler.sample(seed_value,((member*ATTEMPTS_PER_MEMBER+attempt)*8)+channel)
