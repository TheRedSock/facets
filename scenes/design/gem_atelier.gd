extends Control
## Durable resource editing and asynchronous production-worker preview/build.
const AtelierUi:=preload("res://scenes/design/atelier/atelier_ui.gd")
var auto_preview:=true
var document:=GemAuthoringDocument.new()
var client:GemPreviewClient
var _c:Dictionary={}
var _last_image:Image
var _render_at:=0
var _syncing:=false
var _dialog:FileDialog
var _dialog_action:=""
var _resource_path:Array=[]
var _pending_replace:=""
var _replace_dialog:ConfirmationDialog
var _pending_open:=""
var _discard_dialog:ConfirmationDialog
var _frame_times:Array[float]=[]
var _last_frame_usec:=0
func _ready()->void:
	_c=AtelierUi.build(self);client=GemPreviewClient.new();add_child(client)
	client.invalidated.connect(_invalidate);client.updated.connect(_response)
	_dialog=FileDialog.new();_dialog.access=FileDialog.ACCESS_FILESYSTEM;_dialog.filters=PackedStringArray(["*.tres,*.res ; Godot resources"]);add_child(_dialog);_dialog.file_selected.connect(_file_selected)
	_replace_dialog=ConfirmationDialog.new();_replace_dialog.title="Replace resource";add_child(_replace_dialog);_replace_dialog.confirmed.connect(func()->void:_save_to(_pending_replace,true))
	_discard_dialog=ConfirmationDialog.new();_discard_dialog.title="Unsaved changes";add_child(_discard_dialog);_discard_dialog.confirmed.connect(func()->void:_open(_pending_open,true))
	_c.inspector.value_edited.connect(edit_value);_c.inspector.problem.connect(_error)
	_c.inspector.resource_requested.connect(func(path:Array)->void:_resource_path=path;_choose("resource",FileDialog.FILE_MODE_OPEN_FILE))
	_c.inspector.resource_save_requested.connect(func(path:Array)->void:_resource_path=path;_choose("resource_save",FileDialog.FILE_MODE_SAVE_FILE))
	_c.automatic.button_pressed=auto_preview
	_c.automatic.toggled.connect(func(value:bool)->void:auto_preview=value;_queue_preview())
	_c.preview_now.pressed.connect(func()->void:_submit("preview"))
	_c.new.pressed.connect(_new_from_current);_c.open.pressed.connect(func()->void:_choose("open",FileDialog.FILE_MODE_OPEN_FILE))
	_c.save.pressed.connect(_save_current)
	_c.save_as.pressed.connect(func()->void:_choose("save",FileDialog.FILE_MODE_SAVE_FILE))
	_c.undo.pressed.connect(_undo)
	_c.redo.pressed.connect(_redo)
	_c.changes.pressed.connect(func()->void:_c.details.text=var_to_str(document.changes()))
	_c.cancel.pressed.connect(func()->void:_render_at=0;client.invalidate();_c.status.text="Canceled; valid worker checkpoints are retained.")
	_c.plan.pressed.connect(func()->void:_submit("plan"));_c.build.pressed.connect(func()->void:_submit("build"));_c.inspect.pressed.connect(_inspect)
	_c.background.item_selected.connect(_background_changed)
	_c.view.item_selected.connect(func(_index:int)->void:_queue_preview())
	_c.clips.item_selected.connect(func(_index:int)->void:_sync_frames();_queue_preview())
	_c.scrub.value_changed.connect(_scrub_changed)
	if DisplayServer.get_name()!="headless":
		var error:=client.start()
		if not error.is_empty():_error(error)
	_open("res://data/lapidary/stones/quartz.tres",true)
func _exit_tree()->void:
	if client!=null:client.close()
func _process(_delta:float)->void:
	# Engine delta can be smoothed/clamped; responsiveness measures wall time.
	var now:=Time.get_ticks_usec()
	if _last_frame_usec>0:_frame_times.append((now-_last_frame_usec)/1000.0)
	_last_frame_usec=now
	if _frame_times.size()>10000:_frame_times.pop_front()
	if _render_at>0 and Time.get_ticks_msec()>=_render_at:_render_at=0;_submit("preview")
func edit_value(path:Array,value:Variant)->void:
	var why:=document.edit(path,value)
	if not why.is_empty():_error(why);return
	_changed()
func _changed()->void:
	client.invalidate();_last_image=null
	var current:=document.snapshot() as GemAssetRequest
	_c.inspector.display(current);_c.path.text=("* " if document.dirty() else "")+(document.path if not document.path.is_empty() else "Untitled asset request")
	_c.undo.disabled=not document.can_undo();_c.redo.disabled=not document.can_redo()
	_syncing=true;var previous:int=_c.clips.selected;_c.clips.clear()
	for clip in current.clips:_c.clips.add_item(String(clip.clip_id) if clip!=null else "Missing clip")
	if not current.clips.is_empty():_c.clips.select(clampi(previous,0,current.clips.size()-1))
	_sync_frames();_syncing=false;_queue_preview()
func _sync_frames()->void:
	var current:=document.snapshot() as GemAssetRequest
	if current==null or _c.clips.selected<0 or _c.clips.selected>=current.clips.size() or current.clips[_c.clips.selected]==null:return
	var clip:GemClip=current.clips[_c.clips.selected]
	if not is_finite(clip.duration_s) or not is_finite(clip.fps) or clip.duration_s<=0 or clip.fps<=0:_c.scrub.max_value=0;return
	_c.scrub.max_value=maxi(0,clip.frame_count()-1);_c.frame.text="%d / %d"%[int(_c.scrub.value)+1,clip.frame_count()]
