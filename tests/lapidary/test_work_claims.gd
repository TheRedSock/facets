extends SceneTree
var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var args:={}
	for argument in OS.get_cmdline_user_args():
		var pair:=argument.trim_prefix("--").split("=",true,1)
		if pair.size()==2:args[pair[0]]=pair[1]
	if args.has("child-root"):_child.call_deferred(args)
	else:_run.call_deferred()

func _child(args:Dictionary)->void:
	var result:=GemWorkClaim.acquire(args["child-root"],args.key,"test-child")
	var status:String=result.get("status","error")
	if result.has("error"):GemArtifactStore.atomic_write(args["child-root"].path_join(args.token+".error"),str(result).to_utf8_buffer())
	GemArtifactStore.atomic_write(args["child-root"].path_join(args.token+".ready"),status.to_utf8_buffer())
	if status!="acquired":print("CHECK_COMPLETE: test_work_claims"); quit(0 if status=="busy" else 1);return
	var stop:String=args["child-root"].path_join(args.token+".stop")
	while not FileAccess.file_exists(stop):await create_timer(.02).timeout
	result.claim.release();print("CHECK_COMPLETE: test_work_claims"); quit()

func _spawn(root_path:String,key:String,token:String)->int:
	return OS.create_process(OS.get_executable_path(),PackedStringArray(["--audio-driver","Dummy","--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/lapidary/test_work_claims.gd","--","--child-root="+root_path,"--key="+key,"--token="+token]),false)

func _wait_file(path:String)->bool:
	var deadline:=Time.get_ticks_msec()+15000
	while not FileAccess.file_exists(path) and Time.get_ticks_msec()<deadline:await create_timer(.02).timeout
	return FileAccess.file_exists(path)

func _wait_exit(pid:int)->bool:
	if pid<=0:return false
	var deadline:=Time.get_ticks_msec()+15000
	while OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:await create_timer(.02).timeout
	return not OS.is_process_running(pid)

func _scope(root_path:String,key:String)->void:
	var claim:=GemWorkClaim.acquire(root_path,key,"scope")
	check(claim.get("status")=="acquired","scoped claim acquired")

