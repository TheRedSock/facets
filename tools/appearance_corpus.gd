extends SceneTree
## Production-worker spatial/motion corpus. Output records are content-checked on resume.
## --cases=... --sizes=112,256,512 --profiles=draft,detail,reference --frames=0,1,2,3
## --plan-only freezes every selected immutable job without a GPU.
const CONFIG := "res://data/lapidary/acceptance/corpus.json"
var out := "res://artifacts/appearance-corpus"
var report := {"schema":1,"records":{}}
var failed := false
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var options := {"cases":",".join(config.cases),"sizes":"112,256,512","profiles":",".join(config.profiles.keys()),"frames":"0,1,2,3","rigs":",".join(config.rigs)}
	var plan_only := false
	for arg in OS.get_cmdline_user_args():
		if arg=="--plan-only":plan_only=true;continue
		var pair:=arg.trim_prefix("--").split("=",true,1)
		if pair.size()!=2 or not options.has(pair[0]):_fail("Unknown option "+arg);return
		options[pair[0]]=pair[1]
	DirAccess.make_dir_recursive_absolute(out.path_join("jobs"));DirAccess.make_dir_recursive_absolute(out.path_join("images"))
	var report_path:=out.path_join("report.json")
	if FileAccess.file_exists(report_path):
		var previous:Variant=JSON.parse_string(FileAccess.get_file_as_string(report_path))
		if not previous is Dictionary or previous.get("schema")!=1:_fail("Invalid existing corpus report");return
		report=previous
	report["config_sha256"]=FileAccess.get_sha256(CONFIG)
	report["source_inventory"]=GemRenderIdentity.inventory()
	report["source_engine"]=GemRenderIdentity.worker_digest()
	var worker:=GemFrameWorker.new(out.path_join("store"))
	for case_name in String(options.cases).split(",",false):
		if case_name not in config.cases:_fail("Unknown case "+case_name);return
		var stone:GemStone=load("res://data/lapidary/acceptance/%s.tres"%case_name)
		for rig_name in String(options.rigs).split(",",false):
			if rig_name not in config.rigs:_fail("Unknown rig");return
			for size_text in String(options.sizes).split(",",false):
				if not size_text.is_valid_int() or int(size_text) not in config.sizes.map(func(value: Variant) -> int: return int(value)):_fail("Unknown output size");return
				var size:=int(size_text)
				for frame_text in String(options.frames).split(",",false):
					if not frame_text.is_valid_int() or int(frame_text)<0 or int(frame_text)>=int(config.frames):_fail("Unknown frame");return
					var frame:=int(frame_text)
					for profile_name in String(options.profiles).split(",",false):
						if not config.profiles.has(profile_name):_fail("Unknown profile");return
						var profile:Dictionary=config.profiles[profile_name]
						for stream in 2:
							# A second high-SPP stationary reference estimates reference uncertainty.
							if profile_name=="reference" and stream==1 and frame!=0:continue
							var job:=GemFrameJob.new();job.stone=stone
							job.rig=load("res://data/lapidary/rigs/%s.tres"%rig_name);job.print_style=GemPrint.load_house()
							job.quality=GemRung.policy(GemRung.rung_from_name(profile.rung))
							job.quality.max_bounces=int(profile.bounces);job.quality.denoise_passes=int(profile.passes)
							job.quality.batch=16
							job.resolution=Vector2i.ONE*(size*2 if size<512 else 512);job.output_size=Vector2i.ONE*size
							job.samples=int(profile.samples);job.sample_seed=int(profile.seeds[stream])
							job.orientation=pose(float(frame)/config.frames);job.ortho_half=1.25
							var why:=GemJobValidator.validate(job)
							if not why.is_empty():worker.release();_fail(case_name+": "+why);return
							if GemFramePlan.canonical_orientation(pose(0))!=GemFramePlan.canonical_orientation(pose(1)):_fail("Motion endpoints disagree");return
							var id:="%s-%s-%d-%d-%s-%d"%[case_name,rig_name,size,frame,profile_name,stream]
							var key:=GemFramePlan.display_key(job)
							var image_path:=out.path_join("images/"+id+".png")
							var saved:Dictionary=report.records.get(id,{})
							if saved.get("display")==key and FileAccess.file_exists(image_path) and FileAccess.get_sha256(image_path)==saved.get("png_sha256") and saved.has("request_sha256") and FileAccess.get_sha256(out.path_join("jobs/"+id+".res"))==saved.request_sha256:
								# Revalidate the current planned job even on a complete cache hit.
								# Preserve measured render cost and original producer information.
								if GemResourceBundle.save(job,out.path_join("jobs/"+id+".res"))!=OK:_fail("Cannot refresh frozen evidence");return
								saved.request_sha256=FileAccess.get_sha256(out.path_join("jobs/"+id+".res"))
								_evidence(saved,job,profile);report.records[id]=saved
								print("Corpus cached ",id);continue
							if GemResourceBundle.save(job,out.path_join("jobs/"+id+".res"))!=OK:_fail("Cannot freeze job");return
							if plan_only:continue
							var start:=Time.get_ticks_usec()
							var result:=worker.run(job)
							if result.get("status")!="complete":worker.release();_fail(worker.last_error);return
							var image:=GemFrameWorker._display_image(worker.store.read(key),job,GemFramePlan.display_engine(job))
							if image==null or image.save_png(image_path)!=OK:worker.release();_fail("Cannot save corpus frame");return
							var master:Dictionary=worker.store.read(GemFramePlan.master_key(job)).get("metadata",{})
							var record:={"case":case_name,"rig":rig_name,"size":size,"frame":frame,"profile":profile_name,"stream":stream,"display":key,"master":GemFramePlan.master_key(job),"samples":job.samples,"sample_seed":job.sample_seed,"specimen_fingerprint":stone.fingerprint(),"pose":[job.orientation.x,job.orientation.y,job.orientation.z,job.orientation.w],"wall_ms":(Time.get_ticks_usec()-start)/1000.0,"worker_profile":master.get("profile",{}),"producer":master.get("producer",{}),"png_sha256":FileAccess.get_sha256(image_path),"request_sha256":FileAccess.get_sha256(out.path_join("jobs/"+id+".res"))}
							report.records[id]=record
							_evidence(record,job,profile)
							if not GemArtifactStore.atomic_write(report_path,JSON.stringify(report,"\t").to_utf8_buffer()):worker.release();_fail("Cannot save report");return
							print("Corpus ",id," ",record.wall_ms," ms");await process_frame
	worker.release()
	if not GemArtifactStore.atomic_write(report_path,JSON.stringify(report,"\t").to_utf8_buffer()):_fail("Cannot save corpus verification");return
	print("CHECK_COMPLETE: appearance_corpus");quit()
