extends SceneTree
## Explicit concentration zoning, not a chemistry or clarity-grade model.
func _initialize()->void:
	var material:=GemMaterial.new()
	material.material_id=&"clear_corundum_host"
	material.species=load("res://data/lapidary/species/corundum.tres")
	material.atom_density_per_cm3=1.178e23;material.scatter_per_mm=0
	material.source_note="Clear corundum host for authored dilute-absorber zoning. Atom density follows the GIA2020 total-atom ppma convention. Spatial dopants do not modify the real-index tensor in this approximation."
	material.scattering_evidence.method="Explicit zero-scattering example; not a measured specimen"
	var condition:=GemCondition.new()
	for item in [["chromium",250.0,PI/2],["iron_titanium",10.0,-PI/2]]:
		var field:=GemVolumeField.new()
		field.profile=GemVolumeField.Profile.PLANAR_TRANSITION
		field.radius_mm.z=.5
		field.orientation=Quaternion(Vector3.UP,item[2])
		field.source_note="Authored complementary C2 concentration transition in a shared corundum host. Measured cross section with an illustrative active-absorber concentration; no diffusion, growth kinetics, grade assignment or real-index change is inferred."
		var term:=GemAbsorber.new()
		term.chromophore=load("res://data/lapidary/materials/measured_corundum/"+item[0]+".tres")
		term.amount=item[1];term.unit=GemAbsorber.Unit.PPMA_TOTAL_ATOMS
		field.absorbers=[term]
		condition.volume_fields.append(field)
	var spectra:=GemMaterialCompiler.field_absorption(material,condition.volume_fields)
	if spectra.has("error"):printerr(spectra.error);quit(1);return
	if ResourceSaver.save(material,"res://data/lapidary/materials/measured_corundum/clear_host.tres")!=OK or ResourceSaver.save(condition,"res://data/lapidary/conditions/corundum_bicolor.tres")!=OK:
		printerr("FAIL: saving composition examples");quit(1);return
	print("Generated clear host and explicit bicolor concentration condition");quit()
