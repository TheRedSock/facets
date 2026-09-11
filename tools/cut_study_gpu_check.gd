extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material=GemMaterial.new();stone.material.species=GemSpecies.new()
	stone.material.species.ordinary.index_offset=.5
	stone.condition=GemCondition.new()
	var rig:=GemLightRig.new()
	rig.background_spectrum.model=GemSpectrum.Model.EQUAL_ENERGY
	rig.bg_zenith=1;rig.bg_horizon=1;rig.bg_below=1
	var scenarios:Array[Dictionary]=[{"rig":rig,"orientation":Quaternion.IDENTITY,"motion_orientation":Quaternion(Vector3.UP,deg_to_rad(2.5))}]
	var tracer:=GemTracer.create(48,48)
	if tracer==null:quit(1);return
	var policy:=GemRung.policy(GemRung.PREVIEW)
	policy.denoise_passes=0;policy.birefringence=false
	var preference:=GemCutPreference.new()
	for mode in ["scalar","polarized","crystal"]:
		policy.polarization=mode=="polarized";policy.crystal_transport=mode=="crystal"
		var result:=GemCutSearch.evaluate(tracer,stone,scenarios,policy,64,preference)
		check(result.error.is_empty(),mode+" study admission: "+result.error)
		if not result.error.is_empty():continue
		check(absf(result.mean_Y-1)<.004 and absf(result.worst_Y-1)<.004,mode+" furnace return")
		check(result.worst_dark_fraction==0 and result.mean_contrast_cv<.005,mode+" furnace uniformity")
		check(result.mean_facet_modulation<.005 and result.mean_stationary_modulation<.005,mode+" no spurious furnace motion")
		check(result.minimum_matched_fraction>.95,mode+" primary facet correspondence")
		check(not result.views[0].base.has("facets"),mode+" aggregate report omits per-pixel machinery")
		var score:=GemCutSearch.preference_score(result,result,preference)
		check(score.error.is_empty() and score.eligible,mode+" valid measurement ranks")
	policy.crystal_transport=false;policy.polarization=false
	var invalid:Array[Dictionary]=[{}, {"rig":rig,"orientation":Quaternion(0,0,0,0)}, {"rig":rig,"orientation":Quaternion.IDENTITY,"motion_orientation":Quaternion(0,0,0,0)}, {"rig":rig,"orientation":Quaternion.IDENTITY,"weight":-1}, {"rig":rig,"orientation":Quaternion.IDENTITY,"yaw":"wrong"}, {"rig":rig,"orientation":Quaternion.IDENTITY,"ortho_half":NAN}]
	for scenario in invalid:
		var bad:Array[Dictionary]=[scenario]
		check(not GemCutSearch.evaluate(tracer,stone,bad,policy,16).error.is_empty(),"invalid scenario rejected")
	check(not GemCutSearch.evaluate(tracer,stone,scenarios,policy,0).error.is_empty(),"invalid sample budget rejected")
	check(not GemCutSearch.evaluate(tracer,stone,scenarios,policy,16,preference,17,17).error.is_empty(),"identical noise seeds rejected")
	check(not GemCutSearch.evaluate(tracer,stone,scenarios,policy,16,preference,-1,71).error.is_empty(),"negative seed rejected")
	check(not GemCutSearch.evaluate(tracer,stone,scenarios,policy,16,preference,0x100000000,71).error.is_empty(),"wrapped seed rejected")
	var enormous:Array[Dictionary]=[scenarios[0].duplicate(),scenarios[0].duplicate()]
	for scenario in enormous:scenario.weight=1e308
	var weighted:=GemCutSearch.evaluate(tracer,stone,enormous,policy,16)
	check(weighted.error.is_empty() and is_finite(weighted.get("mean_Y",NAN)) and absf(weighted.get("mean_Y",0)-1)<.004,"finite extreme weights normalize safely")
	stone.material.scatter_per_mm=.1;policy.crystal_transport=true
	var unsupported:=GemCutSearch.evaluate(tracer,stone,scenarios,policy,16)
	check(not unsupported.error.is_empty(),"unsupported crystal volume cannot reuse prior film")
	check(not GemCutSearch.preference_score(unsupported,weighted,preference).error.is_empty(),"failed transport cannot rank")
	tracer.release()
	print("Cut study GPU: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
