class_name TileView
extends Control
## One delivered tile. BoardScene owns translation/scale/modulate choreography.
signal playback_completed(role:StringName)
signal playback_interrupted(role:StringName)
signal delivery_failed(message:String)
const REST_ROLE:=&"rest"
var cell:=Vector2i.ZERO
var tile_id:StringName=&""
var tier:=0
var _clip_rect:TextureRect
var _forge:Node
var _role:StringName=&""
var _frames:=0
var _fps:=1.0
var _loop:=false
var _frame:=0
var _elapsed:=0.0
func _ready()->void:
	mouse_filter=MOUSE_FILTER_IGNORE
	_clip_rect=TextureRect.new();_clip_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_clip_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_clip_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_clip_rect.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;_clip_rect.mouse_filter=MOUSE_FILTER_IGNORE;add_child(_clip_rect)
	pivot_offset=size*.5;resized.connect(func()->void:pivot_offset=size*.5);set_process(false)
	_forge=get_node_or_null("/root/GemForge")
	if _forge!=null:_forge.library_changed.connect(_show_rest)
	if tile_id!=&"":_show_rest()
func _exit_tree()->void:
	if _forge!=null and _forge.library_changed.is_connected(_show_rest):_forge.library_changed.disconnect(_show_rest)
func configure(tile:TileState,new_cell:Vector2i)->void:configure_from_data(tile.tile_id,tile.tier,new_cell)
func configure_from_data(id:StringName,new_tier:int,new_cell:Vector2i)->void:
	_interrupt();tile_id=id;tier=new_tier;cell=new_cell
	if is_inside_tree():_show_rest()
func show_upgrade_full(new_tier:int,new_tile_id:StringName)->void:configure_from_data(new_tile_id,new_tier,cell)

## Restart is explicit. Replacing an active role emits interruption; natural
## oneshot completion emits completion and restores the catalog's rest role.
func play_role(role:StringName,restart:=true)->bool:
	if role==_role and not restart:return true
	_interrupt()
	if _forge==null:return _fail("Gem delivery service is unavailable")
	var clip:Dictionary=_forge.get_clip(tile_id,role)
	if clip.is_empty():return _fail(_forge.last_error)
	var texture:AtlasTexture=_forge.get_frame(tile_id,role,0)
	if texture==null:return _fail(_forge.last_error)
	_role=role;_frames=int(clip.frames);_fps=float(clip.fps);_loop=bool(clip.loop);_frame=0;_elapsed=0
	_clip_rect.texture=texture;set_process(_frames>1 or (not _loop and role!=REST_ROLE));return true
func return_to_rest()->void:_show_rest()
func _show_rest()->void:
	if tile_id!=&"":play_role(REST_ROLE)
func _process(delta:float)->void:
	if not is_visible_in_tree():return
	_elapsed+=delta;var next:=int(_elapsed*_fps)
	if next>=_frames:
		if _loop:next%=_frames
		else:
			var completed:=_role;_role=&"";set_process(false);_show_rest();playback_completed.emit(completed);return
	if next!=_frame:
		var texture:AtlasTexture=_forge.get_frame(tile_id,_role,next)
		if texture==null:_fail(_forge.last_error);return
		_frame=next;_clip_rect.texture=texture
func _interrupt()->void:
	var prior:=_role;var active:=is_processing();_role=&"";set_process(false)
	if active:playback_interrupted.emit(prior)
func _fail(message:String)->bool:
	_interrupt();_frames=0
	if _clip_rect!=null:_clip_rect.texture=null
	delivery_failed.emit(message);return false
