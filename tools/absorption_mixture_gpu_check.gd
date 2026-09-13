extends SceneTree
## Uniform source-backed slabs; Python independently integrates the raw CSVs.
func _initialize()->void:
	var tracer:=GemTracer.create(16,16)
	if tracer==null:print("CHECK_COMPLETE: absorption_mixture_gpu_check"); quit(1);return
	var report:=[]
	var rig:=GemLightRig.new()
	rig.bg_zenith=1;rig.bg_horizon=1;rig.bg_below=1
	rig.background_spectrum.model=GemSpectrum.Model.CIE_D65
	rig.background_spectrum.normalization=GemSpectrum.Normalization.UNIT_LUMINANCE
	var lighting:=GemRigCompiler.compile(rig)
	for id in ["chromium_134ppma","iron_titanium_10ppma","mixed_134cr_5feti_ppma"]:
		var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		stone.material=load("res://data/lapidary/materials/measured_corundum/"+id+".tres")
		stone.condition=GemCondition.new();stone.size_mm=1
		for crystal in [false,true]:
			var instance:=LapidaryStoneCompiler.compile(stone)
			instance.optic_axis=Vector3.UP
			if not crystal:
				instance.sellmeier_b=Vector3.ZERO;instance.sellmeier_c=Vector3.ZERO
				instance.extraordinary_refraction={};instance.index_offset=0.0
			var policy:=GemRung.policy(GemRung.REFERENCE)
			policy.crystal_transport=crystal;policy.polarization=not crystal;policy.volume=false
			for depth in [.5,2.0]:
				instance.planes=PackedFloat32Array()
				for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
					for sign_value in [-1.0,1.0]:
						var normal:Vector3=axis*sign_value
						instance.planes.append_array(PackedFloat32Array([normal.x,normal.y,normal.z,depth/2 if axis.z!=0 else 100,0,0,0,0]))
				if not tracer.configure_stone(instance,lighting,policy):
					printerr("FAIL: ",tracer.configuration_error);tracer.release();print("CHECK_COMPLETE: absorption_mixture_gpu_check"); quit(1);return
				tracer.accumulate(512)
				var film:=tracer.read_xyz()
				var sum_x:=0.0;var sum_y:=0.0;var sum_z:=0.0;var coverage:=0.0
				for pixel in film.size()/4:
					sum_x+=film[pixel*4];sum_y+=film[pixel*4+1];sum_z+=film[pixel*4+2];coverage+=film[pixel*4+3]
				if not tracer.transport_error().is_empty() or coverage<255.99:
					printerr("FAIL: slab transport ",tracer.transport_error());tracer.release();print("CHECK_COMPLETE: absorption_mixture_gpu_check"); quit(1);return
				var terms:=[]
				for term in stone.material.absorbers:
					terms.append({"id":String(term.chromophore.chromophore_id).trim_prefix("gia_2020_corundum_"),"ppma":term.amount})
				var b:Vector3=instance.sellmeier_b;var c:Vector3=instance.sellmeier_c
				var extra:Dictionary=instance.extraordinary_refraction
				var be:Vector3=extra.get("b",b);var ce:Vector3=extra.get("c",c)
				report.append({"id":id,"crystal":crystal,"depth_mm":depth,"terms":terms,
					"xyz":[sum_x/coverage,sum_y/coverage,sum_z/coverage],"b":[b.x,b.y,b.z],"c":[c.x,c.y,c.z],
					"be":[be.x,be.y,be.z],"ce":[ce.x,ce.y,ce.z],"profile":tracer.profile()})
				print("Measured slab ",id," crystal=",crystal," depth=",depth," XYZ=",report[-1].xyz)
	tracer.release()
	GemArtifactStore.atomic_write("res://artifacts/reference/absorption-mixtures.json",JSON.stringify(report,"\t").to_utf8_buffer())
	print("Absorption mixture GPU: 12 slabs rendered without transport errors; run check_absorption_mixtures.py for numeric comparison")
	print("CHECK_COMPLETE: absorption_mixture_gpu_check"); quit()
