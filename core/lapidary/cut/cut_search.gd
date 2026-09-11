class_name GemCutSearch
extends RefCounted
## Bounded design-space exploration. The score is an explicit engineering
## objective under an illumination/view ensemble, never a gemological grade.

static func candidate(source: GemStone, pavilion_deg: float, table_ratio: float, crown_scale: float) -> GemStone:
	var stone := source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GemStone
	stone.cut.pavilion_angle_deg = pavilion_deg
	stone.cut.table_ratio = table_ratio
	for row in stone.cut.crown_rows:
		row.angle_deg *= crown_scale
	return stone

static func evaluate(tracer:GemTracer, stone:GemStone, scenarios:Array[Dictionary], policy:Dictionary, samples:int, preference:GemCutPreference=null, seed_value:=17, noise_seed:=71)->Dictionary:
	if tracer==null or stone==null or scenarios.is_empty():return {"error":"Study needs a tracer, specimen and scenarios"}
	if preference==null:preference=GemCutPreference.new()
	if not preference.validate().is_empty():return {"error":"; ".join(preference.validate())}
	if seed_value==noise_seed or mini(seed_value,noise_seed)<0 or maxi(seed_value,noise_seed)>0xffffffff:return {"error":"Study seeds must be distinct unsigned 32-bit values"}
	var prepared:=[]
	var maximum_weight:=0.0
	for scenario in scenarios:
		if not scenario.get("rig") is GemLightRig or not scenario.get("orientation") is Quaternion:
			return {"error":"Each scenario needs an authored rig and orientation"}
		var motion:Variant=scenario.get("motion_orientation",scenario.orientation)
		if not motion is Quaternion or not motion.is_finite() or absf(motion.length_squared()-1)>1e-5:
			return {"error":"Motion orientation must be a finite unit quaternion"}
		var weight:Variant=scenario.get("weight",1.0)
		if typeof(weight) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(weight) or weight<=0:return {"error":"Scenario weights must be positive"}
		for key in ["yaw","ortho_half"]:
			if scenario.has(key) and typeof(scenario[key]) not in [TYPE_FLOAT,TYPE_INT]:return {"error":"Invalid numeric scenario field: "+key}
		var job:=GemFrameJob.new()
		job.stone=stone;job.rig=scenario.rig;job.print_style=GemPrint.load_house();job.quality=policy
		job.samples=samples;job.sample_seed=seed_value;job.resolution=Vector2i(tracer.width,tracer.height);job.output_size=job.resolution
		job.orientation=scenario.orientation;job.rig_yaw=scenario.get("yaw",0.0);job.ortho_half=scenario.get("ortho_half",1.4)
		var error:=GemJobValidator.validate(job)
		if not error.is_empty():return {"error":"Scenario admission: "+error}
		prepared.append({"lighting":GemRigCompiler.compile(scenario.rig),"base":job.orientation,"motion":motion,"yaw":job.rig_yaw,"half":job.ortho_half,"weight":float(weight)})
		maximum_weight=maxf(maximum_weight,float(weight))
	# Scaling preserves relative weights without overflowing their sum/products.
	for scenario in prepared:scenario.weight/=maximum_weight
	var instance:=LapidaryStoneCompiler.compile(stone)
	if instance.has("compilation_error"):return {"error":instance.compilation_error}
	var result:={"error":"","mean_Y":0.0,"worst_Y":INF,"worst_dark_fraction":0.0,"mean_contrast_cv":0.0,"mean_facet_modulation":0.0,"mean_stationary_modulation":0.0,"minimum_matched_fraction":1.0,"views":[]}
	var total_weight:=0.0
	for scenario in prepared:
		if not tracer.configure_stone(instance,scenario.lighting,policy):return {"error":tracer.configuration_error}
		var base:=_measure(tracer,scenario.base,scenario,seed_value,samples,preference.relative_dark_threshold)
		if not base.error.is_empty():return base
		var moved:=_measure(tracer,scenario.motion,scenario,seed_value,samples,preference.relative_dark_threshold)
		if not moved.error.is_empty():return moved
		var stationary:=_measure(tracer,scenario.base,scenario,noise_seed,samples,preference.relative_dark_threshold,base.ids)
		if not stationary.error.is_empty():return stationary
		var motion:=GemCutMetrics.pair(base.metrics,moved.metrics)
		var noise:=GemCutMetrics.pair(base.metrics,stationary.metrics)
		if not motion.error.is_empty():return motion
		if not noise.error.is_empty():return noise
		var weight:float=scenario.weight
		total_weight+=weight
		result.mean_Y+=weight*.5*(base.metrics.mean_Y+moved.metrics.mean_Y)
		result.worst_Y=minf(result.worst_Y,minf(base.metrics.mean_Y,moved.metrics.mean_Y))
		result.worst_dark_fraction=maxf(result.worst_dark_fraction,maxf(base.metrics.relative_dark_fraction,moved.metrics.relative_dark_fraction))
		result.mean_contrast_cv+=weight*.5*(base.metrics.contrast_cv+moved.metrics.contrast_cv)
		result.mean_facet_modulation+=weight*motion.modulation
		result.mean_stationary_modulation+=weight*noise.modulation
		result.minimum_matched_fraction=minf(result.minimum_matched_fraction,motion.matched_fraction)
		result.views.append({"base":GemCutMetrics.public_frame(base.metrics),"moved":GemCutMetrics.public_frame(moved.metrics),"stationary":GemCutMetrics.public_frame(stationary.metrics),"motion":motion,"noise":noise,"weight":weight})
	for key in ["mean_Y","mean_contrast_cv","mean_facet_modulation","mean_stationary_modulation"]:result[key]/=total_weight
	result["excess_modulation"]=maxf(0,result.mean_facet_modulation-result.mean_stationary_modulation)
	return result

