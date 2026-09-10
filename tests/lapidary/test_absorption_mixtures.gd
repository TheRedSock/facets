extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+message)
func _initialize()->void:
	var material:=GemMaterial.new()
	material.species=load("res://data/lapidary/species/corundum.tres")
	material.atom_density_per_cm3=1.178e23
	var cross:=GemChromophore.new()
	cross.basis=GemChromophore.SpectrumBasis.CROSS_SECTION_CM2
	cross.host_species_id=&"corundum"
	cross.wavelength_step_nm=400
	cross.cross_section_cm2=PackedFloat64Array([2e-19,4e-19])
	cross.cross_section_parallel_cm2=PackedFloat64Array([1e-19,3e-19])
	var term:=GemAbsorber.new()
	term.chromophore=cross;term.unit=GemAbsorber.Unit.PPMA_TOTAL_ATOMS;term.amount=100
	material.absorbers=[term]
	check(material.validate().is_empty(),"cross-section/total-atom concentration recipe validates")
	var result:=GemMaterialCompiler.compile(material)
	check(absf(result.absorption[200]-.3534)<1e-7 and absf(result.absorption_eray[200]-.2356)<1e-7,"sigma*N/10 produces physical mm inverse on both axes")
	term.unit=GemAbsorber.Unit.NUMBER_PER_CM3;term.amount=1.178e19
	check(GemMaterialCompiler.compile(material).absorption==result.absorption,"number density and declared total-atom ppma agree")
	var base:=GemChromophore.new()
	base.wavelength_step_nm=400;base.absorption_mm=PackedFloat32Array([.1,.1])
	material.absorbers.append(GemAbsorber.relative(base,2))
	var mix:=GemMaterialCompiler.compile(material)
	check(absf(mix.absorption[200]-.5534)<1e-7 and absf(mix.absorption_eray[200]-.4356)<1e-7,"isotropic term contributes to both principal mixed axes")
	check(absf(exp(-mix.absorption[200]*7)-exp(-result.absorption[200]*7)*exp(-.2*7))<1e-7,"independent absorbers multiply transmission by adding optical depth")
	material.absorbers.reverse()
	check(GemMaterialCompiler.compile(material).absorption==mix.absorption,"mixture order does not change this physical recipe")
	term.amount=0
	check(GemMaterialCompiler.compile(material).absorption_eray.is_empty(),"zero anisotropic component does not introduce dichroism")
	term.amount=1e19;term.unit=GemAbsorber.Unit.RELATIVE_SCALE
	check(not material.validate().is_empty(),"cross section cannot use an ambiguous relative amount")
	term.unit=GemAbsorber.Unit.PPMA_TOTAL_ATOMS;term.amount=100
	material.atom_density_per_cm3=0
	check(not material.validate().is_empty(),"ppma cannot infer an unspecified host density")
	material.atom_density_per_cm3=1.178e23
	cross.host_species_id=&"quartz"
	check(not material.validate().is_empty(),"host-specific ion spectrum cannot silently move between lattices")
	cross.host_species_id=&"corundum"
	cross.absorption_mm=PackedFloat32Array([1,1])
	check(not material.validate().is_empty(),"different spectral quantities cannot coexist in one basis")
	cross.absorption_mm.clear()
	term.amount=INF
	check(not material.validate().is_empty(),"nonfinite amount fails")
	term.amount=100
	base.absorption_mm=PackedFloat32Array([2e38,2e38])
	check(not material.validate().is_empty(),"mixed/scaled coefficient overflow is rejected")
	var metadata:={"quantity":"cross_section_mm2","optical_basis":"ordinary_extraordinary","host_species_id":"corundum","citation":"Synthetic dimensional-analysis fixture","dataset_sha256":"a".repeat(64),"method":"Known constant cross section"}
	var imported:=GemAbsorptionImport.compile_samples(PackedFloat64Array([380,780]),PackedFloat64Array([2e-17,2e-17]),PackedFloat64Array([1e-17,1e-17]),metadata)
	check(imported.has("chromophore") and absf(imported.chromophore.cross_section_cm2[0]/2e-19-1)<1e-12,"cross-section importer converts mm2 to cm2 without concentration or float32 truncation")
	metadata.erase("host_species_id")
	check(GemAbsorptionImport.compile_samples(PackedFloat64Array([380,780]),PackedFloat64Array([2e-17,2e-17]),PackedFloat64Array([1e-17,1e-17]),metadata).has("error"),"imported cross section needs its host")
	check(is_nan(cross.sample(379)) and is_nan(cross.sample(781)) and is_nan(cross.sample(NAN)),"spectral sampling refuses extrapolation and nonfinite wavelengths")
	_measured()
	print("Absorption mixtures: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _measured()->void:
	var path:="res://data/lapidary/materials/measured_corundum/"
	var source_path:="res://data/lapidary/measurements/gia_corundum_2020/"
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source_path+"source.json"))
	for name in ["chromium","iron_titanium"]:
		var spectrum:GemChromophore=load(path+name+".tres")
		var record:Dictionary=source.spectra[name]
		check(spectrum.validate().is_empty() and FileAccess.get_sha256(source_path+record.file)==spectrum.absorption_evidence.dataset_sha256,"measured "+name+" source hash and resource admission")
		var imported:=GemAbsorptionImport.read_csv(source_path+record.file,spectrum.absorption_evidence.source_record)
		var max_relative:=0.0
		for wavelength in range(380,781):
			for parallel in [false,true]:
				max_relative=maxf(max_relative,absf(spectrum.sample(wavelength,parallel)/imported.chromophore.sample(wavelength,parallel)-1))
		check(max_relative<1e-12,"serialized "+name+" retains measured cross-section precision")
	var chromium:GemChromophore=load(path+"chromium.tres")
	var iron_titanium:GemChromophore=load(path+"iron_titanium.tres")
	check(absf(chromium.sample(560)/1.62e-19-1)<.076,"chromium ordinary peak agrees with reported normalization uncertainty")
	check(absf(iron_titanium.sample(580)/1.94e-18-1)<.25,"iron-titanium ordinary peak agrees with reported normalization uncertainty")
	var mixture:GemMaterial=load(path+"mixed_134cr_5feti_ppma.tres")
	var compiled:=GemMaterialCompiler.compile(mixture)
	for parallel in [false,true]:
		var expected:=(134*chromium.sample(560,parallel)+5*iron_titanium.sample(560,parallel))*1.178e16
		var actual:float=compiled.absorption_eray[180] if parallel else compiled.absorption[180]
		check(absf(actual/expected-1)<1e-7,"measured mixed coefficient independently matches source quantities")
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material=mixture;stone.condition=GemCondition.new()
	var job:=GemFrameJob.new();job.stone=stone
	var key:=GemContentIdentity.digest(stone.transport_inputs())
	var output:="res://artifacts/materials/mixture.res"
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	check(GemResourceBundle.save(job,output)==OK,"physical absorption mixture bundles for workers")
	var restored:GemFrameJob=load(output)
	check(GemContentIdentity.digest(restored.stone.transport_inputs())==key and GemMaterialCompiler.compile(restored.stone.material).absorption==compiled.absorption,"portable binary preserves concentration and float64 source spectra exactly")
	var changed:GemStone=stone.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	changed.material.absorbers[1].amount+=1
	check(GemContentIdentity.digest(changed.transport_inputs())!=key,"changing one active absorber invalidates optical identity")
