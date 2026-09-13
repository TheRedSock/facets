class_name GemResourceInspector
extends VBoxContainer
## Lazy resource tree with typed literal editing. All mutations go through the document.
signal value_edited(path: Array, value: Variant)
signal resource_requested(path: Array)
signal resource_save_requested(path: Array)
signal problem(message: String)
var tree: Tree
var editor: TextEdit
var hint: Label
var choice: OptionButton
var entry_key: LineEdit
var _snapshot: Resource
var _selected: Array = []
var _expanded := {}
var _syncing := false
func _ready()->void:
	tree=Tree.new();tree.columns=2;tree.set_column_title(0,"Resource / property");tree.set_column_title(1,"Value");tree.column_titles_visible=true
	tree.size_flags_vertical=Control.SIZE_EXPAND_FILL;tree.custom_minimum_size=Vector2(500,300);add_child(tree)
	tree.item_selected.connect(_select);tree.item_collapsed.connect(_collapse)
	hint=Label.new();hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	var caption:=Label.new();caption.text="Selected value";add_child(caption)
	choice=OptionButton.new();choice.visible=false;add_child(choice)
	editor=TextEdit.new();editor.custom_minimum_size.y=95;add_child(editor)
	entry_key=LineEdit.new();entry_key.placeholder_text="New dictionary entry name";entry_key.visible=false;add_child(entry_key)
	var row:=HBoxContainer.new();add_child(row)
	for action in [["Apply value",_apply],["Load resource",_load],["New resource",_new_resource],["Clear resource",_clear_resource],["Save selected resource",_save],["Add element",_add],["Remove element",_remove]]:
		var button:=Button.new();button.text=action[0];button.pressed.connect(action[1]);row.add_child(button)
func display(resource:Resource)->void:
	_snapshot=resource;_syncing=true;tree.clear();var root:=tree.create_item();root.set_text(0,"Asset request");root.set_metadata(0,[])
	_fill(resource,root,[]);_syncing=false
	var selected:=_find_path(root,_selected)
	if selected!=null:selected.select(0);_select()
	else:_selected=[];editor.text="";hint.text="Select a property";choice.visible=false;editor.visible=true
func _find_path(item:TreeItem,path:Array)->TreeItem:
	if item.get_metadata(0)==path:return item
	for child in item.get_children():
		var found:=_find_path(child,path)
		if found!=null:return found
	return null
func selected_path()->Array:return _selected.duplicate()
func selected_value()->Variant:return value_at(_snapshot,_selected)
static func value_at(root:Variant,path:Array)->Variant:
	var value:Variant=root
	for key in path:
		if value==null:return null
		value=value[key]
	return value
func _fill(value:Variant,parent:TreeItem,path:Array)->void:
	if value is Curve:
		var item:=tree.create_item(parent);item.set_text(0,"Linear curve points");item.set_metadata(0,path);item.set_metadata(1,{"curve":true});item.set_text(1,str(value.point_count)+" points");return
	if value is Resource:
		for property:Dictionary in value.get_property_list():
			if not GemContentIdentity._content_property(property) or String(property.name).begins_with("_"):continue
			if not _active(value,property.name):continue
			_row(parent,path+[property.name],value.get(property.name),property)
	elif value is Array:
		for i in value.size():_row(parent,path+[i],value[i],{})
	elif value is Dictionary:
		for key in value:_row(parent,path+[key],value[key],{})
func _row(parent:TreeItem,path:Array,value:Variant,property:Dictionary)->void:
	var item:=tree.create_item(parent);item.set_metadata(0,path);item.set_metadata(1,property)
	item.set_text(0,str(path.back()));item.set_tooltip_text(0,_help(path,property))
	var label:=str(value)
	if value is Resource:label=value.get_script().get_global_name() if value.get_script()!=null else value.get_class()
	elif value is Array:label="%d elements"%value.size()
	elif value is Dictionary:label="%d entries"%value.size()
	item.set_text(1,label.left(120));item.set_tooltip_text(1,label)
	if value is Resource or value is Array or value is Dictionary:
		var key:=var_to_str(path);item.collapsed=not _expanded.has(key)
		if item.collapsed:tree.create_item(item).set_text(0,"Expand to inspect")
		else:_fill(value,item,path);item.set_meta("loaded",true)
func _collapse(item:TreeItem)->void:
	if _syncing:return
	var path:Array=item.get_metadata(0);var key:=var_to_str(path)
	if item.collapsed:_expanded.erase(key);return
	_expanded[key]=true
	if not item.has_meta("loaded"):
		for child in item.get_children():child.free()
		_fill(value_at(_snapshot,path),item,path);item.set_meta("loaded",true)
func _select()->void:
	if _syncing:return
	var item:=tree.get_selected()
	if item==null:return
	_selected=item.get_metadata(0);var value:Variant=selected_value();var meta:Dictionary=item.get_metadata(1) if item.get_metadata(1) is Dictionary else {}
	choice.visible=false;editor.visible=true;choice.clear()
	entry_key.visible=value is Dictionary
	if meta.get("hint",-1)==PROPERTY_HINT_ENUM:
		choice.visible=true;editor.visible=false
		var names:=String(meta.hint_string).split(",")
		for index in names.size():
			var entry:=names[index].split(":");var option:Variant=entry[0] if value is String or value is StringName else (int(entry[1]) if entry.size()>1 else index)
			choice.add_item(entry[0]);choice.set_item_metadata(index,option)
			if str(option)==str(value):choice.select(index)
	if value is Curve:
		var points:Array[Vector2]=[]
		for i in value.point_count:points.append(value.get_point_position(i))
		editor.text=var_to_str(points);hint.text="Curve replacement: [Vector2(time, value), ...], linear tangents."
	elif value is Resource:editor.text="";hint.text="Detached resource. Load replaces this branch; Save selected writes a new reusable resource."
	else:editor.text=str(value) if value is String or value is StringName else var_to_str(value);hint.text=_help(_selected,meta)