func _queue_preview()->void:
	_render_at=0
	client.invalidate();_c.frame.text="Frame %d"%(int(_c.scrub.value)+1)
	if client.worker_pid>0 and auto_preview:_render_at=Time.get_ticks_msec()+250
	else:_c.status.text="Auto preview paused." if client.worker_pid>0 else "Headless authoring: GPU preview requires a windowed Atelier."
func _submit(mode:String)->void:
	_render_at=0
	var error:=client.submit(document.snapshot() as GemAssetRequest,mode,maxi(0,_c.clips.selected),int(_c.scrub.value),_c.view.get_selected_id())
	if not error.is_empty():_error(error)
func _invalidate(_generation:int)->void:
	_last_image=null;_c.preview.texture=null;_c.thumb.texture=null;_c.cut_overlay.visible=false;_c.overlay.text="Pending request";_c.overlay.visible=true
func _response(report:Dictionary,image:Image)->void:
	_c.status.text=str(report.get("status",""))+" — "+str(report.get("error",""))
	if report.has("samples"):_c.status.text+=" %d / %d samples"%[report.samples,report.target_samples]
	if image!=null:
		_last_image=image;var texture:=ImageTexture.create_from_image(image);_c.preview.texture=texture;_c.thumb.texture=texture
		_c.thumb.custom_minimum_size=Vector2(image.get_size());_c.overlay.visible=false
	elif report.get("status")=="error":_last_image=null;_c.preview.texture=null;_c.thumb.texture=null;_c.overlay.text=str(report.error);_c.overlay.visible=true
	if report.has("inspection"):_c.cut_overlay.show_inspection(report.inspection);_c.overlay.visible=false
	_c.details.text=JSON.stringify(report,"  ")
func _choose(action:String,mode:FileDialog.FileMode)->void:
	_dialog_action=action;_dialog.title="Save resource (replace selected file)" if mode==FileDialog.FILE_MODE_SAVE_FILE else "Open resource";_dialog.file_mode=mode;_dialog.current_dir=ProjectSettings.globalize_path("res://data/lapidary");_dialog.popup_centered_ratio(.7)
func _file_selected(path:String)->void:
	match _dialog_action:
		"open":_open(path)
		"save","resource_save":_save_to(path,true) # Save dialog is the explicit destination/replacement decision.
		"resource":
			var value:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			if value==null:_error("Cannot load selected resource");return
			edit_value(_resource_path,value)
func _open(path:String,discard:=false)->void:
	if document.dirty() and not discard:_pending_open=path;_discard_dialog.dialog_text="Discard the current unsaved changes and open this resource?";_discard_dialog.popup_centered();return
	var incoming:=GemAuthoringDocument.new();var why:=incoming.open(path)
	if not why.is_empty():_error(why);return
	var resource:=incoming.snapshot()
	if resource is GemStone:
		var request:=GemAssetRequest.new();request.stone=resource;request.asset_id=resource.stone_id
		request.rig=load("res://data/lapidary/rigs/gameplay_studio.tres");request.print_style=GemPrint.load_house();request.clips=[load("res://data/lapidary/clips/idle.tres")]
		document.create(request)
	elif resource is GemAssetRequest:document=incoming
	else:_error("Open a GemStone or GemAssetRequest; load cuts/materials into a selected branch.");return
	_changed()
func _save_to(path:String,replace:bool)->void:
	var target:=document
	if _dialog_action=="resource_save":
		target=GemAuthoringDocument.new();var selected:Variant=GemResourceInspector.value_at(document.snapshot(),_resource_path)
		if not selected is Resource:_error("Select a resource to save");return
		target.create(selected)
	var why:=target.save(path,replace)
	if not why.is_empty():
		if "explicit" in why and FileAccess.file_exists(path):_pending_replace=path;_replace_dialog.dialog_text="Replace the existing resource at "+path+"?";_replace_dialog.popup_centered()
		else:_error(why)
		return
	if target!=document:
		why=document.edit(_resource_path,target.snapshot())
		if not why.is_empty():_error(why);return
	_changed();_c.status.text="Saved and reloaded "+path
func _new_from_current()->void:
	var request:=document.snapshot() as GemAssetRequest
	if request==null:return
	var identifier:=StringName(String(request.asset_id)+"_new")
	request.asset_id=identifier
	if request.stone!=null:request.stone.stone_id=identifier
	document.create(request);_changed()
func _background_changed(index:int)->void:_c.well.color=[Color("10141c"),Color.BLACK,Color.WHITE][index]
func _inspect()->void:_submit("inspect")
func _error(message:String)->void:_c.status.text=message
func debug_get_preview_image()->Image:return _last_image
func debug_get_render_state()->Dictionary:return {"status":client.status,"generation":client.generation,"report":client.last_report,"submit_ms":client.submit_ms,"frame_ms":_frame_times.duplicate(),"session":client.session,"worker_pid":client.worker_pid}

func _save_current()->void:
	if document.path.is_empty():_choose("save",FileDialog.FILE_MODE_SAVE_FILE)
	else:_dialog_action="save";_save_to(document.path,false)
func _undo()->void:
	if document.undo():_changed()
func _redo()->void:
	if document.redo():_changed()
func _scrub_changed(_value:float)->void:
	if not _syncing:_queue_preview()
