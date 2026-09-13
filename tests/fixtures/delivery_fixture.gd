class_name GemDeliveryFixture
extends RefCounted
## Explicit synthetic delivery, used only by tests. No production visual fallback.
static func create(destination:String,catalog:GemDeliveryCatalog=null)->Dictionary:
	var store:=GemArtifactStore.new(destination.path_join("store"))
	var frames:Array[String]=[]
	for i in 3:
		var image:=Image.create(24,24,false,Image.FORMAT_RGBA8)
		image.fill_rect(Rect2i(4,4,16,16),Color(.2+.3*i,.25,.7,1))
		var key:=GemContentIdentity.digest(["explicit-delivery-fixture",i])
		if not store.publish(key,image.save_webp_to_buffer(false),{"kind":"display"}):return {}
		frames.append(key)
	var packer:=GemPagePacker.new(store,destination.path_join("library"));packer.page_edge=64
	if catalog==null:
		catalog=GemDeliveryCatalog.new()
		for id in [&"logical_tile",&"logical_upgrade"]:
			var binding:=GemTilePresentation.new();binding.tile_id=id;binding.asset_id=&"physical_asset";binding.roles={&"rest":&"rest_still",&"upgrade":&"celebrate"};catalog.bindings.append(binding)
	var clips:Dictionary={}
	for binding in catalog.bindings:
		for role in binding.roles:
			var key:=String(binding.asset_id)+"/"+String(binding.roles[role])
			clips[key]={"frames":[frames[0]] if role==&"rest" else frames,"fps":10,"loop":false}
	if packer.pack(clips).is_empty():return {}
	return {"library":destination.path_join("library/library.json"),"catalog":catalog}
