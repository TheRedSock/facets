extends SceneTree
## Run externally with the editor binary --main-pack GAME.pck --headless.
## Audits the exact exported resources, not the source project's dependencies.
const ALLOWED_ROOTS := ["autoloads/", "core/board/", "core/rules/", "core/run/", "core/delivery/", "resources/definitions/", "resources/delivery/", "data/tiles/", "data/presentation/", "scenes/board/", "scenes/tile/", "scenes/run/", "scenes/main/", "scenes/menu/", "scenes/debug/"]
var failures:Array[String]=[]
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var args:={"pack":"","report":""}
	for argument in OS.get_cmdline_user_args():
		var pair:=argument.trim_prefix("--").split("=",true,1)
		if pair.size()!=2 or not args.has(pair[0]):printerr("FAIL: Unknown package audit argument");quit(1);return
		args[pair[0]]=pair[1]
	if args.pack.is_empty() or args.report.is_empty():printerr("FAIL: pack and report paths are required");quit(1);return
	var main_files:Dictionary={};_inventory("res://",main_files)
	if FileAccess.file_exists("res://core/lapidary/stone_compiler.gd"):failures.append("Source tree is accessible to package audit")
	for path:String in main_files:
		if not _allowed(path):failures.append("Unexpected main-package file: "+path)
	var classes:=ConfigFile.new()
	if classes.load("res://.godot/global_script_class_cache.cfg")!=OK:failures.append("Missing exported script class cache")
	else:
		for entry:Dictionary in classes.get_value("","list",[]):
			if not _runtime_path(entry.path) or not ResourceLoader.exists(entry.path):failures.append("Unavailable/non-runtime exported class: "+str(entry))
	var tiles:Array=[]
	for file in ResourceLoader.list_directory("res://data/tiles"):
		if file.ends_with(".tres"):
			var definition:Resource=load("res://data/tiles/"+file)
			tiles.append(definition.tile_id)
	if tiles.is_empty():failures.append("Exported tile catalog is empty")
	var library:=GemAssetLibrary.new();var index:=GemPresentationIndex.new()
	var all_files:Dictionary={};var gem_files:Dictionary={};var memory:Dictionary={}
	if not FileAccess.file_exists(args.pack):failures.append("Missing gem pack: "+args.pack)
	elif not ProjectSettings.load_resource_pack(args.pack,false):failures.append("Cannot mount gem pack")
	elif not library.open("res://gem-assets/library.json"):failures.append(library.last_error)
	elif not index.open(load("res://data/presentation/default.tres"),library) or not index.require_tiles(tiles):failures.append(index.last_error)
	else:
		_inventory("res://",all_files)
		var expected:Array[String]=["res://gem-assets/library.json"]
		for page:Dictionary in library.manifest.pages.values():expected.append("res://gem-assets/"+String(page.path))
		for path:String in all_files:
			if main_files.has(path):
				if main_files[path]!=all_files[path]:failures.append("Gem pack shadows game resource: "+path)
			else:
				gem_files[path]=all_files[path]
				if path not in expected:failures.append("Unreferenced file in gem pack: "+path)
		for path in expected:
			if not gem_files.has(path):failures.append("Gem pack lacks referenced file: "+path)
		for key:String in library.manifest.pages:
			if library.load_page(key)==null:failures.append(library.last_error)
		memory=library.memory_report()
	var report:={"status":"passed" if failures.is_empty() else "failed","failures":failures,"main_files":main_files,"gem_files":gem_files,"tiles":tiles,"semantic_clips":index.clip_keys(tiles,GemPresentationIndex.REQUIRED_ROLES).size(),"page_loads":library.page_loads,"memory":memory,"godot":Engine.get_version_info(),"execution":"editor binary, exact exported PCK"}
	var output:=FileAccess.open(args.report,FileAccess.WRITE)
	if output==null:printerr("FAIL: Cannot write package audit report");quit(1);return
	output.store_string(JSON.stringify(report,"\t"));output.close()
	for failure in failures:printerr("FAIL: "+failure)
	print("CHECK_COMPLETE: audit_game_package");quit(1 if not failures.is_empty() else 0)
static func _runtime_path(path:String)->bool:
	for prefix:String in ALLOWED_ROOTS:
		if path.begins_with("res://"+prefix):return true
	return false
static func _allowed(path:String)->bool:
	if _runtime_path(path):return true
	if path in ["res://project.binary","res://icon.svg","res://icon.svg.import","res://.godot/global_script_class_cache.cfg","res://.godot/uid_cache.bin"]:return true
	return path.begins_with("res://.godot/exported/") or path.begins_with("res://.godot/imported/icon.svg-")
static func _inventory(path:String,entries:Dictionary)->void:
	var directory:=DirAccess.open(path)
	if directory==null:return
	directory.include_hidden=true
	for file in directory.get_files():
		var full:=path.path_join(file);entries[full]=FileAccess.get_sha256(full)
	for child in directory.get_directories():
		if child not in [".",".."]:_inventory(path.path_join(child),entries)