func _run()->void:
	var root_path:=ProjectSettings.globalize_path("res://artifacts/work-claims/%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var store:=GemArtifactStore.new(root_path)
	check(store.initialize(),"initialize shared store before dispatch")
	var a:="master-a".sha256_text();var b:="master-b".sha256_text()
	var owner:=GemWorkClaim.acquire(root_path,a,"unit")
	check(owner.get("status")=="acquired","claim master")
	check(GemWorkClaim.acquire(root_path,a,"competitor").get("status")=="busy","same master is exclusive")
	var different:=GemWorkClaim.acquire(root_path,b,"independent")
	check(different.get("status")=="acquired","different master proceeds")
	check(GemStoreGuard.exclusive(root_path)==null,"claims exclude maintenance")
	different.claim.release();owner.claim.release()
	_scope(root_path,a)
	owner=GemWorkClaim.acquire(root_path,a,"after-scope")
	check(owner.get("status")=="acquired","normal destruction releases claim")
	owner.claim.release()
	var maintenance:=GemStoreGuard.exclusive(root_path)
	check(maintenance!=null and GemWorkClaim.acquire(root_path,a,"blocked").get("reason")=="maintenance","maintenance blocks claims")
	maintenance.release()
	var pids:=[]
	for i in 8:pids.append(_spawn(root_path,a,"race%d"%i))
	var winners:=0
	for i in 8:
		check(await _wait_file(root_path.path_join("race%d.ready"%i)),"child reports contention result")
		var status:=FileAccess.get_file_as_string(root_path.path_join("race%d.ready"%i))
		check(status in ["acquired","busy"],"child result is acquired or retryable")
		if status=="acquired":winners+=1
	check(winners==1,"eight simultaneous processes have exactly one owner")
	for i in 8:GemArtifactStore.atomic_write(root_path.path_join("race%d.stop"%i),"stop".to_utf8_buffer())
	for pid in pids:check(await _wait_exit(pid),"contention child exited")
	# Worker APIs must stop before device creation, including all prints of a master.
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres")
	var job:=GemFramePlan.animation(stone,load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.INTERACT)[0]
	owner=GemWorkClaim.acquire(root_path,GemFramePlan.master_key(job),"held-master")
	var worker:=GemFrameWorker.new(root_path)
	check(worker.run(job).get("status")=="busy" and worker.tracer==null,"optical worker reports busy before GPU")
	job.exposure*=2
	check(worker.run(job).get("status")=="busy","another print cannot duplicate the same master")
	owner.claim.release()
	owner=GemWorkClaim.acquire(root_path,GemGeometryPlan.key(job,2),"held-geometry")
	var geometry:=GemGeometryWorker.new(root_path)
	check(geometry.run(job,2).get("status")=="busy" and geometry.tracer==null,"geometry worker reports busy before GPU")
	owner.claim.release()
	# Kill only the child created here, verify terminal state, then recover offline.
	var checkpoint:=GemContentIdentity.digest(["checkpoint-v1",a])
	check(store.publish(checkpoint,"saved-progress".to_utf8_buffer(),{"kind":"checkpoint"}),"checkpoint exists before interruption")
	var victim:=_spawn(root_path,a,"interrupted")
	check(await _wait_file(root_path.path_join("interrupted.ready")),"interrupted child owns work")
	check(OS.kill(victim)==OK and await _wait_exit(victim),"owned child is authoritatively stopped")
	check(GemWorkClaim.acquire(root_path,a,"after-crash").get("status")=="busy","crash never expires or steals ownership")
	var recovery:=GemStoreRecovery.new()
	var snapshot:=recovery.inspect(root_path)
	check(not snapshot.is_empty() and snapshot.claims.size()==1,"inspect abandoned state")
	check(recovery.recover(root_path,snapshot.snapshot,false).is_empty(),"recovery requires stopped-store assertion")
	var extra:=GemStoreGuard.enter(root_path,"snapshot-change")
	var changed:=recovery.inspect(root_path)
	extra.release()
	check(recovery.recover(root_path,changed.snapshot,true).is_empty(),"changed snapshot is rejected before mutation")
	var result:=recovery.recover(root_path,snapshot.snapshot,true)
	check(result.get("recovered",0)==2,"recover claim and abandoned activity token")
	check(FileAccess.file_exists(str(result.get("quarantine","")).path_join("snapshot.json")),"recovery preserves inventory")
	check(store.read(checkpoint).get("payload")=="saved-progress".to_utf8_buffer(),"recovery preserves checkpoint bytes")
	owner=GemWorkClaim.acquire(root_path,a,"resume")
	check(owner.get("status")=="acquired","new attempt acquires recovered work")
	owner.claim.release()
	maintenance=GemStoreGuard.exclusive(root_path)
	check(maintenance!=null,"recovered store permits maintenance")
	maintenance.release()
	var invalid_root:=root_path.path_join("not-a-directory")
	GemArtifactStore.atomic_write(invalid_root,"owned-test-file".to_utf8_buffer())
	check(GemWorkClaim.acquire(invalid_root,a,"invalid-io").has("error"),"activity I/O failure is not retryable contention")
	var unknown:=root_path.path_join(".active/unrecognized.txt")
	GemArtifactStore.atomic_write(unknown,"keep".to_utf8_buffer())
	check(recovery.inspect(root_path).is_empty() and FileAccess.file_exists(unknown),"recovery refuses unknown coordination files")
	DirAccess.remove_absolute(unknown)
	var empty:=recovery.inspect(root_path)
	check(recovery.recover(root_path,empty.snapshot,true).get("recovered",-1)==0,"empty recovery is idempotent")
	maintenance=GemStoreGuard.exclusive(root_path)
	var maintenance_owner:=FileAccess.get_sha256(root_path.path_join(".maintenance/owner.json"))
	check(recovery.recover(root_path,empty.snapshot,true).is_empty() and FileAccess.get_sha256(root_path.path_join(".maintenance/owner.json"))==maintenance_owner,"offline recovery cannot steal an existing maintenance owner")
	maintenance.release()
	print("Work claims: %d checks, %d failures; %s"%[checks,failures,root_path])
	print("CHECK_COMPLETE: test_work_claims"); quit(1 if failures else 0)
