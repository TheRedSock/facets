extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var field:=GemVolumeField.new()
	field.profile=GemVolumeField.Profile.PLANAR_TRANSITION
	check(field.density(Vector3(10,20,-2))==0 and field.density(Vector3(-20,30,2))==1,"planar plateaus are unbounded transversely")
	check(field.density(Vector3.ZERO)==.5,"transition midpoint")
	check(absf(field.column(Vector3(0,0,-2),Vector3.BACK,4)-2)<1e-7,"symmetric transition chord")
	check(absf(field.column(Vector3.ZERO,Vector3.RIGHT,4)-2)<1e-7,"parallel ray has constant concentration")
	for index in 48:
		field.orientation=Quaternion(Vector3(1,2,3).normalized(),index*.2)
		field.radius_mm.z=.02+index*.03
		field.center_mm=Vector3(.15,-.2,.1)
		var origin:=Vector3(sin(index*.5),.2,-1)
		var direction:=Vector3(.2*cos(index),.1,1).normalized()
		var distance:=.1+index*.08
		var quadrature:=0.0
		for step in 4096:quadrature+=field.density(origin+direction*distance*(step+.5)/4096)
		quadrature*=distance/4096
		var exact:=field.column(origin,direction,distance)
		check(absf(exact-quadrature)<3e-6,"planar column agrees with midpoint integration")
		var split:=field.column(origin,direction,.37*distance)+field.column(origin+direction*.37*distance,direction,.63*distance)
		check(absf(exact-split)<3e-6 and absf(exact-field.column(origin+direction*distance,-direction,distance))<3e-6,"planar depth composes and reverses")
		var opposite:GemVolumeField=field.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		opposite.orientation=field.orientation*Quaternion(Vector3.RIGHT,PI)
		check(absf(exact+opposite.column(origin,direction,distance)-distance)<3e-6,"opposite profiles partition concentration without negative fields")
	_composition()
	print("Spatial composition: %d checks, %d failures"%[checks,failures]);print("CHECK_COMPLETE: test_spatial_composition"); quit(1 if failures else 0)

func _composition()->void:
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material=load("res://data/lapidary/materials/measured_corundum/mixed_134cr_5feti_ppma.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition=GemCondition.new()
	var field:=GemVolumeField.new()
	field.absorbers=[stone.material.absorbers[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)]
	field.absorbers[0].amount=250
	field.profile=GemVolumeField.Profile.PLANAR_TRANSITION
	stone.condition.volume_fields=[field]
	var compiled:=LapidaryStoneCompiler.compile(stone)
	var spectrum:Dictionary=compiled.field_absorption[0]
	var source:GemChromophore=field.absorbers[0].chromophore
	check(absf(spectrum.absorption[180]/(source.sample(560)*250*1.178e16)-1)<1e-7,"field peak concentration compiles in its host's physical units")
	check(GemCrystalAdmission.stone_error(stone).is_empty(),"smooth clear measured composition fields are admitted by crystal transport")
	var peak:=GemMaterialCompiler.peak_absorption(compiled)
	check(absf(peak.ordinary[180]-compiled.absorption[180]-spectrum.absorption[180])<1e-7,"overlap bound includes additional spectrum independently of bulk mixture")
	stone.material.absorbers.clear()
	compiled=LapidaryStoneCompiler.compile(stone)
	check(compiled.absorption_eray.is_empty() and GemMaterialCompiler.peak_absorption(compiled).anisotropic,"local absorber introduces dichroism into colorless bulk")
	var original:=GemContentIdentity.digest(stone.transport_inputs())
	var job:=GemFrameJob.new();job.stone=stone
	var output:="res://artifacts/materials/spatial.res"
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	check(GemResourceBundle.save(job,output)==OK,"composition fields serialize into portable jobs")
	var restored:GemFrameJob=load(output)
	check(GemContentIdentity.digest(restored.stone.transport_inputs())==original,"profile and physical absorber bits survive binary roundtrip")
	field.absorbers[0].chromophore.host_species_id=&"quartz"
	check(GemMaterialCompiler.field_absorption(stone.material,[field]).has("error"),"spatial absorbers cannot cross host lattices")
	field.absorbers[0].chromophore.host_species_id=&"corundum"
	stone.material.atom_density_per_cm3=0
	check(GemMaterialCompiler.field_absorption(stone.material,[field]).has("error"),"spatial ppma requires the host atom density")
	stone.material.atom_density_per_cm3=1.178e23
	compiled.field_absorption=[]
	check(GemMaterialCompiler.peak_absorption(compiled).has("error"),"direct GPU inputs cannot omit compiled local spectra")
	compiled=LapidaryStoneCompiler.compile(stone)
	compiled.field_absorption[0].absorption.fill(1000)
	check(not GemCrystalAdmission.compiled_error(compiled).is_empty(),"weak-loss admission includes local spectral peaks")
	compiled.field_absorption[0].absorption.fill(2e38)
	compiled.absorption.fill(2e38)
	check(GemMaterialCompiler.peak_absorption(compiled).has("error"),"overlapping spectra cannot overflow GPU coefficients")
	var bytes:=field.packed(123,true)
	check(bytes.size()==64 and bytes.decode_s32(48)==123 and bytes.decode_s32(52)==1 and bytes.decode_s32(56)==1,"field wire stores exact int32 spectrum/profile metadata")