func _evidence(record:Dictionary,job:GemFrameJob,profile:Dictionary)->void:
	record.profile_spec=profile.duplicate(true);record.verified_source_engine=GemRenderIdentity.worker_digest()
	var sources:Dictionary={};_input_sources(job,sources,{})
	record.input_sources=sources
func _input_sources(value:Variant,files:Dictionary,seen:Dictionary)->void:
	if value is Script:return
	if value is Resource:
		var id:int=value.get_instance_id()
		if seen.has(id):return
		seen[id]=true
		var path:String=value.resource_path.split("::")[0]
		if path.begins_with("res://") and FileAccess.file_exists(path):files[path.trim_prefix("res://")]=FileAccess.get_sha256(path)
		for property:Dictionary in value.get_property_list():
			if int(property.usage)&PROPERTY_USAGE_STORAGE and property.name not in ["script","resource_path"]:_input_sources(value.get(property.name),files,seen)
	elif value is Array:
		for item in value:_input_sources(item,files,seen)
	elif value is Dictionary:
		for item in value.values():_input_sources(item,files,seen)
static func pose(t:float)->Quaternion:
	# Four distinct poses on a closed tilt ellipse, fixed specimen/camera origin.
	return GemFramePlan.canonical_orientation(Quaternion(Vector3.UP,.18*sin(TAU*t))*Quaternion(Vector3.RIGHT,-.12+.06*(cos(TAU*t)-1)))
func _fail(message:String)->void:
	printerr("FAIL: "+message);print("CHECK_COMPLETE: appearance_corpus");quit(1)
