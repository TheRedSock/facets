class_name GemStandardSpectra
extends RefCounted
## CIE 1931 2-degree observer and standard illuminant D65, 1 nm tables.
## CIE 2019, DOI 10.25039/CIE.DS.xvudnb9b and 10.25039/CIE.DS.hjfjmt59.
## CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
## Original tables and publisher attribution/metadata remain beside the data.
## No analytic CMF fit or blackbody approximation to daylight is used here.
const ROOT := "res://data/lapidary/standards/"
const CMF_FILE := ROOT + "CIE_xyz_1931_2deg.csv"
const D65_FILE := ROOT + "CIE_std_illum_D65.csv"
static var _cmf := PackedVector3Array()
static var _d65 := PackedFloat32Array()

static func _load() -> void:
	if not _cmf.is_empty():
		return
	assert(FileAccess.get_sha256(CMF_FILE) == "fa663e3535a7e0763a745993a1f0a192eb0275ac46ad2d1befd7626841e713c1", "CIE observer table checksum mismatch")
	assert(FileAccess.get_sha256(D65_FILE) == "e76f210bffff3d552ef7113025da5f325d5dfec200dd4b878b1a2f3a507032cb", "CIE daylight table checksum mismatch")
	var file := FileAccess.open(CMF_FILE, FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() != 4:
			continue
		assert(int(row[0]) == 360 + _cmf.size())
		_cmf.append(Vector3(float(row[1]), float(row[2]), float(row[3])))
	file = FileAccess.open(D65_FILE, FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() != 2:
			continue
		assert(int(row[0]) == 300 + _d65.size())
		_d65.append(float(row[1]))
	assert(_cmf.size() == 471 and _d65.size() == 531, "Incomplete CIE tables")

static func xyz(wavelength_nm: float) -> Vector3:
	_load()
	if wavelength_nm < 360.0 or wavelength_nm > 830.0:
		return Vector3.ZERO
	var position := wavelength_nm - 360.0
	var index := int(position)
	return _cmf[index].lerp(_cmf[mini(index + 1, 470)], position - index)

## Relative spectral radiance with D65(560 nm) = 1.
static func daylight(wavelength_nm: float) -> float:
	_load()
	if wavelength_nm < 300.0 or wavelength_nm > 830.0:
		return 0.0
	var position := wavelength_nm - 300.0
	var index := int(position)
	return lerpf(_d65[index], _d65[mini(index + 1, 530)], position - index) / _d65[260]

## The current transport domain is 380..780 nm (matching the material curves).
## A vec4 per nanometer contains xbar, ybar, zbar, relative D65.
static func packed() -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for i in 401:
		var cmf := xyz(380 + i)
		values.append_array(PackedFloat32Array([cmf.x, cmf.y, cmf.z, daylight(380 + i)]))
	return values
