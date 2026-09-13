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
	_select(inspector,["clips",0,"effect_envelopes","key_boost"]);inspector.editor.text="[Vector4(0, 1, 0, 0), Vector4(0.5, 1.5, 0, 0), Vector4(1, 1, 0, 0)]";inspector.call("_apply")
	check(document.snapshot().clips[0].effect_envelopes.key_boost.point_count==3,"Effect curve replacement preserves authored points")
	inspector.call("_remove");check(document.snapshot().clips[0].effect_envelopes.is_empty(),"Named curve removal edits its dictionary")
	# Author a real tilt/return through the generic key and tangent widgets.
	scene.call("edit_value",["clips",0,"fps"],12.0)
	_select(inspector,["clips",0,"orientation_keys"]);inspector.call("_add")
	_select(inspector,["clips",0,"orientation_keys",1,"time"]);inspector.editor.text="0.5";inspector.call("_apply")
	_select(inspector,["clips",0,"orientation_keys",1,"orientation"]);inspector.editor.text="Vector3(-12, 12, 0)";inspector.call("_apply")
	_select(inspector,["clips",0,"orientation_keys"]);inspector.call("_add")
	_select(inspector,["clips",0,"orientation_keys",2,"time"]);inspector.editor.text="1.0";inspector.call("_apply")
	_select(inspector,["clips",0,"orientation_keys",2,"orientation"]);inspector.editor.text="Vector3(-12, 0, 0)";inspector.call("_apply")
	_select(inspector,["clips",0,"time_curve"]);inspector.call("_new_resource")
	_select(inspector,["clips",0,"time_curve"]);inspector.editor.text="[Vector4(0, 0, 0, 0), Vector4(0.5, 0.5, 0, 0), Vector4(1, 1, 0, 0)]";inspector.call("_apply")
	var authored_clip:GemClip=document.snapshot().clips[0]
	check(authored_clip.track_error().is_empty(),"Generic orientation/time controls author an admitted closed tilt")
	check(authored_clip.time_curve.get_point_right_tangent(1)==0 and authored_clip.orientation_keys.size()==3,"Curve slopes and key resources survive detached editing")
	check(GemClipSampler.frame_orientation(authored_clip,.5).angle_to(GemClipSampler.frame_orientation(authored_clip,0))>.1,"Authored keys produce real motion through the shared sampler")
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
	_select(inspector,["stone","cut","parameters"])
	var cut_parameters:Dictionary=document.snapshot().stone.cut.parameters.duplicate()
	cut_parameters["table"]=.49;inspector.editor.text=var_to_str(cut_parameters);inspector.call("_apply")
	check(document.snapshot().stone.cut.parameters.table==.49,"Cut parameter editor changes the declarative design")
	scene.call("_new_from_current")
	check(document.path.is_empty(),"New asset cannot accidentally Save over the old file")
	var current:GemAssetRequest=document.snapshot()
	check(current.asset_id==&"quartz_new" and current.stone.cut.cut_id==&"new_authored_cut","New asset carries the edited declarative cut")
	var output:="res://artifacts/atelier-ui/%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(output)
	var clip_document:=GemAuthoringDocument.new();clip_document.create(authored_clip)
	check(clip_document.save(output.path_join("authored tilt.tres")).is_empty(),"Authored clip saves as a reusable resource")
	var curve_document:=GemAuthoringDocument.new();curve_document.create(authored_clip.time_curve)
	check(curve_document.save(output.path_join("authored time curve.tres")).is_empty(),"Authored time curve saves through public admission")
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
	var transient:=output.path_join("transient");DirAccess.make_dir_recursive_absolute(transient)
	for filename in ["request-1.res","request-3.res","request-5.res","preview-1-1.png","preview-3-2.png","preview-3-3.png","request-notes.res","preview-review.png"]:
		GemArtifactStore.atomic_write(transient.path_join(filename),"fixture".to_utf8_buffer())
	DirAccess.make_dir_recursive_absolute(transient.path_join("delivery-1"))
	GemArtifactStore.atomic_write(transient.path_join("delivery-1/library.json"),"durable".to_utf8_buffer())
	check(GemAtelierSessionFiles.collect(transient,3).is_empty(),"Worker collects exact transient names")
	check(not FileAccess.file_exists(transient.path_join("request-1.res")) and not FileAccess.file_exists(transient.path_join("preview-1-1.png")),"Consumed old requests and superseded preview images are removed")
	for filename in ["request-3.res","request-5.res","preview-3-2.png","preview-3-3.png","request-notes.res","preview-review.png","delivery-1/library.json"]:
		check(FileAccess.file_exists(transient.path_join(filename)),"Collection preserves current/future requests, recent images and durable files: "+filename)
	var retry:=GemPreviewClient.new();retry.session=ProjectSettings.globalize_path(transient);retry.generation=7
	var delivered:Array[Image]=[];retry.updated.connect(func(_report:Dictionary,image:Image):delivered.append(image))
	var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color.RED)
	var bytes:=image.save_png_to_buffer();var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	var response:={"generation":7,"status":"complete","image":"preview-7-4.png","image_sha256":hash.finish().hex_encode()}
	for incomplete in ["", "{\"generation\":", "[]"]:
		GemArtifactStore.atomic_write(transient.path_join("response.json"),incomplete.to_utf8_buffer())
		retry.call("_process",0.0)
		check(delivered.is_empty() and retry.stale_results==0,"Incomplete mailbox does not consume a response or log a parse error")
		check(GemAtelierSessionFiles.read_message(transient.path_join("response.json"),submitted)==submitted,"Incomplete request preserves the worker's current action")
	GemArtifactStore.atomic_write(transient.path_join("response.json"),JSON.stringify(response).to_utf8_buffer())
	retry.call("_process",0.0);check(delivered.is_empty(),"Missing/superseded image is not accepted")
	GemArtifactStore.atomic_write(transient.path_join(response.image),bytes)
	retry.call("_process",0.0)
	check(delivered.size()==1 and delivered[0].get_data()==image.get_data(),"Unchanged response is retried and its verified bytes are displayed")
	retry.call("_process",0.0);check(delivered.size()==1,"Accepted response is emitted only once")
	retry.free()
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