func _apply()->void:
	if _selected.is_empty():problem.emit("Select a property to edit");return
	var old:Variant=selected_value();var value:Variant
	if choice.visible:
		value=choice.get_selected_metadata()
		if old is StringName:value=StringName(value)
	elif old is Curve:
		var points:Variant=str_to_var(editor.text)
		if not points is Array:problem.emit("Curve needs an array of Vector2 points");return
		var curve:=Curve.new();curve.min_value=old.min_value;curve.max_value=old.max_value
		for point in points:
			if not point is Vector2 or not point.is_finite() or point.x<0 or point.x>1:problem.emit("Invalid curve point");return
			curve.add_point(point,0,0,Curve.TANGENT_LINEAR,Curve.TANGENT_LINEAR)
		value=curve
	elif old is Resource:problem.emit("Use Load resource to replace this resource");return
	elif old is String:value=editor.text
	elif old is StringName:value=StringName(editor.text)
	elif old is float:
		if not editor.text.is_valid_float():problem.emit("Enter a number");return
		value=float(editor.text)
	elif old is int:
		if not editor.text.is_valid_int():problem.emit("Enter an integer enum/value; see the field hint");return
		value=int(editor.text)
	else:value=str_to_var(editor.text)
	value_edited.emit(_selected.duplicate(),value)
func _load()->void:resource_requested.emit(_selected.duplicate())
func _new_resource()->void:
	var item:=tree.get_selected()
	if item==null or _selected.is_empty():problem.emit("Select a resource slot");return
	var old:Variant=selected_value();var script:Script
	if old is Resource:script=old.get_script()
	else:
		var property:Dictionary=item.get_metadata(1)
		if property.get("class_name","")=="Curve":
			var curve:=Curve.new();curve.add_point(Vector2.ZERO);curve.add_point(Vector2.ONE)
			value_edited.emit(_selected.duplicate(),curve);return
		for entry in ProjectSettings.get_global_class_list():
			if entry.class==property.get("class_name",""):script=load(entry.path);break
	if script==null:problem.emit("This property is not a constructible resource slot");return
	value_edited.emit(_selected.duplicate(),script.new())
func _clear_resource()->void:
	if not selected_value() is Resource:problem.emit("Select a resource slot");return
	value_edited.emit(_selected.duplicate(),null)
func _save()->void:
	if not selected_value() is Resource:problem.emit("Select a resource branch");return
	resource_save_requested.emit(_selected.duplicate())
func _add()->void:
	var value:Variant=selected_value()
	if value is Dictionary:
		var key:=entry_key.text.strip_edges()
		if key.is_empty() or value.has(key):problem.emit("Enter a new, nonempty dictionary key");return
		if value.get_typed_value_class_name()!="Curve":problem.emit("Edit scalar dictionaries as a complete literal");return
		var curve:=Curve.new();curve.add_point(Vector2(0,1));curve.add_point(Vector2(1,1))
		var draft:Dictionary=value.duplicate();draft[key]=curve;value_edited.emit(_selected.duplicate(),draft);return
	if not value is Array:problem.emit("Select a resource array or curve dictionary");return
	var draft:Array=value.duplicate();var script:Script=draft.get_typed_script()
	if script==null:problem.emit("Edit this scalar array as a complete literal");return
	draft.append(script.new());value_edited.emit(_selected.duplicate(),draft)
func _remove()->void:
	if _selected.is_empty():problem.emit("Select a collection element");return
	var parent:=_selected.slice(0,-1);var values:Variant=value_at(_snapshot,parent)
	if values is Dictionary:
		var draft:Dictionary=values.duplicate();draft.erase(_selected.back());value_edited.emit(parent,draft);return
	if not values is Array:return
	var draft:Array=values.duplicate();draft.remove_at(_selected.back());value_edited.emit(parent,draft)
static func _help(path:Array,property:Dictionary)->String:
	if path.is_empty():return "Asset request"
	var text:=" / ".join(path.map(func(key:Variant)->String:return str(key)))
	if property.get("hint_string","")!="":text+=" — "+str(property.hint_string)
	if str(path.back())=="size_mm":text+=" — mm per normalized unit; radius for a round unit girdle. Inspect actual dimensions for other shapes."
	if str(path.back())=="amount":text+=" — interpreted in this absorber's explicitly selected unit."
	if path.has("grade"):text+=" — descriptive label; changing this does not change transport."
	return text
static func _active(value:Resource,key:String)->bool:
	if value is GemAssetRequest and key in ["preset_id","specimen_seed"]:return value.recipe!=null
	if value is GemShape:
		if key in ["dome_height","dome_rings"]:return value.mode=="cabochon"
		if key=="loft_sections":return value.mode=="loft"
	if value is GemDefect:
		if key in ["crystal_habit","crystal_scale"]:return value.kind=="crystal"
		if key=="fracture_profile":return value.kind=="fracture"
		if key in ["irregularity","radial_segments","radial_rings"]:return value.kind in ["fracture","chip"]
	if value is GemClip and key in ["turntable_axis","turntable_degrees","easing"]:return value.stone_motion==GemClip.StoneMotion.TURNTABLE
	return true
