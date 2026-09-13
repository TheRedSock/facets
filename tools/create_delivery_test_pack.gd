extends SceneTree
## Explicit synthetic package for export integration tests, never default content.
func _initialize()->void:
	var fixture:=GemDeliveryFixture.create("res://artifacts/export-audit/fixture",load("res://data/presentation/default.tres"))
	if fixture.is_empty():quit(1);return
	var library:=GemAssetLibrary.new();var index:=GemPresentationIndex.new()
	if not library.open(fixture.library) or not index.open(fixture.catalog,library):printerr("FAIL: Synthetic delivery admission");quit(1);return
	if GemPagePacker.write_game_pack(fixture.library,"res://artifacts/export-audit/fixture/gem-assets.pck")!=OK:quit(1);return
	print("CHECK_COMPLETE: create_delivery_test_pack");quit()
