extends SceneTree
## Build-time presentation completeness. No RenderingDevice or optical work.
func _initialize()->void:
	var args:Dictionary={"library":"res://generated/gem-library/library.json","catalog":"res://data/presentation/default.tres"}
	for argument in OS.get_cmdline_user_args():
		var pair:=argument.trim_prefix("--").split("=",true,1)
		if pair.size()!=2 or not args.has(pair[0]):_fail("Unknown delivery validation argument");return
		args[pair[0]]=pair[1]
	if not ResourceLoader.exists(args.catalog):_fail("Presentation catalog is missing: "+args.catalog);return
	var library:=GemAssetLibrary.new();var index:=GemPresentationIndex.new()
	if not library.open(args.library):_fail(library.last_error);return
	if not index.open(load(args.catalog) as GemDeliveryCatalog,library):_fail(index.last_error);return
	var tiles:Array=[]
	for file in ResourceLoader.list_directory("res://data/tiles"):
		if file.ends_with(".tres"):tiles.append(load("res://data/tiles/"+file).tile_id)
	if tiles.is_empty() or not index.require_tiles(tiles):_fail("Required tile catalog is incomplete: "+index.last_error);return
	print("Delivery completeness: %d tiles, %d semantic clips"%[tiles.size(),index.clip_keys(tiles,GemPresentationIndex.REQUIRED_ROLES).size()])
	print("CHECK_COMPLETE: validate_gem_delivery");quit()
func _fail(message:String)->void:printerr("FAIL: "+message);quit(1)
