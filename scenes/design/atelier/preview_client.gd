class_name GemPreviewClient
extends Node
## Scene-thread client. GPU ownership and request admission live in one child process.
signal invalidated(generation: int)
signal updated(report: Dictionary, image: Image)
var session := ""
var worker_pid := -1
var generation := 0
var status := "closed"
var last_report: Dictionary = {}
var stale_results := 0
var submit_ms := 0.0
var _last_response := ""
var _heartbeat_at := 0
var _last_image := ""
var _closed := false
func _ready()->void:set_process(worker_pid>0 and not _closed)
func start(root_path := "res://generated/atelier") -> String:
	if worker_pid > 0: return "Worker already started"
	session = ProjectSettings.globalize_path(root_path.path_join("sessions/%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]))
	if DirAccess.make_dir_recursive_absolute(session)!=OK:return "Cannot create Atelier session"
	var args := PackedStringArray(["--audio-driver","Dummy","--path",ProjectSettings.globalize_path("res://"),"--position","-32000,-32000","--resolution","16x16","--log-file",session.path_join("worker.log"),"--script","res://tools/atelier_render_worker.gd","--","--session="+session,"--store="+ProjectSettings.globalize_path(root_path.path_join("store"))])
	_heartbeat()
	worker_pid=OS.create_process(OS.get_executable_path(),args,false)
	if worker_pid<0:return "Cannot launch Atelier render worker"
	status="idle";set_process(true);return ""
func invalidate() -> void:
	generation+=1;status="editing";_last_image=""
	_write({"generation":generation,"action":"cancel"})
	invalidated.emit(generation)
func submit(request: GemAssetRequest, mode := "preview", clip_index := 0, frame_index := 0, view: GemPrint.View = GemPrint.View.HOUSE_PRINT) -> String:
	var start_time:=Time.get_ticks_usec()
	if _closed or worker_pid<0:return "Render worker is closed"
	if mode not in ["preview","build","plan","inspect"]:return "Unknown Atelier action"
	var graph:=GemContentIdentity.graph_error(request)
	if not graph.is_empty():return graph
	invalidate()
	# The worker may observe cancellation while the immutable bundle is saved.
	# A subsequent action therefore needs its own monotonically newer generation.
	generation+=1
	var path:=session.path_join("request-%d.res"%generation)
	if GemResourceBundle.save(request,path)!=OK:return "Cannot freeze preview request"
	if not _write({"generation":generation,"action":mode,"request":path.get_file(),"sha256":FileAccess.get_sha256(path),"clip":clip_index,"frame":frame_index,"view":view}):return "Cannot send render request"
	status="queued";submit_ms=(Time.get_ticks_usec()-start_time)/1000.0
	return ""
func close() -> void:
	if _closed:return
	_closed=true;generation+=1;status="closed"
	_write({"generation":generation,"action":"stop"});set_process(false)
func _exit_tree() -> void:close()
func _process(_delta:float)->void:
	if Time.get_ticks_msec()>=_heartbeat_at:_heartbeat()
	if worker_pid>0 and not OS.is_process_running(worker_pid):
		status="error";updated.emit({"generation":generation,"status":"error","error":"Render worker exited; inspect "+session.path_join("worker.log")},null);set_process(false);return
	var path:=session.path_join("response.json")
	if not FileAccess.file_exists(path):return
	var content:=FileAccess.get_file_as_string(path)
	if content==_last_response:return
	_last_response=content
	var response:Variant=JSON.parse_string(content)
	if not response is Dictionary or int(response.get("generation",-1))!=generation:stale_results+=1;return
	var image:Image=null
	var image_file:=str(response.get("image",""))
	if not image_file.is_empty() and image_file!=_last_image:
		if image_file!=image_file.get_file() or not image_file.begins_with("preview-%d-"%generation):
			status="error";updated.emit({"status":"error","error":"Invalid worker image reference"},null);return
		var image_path:=session.path_join(image_file)
		if FileAccess.get_sha256(image_path)!=response.get("image_sha256"):return
		image=Image.load_from_file(image_path);_last_image=image_file
	status=str(response.get("status","error"));last_report=response
	updated.emit(response,image)
func _write(value:Dictionary)->bool:
	return not session.is_empty() and GemArtifactStore.atomic_write(session.path_join("request.json"),JSON.stringify(value).to_utf8_buffer())
func _heartbeat()->void:
	if session.is_empty():return
	GemArtifactStore.atomic_write(session.path_join("heartbeat"),str(Time.get_ticks_usec()).to_utf8_buffer())
	_heartbeat_at=Time.get_ticks_msec()+1000
