extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var tracer:=GemTracer.create(16,16)
	if tracer==null:quit(1);return
	var stone:=fixture()
	var lighting:=GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	for mode in ["scalar","polarized","crystal_matched","crystal"]:
		var instance:=slab(stone,mode=="crystal")
		var policy:=GemRung.policy(GemRung.REFERENCE)
		policy.volume=false;policy.polarization=mode=="polarized";policy.crystal_transport=mode.begins_with("crystal")
		for cavity in [false,true]:
			if cavity and mode=="crystal":continue # The matched gap has an exact independent Beer reference.
			if cavity:
				var boxes:=load("res://tests/lapidary/test_boundaries.gd")
				var boundaries:=GemBoundarySet.new()
				boundaries.add(boxes.box(Vector3(-100,-100,-1),Vector3(100,100,1)),0)
				boundaries.add(boxes.box(Vector3(-100,-100,-.2),Vector3(100,100,.2)),-1)
				instance.boundaries=boundaries
			check(tracer.configure_stone(instance,lighting,policy),"configure "+mode)
			if not tracer.configuration_error.is_empty():printerr(tracer.configuration_error);continue
			tracer.accumulate(512)
			var expected:=expectation(stone,mode=="crystal",cavity)
			var actual:=mean_y(tracer.read_xyz())
			check(absf(actual-expected)<.0003,"independent tensor depth / slab series %s cavity=%s: %.9f versus %.9f"%[mode,cavity,actual,expected])
			check(tracer.transport_error().is_empty(),"valid transport "+mode)
	tracer.release()
	# Different host sizes/compositions in one batch exercise both offset tables.
	tracer=GemTracer.create(32,16)
	var other:GemStone=stone.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	other.size_mm=2
	other.condition.volume_fields[0].absorbers[0].amount=2
	var policy:=GemRung.policy(GemRung.REFERENCE)
	policy.volume=false;policy.polarization=true
	check(tracer.configure_stones([slab(stone,false),slab(other,false)],lighting,policy,Vector2i(2,1)),"mixed spatial material batch")
	tracer.accumulate(512)
	var film:=tracer.read_xyz()
	for cell in 2:
		var total:=0.0
		for y in 16:
			for x in 16:total+=film[(y*32+cell*16+x)*4+1]
		check(absf(total/256-expectation(stone if cell==0 else other,false,false))<.0003,"batch spectral/field offsets and physical size "+str(cell))
	tracer.release()
	_nested_axes()
	print("GPU spatial composition: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func _nested_axes()->void:
	var tracer:=GemTracer.create(16,16)
	var stone:=fixture()
	stone.condition=GemCondition.new()
	stone.material.absorbers=[absorber(.2,.8)]
	var instance:=slab(stone,false)
	instance.absorb_scale=1.0
	# Isotropic host surrounding a rotated dichroic filling also checks the
	# aggregate flag that selects persistent state for nested-only absorption.
	instance.absorption_eray=PackedFloat32Array()
	var material:=GemMaterial.new()
	material.species=GemSpecies.new();material.absorbers=[absorber(.1,1.2)]
	var inner:=GemMaterialCompiler.compile(material)
	inner.optic_axis=Vector3(1,1,0).normalized()
	instance.region_materials=[inner]
	var boxes:=load("res://tests/lapidary/test_boundaries.gd")
	var boundaries:=GemBoundarySet.new()
	boundaries.add(boxes.box(Vector3(-100,-100,-1),Vector3(100,100,1)),0)
	boundaries.add(boxes.box(Vector3(-100,-100,-.2),Vector3(100,100,.2)),1)
	instance.boundaries=boundaries
	var lighting:=GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	for host_dichroic in [false,true]:
		if host_dichroic:instance.absorption_eray=PackedFloat32Array();instance.absorption_eray.resize(401);instance.absorption_eray.fill(.8)
		# Independent 2x2 real Jones product: H(.8mm) * R N(.4mm) R^T * H(.8mm).
		var h0:=exp(-.5*.2*.8)
		var h1:=exp(-.5*(.8 if host_dichroic else .2)*.8)
		var n0:=exp(-.5*.1*.4)
		var n1:=exp(-.5*1.2*.4)
		var diagonal:=.5*(n0+n1)
		var off:=.5*(n0-n1)
		var expected:=.5*(pow(h0*h0*diagonal,2)+2*pow(h0*h1*off,2)+pow(h1*h1*diagonal,2))
		for polarized in [false,true]:
			var policy:=GemRung.policy(GemRung.REFERENCE)
			policy.volume=false;policy.polarization=polarized
			check(tracer.configure_stone(instance,lighting,policy),"nested absorber axes configure")
			tracer.accumulate(512)
			check(absf(mean_y(tracer.read_xyz())-expected)<.0002,"nested rotated axes retain Jones-product attenuation scalar/polarized")
	tracer.release()

static func absorber(ordinary:float,parallel:float)->GemAbsorber:
	var spectrum:=GemChromophore.new()
	spectrum.wavelength_step_nm=400
	spectrum.absorption_mm=PackedFloat32Array([ordinary,ordinary])
	if parallel!=ordinary:spectrum.absorption_eray_mm=PackedFloat32Array([parallel,parallel])
	return GemAbsorber.relative(spectrum)

static func fixture()->GemStone:
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm=0
	stone.material.absorbers=[absorber(.04,.04)]
	stone.size_mm=1;stone.condition=GemCondition.new()
	var a:=GemVolumeField.new()
	a.profile=GemVolumeField.Profile.PLANAR_TRANSITION
	a.radius_mm.z=.3;a.orientation=Quaternion(Vector3.UP,PI/2)
	a.absorbers=[absorber(.3,.9)];a.absorption_concentration=.5
	var b:=GemVolumeField.new()
	b.center_mm=Vector3(-.1,.15,.1);b.radius_mm=Vector3(.7,.9,.5)
	b.orientation=Quaternion(Vector3.UP,.4);b.absorbers=[absorber(.1,.45)]
	stone.condition.volume_fields=[a,b]
	return stone

static func slab(stone:GemStone,crystal:bool)->Dictionary:
	var instance:=LapidaryStoneCompiler.compile(stone)
	instance.sellmeier_b=Vector3(1.56,0,0) if crystal else Vector3.ZERO
	instance.sellmeier_c=Vector3.ZERO;instance.index_offset=0
	instance.extraordinary_refraction={"b":Vector3(2.24,0,0),"c":Vector3.ZERO,"offset":0.0} if crystal else {}
	instance.optic_axis=Vector3.UP
	instance.absorb_scale=1.3
	instance.planes=PackedFloat32Array()
	for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
		for sign_value in [-1.0,1.0]:
			var n:Vector3=axis*sign_value
			instance.planes.append_array(PackedFloat32Array([n.x,n.y,n.z,1 if axis.z!=0 else 100,0,0,0,0]))
	return instance

static func expectation(stone:GemStone,crystal:bool,cavity:bool)->float:
	var total:=0.0
	# This reference uses the authored source spectra, never packed GPU tables.
	for y in 16:
		for x in 16:
			for sy in 8:
				for sx in 8:
					var px:=((x+(sx+.5)/8-.5)/16*2-1)*1.25*stone.size_mm
					var py:=-((y+(sy+.5)/8-.5)/16*2-1)*1.25*stone.size_mm
					var origin:=Vector3(px,py,stone.size_mm)
					for channel in 2:
						var base:=.04
						var depth:=base*(1.6 if cavity else 2.0)*stone.size_mm
						for field in stone.condition.volume_fields:
							var column:=field.column(origin,Vector3.FORWARD,2*stone.size_mm)
							if cavity:column-=field.column(Vector3(px,py,.2*stone.size_mm),Vector3.FORWARD,.4*stone.size_mm)
							var coefficient:=base*field.absorption_concentration
							for term in field.absorbers:coefficient+=term.chromophore.sample(550,channel==1)*term.amount
							depth+=column*coefficient
						var n:float=(1.6 if channel==0 else 1.8) if crystal else 1.0
						var r:=pow((n-1)/(n+1),2)
						var t:=exp(-1.3*depth)
						total+=.5*(r+pow(1-r,2)*t/(1-r*t))/(256*64)
	return total

static func mean_y(film:PackedFloat32Array)->float:
	var total:=0.0
	var coverage:=0.0
	for pixel in film.size()/4:total+=film[pixel*4+1];coverage+=film[pixel*4+3]
	return total/coverage
