extends SceneTree
## Bounded multi-metric study. Preferences are explicit; no catalog promotion.
var output:="res://artifacts/cut-search"
var failed:=false
func _initialize()->void:_run.call_deferred()

func _run()->void:
	var id:="quartz";var quick:=OS.get_cmdline_user_args().has("--quick")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--stone="):id=argument.trim_prefix("--stone=")
	if not id.is_valid_filename():_fail("Invalid specimen name");quit(1);return
	var source:GemStone=load("res://data/lapidary/stones/%s.tres"%id)
	if source==null or source.shape.mode!="faceted":_fail("Study needs an authored faceted specimen");quit(1);return
	output=output.path_join(id).path_join("multi")
	DirAccess.make_dir_recursive_absolute(output)
	var preference:=GemCutPreference.new()
	var policy:=GemRung.policy(GemRung.PREVIEW);policy.denoise_passes=0
	var training:Array[Dictionary]=[];var heldout:Array[Dictionary]=[]
	for i in 4:training.append(_scenario(i,false));heldout.append(_scenario(i,true))
	var resolution:=48 if quick else 96;var samples:=8 if quick else 32
	var tracer:=GemTracer.create(resolution,resolution)
	if tracer==null:quit(1);return
	var baseline:=GemCutSearch.evaluate(tracer,source,training,policy,samples,preference)
	if not _valid(baseline,"baseline"):tracer.release();quit(1);return
	var records:Array[Dictionary]=[];var rejected:=[]
	var started:=Time.get_ticks_msec()
	for angle in [34.0,38.0,42.0,46.0,50.0]:
		for table in [.48,.56,.64]:
			for scale in [.85,1.0,1.15]:
				var stone:=GemCutSearch.candidate(source,angle,table,scale)
				var measured:=GemCutSearch.evaluate(tracer,stone,training,policy,samples,preference)
				if not measured.error.is_empty():
					rejected.append({"pavilion_deg":angle,"table_ratio":table,"crown_scale":scale,"error":measured.error});continue
				var score:=GemCutSearch.preference_score(measured,baseline,preference)
				if not _valid(score,"preference"):tracer.release();quit(1);return
				records.append({"pavilion_deg":angle,"table_ratio":table,"crown_scale":scale,"measurement":measured,"preference":score})
		print("Cut study %s: %d accepted, %d rejected, %.1fs"%[id,records.size(),rejected.size(),(Time.get_ticks_msec()-started)/1000.0])
		await process_frame
	var scores:Array[Dictionary]=[]
	for record in records:scores.append(record.preference)
	var frontier:=GemCutSearch.frontier(scores,preference)
	for i in records.size():records[i]["frontier"]=frontier.has(i)
	records.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.preference.utility>b.preference.utility)
	tracer.release();tracer=GemTracer.create(96,96)
	if tracer==null:quit(1);return
	var confirmation_samples:=128
	var confirmed_baseline:=GemCutSearch.evaluate(tracer,source,training,policy,confirmation_samples,preference)
	if not _valid(confirmed_baseline,"confirmed baseline"):tracer.release();quit(1);return
	var confirmed:Array[Dictionary]=[]
	for record in records:
		if not record.frontier:continue
		var stone:=GemCutSearch.candidate(source,record.pavilion_deg,record.table_ratio,record.crown_scale)
		var measured:=GemCutSearch.evaluate(tracer,stone,training,policy,confirmation_samples,preference)
		if not _valid(measured,"confirmation"):tracer.release();quit(1);return
		var score:=GemCutSearch.preference_score(measured,confirmed_baseline,preference)
		if not _valid(score,"confirmed preference"):tracer.release();quit(1);return
		confirmed.append({"pavilion_deg":record.pavilion_deg,"table_ratio":record.table_ratio,"crown_scale":record.crown_scale,"measurement":measured,"preference":score})
		if confirmed.size()==3:break
	confirmed.append({"baseline":true,"pavilion_deg":source.cut.pavilion_angle_deg,"table_ratio":source.cut.table_ratio,"crown_scale":1.0,"measurement":confirmed_baseline,"preference":GemCutSearch.preference_score(confirmed_baseline,confirmed_baseline,preference)})
	confirmed.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.preference.eligible!=b.preference.eligible:return a.preference.eligible
		return a.preference.utility>b.preference.utility)
	# Independent streams test selection sensitivity. These are a repeat, not a
	# confidence interval: two seed pairs cannot establish statistical certainty.
	var repeat_baseline:=GemCutSearch.evaluate(tracer,source,training,policy,confirmation_samples,preference,113,191)
	if not _valid(repeat_baseline,"repeat baseline"):tracer.release();quit(1);return
	var repeat_scores:Array[Dictionary]=[]
	for record in confirmed:
		var stone:=GemCutSearch.candidate(source,record.pavilion_deg,record.table_ratio,record.crown_scale)
		var measured:Dictionary=repeat_baseline if record.get("baseline",false) else GemCutSearch.evaluate(tracer,stone,training,policy,confirmation_samples,preference,113,191)
		if not _valid(measured,"repeat candidate"):tracer.release();quit(1);return
		record["repeat_measurement"]=measured
		record["repeat_preference"]=GemCutSearch.preference_score(measured,repeat_baseline,preference)
		if not _valid(record.repeat_preference,"repeat preference"):tracer.release();quit(1);return
		repeat_scores.append(record.repeat_preference)
	var repeat_best:=-1
	for i in repeat_scores.size():
		if repeat_scores[i].eligible and (repeat_best<0 or repeat_scores[i].utility>repeat_scores[repeat_best].utility):repeat_best=i
	var stability:={"repeat_seeds":[113,191],"repeat_best_index":repeat_best,"same_leader":repeat_best==0,"interpretation":"Seed sensitivity only; not a confidence interval. Original training preference selects the review candidate; retain alternatives if the leader changes."}
	var baseline_heldout:=GemCutSearch.evaluate(tracer,source,heldout,policy,confirmation_samples,preference)
	if not _valid(baseline_heldout,"held-out baseline"):tracer.release();quit(1);return
	for i in confirmed.size():
		var record:=confirmed[i]
		var stone:=GemCutSearch.candidate(source,record.pavilion_deg,record.table_ratio,record.crown_scale)
		record["heldout"]=GemCutSearch.evaluate(tracer,stone,heldout,policy,confirmation_samples,preference)
		if not _valid(record.heldout,"held-out candidate"):tracer.release();quit(1);return
		if GemResourceBundle.save(stone,output.path_join("candidate-%d.res"%i))!=OK:_fail("Cannot save candidate")
	var report:={"version":3,"specimen":id,"source":source.fingerprint(),"engine":GemRenderIdentity.worker_digest(),"policy":policy,
		"screening":{"resolution":resolution,"samples":samples},"confirmation":{"resolution":96,"samples":confirmation_samples},"seeds":[17,71],
		"preference":preference.describe(),"preference_id":GemContentIdentity.digest(preference),
		"seed_sensitivity":stability,"repeat_baseline":repeat_baseline,
		"limits":"Engineering utility, not a gemological grade. Relative darkness is not leakage. Modulation uses shared primary facets and reports stationary noise; excess modulation is a conservative score term, not an unbiased estimator. No fire or rough-stock yield measurement. No automatic catalog promotion.",
		"training_scenarios":training.map(func(s:Dictionary)->Dictionary:return s.description),"heldout_scenarios":heldout.map(func(s:Dictionary)->Dictionary:return s.description),
		"baseline_screening":baseline,"baseline_confirmation":confirmed_baseline,"baseline_heldout":baseline_heldout,"screened":records,"confirmed":confirmed,"rejected":rejected,"elapsed_ms":Time.get_ticks_msec()-started}
	if not GemArtifactStore.atomic_write(output.path_join("report.json"),JSON.stringify(report,"\t",true,true).to_utf8_buffer()):_fail("Cannot save report")
	tracer.release()
	if confirmed.is_empty() or not confirmed[0].preference.eligible:
		print("No candidate meets the declared preference constraints; report saved.");quit(1 if failed else 0);return
	var winner:=confirmed[0]
	print("Selected utility %.6f; held-out mean Y %.6f -> %.6f"%[winner.preference.utility,baseline_heldout.mean_Y,winner.heldout.mean_Y])
	print("Independent seed repeat retains leader: "+str(stability.same_leader))
	var selected:=GemCutSearch.candidate(source,winner.pavilion_deg,winner.table_ratio,winner.crown_scale)
	tracer=GemTracer.create(256,256)
	if tracer==null:quit(1);return
	policy.denoise_passes=3
	for variant in [{"name":"baseline","stone":source},{"name":"candidate","stone":selected}]:
		for i in 2:
			var scenario:=heldout[i]
			if not tracer.configure_stone(LapidaryStoneCompiler.compile(variant.stone),scenario.lighting,policy):_fail(tracer.configuration_error);continue
			tracer.set_seed(17);tracer.set_clip_sample(scenario.orientation,0,Vector4.ONE,1.4)
			tracer.accumulate(128)
			if not tracer.transport_error().is_empty():_fail(tracer.transport_error());continue
			if tracer.finalize_print(GemPrint.load_house()).save_png(output.path_join("%s-%d.png"%[variant.name,i]))!=OK:_fail("Cannot save review image")
	tracer.release();quit(1 if failed else 0)

