extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_import_units()
	_validation()
	_resampling()
	print("Material inputs: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _metadata(quantity: String) -> Dictionary:
	return {"quantity": quantity, "optical_basis": "isotropic", "path_mm": 2.0,
		"surface_reflection_removed": true, "scattering_removed": true,
		"citation": "Synthetic unit fixture, not mineral measurements",
		"dataset_sha256": "a".repeat(64), "method": "Analytic constant absorption fixture"}

func _import_units() -> void:
	var units := {"napierian_per_mm": 0.2, "napierian_per_cm": 2.0, "napierian_per_m": 200.0,
		"decadic_per_mm": 0.2 / log(10.0), "decadic_per_cm": 2.0 / log(10.0), "decadic_per_m": 200.0 / log(10.0),
		"internal_transmittance": exp(-0.4), "internal_transmittance_percent": exp(-0.4) * 100.0,
		"decadic_absorbance": 0.4 / log(10.0)}
	var wavelengths := PackedFloat64Array([380, 780])
	for quantity: String in units:
		var value: float = units[quantity]
		var result := GemAbsorptionImport.compile_samples(wavelengths, PackedFloat64Array([value, value]), PackedFloat64Array(), _metadata(quantity))
		check(result.has("chromophore"), quantity + " imports")
		if result.has("chromophore"):
			var chromo: GemChromophore = result["chromophore"]
			check(absf(chromo.absorption_mm[180] - 0.2) < 1e-7, quantity + " converts to correct Napierian /mm")
			check(absf(exp(-chromo.absorption_mm[180] * 7.0) - exp(-1.4)) < 1e-7, quantity + " retains Beer path-length scaling")
	var metadata := _metadata("internal_transmittance")
	metadata["surface_reflection_removed"] = false
	check(GemAbsorptionImport.compile_samples(wavelengths, PackedFloat64Array([0.5, 0.5]), PackedFloat64Array(), metadata).has("error"), "external interface losses are not treated as absorption")
	metadata["surface_reflection_removed"] = true
	metadata["scattering_removed"] = false
	check(GemAbsorptionImport.compile_samples(wavelengths, PackedFloat64Array([0.5, 0.5]), PackedFloat64Array(), metadata).has("error"), "scattering extinction is not treated as absorption")
	metadata = _metadata("internal_transmittance")
	for value in [0.0, 1.1, -0.1, NAN]:
		check(GemAbsorptionImport.compile_samples(wavelengths, PackedFloat64Array([value, value]), PackedFloat64Array(), metadata).has("error"), "invalid transmission is rejected")
	check(GemAbsorptionImport.compile_samples(PackedFloat64Array([400, 700]), PackedFloat64Array([0.2, 0.2]), PackedFloat64Array(), _metadata("napierian_per_mm")).has("error"), "incomplete measured domain is rejected")
	metadata = _metadata("napierian_per_mm")
	metadata["optical_basis"] = "ordinary_extraordinary"
	var result := GemAbsorptionImport.compile_samples(wavelengths, PackedFloat64Array([0.1, 0.3]), PackedFloat64Array([0.2, 0.6]), metadata)
	check(result.has("chromophore") and absf(result["chromophore"].absorption_eray_mm[200] - 0.4) < 1e-7, "ordinary and extraordinary measurements stay separate")
	# CSV parser retains raw-byte provenance and handles nonuniform sampling.
	var path := "res://artifacts/tests/material-input.csv"
	var csv := "wavelength_nm,ordinary\n380,0.1\n480,0.2\n780,0.5\n"
	check(GemArtifactStore.atomic_write(path, csv.to_utf8_buffer()), "write isolated spectroscopy fixture")
	result = GemAbsorptionImport.read_csv(path, _metadata("napierian_per_mm"))
	check(result.has("chromophore") and absf(result["chromophore"].absorption_mm[200] - 0.3) < 1e-7, "nonuniform measurement interpolates in coefficient space")
	check(result.has("chromophore") and result["chromophore"].absorption_evidence.dataset_sha256 == FileAccess.get_sha256(path), "raw measurement SHA is retained")

func _validation() -> void:
	var material: GemMaterial = load("res://data/lapidary/stones/ruby.tres").material.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	check(material.validate().is_empty(), "catalog material validates")
	check(material.species.refraction_evidence.kind == GemOpticalEvidence.Kind.PUBLISHED_MODEL, "published refraction classification is explicit")
	check(material.chromophore.absorption_evidence.kind == GemOpticalEvidence.Kind.AUTHORED_APPROXIMATION, "authored absorption does not inherit refraction credibility")
	material.chromophore.concentration = -1.0
	check(not material.validate().is_empty(), "negative concentration rejected")
	material.chromophore.concentration = NAN
	check(not material.validate().is_empty(), "nonfinite concentration rejected")
	material.chromophore.concentration = 1e100
	check(not material.validate().is_empty(), "float32 coefficient overflow rejected")
	material.chromophore.concentration = 1.0
	material.species.sellmeier_c_um2.x = 0.5 * 0.5
	check(not material.validate().is_empty(), "visible Sellmeier pole rejected before geometry/transport")
	material.species.sellmeier_c_um2 = Vector3.ZERO
	material.species.sellmeier_b = Vector3(1.5, 0, -0.25)
	check(absf(material.species.ior_at(500) - 1.5) < 1e-7, "signed Sellmeier terms are evaluated consistently")
	material.species.sellmeier_b = Vector3(-2, 0, 0)
	check(not material.validate().is_empty(), "negative n squared is not clamped into a valid material")
	material.species.sellmeier_b = Vector3(1.25, 0, 0)
	material.species.refraction_range_nm = Vector2(500, 700)
	check(not material.validate().is_empty(), "out-of-domain refraction is rejected")

func _resampling() -> void:
	var material := GemMaterial.new()
	material.species = GemSpecies.new()
	material.chromophore = GemChromophore.new()
	material.chromophore.wavelength_step_nm = 200.0
	material.chromophore.absorption_mm = PackedFloat32Array([0, 1, 0])
	material.chromophore.absorption_eray_mm = PackedFloat32Array([0, 2, 0])
	var result := GemMaterialCompiler.compile(material)
	check(result["absorption"].size() == 401 and result["absorption_eray"].size() == 401, "bulk compiler emits the shared 1 nm grid")
	check(result["absorption"][100] == 0.5 and result["absorption_eray"][100] == 1.0, "source-grid resampling preserves both axes")
	material.chromophore.wavelength_start_nm = 400.0
	check(not material.validate().is_empty(), "source absorption never silently extrapolates")
