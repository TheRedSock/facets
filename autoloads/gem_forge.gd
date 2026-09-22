extends Node
## Read-only delivery and semantic presentation service. No optical dependencies.
signal library_changed
signal readiness_changed(assets_ready:bool,completed:int,total:int)
const DEFAULT_LIBRARY:="res://gem-assets/library.json"
const DEFAULT_CATALOG:="res://data/presentation/default.tres"
var library:=GemAssetLibrary.new()
var presentation:=GemPresentationIndex.new()
var last_error:=""
var assets_ready:=false
var _attempted:=false
var _load_ms:=0.0
var _prepare_generation:=0
var _prepared_pages:Array[Texture2D]=[]
var _retired_libraries:Array[GemAssetLibrary]=[]
var prefetch_budget_bytes:=128*1024*1024
var _required_page_bytes:=0
func _ready()->void:set_process(false)

## Failed replacement preserves the previous admitted library and binding map.
func open_library(path:String,catalog:GemDeliveryCatalog)->bool:
	_attempted=true;var started:=Time.get_ticks_usec()
	var candidate:=GemAssetLibrary.new();candidate.cache_budget_bytes=library.cache_budget_bytes
	if not candidate.open(path):last_error=candidate.last_error;return false
	var index:=GemPresentationIndex.new()
	if not index.open(catalog,candidate):last_error=index.last_error;return false
	library.clear_cache();_retired_libraries.append(library)
	library=candidate;presentation=index;last_error="";_load_ms=(Time.get_ticks_usec()-started)/1000.0
	_prepare_generation+=1;_prepared_pages.clear();assets_ready=false
	library_changed.emit();return true
func _ensure_open()->bool:
	if _attempted:return not presentation.bindings.is_empty()
	_attempted=true
	var default_pack:="res://generated/gem-assets.pck" if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("gem-assets.pck")
	var pack:String=ProjectSettings.get_setting("lapidary/delivery/pack",default_pack)
	if not FileAccess.file_exists(pack):last_error="Required gem asset pack is missing: "+pack;return false
	if not ProjectSettings.load_resource_pack(pack,false):last_error="Cannot mount required gem asset pack: "+pack;return false
	var catalog_path:String=ProjectSettings.get_setting("lapidary/delivery/catalog",DEFAULT_CATALOG)
	if not ResourceLoader.exists(catalog_path):last_error="Required presentation catalog is missing: "+catalog_path;return false
	return open_library(ProjectSettings.get_setting("lapidary/delivery/library",DEFAULT_LIBRARY),load(catalog_path) as GemDeliveryCatalog)
func get_clip(tile_id:StringName,role:StringName)->Dictionary:
	if not _ensure_open():return {}
	var key:=presentation.resolve(tile_id,role)
	if key.is_empty():last_error="Missing presentation role %s for tile %s"%[role,tile_id];return {}
	last_error="";return library.clip_info(key)
func get_frame(tile_id:StringName,role:StringName,index:int)->AtlasTexture:
	if not _ensure_open():return null
	var key:=presentation.resolve(tile_id,role)
	if key.is_empty():last_error="Missing presentation role %s for tile %s"%[role,tile_id];return null
	var texture:=library.frame(key,index)
	if texture==null:last_error=library.last_error if not library.last_error.is_empty() else "Missing frame %d in %s"%[index,key]
	else:last_error=""
	return texture

## Keep the declared upcoming pages alive until the next preparation. The run
## awaits readiness before displaying tiles or beginning its next presentation.
## Navigation-safe request: this persistent service owns the coroutine, and a
## freed scene's callback is never invoked. Callers still check their generation.
func request_required(tile_ids:Array,completed:Callable)->void:
	var prepared:bool=await prepare_required(tile_ids)
	if completed.is_valid():completed.call(prepared)

func prepare_required(tile_ids:Array,roles:Array[StringName]=GemPresentationIndex.REQUIRED_ROLES)->bool:
	assets_ready=false
	if not _ensure_open():return false
	_prepare_generation+=1;var generation:=_prepare_generation
	if not presentation.require_tiles(tile_ids):last_error=presentation.last_error;return false
	for tile in tile_ids:
		for role in roles:
			if presentation.resolve(StringName(tile),role).is_empty():last_error="Missing upcoming role %s for tile %s"%[role,tile];return false
	var pages:=library.required_pages(presentation.clip_keys(tile_ids,roles))
	_prepared_pages.clear();library.clear_cache()
	_required_page_bytes=0
	for key in pages:_required_page_bytes+=int(library.manifest.pages[key].gpu_bytes)
	var projected:int=library.projected_resident_bytes(pages)+int(_retired_memory().resident_texture_bytes)
	if projected>prefetch_budget_bytes:
		last_error="Upcoming gem textures require %d bytes including active views; delivery budget is %d bytes"%[projected,prefetch_budget_bytes];return false
	var retained:Array[Texture2D]=[]
	readiness_changed.emit(false,0,pages.size())
	for i in pages.size():
		if generation!=_prepare_generation:return false
		var texture:=library.load_page(pages[i])
		if texture==null:last_error=library.last_error;return false
		retained.append(texture);readiness_changed.emit(false,i+1,pages.size())
		if is_inside_tree():await get_tree().process_frame
	if generation!=_prepare_generation:return false
	_prepared_pages=retained;assets_ready=true;last_error="";readiness_changed.emit(true,pages.size(),pages.size());return true
func delivery_report()->Dictionary:
	var memory:=library.memory_report();var retired:=_retired_memory()
	memory.resident_texture_bytes+=retired.resident_texture_bytes;memory.resident_pages+=retired.resident_pages;memory.outside_cache_bytes+=retired.resident_texture_bytes
	return {"metadata_ms":_load_ms,"page_loads":library.page_loads,"memory":memory,"prefetched_pages":_prepared_pages.size(),"required_page_bytes":_required_page_bytes,"prefetch_budget_bytes":prefetch_budget_bytes,"ready":assets_ready,"tiles":presentation.bindings.size(),"clips":library.manifest.get("clips",{}).size(),"error":last_error}
func _retired_memory()->Dictionary:
	var result:={"resident_texture_bytes":0,"resident_pages":0}
	for old:GemAssetLibrary in _retired_libraries.duplicate():
		var memory:Dictionary=old.memory_report()
		if memory.resident_pages==0:_retired_libraries.erase(old)
		else:result.resident_texture_bytes+=memory.resident_texture_bytes;result.resident_pages+=memory.resident_pages
	return result