func _valid(value:Dictionary,label:String)->bool:
	if value.get("error","").is_empty():return true
	_fail(label+": "+str(value.error));return false
func _fail(message:String)->void:
	failed=true;printerr("FAIL: "+message)

func _scenario(index: int, heldout: bool) -> Dictionary:
	var rig := GemLightRig.new()
	rig.background_spectrum.model = GemSpectrum.Model.CIE_D65
	rig.white_spectrum = rig.background_spectrum
	rig.bg_zenith = 0.25
	rig.bg_horizon = 0.08
	rig.bg_below = 0.005
	var azimuth := 37.0 * index + (23.0 if heldout else 0.0)
	var elevation := 25.0 + 13.0 * index + (5.0 if heldout else 0.0)
	var radius := 11.0 + 4.0 * index + (2.0 if heldout else 0.0)
	for role in 2:
		var light := GemRigLight.new()
		light.role = role
		light.azimuth_deg = azimuth + 100.0 * role
		light.elevation_deg = elevation - 20.0 * role
		light.angular_radius_deg = radius + 15.0 * role
		light.power = 3.0 if role == 0 else 0.75
		light.spectrum = rig.background_spectrum
		rig.lights.append(light)
	if index%2==0:
		var observer:=GemRigLight.new()
		observer.role=GemRigLight.Role.BLOCKER;observer.azimuth_deg=0;observer.elevation_deg=0
		observer.angular_radius_deg=11.0 if heldout else 8.0;observer.inner_fraction=.85;observer.power=1.0
		rig.lights.append(observer)
	var tilt_x := -12.0 + 8.0 * index + (3.0 if heldout else 0.0)
	var tilt_y := 7.0 if index % 2 == 0 else -7.0
	if heldout:
		tilt_y *= 1.7
	var orientation:=Quaternion(Vector3.UP, deg_to_rad(tilt_y)) * Quaternion(Vector3.RIGHT, deg_to_rad(tilt_x))
	return {"rig": rig, "lighting": GemRigCompiler.compile(rig),
		"orientation":orientation,"motion_orientation":Quaternion(Vector3.UP,deg_to_rad(2.5))*orientation,
		"description": {"key_azimuth_deg": azimuth, "key_elevation_deg": elevation, "key_radius_deg": radius,
			"motion_y_deg":2.5,"observer_mask":index%2==0,"tilt_x_deg": tilt_x, "tilt_y_deg": tilt_y, "illumination": "D65; key3/fill0.75; background0.25/0.08/0.005"}}
