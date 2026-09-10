extends SceneTree
## Display-space convergence diagnostic; no automatic quality promotion.
func _initialize()->void:
	var reports:=[]
	for column in 3:
		for row in 2:
			var file:="radius%d_pose%d.png"%[column,row]
			var coarse:=Image.load_from_file("res://artifacts/rounding/macro/"+file)
			var fine:=Image.load_from_file("res://artifacts/rounding/macro-fine/"+file)
			if coarse==null or fine==null or coarse.get_size()!=fine.get_size():printerr("Missing matching convergence images");quit(1);return
			var square:=0.0;var opaque_square:=0.0;var alpha_square:=0.0;var maximum:=0.0;var opaque:=0
			for y in coarse.get_height():
				for x in coarse.get_width():
					var a:=coarse.get_pixel(x,y);var b:=fine.get_pixel(x,y)
					var va:=Vector3(a.r,a.g,a.b);var vb:=Vector3(b.r,b.g,b.b)
					square+=(va*a.a-vb*b.a).length_squared();alpha_square+=pow(a.a-b.a,2)
					if minf(a.a,b.a)>.999:
						var delta:=va-vb;opaque_square+=delta.length_squared();opaque+=1
						maximum=maxf(maximum,maxf(absf(delta.x),maxf(absf(delta.y),absf(delta.z))))
			var pixels:=coarse.get_width()*coarse.get_height()
			reports.append({"file":file,"associated_rgb_rmse_lsb":255*sqrt(square/(3*pixels)),"opaque_rgb_rmse_lsb":255*sqrt(opaque_square/(3*maxi(opaque,1))),"opaque_max_channel_lsb":255*maximum,"alpha_rmse_lsb":255*sqrt(alpha_square/pixels)})
			print(JSON.stringify(reports[-1]))
	GemArtifactStore.atomic_write("res://artifacts/rounding/convergence.json",JSON.stringify(reports,"\t").to_utf8_buffer());quit()
