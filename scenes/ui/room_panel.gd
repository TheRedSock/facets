class_name RoomPanel
extends PanelContainer
signal begin_requested
signal tool_selected(kind: String)
signal confirm_requested
signal cancel_requested
signal hint_requested
var _body: VBoxContainer
var _objective: Label
var _description: Label
var _allowance: Label
var _inspector: Label
var _preview: Label
var _collection: Label
var _begin: Button
var _confirm: Button
var _cancel: Button
var _hint: Button
var _tools := {}
const NAMES := {"action.exchange":"Reposition","action.clear_target":"Chisel","action.promote_target":"Refine"}
const HELP := {"action.exchange":"Exchange two adjacent gems, even without a match.",
	"action.clear_target":"Hit rubble once or remove a tier 1–3 gem.","action.promote_target":"Promote a tier 1–4 gem once."}

func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	add_child(margin)
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_body = VBoxContainer.new(); _body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation",10); scroll.add_child(_body)
	_objective = _label(28); _description = _label(20)
	_begin = _button(tr("ui.begin"),func() -> void: begin_requested.emit())
	_allowance = _label(20)
	for kind in NAMES:
		var button := _button(NAMES[kind],func() -> void: tool_selected.emit(kind))
		button.icon = load("res://assets/ui/icons/"+kind.trim_prefix("action.")+".svg")
		button.expand_icon = true; button.add_theme_constant_override("icon_max_width",24)
		_tools[kind] = button
	_preview = _label(20)
	_confirm = _button(tr("ui.confirm"),func() -> void: confirm_requested.emit())
	_cancel = _button(tr("ui.cancel"),func() -> void: cancel_requested.emit())
	_hint = _button(tr("ui.hint"),func() -> void: hint_requested.emit())
	_inspector = _label(20)
	_collection = _label(18)

func _label(font_size: int) -> Label:
	var label := Label.new(); label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size); _body.add_child(label); return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text; button.custom_minimum_size.y = 36
	button.pressed.connect(callback); _body.add_child(button); return button

func present(model: Dictionary, busy: bool) -> void:
	if _body == null: return
	_objective.text = tr("room.open_seam")+"\n"+tr("room.progress").format({"cleared":model.total-model.remaining,"total":model.total})
	_description.text = "Match beside marked rubble twice to clear it. Matching swaps cost 1 Work. A line of four earns 1 Craft; five or an intersection earns 2."
	if model.phase == "complete": _description.text = "Seam cleared. Every marked rubble is gone. Restart to try a different route."
	elif model.phase == "failed": _description.text = "No Work remaining. Restart to try again." if model.reason == "work_exhausted" else "No moves or tools remain, and the board could not recover. Restart to try again."
	_begin.visible = model.phase == "briefing"; _begin.disabled = busy
	_allowance.text = "One tool before your next matching swap." if model.allowance else "Tool used · make a matching swap to reopen."
	for tool in model.tools:
		var button: Button = _tools[tool.kind]
		button.text = tr("ui.tool_cost").format({"tool":tr(tool.kind),"cost":tool.cost})
		button.disabled = busy or not tool.reason.is_empty()
		button.tooltip_text = HELP[tool.kind]+"\n"+(tool.reason if not tool.reason.is_empty() else "Tools cost no Work and earn no Craft.")
	_hint.disabled = busy or model.phase != "ready"
	_inspector.text = model.inspection
	_collection.text = "STARTER COLLECTION\n"+" · ".join(model.collection)

func preview(text: String, can_confirm: bool, selecting: bool) -> void:
	if _body == null: return
	_preview.text = text; _preview.visible = not text.is_empty()
	_confirm.visible = selecting; _confirm.disabled = not can_confirm
	_cancel.visible = selecting
