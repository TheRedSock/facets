extends SceneTree
## Real headless authoring controls remain usable without starting a GPU process.
var failures:=0
func _initialize()->void:_run.call_deferred()
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("FAIL: "+message)
func _run()->void:
	var scene:Control=load("res://scenes/design/gem_atelier.tscn").instantiate();root.add_child(scene)
	await process_frame
	var document:GemAuthoringDocument=scene.get("document")
	var before:GemAssetRequest=document.snapshot()
	check(before.stone!=null and before.clips.size()==1,"Source stone becomes an editable asset request")
	check(scene.get("client").worker_pid==-1,"Headless UI does not launch a GPU process")
	check(not scene.get("client").is_processing(),"Unstarted client does not poll files or write heartbeats")
	var inspector:GemResourceInspector=scene.get("_c").inspector
	_select(inspector,["stone","size_mm"]);inspector.editor.text="3.125";inspector.call("_apply")
	check(document.snapshot().stone.size_mm==3.125,"Actual value editor applies a physical scalar")
	_select(inspector,["game_style"]);inspector.call("_new_resource")
	check(document.snapshot().game_style is GemStyle,"Nullable resource slot can create its declared schema")
	inspector.call("_clear_resource");check(document.snapshot().game_style==null,"Resource slot can be explicitly cleared")
	_select(inspector,["stone","condition","volume_fields"]);inspector.call("_add")
	check(document.snapshot().stone.condition.volume_fields.size()==1,"Typed resource arrays add a real volume field")
	_select(inspector,["stone","condition","volume_fields",0]);inspector.call("_remove")
	check(document.snapshot().stone.condition.volume_fields.is_empty(),"Typed resource array removal participates in document editing")
	_select(inspector,["clips",0,"effect_envelopes"]);inspector.entry_key.text="key_boost";inspector.call("_add")
	check(document.snapshot().clips[0].effect_envelopes.get("key_boost") is Curve,"Named effect track creates a real editable curve")
	_select(inspector,["clips",0,"effect_envelopes","key_boost"]);inspector.editor.text="[Vector2(0, 1), Vector2(0.5, 1.5), Vector2(1, 1)]";inspector.call("_apply")
	check(document.snapshot().clips[0].effect_envelopes.key_boost.point_count==3,"Effect curve replacement preserves authored points")
	inspector.call("_remove");check(document.snapshot().clips[0].effect_envelopes.is_empty(),"Named curve removal edits its dictionary")
	var term:=GemAbsorber.new();term.chromophore=GemChromophore.new();term.chromophore.wavelength_step_nm=400;term.chromophore.absorption_mm=PackedFloat32Array([.01,.01])
	var terms:Array[GemAbsorber]=[term];scene.call("edit_value",["stone","material","absorbers"],terms)
	_select(inspector,["stone","material","absorbers",0,"unit"])
	check(inspector.choice.visible and inspector.choice.item_count>1,"Absorber units are named choices")
	var old_unit:int=document.snapshot().stone.material.absorbers[0].unit
	inspector.choice.select((inspector.choice.selected+1)%inspector.choice.item_count);inspector.call("_apply")
	check(document.snapshot().stone.material.absorbers[0].unit!=old_unit,"Unit selector applies a typed enum")
	scene.call("_undo")
	scene.call("edit_value",["stone","size_mm"],-1.0)
	check(not document.validation_error().is_empty() and scene.call("debug_get_preview_image")==null,"Invalid draft clears image and remains editable")
	scene.call("_undo");check(document.validation_error().is_empty(),"UI undo restores admitted values")
	scene.call("edit_value",["stone","cut","cut_id"],&"new_authored_cut")
	scene.call("_new_from_current")
	check(document.path.is_empty(),"New asset cannot accidentally Save over the old file")
	var current:GemAssetRequest=document.snapshot()
	check(current.asset_id==&"quartz_new" and current.stone.cut.cut_id==&"new_authored_cut","New asset carries the edited declarative cut")
	var output:="res://artifacts/atelier-ui/%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(output)
	var path:=output.path_join("new gem ø.tres")
	check(document.save(path).is_empty(),"UI document saves new request")
	var reopened:=GemAuthoringDocument.new();check(reopened.open(path).is_empty(),"Saved request reopens through shared admission")
	check(GemContentIdentity.digest(reopened.snapshot())==GemContentIdentity.digest(document.snapshot()),"Saved/reopened values are identical")
	check(load("res://data/lapidary/stones/quartz.tres").cut.cut_id!=&"new_authored_cut","Source/shared resources stay unchanged")
	# Observe the intermediate cancel synchronously, as a worker can while saving.
	var protocol:=GemPreviewClient.new();protocol.session=ProjectSettings.globalize_path(output);protocol.worker_pid=1
	var observed:Array[int]=[]
	protocol.invalidated.connect(func(_generation:int):
		var message:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(protocol.session.path_join("request.json")))
		observed.append(int(message.generation)))
	check(protocol.submit(document.snapshot(),"build").is_empty(),"Protocol freezes a real request")
	var submitted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(protocol.session.path_join("request.json")))
	check(observed.size()==1 and int(submitted.generation)>observed[0],"Build remains newer when worker already consumed cancellation")
	protocol.free()
	scene.free();await process_frame
	print("Atelier document UI failures: ",failures);print("CHECK_COMPLETE: test_atelier_document_ui");quit(1 if failures else 0)

func _select(inspector:GemResourceInspector,path:Array)->void:
	var item:=inspector.tree.get_root()
	for depth in path.size():
		if item.collapsed:item.collapsed=false;inspector.call("_collapse",item)
		var found:TreeItem=null
		for child in item.get_children():
			if child.get_metadata(0)==path.slice(0,depth+1):found=child;break
		if found==null:check(false,"Missing editor path "+str(path));return
		item=found
	item.select(0);inspector.call("_select")
