extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	# Independent 50-digit Decimal evaluation of the published equations,
	# including sapphire's squared poles and quartz's additive n^2 constant.
	var references := {
		"quartz": [[380, 1.560460246591919061, 1.570117262113737986],
			[400, 1.557730765267995062, 1.567293663367565936],
			[486.1, 1.549666046616637765, 1.558952791033776493],
			[589.3, 1.544205738784121256, 1.553305774267676747],
			[656.3, 1.541852816922045142, 1.550871606931756967],
			[780, 1.538743469497470979, 1.547652729690582856]],
		"corundum": [[380, 1.790253608753186730, 1.781717997919126080],
			[400, 1.786521204997414553, 1.778065653643686949],
			[486.1, 1.775510606882314402, 1.767286928762826616],
			[589.3, 1.768076354865010903, 1.760002029781818657],
			[656.3, 1.764882843813710546, 1.756868803603430713],
			[780, 1.760681436979620505, 1.752739809036610915]]}
	for id: String in references:
		var species: GemSpecies = load("res://data/lapidary/species/" + id + ".tres")
		check(species.validate().is_empty(), id + " principal model validates")
		for row: Array in references[id]:
			check(absf(species.ior_at(row[0]) - row[1]) < 2e-12, id + " ordinary published index")
			check(absf(species.extraordinary_ior_at(row[0]) - row[2]) < 2e-12, id + " extraordinary published index")
		check(absf(species.birefringence_at(380) - species.birefringence_at(780)) > 0.0005, id + " difference varies with wavelength")
		check(species.extraordinary.evidence.kind == GemOpticalEvidence.Kind.PUBLISHED_MODEL, id + " separate evidence")
	var quartz: GemSpecies = load("res://data/lapidary/species/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var material := GemMaterial.new()
	material.species = quartz
	check(not GemMaterialCompiler.polarization_error(GemMaterialCompiler.compile(material)).is_empty(), "anisotropic real indices reject isotropic polarized transport")
	# An offset chosen to make n_e == n_o at one wavelength must not make
	# the full material pass the isotropic capability gate.
	quartz.extraordinary.index_offset = -quartz.birefringence_at(589.3)
	check(absf(quartz.birefringence_at(589.3)) < 1e-14, "crossing fixture at reference wavelength")
	check(not GemMaterialCompiler.polarization_error(GemMaterialCompiler.compile(material)).is_empty(), "crossing spectra stay anisotropic")
	quartz.extraordinary = null
	check(GemMaterialCompiler.polarization_error(GemMaterialCompiler.compile(material)).is_empty(), "explicit isotropic material admitted")
	var elbaite: GemSpecies = load("res://data/lapidary/species/elbaite.tres")
	check(elbaite.extraordinary.evidence.kind == GemOpticalEvidence.Kind.AUTHORED_APPROXIMATION, "unmeasured extraordinary dispersion does not inherit published status")
	for wavelength in [380, 589.3, 780]:
		check(absf(elbaite.birefringence_at(wavelength) + 0.018) < 1e-12, "explicit offset model")
	var curve := GemIndexCurve.new()
	curve.b = PackedFloat64Array([1.0])
	check(not curve.validate().is_empty(), "wrong coefficient dimensions rejected")
	curve.b = PackedFloat64Array([NAN, 0, 0])
	check(not curve.validate().is_empty(), "nonfinite coefficients rejected")
	curve.b = PackedFloat64Array([1, 0, 0])
	curve.c_um2[0] = 0.25
	check(not curve.validate().is_empty(), "interior spectral pole rejected")
	curve.c_um2[0] = 0
	curve.index_offset = -1
	check(not curve.validate().is_empty(), "sub-unity visible real index rejected")
	curve.index_offset = 0
	curve.range_nm = Vector2(400, 700)
	check(not curve.validate().is_empty() and is_nan(curve.at(380)), "model domain is enforced")
	curve.range_nm = Vector2(380, 780)
	curve.b = PackedFloat64Array([100000001.0, -100000000.0, 0])
	check(absf(curve.at(500) - sqrt(2)) < 1e-12 and not curve.validate().is_empty(), "catastrophic GPU coefficient cancellation rejected")
	var stone: GemStone = load("res://data/lapidary/stones/ruby.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var key := stone.fingerprint()
	stone.material.species.extraordinary.b[0] += 1e-12
	check(stone.fingerprint() != key, "float64 extraordinary coefficient participates in identity")
	var path := "res://artifacts/tests/principal-indices.res"
	check(GemResourceBundle.save(stone, path) == OK, "serialize independent principal resources")
	var loaded: GemStone = load(path)
	check(loaded.fingerprint() == stone.fingerprint(), "farm binary preserves float64 principal model")
	print("Principal indices: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
