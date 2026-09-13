extends SceneTree
## An isolated real worker must report contention, finish unrelated work and
## resume the held job on retry without duplicating the completed master.
var failures:=0
func check(value:bool,label:String)->void:
	if not value:failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var base:=ProjectSettings.globalize_path("res://artifacts/work-claims-gpu/%d"%Time.get_ticks_usec())
	var bundle:=base.path_join("bundle");var output:=base.path_join("output")
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm=.15
	var job:=GemFramePlan.animation(stone,load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.PREVIEW)[0]
	job.resolution=Vector2i(48,48);job.output_size=Vector2i(24,24);job.samples=16
	var other:GemFrameJob=job.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	other.orientation=Quaternion(Vector3.UP,.4)
	var jobs:Array[GemFrameJob]=[job,other]
	check(not GemJobBundle.write(bundle,jobs,{},2).is_empty(),"portable bundle")
	if failures:print("CHECK_COMPLETE: work_claims_gpu_check"); quit(1);return
	check(_execute(bundle,base,"import",PackedStringArray(["--headless","--editor","--quit"])).code==0,"fresh portable import")
	var args:=PackedStringArray(["--quit-after","600","--script","res://tools/gem_frame_worker.gd","--","--manifest=res://manifest.json","--output="+output])
	var initialize:=args.duplicate();initialize.insert(0,"--headless");initialize.append("--initialize-only=true")
	check(_execute(bundle,base,"initialize",initialize).code==0,"headless shared-store initialization")
	var partial:=args.duplicate();partial.append("--sample-limit=5");partial.append("--outputs=optical")
	var result:=_execute(bundle,base,"partial",partial)
	check(result.code==0 and _count(result.text,"partial")==2,"two real partial checkpoints")
	var store:=GemArtifactStore.new(output)
	var checkpoint:=GemContentIdentity.digest(["checkpoint-v1",GemFramePlan.master_key(job)])
	var before:PackedByteArray=store.read(checkpoint).get("payload",PackedByteArray())
	var ownership:=GemWorkClaim.acquire(output,GemFramePlan.master_key(job),"held-by-other-attempt")
	check(ownership.get("status")=="acquired","another attempt owns first master")
	result=_execute(bundle,base,"contended",args)
	check(result.code==2 and _count(result.text,"busy")==1,"CLI reports retryable contention with exit 2")
	check(store.read(GemFramePlan.display_key(job)).is_empty(),"busy master is not published")
	check(store.read(checkpoint).get("payload")==before,"busy checkpoint is untouched")
	check(not store.read(GemFramePlan.display_key(other)).is_empty(),"unrelated master finishes")
	check(_last_counters(result.text,"job").get("resumed_samples")==5,"unrelated job resumes its own checkpoint")
	ownership.claim.release()
	result=_execute(bundle,base,"retry",args)
	check(result.code==0 and _count(result.text,"busy")==0,"retry finishes after owner releases")
	var counters:=_last_counters(result.text,"job")
	check(counters.get("rendered")==1 and counters.get("display_hits")==1 and counters.get("resumed_samples")==5,"retry resumes one master and reuses completed peer")
	var headless:=args.duplicate();headless.insert(0,"--headless")
	result=_execute(bundle,base,"cache",headless)
	check(result.code==0 and _last_counters(result.text,"job").get("display_hits")==2,"headless completed displays")
	check(_last_counters(result.text,"geometry").get("cache_hits")==2,"headless geometry companions")
	print("Work claims portable GPU: %d failures; %s"%[failures,base]);print("CHECK_COMPLETE: work_claims_gpu_check"); quit(1 if failures else 0)

func _execute(bundle:String,base:String,name:String,arguments:PackedStringArray)->Dictionary:
	var args:=PackedStringArray(["--audio-driver","Dummy","--path",bundle]);args.append_array(arguments)
	var lines:Array=[]
	var code:=OS.execute(OS.get_executable_path(),args,lines,true,false)
	var log_text:="\n".join(lines)
	GemArtifactStore.atomic_write(base.path_join(name+".log"),log_text.to_utf8_buffer())
	if "SCRIPT ERROR:" in log_text or "ERROR:" in log_text:check(false,name+": "+log_text)
	return {"code":code,"text":log_text}

func _count(log_text:String,status:String)->int:
	var count:=0
	for line in log_text.split("\n"):
		if not line.begins_with("{"):continue
		var entry:Variant=JSON.parse_string(line)
		if entry is Dictionary and entry.get("status")==status:count+=1
	return count

func _last_counters(log_text:String,kind:String)->Dictionary:
	var result:={}
	for line in log_text.split("\n"):
		if not line.begins_with("{"):continue
		var entry:Variant=JSON.parse_string(line)
		if entry is Dictionary and entry.has(kind):result=entry.counters
	return result
