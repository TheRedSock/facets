extends RefCounted
## Resource-oriented authoring client layout; execution and editing have one owner each.
static func build(root:Control)->Dictionary:
	var c:={}
	var theme:=Theme.new();var font:=SystemFont.new();font.font_names=PackedStringArray(["Segoe UI"]);theme.default_font=font;theme.default_font_size=17;root.theme=theme
	var background:=ColorRect.new();background.color=Color("17171b");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:margin.add_theme_constant_override(side,16)
	root.add_child(margin)
	var layout:=VBoxContainer.new();margin.add_child(layout)
	var bar:=HBoxContainer.new();layout.add_child(bar)
	for pair in [["preview_now","Preview"],["new","New from current"],["open","Open"],["save","Save"],["save_as","Save As"],["undo","Undo"],["redo","Redo"],["changes","Compare changes"],["plan","Estimate"],["inspect","Inspect cut"],["build","Build asset"],["cancel","Cancel"]]:
		var button:=Button.new();button.text=pair[1];bar.add_child(button);c[pair[0]]=button
	var path:=Label.new();path.text="Untitled asset request";layout.add_child(path);c.path=path
	var columns:=HSplitContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(columns)
	var left:=VBoxContainer.new();left.custom_minimum_size.x=550;columns.add_child(left)
	var background_row:=HBoxContainer.new();left.add_child(background_row)
	background_row.add_child(_label("Preview background"))
	var bg:=OptionButton.new();for name in ["Game","Black","White"]:bg.add_item(name)
	background_row.add_child(bg);c.background=bg
	var automatic:=CheckButton.new();automatic.text="Auto preview";automatic.button_pressed=true;background_row.add_child(automatic);c.automatic=automatic
	var view:=OptionButton.new();view.add_item("House print",GemPrint.View.HOUSE_PRINT);view.add_item("Display preview",GemPrint.View.DISPLAY_PREVIEW);background_row.add_child(view);c.view=view
	var well:=ColorRect.new();well.color=Color("10141c");well.custom_minimum_size=Vector2(512,512);well.size_flags_vertical=Control.SIZE_EXPAND_FILL;left.add_child(well);c.well=well
	var preview:=TextureRect.new();preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;well.add_child(preview);c.preview=preview
	var overlay:=Label.new();overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;overlay.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;overlay.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;well.add_child(overlay);c.overlay=overlay
	var cut_overlay:=GemCutOverlay.new();cut_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);cut_overlay.visible=false;well.add_child(cut_overlay);c.cut_overlay=cut_overlay
	var shipping:=HBoxContainer.new();left.add_child(shipping);shipping.add_child(_label("Output at native size"))
	var thumb:=TextureRect.new();thumb.custom_minimum_size=Vector2(112,112);thumb.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;thumb.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;shipping.add_child(thumb);c.thumb=thumb
	var motion:=HBoxContainer.new();left.add_child(motion)
	var clips:=OptionButton.new();clips.custom_minimum_size.x=150;motion.add_child(clips);c.clips=clips
	var scrub:=HSlider.new();scrub.min_value=0;scrub.step=1;scrub.size_flags_horizontal=Control.SIZE_EXPAND_FILL;motion.add_child(scrub);c.scrub=scrub
	var frame:=Label.new();motion.add_child(frame);c.frame=frame
	var inspector:=GemResourceInspector.new();inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(inspector);c.inspector=inspector
	var status:=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.y=40;layout.add_child(status);c.status=status
	var details:=TextEdit.new();details.editable=false;details.custom_minimum_size.y=105;layout.add_child(details);c.details=details
	return c
static func _label(text:String)->Label:
	var label:=Label.new();label.text=text;return label
