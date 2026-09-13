extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("Compression capabilities bptc=%s astc=%s" % [RenderingServer.has_os_feature("bptc"), RenderingServer.has_os_feature("astc")])
	var out := "res://artifacts/library-check/"
	var store := GemArtifactStore.new(out + "store")
	var ids := []
	for i in 12:
		var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		image.fill_rect(Rect2i(8, 8, 16, 16), Color(float(i + 1) / 12.0, 0.25, 0.5))
		var key := GemContentIdentity.digest(["library-test", i])
		check(store.publish(key, image.save_webp_to_buffer(false), {"kind": "display"}), "source display publishes")
		ids.append(key)
	var clips := {"test/turn": {"frames": ids, "fps": 24, "loop": false}, "test/idle": {"frames": [ids[0]], "fps": 1, "loop": false}}
	for codec in ["webp_lossless", "bc7", "astc4x4"]:
		var packer := GemPagePacker.new(store, out + codec)
		packer.page_edge = 64
		packer.codec = codec
		var index := packer.pack(clips)
		check(not index.is_empty(), "compression profile validates: " + codec)
		if index.is_empty():
			continue
		check(index["pages"].size() == 3, "bounded pages respect shelf capacity")
		for key:String in index.pages:
			var page:Dictionary=index.pages[key]
			var bytes:=FileAccess.get_file_as_bytes((out+codec).path_join(page.path))
			check(key==GemContentIdentity.digest(["delivery-page-v1",Vector2i(page.width,page.height),int(page.format),String(page.codec),bytes]),"Dedicated delivery identity preserves v1 wire records")
		var bad := index.duplicate(true)
		bad["pages"].values()[0]["width"] = 16384
		check(not GemAssetLibrary.valid_manifest(bad), "oversized page rejected before allocation")
		bad = index.duplicate(true)
		bad["frames"].values()[0]["offset"][0] = -1
		check(not GemAssetLibrary.valid_manifest(bad), "invalid trim rejected")
		bad = index.duplicate(true)
		bad["clips"]["test/idle"]["frames"] = ["missing"]
		check(not GemAssetLibrary.valid_manifest(bad), "dangling clip reference rejected")
		bad=index.duplicate(true)
		bad.clips.erase("test/turn")
		check(not GemAssetLibrary.valid_manifest(bad),"Unreferenced frames/pages cannot enter a runtime library")
		if codec == "astc4x4" and not RenderingServer.has_os_feature("astc"):
			check(not GemAssetLibrary.new().open(out + codec + "/library.json"), "unsupported GPU codec rejected")
			continue # Encoder/quality tested; this device cannot upload ASTC.
		var library := GemAssetLibrary.new()
		check(library.open(out + codec + "/library.json") and library.page_loads == 0, "library open loads metadata only")
		var first := library.frame("test/turn", 0)
		check(first != null and first.get_size() == Vector2(32, 32), "trimmed atlas preserves logical frame dimensions")
		var page_key: String = index["frames"][ids[0]]["page"]
		library.cache_budget_bytes = index["pages"][page_key]["gpu_bytes"]
		library.frame("test/turn", 0)
		check(library.page_loads == 1, "same page is reused")
		for i in range(1, ids.size()):
			if index["frames"][ids[i]]["page"] != page_key:
				library.frame("test/turn", i)
				break
		check(library.page_loads == 2 and library.cache_bytes <= library.cache_budget_bytes, "selective loading and LRU ownership budget")
		var memory:=library.memory_report()
		check(memory.resident_pages==2 and memory.resident_texture_bytes==2*library.cache_budget_bytes and memory.outside_cache_bytes==library.cache_budget_bytes,"Active view retains evicted page and is counted outside cache ownership")
		first=null;memory=library.memory_report()
		check(memory.resident_pages==1 and memory.outside_cache_bytes==0,"Released view references leave the resident working set")
	var forge: Node = root.get_node("GemForge")
	check(GemPagePacker.write_game_pack(out + "webp_lossless/library.json", out + "test.pck") == OK, "game pack publishes referenced pages")
	check(ProjectSettings.load_resource_pack(out + "test.pck"), "game pack mounts")
	var catalog:=GemDeliveryCatalog.new();var binding:=GemTilePresentation.new();binding.tile_id=&"test";binding.asset_id=&"test";binding.roles={&"rest":&"idle",&"upgrade":&"turn"};catalog.bindings=[binding]
	check(forge.open_library("res://gem-assets/library.json",catalog), "game service opens packed library")
	var view: TileView = load("res://scenes/tile/tile_view.tscn").instantiate()
	root.add_child(view)
	view.configure_from_data(&"test", 1, Vector2i.ZERO)
	check(view._clip_rect.texture is AtlasTexture and not view.is_processing(), "game view serves idle from a page without a render job")
	view.play_role(&"upgrade")
	view._process(1.01 / 24.0)
	check(view._frame == 1 and view._clip_rect.texture.get_size() == Vector2(32, 32), "game view advances trimmed frames")
	view._process(1.0)
	check(view._role == &"rest" and not view.is_processing(), "oneshot returns to idle")
	view.free()
	print("Library GPU: %d failures" % failures)
	print("CHECK_COMPLETE: library_gpu_check"); quit(1 if failures else 0)
