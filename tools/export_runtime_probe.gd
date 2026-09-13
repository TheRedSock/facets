extends SceneTree
## External package integration harness: editor binary --main-pack GAME.pck
## --script ABSOLUTE_PATH -- --pack=GEMS.pck --report=REPORT.json.
## Standard export templates disable script overrides. This checks packaged
## code/assets; actual release-executable UI acceptance is a separate check.
var failures:Array[String]=[]
var samples:Array[float]=[]
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var output:=""
	var pack:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):output=argument.trim_prefix("--report=")
		elif argument.begins_with("--pack="):pack=argument.trim_prefix("--pack=")
		else:printerr("FAIL: Unknown package probe argument");quit(1);return
	if output.is_empty() or pack.is_empty():printerr("FAIL: report and pack paths are required");quit(1);return
	ProjectSettings.set_setting("lapidary/delivery/pack",pack)
	_mark(output,"started")
	create_timer(45).timeout.connect(func()->void:_mark(output,"timeout");printerr("FAIL: export probe timed out");quit(1))
	var package_entries:Array[String]=[];_inventory("res://",package_entries)
	if FileAccess.file_exists("res://core/lapidary/stone_compiler.gd"):failures.append("Source tree is accessible to package probe")
	var started:=Time.get_ticks_usec()
	var scene:Control=load("res://scenes/run/run_scene.tscn").instantiate();root.add_child(scene)
	_mark(output,"scene_created")
	var forge:Node=root.get_node("GemForge")
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if not scene.get("_delivery_error").is_empty():failures.append(scene.get("_delivery_error"));break
		if forge.assets_ready and scene.get("board_scene").get("_tile_views").size()>0:break
	var cold_ms:=(Time.get_ticks_usec()-started)/1000.0
	_mark(output,"ready_wait_finished")
	var views:Dictionary=scene.get("board_scene").get("_tile_views")
	if views.is_empty():failures.append("Exported board has no tile views")
	var loaded:=0
	for view:TileView in views.values():
		if view.get("_clip_rect").texture is AtlasTexture:loaded+=1
	if loaded!=views.size():failures.append("Not every exported tile has a delivered texture")
	var before:Dictionary=forge.delivery_report()
	for view:TileView in views.values():
		if not view.play_role(&"upgrade"):failures.append("Upgrade role cannot play")
	var previous:=Time.get_ticks_usec()
	for frame in 180:
		await process_frame
		var now:=Time.get_ticks_usec();samples.append((now-previous)/1000.0);previous=now
	_mark(output,"motion_sampled")
	for view:TileView in views.values():
		if view.get("_role")!=&"rest":failures.append("Oneshot did not return to rest")
	var after:Dictionary=forge.delivery_report()
	if after.page_loads!=before.page_loads:failures.append("Prefetched animation burst triggered additional page loads")
	if DisplayServer.get_name()!="headless":
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(output.get_basename()+".png")
	samples.sort()
	var report:={"status":"passed" if failures.is_empty() else "failed","failures":failures,"cold_ready_ms":cold_ms,"tile_views":views.size(),"loaded_views":loaded,"before":before,"after":after,"frame_ms":{"p50":samples[samples.size()/2],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples.back()},"renderer":RenderingServer.get_video_adapter_name(),"godot":Engine.get_version_info(),"executable":OS.get_executable_path(),"source_tree_available":FileAccess.file_exists("res://core/lapidary/stone_compiler.gd")}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	var inventory:=FileAccess.open(output.get_basename()+"-package.json",FileAccess.WRITE);inventory.store_string(JSON.stringify(package_entries,"\t"));inventory.close()
	scene.free()
	print("CHECK_COMPLETE: export_runtime_probe");quit(1 if not failures.is_empty() else 0)
func _mark(output:String,stage:String)->void:
	var file:=FileAccess.open(output.get_basename()+"-progress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"stage":stage,"ticks_ms":Time.get_ticks_msec()}));file.close()
func _inventory(path:String,entries:Array[String])->void:
	var directory:=DirAccess.open(path)
	if directory==null:return
	directory.include_hidden=true
	for file in directory.get_files():entries.append(path.path_join(file))
	for child in directory.get_directories():
		if child not in [".",".."]:_inventory(path.path_join(child),entries)
