extends SceneTree

## Generates absorption spectra for gem minerals.
##
## Usage:
##   # From Gaussian bands:
##   godot --headless --script tools/generate_absorption_spectrum.gd -- \
##     --bands='[{"center":410,"width":40,"strength":3.2},{"center":560,"width":50,"strength":4.1}]'
##
##   # Migration from old RGB absorption color:
##   godot --headless --script tools/generate_absorption_spectrum.gd -- \
##     --from-rgb="0.003,0.012,0.88" --from-strength=8.5
##
##   # Output formats: json (default), tres (PackedFloat32Array literal)
##   --format=json|tres
##   --output=<path>  (write to file, otherwise stdout)

const LAMBDA_MIN := 380.0
const LAMBDA_MAX := 780.0
const SPECTRUM_SAMPLES := 81
const SPECTRUM_STEP := 5.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var args := _parse_args(OS.get_cmdline_user_args())

	var spectrum: PackedFloat32Array

	if args.has("bands"):
		spectrum = _generate_from_bands(String(args["bands"]))
	elif args.has("from-rgb"):
		var strength := float(args.get("from-strength", 1.0))
		spectrum = _generate_from_rgb(String(args["from-rgb"]), strength)
	else:
		print("Error: Specify --bands='[...]' or --from-rgb=\"R,G,B\"")
		print("")
		print("  --bands: JSON array of {center, width, strength} Gaussian bands")
		print("  --from-rgb: Comma-separated R,G,B absorption color (0-1)")
		print("  --from-strength: Absorption strength multiplier (default 1.0)")
		print("  --format: Output format: json (default) or tres")
		print("  --output: Output file path (default: stdout)")
		quit(1)
		return

	var output_format := String(args.get("format", "json")).strip_edges().to_lower()
	var output_path := String(args.get("output", ""))

	var text: String
	if output_format == "tres":
		text = _format_tres(spectrum)
	else:
		text = _format_json(spectrum)

	if output_path.is_empty():
		print(text)
	else:
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			print("Error: Could not open %s for writing" % output_path)
			quit(1)
			return
		file.store_string(text)
		file.close()
		print("Wrote %d-entry spectrum to %s" % [spectrum.size(), output_path])

	quit(0)


func _generate_from_bands(bands_json: String) -> PackedFloat32Array:
	var parsed = JSON.parse_string(bands_json)
	if typeof(parsed) != TYPE_ARRAY:
		print("Error: --bands must be a JSON array")
		quit(1)
		return PackedFloat32Array()

	var spectrum := PackedFloat32Array()
	spectrum.resize(SPECTRUM_SAMPLES)
	spectrum.fill(0.0)

	for band in parsed:
		if typeof(band) != TYPE_DICTIONARY:
			continue
		var center: float = float(band.get("center", band.get("center_nm", 550.0)))
		var width: float = float(band.get("width", band.get("width_nm", 30.0)))
		var strength: float = float(band.get("strength", 1.0))

		for i in SPECTRUM_SAMPLES:
			var lambda := LAMBDA_MIN + float(i) * SPECTRUM_STEP
			var delta := (lambda - center) / maxf(width, 1.0)
			spectrum[i] += strength * exp(-0.5 * delta * delta)

	return spectrum


func _generate_from_rgb(rgb_str: String, strength: float) -> PackedFloat32Array:
	var parts := rgb_str.split(",", false)
	if parts.size() < 3:
		print("Error: --from-rgb expects R,G,B (e.g., \"0.003,0.012,0.88\")")
		quit(1)
		return PackedFloat32Array()

	var r := float(parts[0].strip_edges())
	var g := float(parts[1].strip_edges())
	var b := float(parts[2].strip_edges())

	# Smooth spectral basis functions (Gaussian peaks)
	# R peaks at 610nm, G at 540nm, B at 460nm, width ~40nm
	var spectrum := PackedFloat32Array()
	spectrum.resize(SPECTRUM_SAMPLES)

	for i in SPECTRUM_SAMPLES:
		var lambda := LAMBDA_MIN + float(i) * SPECTRUM_STEP
		var r_basis := exp(-0.5 * pow((lambda - 610.0) / 40.0, 2.0))
		var g_basis := exp(-0.5 * pow((lambda - 540.0) / 40.0, 2.0))
		var b_basis := exp(-0.5 * pow((lambda - 460.0) / 40.0, 2.0))

		var transmission := r * r_basis + g * g_basis + b * b_basis
		spectrum[i] = maxf((1.0 - clampf(transmission, 0.0, 1.0)) * strength, 0.0)

	return spectrum


func _format_json(spectrum: PackedFloat32Array) -> String:
	var entries: PackedStringArray = []
	for i in spectrum.size():
		entries.append("%.6f" % spectrum[i])
	return "[%s]" % ", ".join(entries)


func _format_tres(spectrum: PackedFloat32Array) -> String:
	var entries: PackedStringArray = []
	for i in spectrum.size():
		entries.append("%.6f" % spectrum[i])
	return "PackedFloat32Array(%s)" % ", ".join(entries)


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var result := {}
	for arg in raw:
		var stripped := arg.strip_edges()
		if stripped.begins_with("--"):
			stripped = stripped.substr(2)
		var eq := stripped.find("=")
		if eq >= 0:
			result[stripped.substr(0, eq)] = stripped.substr(eq + 1)
		else:
			result[stripped] = true
	return result
