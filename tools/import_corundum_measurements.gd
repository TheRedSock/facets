extends SceneTree
## Rebuild reviewed examples from checksum-pinned numeric source data.
## These recipes are illustrative concentrations, not catalog color matching.
const SOURCE := "res://data/lapidary/measurements/gia_corundum_2020/"
const OUTPUT := "res://data/lapidary/materials/measured_corundum/"

func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE+"source.json"))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var spectra := {}
	for name in ["chromium", "iron_titanium"]:
		var record: Dictionary = source.spectra[name]
		var csv: String = SOURCE+record.file
		if FileAccess.get_sha256(csv) != record.sha256:
			printerr("FAIL: measurement checksum "+name); quit(1); return
		var metadata := {"id":"gia_2020_corundum_"+name, "display_name":"Corundum / "+name,
			"quantity":source.quantity, "optical_basis":source.optical_basis,
			"host_species_id":source.host_species_id, "citation":source.citation,
			"method":"Published polarized absorption cross sections; UV-visible spectroscopy and chemical concentration analysis",
			"source_url":source.source_url, "workbook_sha256":source.workbook_sha256,
			"source_columns":record.columns, "instrument_resolution_nm":source.instrument_resolution_nm,
			"relative_uncertainty":0.076 if name=="chromium" else 0.25,
			"assumptions":"Principal absorption axes aligned to corundum c-axis. Constant dilute-absorber cross section. Amount counts active absorbers (Cr3+ ions or Fe2+-Ti4+ pairs), not bulk elemental Fe/Ti. Uncertainty describes reported peak normalization, not every wavelength. No fluorescence or defect-population chemistry."}
		var result := GemAbsorptionImport.read_csv(csv,metadata)
		if result.has("error"):
			printerr("FAIL: ",result.error); quit(1); return
		var spectrum: GemChromophore = result.chromophore
		if ResourceSaver.save(spectrum,OUTPUT+name+".tres") != OK:
			printerr("FAIL: saving spectrum"); quit(1); return
		spectrum.take_over_path(OUTPUT+name+".tres")
		spectra[name]=spectrum
	for recipe in [{"id":"chromium_134ppma","cr":134.0,"feti":0.0},
		{"id":"iron_titanium_10ppma","cr":0.0,"feti":10.0},
		{"id":"mixed_134cr_5feti_ppma","cr":134.0,"feti":5.0}]:
		var material := GemMaterial.new()
		material.material_id=StringName(recipe.id)
		material.species=load("res://data/lapidary/species/corundum.tres")
		material.atom_density_per_cm3=1.178e23
		material.scatter_per_mm=0.0
		material.scattering_evidence.method="Explicit clear-medium example; no measured scattering coefficient supplied"
		material.source_note="Illustrative homogeneous active-absorber recipe using GIA2020 cross sections; total-atom ppma convention. Concentrations are inputs, not inferred from bulk chemistry. Separate from authored game catalog; not a calibrated specimen color or universal corundum chemistry model. "+str(source.citation)
		for pair in [["chromium",recipe.cr],["iron_titanium",recipe.feti]]:
			if pair[1]==0.0:continue
			var term:=GemAbsorber.new()
			term.chromophore=spectra[pair[0]]
			term.unit=GemAbsorber.Unit.PPMA_TOTAL_ATOMS
			term.amount=pair[1]
			material.absorbers.append(term)
		var errors:=material.validate()
		if not errors.is_empty() or ResourceSaver.save(material,OUTPUT+recipe.id+".tres")!=OK:
			printerr("FAIL: material ",recipe.id," ",errors);quit(1);return
	print("Imported two measured spectra and three explicit corundum material recipes")
	quit()
