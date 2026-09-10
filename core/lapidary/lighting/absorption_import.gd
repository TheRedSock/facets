class_name GemAbsorptionImport
extends RefCounted
## Imports coefficients as Napierian /mm or cross sections as float64 cm2.
## Cross sections retain their quantity; material terms supply concentrations.
## IUPAC absorption coefficient: https://doi.org/10.1351/goldbook.A00037
## Internal T=exp(-alpha*length); decadic A=alpha*length/ln(10).
## External transmission includes interfaces and scattering and is not absorption.
const UNITS := ["napierian_per_mm", "napierian_per_cm", "napierian_per_m",
	"decadic_per_mm", "decadic_per_cm", "decadic_per_m",
	"internal_transmittance", "internal_transmittance_percent", "decadic_absorbance", "cross_section_cm2", "cross_section_mm2"]

static func read_csv(path: String, metadata: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4 * 1024 * 1024:
		return {"error": "Cannot read measurement CSV or file exceeds 4 MiB"}
	var header := file.get_csv_line()
	if header != PackedStringArray(["wavelength_nm", "ordinary"]) and header != PackedStringArray(["wavelength_nm", "ordinary", "extraordinary"]):
		return {"error": "CSV header must be wavelength_nm,ordinary[,extraordinary]"}
	var wavelengths := PackedFloat64Array()
	var ordinary := PackedFloat64Array()
	var extraordinary := PackedFloat64Array()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and row[0].strip_edges().is_empty():
			continue
		if row.size() != header.size():
			return {"error": "CSV row has the wrong number of columns"}
		for cell in row:
			if not cell.is_valid_float():
				return {"error": "Measurement CSV contains a nonnumeric value"}
		wavelengths.append(float(row[0]))
		ordinary.append(float(row[1]))
		if row.size() == 3:
			extraordinary.append(float(row[2]))
	var details := metadata.duplicate(true)
	details["dataset_sha256"] = FileAccess.get_sha256(path)
	return compile_samples(wavelengths, ordinary, extraordinary, details)

static func compile_samples(wavelengths: PackedFloat64Array, ordinary: PackedFloat64Array,
		extraordinary: PackedFloat64Array, metadata: Dictionary) -> Dictionary:
	var quantity := String(metadata.get("quantity", ""))
	if quantity not in UNITS:
		return {"error": "Unknown or ambiguous measurement quantity"}
	if wavelengths.size() < 2 or wavelengths.size() > 10000 or ordinary.size() != wavelengths.size() or (not extraordinary.is_empty() and extraordinary.size() != wavelengths.size()):
		return {"error": "Measurement columns must have matching lengths, 2..10000 rows"}
	var is_cross_section := quantity in ["cross_section_cm2", "cross_section_mm2"]
	var basis := String(metadata.get("optical_basis", ""))
	if basis not in ["isotropic", "ordinary_extraordinary"] or (basis == "ordinary_extraordinary") != (not extraordinary.is_empty()):
		return {"error": "Specify isotropic or ordinary_extraordinary data with matching columns"}
	for index in wavelengths.size():
		if not is_finite(wavelengths[index]) or (index > 0 and wavelengths[index] <= wavelengths[index - 1]):
			return {"error": "Wavelengths must be finite and strictly increasing"}
	if wavelengths[0] > 380.0 or wavelengths[-1] < 780.0:
		return {"error": "Measurement must cover 380..780 nm; extrapolation is not implicit"}
	var length_mm := float(metadata.get("path_mm", 0.0))
	if quantity in ["internal_transmittance", "internal_transmittance_percent", "decadic_absorbance"]:
		if not is_finite(length_mm) or length_mm <= 0.0:
			return {"error": "Transmission/absorbance requires a positive path_mm"}
		if metadata.get("surface_reflection_removed", false) != true or metadata.get("scattering_removed", false) != true:
			return {"error": "Transmission/absorbance must have interface loss and scattering removed before importing absorption"}
	var evidence := GemOpticalEvidence.new()
	evidence.kind = GemOpticalEvidence.Kind.SUPPLIED_MEASUREMENT
	evidence.citation = str(metadata.get("citation", ""))
	evidence.dataset_sha256 = str(metadata.get("dataset_sha256", ""))
	evidence.method = str(metadata.get("method", ""))
	evidence.source_record = metadata.duplicate(true)
	evidence.temperature_kelvin = float(metadata.get("temperature_kelvin", 0.0))
	evidence.relative_uncertainty = float(metadata.get("relative_uncertainty", -1.0))
	evidence.assumptions = "Input %s; basis %s; path %.9f mm; spectral interpolation to 1 nm. %s" % [quantity, basis, length_mm, str(metadata.get("assumptions", ""))]
	var evidence_errors := evidence.validate()
	if not evidence_errors.is_empty():
		return {"error": "; ".join(evidence_errors)}
	var arrays := []
	for input in [ordinary, extraordinary]:
		if input.is_empty():
			arrays.append(PackedFloat64Array() if is_cross_section else PackedFloat32Array())
			continue
		var converted := PackedFloat64Array()
		for value in input:
			if not is_finite(value) or value < 0.0:
				return {"error": "Measurement values must be finite and nonnegative"}
			var alpha: float = value
			if is_cross_section:
				alpha = value / (100.0 if quantity=="cross_section_mm2" else 1.0)
			elif quantity.begins_with("internal_transmittance"):
				var transmittance: float = value / (100.0 if quantity.ends_with("_percent") else 1.0)
				if transmittance <= 0.0 or transmittance > 1.0:
					return {"error": "Internal transmission must be in (0,1]; saturated zero is not a finite absorption measurement"}
				alpha = -log(transmittance) / length_mm
			elif quantity == "decadic_absorbance":
				alpha = value * log(10.0) / length_mm
			else:
				alpha /= 10.0 if quantity.ends_with("_cm") else (1000.0 if quantity.ends_with("_m") else 1.0)
				if quantity.begins_with("decadic_"):
					alpha *= log(10.0)
			converted.append(alpha)
		var output: Variant = PackedFloat64Array() if is_cross_section else PackedFloat32Array()
		var left := 0
		for index in 401:
			var wavelength := 380.0 + index
			while left + 1 < wavelengths.size() - 1 and wavelengths[left + 1] < wavelength:
				left += 1
			var fraction := (wavelength - wavelengths[left]) / (wavelengths[left + 1] - wavelengths[left])
			output.append(lerpf(converted[left], converted[left + 1], fraction))
		arrays.append(output)
	var result := GemChromophore.new()
	result.chromophore_id = StringName(metadata.get("id", "imported_absorption"))
	result.display_name = str(metadata.get("display_name", result.chromophore_id))
	result.source_note = evidence.citation
	result.absorption_evidence = evidence
	result.wavelength_step_nm = 1.0
	if is_cross_section:
		result.basis = GemChromophore.SpectrumBasis.CROSS_SECTION_CM2
		result.host_species_id = StringName(metadata.get("host_species_id", ""))
		result.cross_section_cm2 = arrays[0]
		result.cross_section_parallel_cm2 = arrays[1]
	else:
		result.absorption_mm = arrays[0]
		result.absorption_eray_mm = arrays[1]
	var errors := result.validate()
	if not errors.is_empty():
		return {"error": "; ".join(errors)}
	return {"chromophore": result}
