class_name GemPresentationIndex
extends RefCounted
## Shared build/runtime completeness gate. No asset-name parsing or simulation writes.
const REQUIRED_ROLES:Array[StringName]=[&"rest",&"upgrade"]
var bindings:Dictionary={}
var last_error:=""
func open(catalog:GemDeliveryCatalog,library:GemAssetLibrary)->bool:
	last_error=""
	if catalog==null or catalog.bindings.is_empty():return _fail("Presentation catalog is missing or empty")
	var accepted:Dictionary={}
	for binding in catalog.bindings:
		if binding==null or not _identifier(binding.tile_id) or not _identifier(binding.asset_id):return _fail("Presentation binding needs explicit tile and asset identifiers without slashes")
		if accepted.has(binding.tile_id):return _fail("Duplicate presentation tile: "+String(binding.tile_id))
		for role in REQUIRED_ROLES:
			if not binding.roles.has(role):return _fail("Tile %s lacks required role %s"%[binding.tile_id,role])
		var roles:Dictionary={}
		for role in binding.roles:
			if not _identifier(role) or not _identifier(binding.roles[role]):return _fail("Invalid role/clip identifier for "+String(binding.tile_id))
			var key:=String(binding.asset_id)+"/"+String(binding.roles[role])
			var clip:=library.clip_info(key)
			if clip.is_empty():return _fail("Tile %s role %s requires missing clip %s"%[binding.tile_id,role,key])
			if role==&"rest" and int(clip.frames)>1 and not clip.loop:return _fail("Rest clip must be a still or a loop: "+key)
			if role==&"upgrade" and clip.loop:return _fail("Upgrade clip must complete: "+key)
			roles[role]=key
		accepted[binding.tile_id]=roles
	bindings=accepted;return true
func require_tiles(tile_ids:Array)->bool:
	last_error=""
	for id in tile_ids:
		if not bindings.has(StringName(id)):return _fail("Missing presentation binding for tile "+str(id))
	return true
func resolve(tile_id:StringName,role:StringName)->String:
	return bindings.get(tile_id,{}).get(role,"")
func clip_keys(tile_ids:Array,roles:Array[StringName])->Array[String]:
	var result:Array[String]=[]
	for tile in tile_ids:
		for role in roles:
			var key:=resolve(StringName(tile),role)
			if not key.is_empty() and key not in result:result.append(key)
	return result
static func _identifier(value:StringName)->bool:
	var text:=String(value)
	return not text.is_empty() and text==text.strip_edges() and "/" not in text and "\\" not in text
func _fail(message:String)->bool:last_error=message;return false