static func _measure(tracer:GemTracer, orientation:Quaternion, scenario:Dictionary, seed_value:int, samples:int, dark_ratio:float, ids:=PackedInt64Array())->Dictionary:
	tracer.set_seed(seed_value);tracer.set_clip_sample(orientation,scenario.yaw,Vector4.ONE,scenario.half)
	if ids.is_empty():
		var aov:=tracer.geometry_aov(1)
		if aov==null:return {"error":"Primary-facet measurement failed"}
		ids.resize(tracer.width*tracer.height);ids.fill(-1)
		for y in tracer.height:
			for x in tracer.width:
				var hit:=aov.record(x,y)
				if hit.coverage>0:ids[y*tracer.width+x]=((int(hit.region)+1)<<32)|(int(hit.facet)&0xffffffff)
	tracer.accumulate(samples)
	var error:=tracer.transport_error()
	if not error.is_empty():return {"error":error}
	var metrics:=GemCutMetrics.frame(tracer.read_xyz(),ids,dark_ratio)
	if not metrics.error.is_empty():return metrics
	return {"error":"","metrics":metrics,"ids":ids}

static func preference_score(measured:Dictionary, baseline:Dictionary, preference:GemCutPreference)->Dictionary:
	if preference==null or not preference.validate().is_empty():return {"error":"Invalid cut preference"}
	for value in [measured,baseline]:
		if not value.get("error","").is_empty():return {"error":"Failed measurements cannot be ranked"}
		for key in ["mean_Y","worst_Y","worst_dark_fraction","mean_contrast_cv","excess_modulation"]:
			if typeof(value.get(key)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(value[key]) or value[key]<0:return {"error":"Invalid metric: "+key}
		if value.worst_dark_fraction>1 or value.excess_modulation>1:return {"error":"Metric fraction exceeds one"}
	if baseline.mean_Y<=0:return {"error":"A dark baseline cannot normalize return utility"}
	var mean_ratio:float=measured.mean_Y/baseline.mean_Y
	var worst_ratio:float=measured.worst_Y/baseline.mean_Y
	if not is_finite(mean_ratio) or not is_finite(worst_ratio):return {"error":"Return normalization overflows"}
	var contrast:=maxf(0,1-absf(measured.mean_contrast_cv-preference.target_contrast_cv)/preference.target_contrast_cv)
	var total:=preference.mean_return_weight+preference.worst_return_weight+preference.dark_area_weight+preference.contrast_weight+preference.modulation_weight
	var utility:float=(preference.mean_return_weight/total)*mean_ratio+(preference.worst_return_weight/total)*worst_ratio+(preference.dark_area_weight/total)*(1-measured.worst_dark_fraction)+(preference.contrast_weight/total)*contrast+(preference.modulation_weight/total)*measured.excess_modulation
	return {"error":"","utility":utility,"eligible":mean_ratio>=preference.minimum_mean_return_ratio and measured.worst_dark_fraction<=preference.maximum_dark_fraction,
		"mean_return_ratio":mean_ratio,"axes":[mean_ratio,worst_ratio,1-measured.worst_dark_fraction,contrast,measured.excess_modulation]}

## Nondominated eligible alternatives under the nonzero preference axes.
## Numerical equality is exact here; uncertainty is reported by the study.
static func frontier(scores:Array[Dictionary], preference:GemCutPreference)->PackedInt32Array:
	if preference==null or not preference.validate().is_empty():return PackedInt32Array()
	var weights:=[preference.mean_return_weight,preference.worst_return_weight,preference.dark_area_weight,preference.contrast_weight,preference.modulation_weight]
	var result:=PackedInt32Array()
	for i in scores.size():
		if not scores[i].get("error","").is_empty() or not scores[i].get("eligible",false):continue
		var dominated:=false
		for j in scores.size():
			if i==j or not scores[j].get("error","").is_empty() or not scores[j].get("eligible",false):continue
			var no_worse:=true;var better:=false
			for k in weights.size():
				if weights[k]==0:continue
				no_worse=no_worse and scores[j].axes[k]>=scores[i].axes[k]
				better=better or scores[j].axes[k]>scores[i].axes[k]
			if no_worse and better:dominated=true;break
		if not dominated:result.append(i)
	return result
