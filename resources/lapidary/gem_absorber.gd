class_name GemAbsorber
extends Resource
## One homogeneous absorption term. Sum coefficients, never colors/transmissions.
enum Unit { RELATIVE_SCALE, NUMBER_PER_CM3, PPMA_TOTAL_ATOMS }
@export var chromophore: GemChromophore
@export var amount := 1.0
@export var unit := Unit.RELATIVE_SCALE
## Evidence for the concentration, independent of the measured spectrum.
@export var amount_evidence: GemOpticalEvidence = GemOpticalEvidence.new()

static func relative(spectrum: GemChromophore, scale := 1.0) -> GemAbsorber:
	var term:=GemAbsorber.new()
	term.chromophore=spectrum
	term.amount=scale
	return term

func coefficient_scale(atom_density_per_cm3: float) -> float:
	if unit==Unit.RELATIVE_SCALE:return amount
	var density:=amount*atom_density_per_cm3*1e-6 if unit==Unit.PPMA_TOTAL_ATOMS else amount
	# N[/cm3] * sigma[cm2] = alpha[/cm]; convert to Napierian /mm.
	return density/10.0

func validate(species_id: StringName, atom_density_per_cm3: float) -> PackedStringArray:
	var errors:=PackedStringArray()
	if amount_evidence == null: errors.append("Absorption amount evidence is missing")
	else: errors.append_array(amount_evidence.validate())
	if chromophore==null:return PackedStringArray(["Absorption term needs a spectrum"])
	errors.append_array(chromophore.validate())
	if unit not in [Unit.RELATIVE_SCALE,Unit.NUMBER_PER_CM3,Unit.PPMA_TOTAL_ATOMS] or not is_finite(amount) or amount<0:
		errors.append("Absorption amount must be finite, nonnegative and have explicit units")
	if (chromophore.basis==GemChromophore.SpectrumBasis.COEFFICIENT_PER_MM)!=(unit==Unit.RELATIVE_SCALE):
		errors.append("Absorption quantity and concentration units do not match")
	if not chromophore.host_species_id.is_empty() and chromophore.host_species_id!=species_id:
		errors.append("Absorber cross section belongs to a different host species")
	if unit==Unit.PPMA_TOTAL_ATOMS and (atom_density_per_cm3<=0 or amount>1e6):
		errors.append("Total-atom ppma requires a declared host atom density and amount <= 1e6")
	var scale:=coefficient_scale(atom_density_per_cm3)
	if not is_finite(scale):errors.append("Absorption amount conversion overflow")
	return errors
