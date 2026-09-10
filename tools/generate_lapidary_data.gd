extends SceneTree

## GENERATOR (kept on purpose): authors the lapidary SPECIES / CHROMOPHORE /
## GRADE / STONE .tres files under data/lapidary/. The committed .tres files are
## the canonical artifacts; this script exists so the 81-sample absorption
## curves and the fitted Sellmeier coefficients are reproducible and reviewable.
##
## Run:
##   godot --headless --path . --script res://tools/generate_lapidary_data.gd
##
## Sources for every optical constant: docs/lapidary-spectra-sources.md.
## Sellmeier convention (GemSpecies.ior_at): n^2 - 1 = sum B_i * L^2 / (L^2 - C_i),
## L in MICROMETERS, C_i in um^2. Published tables that write (L^2 - C_i^2) have
## their C values SQUARED before storage (corundum, diamond). Ghosh's quartz
## equation is already in um^2 form; its additive constant is stored as a B term
## with C = 0 (L^2/(L^2-0) == 1).

const SpeciesScript := preload("res://resources/lapidary/gem_species.gd")
const ChromophoreScript := preload("res://resources/lapidary/gem_chromophore.gd")
const ArchetypeScript := preload("res://resources/lapidary/gem_inclusion_archetype.gd")
const GradeScript := preload("res://resources/lapidary/gem_grade.gd")
const StoneScript := preload("res://resources/lapidary/gem_stone.gd")

const DIR_SPECIES := "res://data/lapidary/species/"
const DIR_CHROMO := "res://data/lapidary/chromophores/"
const DIR_GRADES := "res://data/lapidary/grades/"
const DIR_STONES := "res://data/lapidary/stones/"

## Fraunhofer lines (nm): D (n_D), F/C (Abbe), B/G (gemological dispersion).
const WL_D := 589.3
const WL_F := 486.1
const WL_C := 656.3
const WL_B := 686.7
const WL_G := 430.8


func _init() -> void:
	for dir in [DIR_SPECIES, DIR_CHROMO, DIR_GRADES, DIR_STONES]:
		DirAccess.make_dir_recursive_absolute(dir)

	var species := _build_species()
	var chromophores := _build_chromophores()
	var grades := _build_grades()
	var stones := _build_stones(species, chromophores, grades)

	print("\n=== Lapidary data generated ===")
	_print_species_table(species)
	_print_beer_lambert(chromophores, stones)
	print("Files: %d species, %d chromophores, %d grades, %d stones" % [
		species.size(), chromophores.size(), grades.size(), stones.size()])
	quit(0)


# ------------------------------------------------------------------ species

func _build_species() -> Dictionary:
	var out := {}

	# --- Quartz (SiO2, trigonal). Ghosh 1999 alpha-quartz ORDINARY ray.
	# n^2 - 1 = 0.28604141 + 1.07044083 L^2/(L^2 - 1.00585997e-2) + 1.10202242 L^2/(L^2 - 100)
	# C values are published in um^2 already (NOT squared here); the additive
	# constant is stored as B3 with C3 = 0. n_D = 1.5443.
	var quartz: Resource = SpeciesScript.new()
	quartz.species_id = &"quartz"
	quartz.display_name = "Quartz (SiO2)"
	quartz.source_note = "Sellmeier: G. Ghosh, Opt. Commun. 163, 95-102 (1999), alpha-quartz o-ray (refractiveindex.info SiO2/Ghosh-o; C already in um^2, constant 0.28604141 stored as B with C=0). Birefringence 0.009 uniaxial(+), Mohs 7, dispersion B-G 0.013: standard gemological values. Sector zoning (amethyst) approximated as planar banding, see docs/lapidary-spectra-sources.md."
	quartz.sellmeier_b = Vector3(1.07044083, 1.10202242, 0.28604141)
	quartz.sellmeier_c_um2 = Vector3(0.0100585997, 100.0, 0.0)
	quartz.birefringence = 0.009
	quartz.uniaxial_positive = true
	quartz.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # table ⊥ c
	quartz.base_scatter_per_mm = 0.002
	quartz.scatter_anisotropy_g = 0.55
	quartz.hardness_mohs = 7.0
	quartz.zoning_axis = Vector3(0.25, 0.1, 0.96)
	quartz.zoning_frequency = 3.0
	quartz.zoning_contrast = 0.35
	quartz.inclusions.append(_archetype(&"quartz_milk_bank", ArchetypeScript.Form.CLOUD,
		Vector2(0.08, 0.22), 1.0, [], 6.0, Color(1.0, 1.0, 1.0), 4.0, 0.0))
	quartz.inclusions.append(_archetype(&"quartz_milky_veil", ArchetypeScript.Form.VEIL,
		Vector2(0.3, 1.0), 24.0, [], 8.0, Color(1.0, 0.99, 0.97), 2.0, 0.15))
	_save(quartz, DIR_SPECIES + "quartz.tres")
	out[&"quartz"] = quartz

	# --- Olivine ((Mg,Fe)2SiO4, orthorhombic). No published visible-range
	# Sellmeier for gem peridot; 2-term fit to n_D = 1.654 (n_alpha of Fo88-92,
	# RI range 1.654-1.690) and B-G dispersion 0.020.
	var olivine: Resource = SpeciesScript.new()
	var olivine_fit := _fit_two_term(1.654, 0.020, 0.025)
	olivine.species_id = &"olivine"
	olivine.display_name = "Olivine (Mg,Fe)2SiO4 Fo90"
	olivine.source_note = "2-term Sellmeier FIT (this file's generator): targets n_D=1.654 (n_alpha; gem peridot RI 1.654-1.690, GIA Gem Encyclopedia / globalgemology.com) and B-G dispersion 0.020; UV pole 0.025 um^2 + constant term. Biaxial, approximated uniaxial(+) with delta-n 0.036 (lit. 0.035-0.038). Mohs 6.5 (GIA: 6.5-7)."
	olivine.sellmeier_b = olivine_fit["b"]
	olivine.sellmeier_c_um2 = olivine_fit["c"]
	olivine.birefringence = 0.036
	olivine.uniaxial_positive = true
	olivine.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # table ⊥ c
	olivine.base_scatter_per_mm = 0.002
	olivine.hardness_mohs = 6.5
	# Lily pads: disc-shaped decrepitation halo around a tiny crystal
	# (chromite / negative crystal). Kernel draws a thin ring, not a filled
	# coin. Axes follow olivine's imperfect cleavages so they are not all
	# table-facing (San Carlos: {010} common, {100} also; GIA G&G 17(4)).
	olivine.inclusions.append(_archetype(&"olivine_lily_pad", ArchetypeScript.Form.PLATELET,
		Vector2(0.12, 0.32), 20.0,
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		6.0, Color(0.92, 0.98, 0.88), 2.0, 0.35))
	olivine.inclusions.append(_archetype(&"olivine_lily_pad_halo", ArchetypeScript.Form.CLOUD,
		Vector2(0.08, 0.20), 1.0,
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		4.5, Color(0.94, 1.0, 0.92), 2.0, 0.35))
	_save(olivine, DIR_SPECIES + "olivine.tres")
	out[&"olivine"] = olivine

	# --- Topaz (Al2SiO4(F,OH)2, orthorhombic). No standard published Sellmeier;
	# 2-term fit to n_D = 1.612 (F-rich topaz 1.61-1.62; full range 1.606-1.644)
	# and B-G dispersion 0.014. The old repo Sellmeier (n_D 1.549) was wrong.
	var topaz: Resource = SpeciesScript.new()
	var topaz_fit := _fit_two_term(1.612, 0.014, 0.025)
	topaz.species_id = &"topaz"
	topaz.display_name = "Topaz (Al2SiO4(F,OH)2)"
	topaz.source_note = "2-term Sellmeier FIT (this file's generator): targets n_D=1.612 (F-rich topaz 1.61-1.62, gemologyproject.com; full range 1.606-1.644) and B-G dispersion 0.014; UV pole 0.025 um^2 + constant term. Biaxial(+), approximated uniaxial(+) with delta-n 0.010 (lit. 0.008-0.010). Mohs 8."
	topaz.sellmeier_b = topaz_fit["b"]
	topaz.sellmeier_c_um2 = topaz_fit["c"]
	topaz.birefringence = 0.010
	topaz.uniaxial_positive = true
	topaz.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # table ⊥ c
	topaz.base_scatter_per_mm = 0.001
	topaz.hardness_mohs = 8.0
	topaz.inclusions.append(_archetype(&"topaz_tear_feather", ArchetypeScript.Form.VEIL,
		Vector2(0.3, 1.0), 26.0, [], 8.0, Color(1.0, 0.98, 0.94), 3.0, 0.2))
	topaz.inclusions.append(_archetype(&"topaz_cloud", ArchetypeScript.Form.CLOUD,
		Vector2(0.08, 0.22), 1.0, [], 5.5, Color(1.0, 1.0, 1.0), 1.5, 0.3))
	_save(topaz, DIR_SPECIES + "topaz.tres")
	out[&"topaz"] = topaz

	# --- Corundum (Al2O3, trigonal). Malitson & Dodge 1972 ordinary ray.
	# Published poles 0.0726631 / 0.1193242 / 18.028251 um are SQUARED here.
	var corundum: Resource = SpeciesScript.new()
	corundum.species_id = &"corundum"
	corundum.display_name = "Corundum (Al2O3)"
	corundum.source_note = "Sellmeier: I. H. Malitson & M. J. Dodge, JOSA 62, 1405 (1972), o-ray (refractiveindex.info Al2O3/Malitson-o); published pole wavelengths 0.0726631/0.1193242/18.028251 um SQUARED to um^2. n_D=1.7680. Birefringence 0.008 uniaxial(-), Mohs 9. Fluorescence: Cr3+ R-line ~693 nm (GIA G&G Spring 2020, Dubinsky et al.); carried by the species, so Fe-quenched sapphire inherits it — see limitations in docs/lapidary-spectra-sources.md."
	corundum.sellmeier_b = Vector3(1.4313493, 0.65054713, 5.3414021)
	corundum.sellmeier_c_um2 = Vector3(0.0052799261, 0.0142382647, 325.017834)
	corundum.birefringence = 0.008
	corundum.uniaxial_positive = false
	corundum.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # table ⊥ c
	corundum.base_scatter_per_mm = 0.001
	corundum.fluorescence_emission_nm = 693.0
	corundum.fluorescence_strength = 0.5
	corundum.hardness_mohs = 9.0
	corundum.zoning_axis = Vector3(0.85, 0.0, 0.53)
	corundum.zoning_frequency = 6.0
	corundum.zoning_contrast = 0.2
	# Rutile silk: needle sets locked at 60 degrees in the girdle (basal) plane.
	corundum.inclusions.append(_archetype(&"corundum_silk", ArchetypeScript.Form.NEEDLE,
		Vector2(0.3, 1.2), 25.0,
		[Vector3(1, 0, 0), Vector3(0.5, 0.866025, 0), Vector3(-0.5, 0.866025, 0)],
		26.0, Color(1.0, 0.96, 0.88), 4.0, 0.15))
	corundum.inclusions.append(_archetype(&"corundum_crystal", ArchetypeScript.Form.CRYSTAL,
		Vector2(0.15, 0.45), 1.5, [], 9.0, Color(0.94, 0.94, 0.98), 0.6, 0.5))
	_save(corundum, DIR_SPECIES + "corundum.tres")
	out[&"corundum"] = corundum

	# --- Beryl (Be3Al2Si6O18, hexagonal). No standard published visible
	# Sellmeier; 2-term fit to n_D = 1.577 (natural emerald n_omega 1.575-1.600)
	# and B-G dispersion 0.014.
	var beryl: Resource = SpeciesScript.new()
	var beryl_fit := _fit_two_term(1.577, 0.014, 0.025)
	beryl.species_id = &"beryl"
	beryl.display_name = "Beryl (Be3Al2Si6O18)"
	beryl.source_note = "2-term Sellmeier FIT (this file's generator): targets n_D=1.577 (natural emerald n_omega 1.575-1.600, geo.libretexts Gemology: Emerald) and B-G dispersion 0.014; UV pole 0.025 um^2 + constant term. Birefringence 0.006 uniaxial(-) (lit. 0.004-0.010). Mohs 7.75 (lit. 7.5-8)."
	beryl.sellmeier_b = beryl_fit["b"]
	beryl.sellmeier_c_um2 = beryl_fit["c"]
	beryl.birefringence = 0.006
	beryl.uniaxial_positive = false
	beryl.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # table ⊥ c
	beryl.base_scatter_per_mm = 0.002
	beryl.hardness_mohs = 7.75
	# Jardin: healed-fracture veils, fingerprints and two-phase droplets.
	beryl.inclusions.append(_archetype(&"beryl_jardin_veil", ArchetypeScript.Form.VEIL,
		Vector2(0.35, 1.1), 30.0, [], 11.0, Color(0.93, 1.0, 0.96), 3.5, 0.2))
	beryl.inclusions.append(_archetype(&"beryl_fingerprint", ArchetypeScript.Form.FINGERPRINT,
		Vector2(0.25, 0.7), 10.0, [], 9.0, Color(0.96, 1.0, 0.98), 2.0, 0.3))
	beryl.inclusions.append(_archetype(&"beryl_droplet_cloud", ArchetypeScript.Form.CLOUD,
		Vector2(0.08, 0.28), 1.0, [], 7.0, Color(0.97, 0.99, 0.96), 1.8, 0.4))
	_save(beryl, DIR_SPECIES + "beryl.tres")
	out[&"beryl"] = beryl

	# --- Diamond (C, cubic). Peter 1923; published poles 0.1060 / 0.1750 um
	# are SQUARED here (the old repo stored them unsquared -> wrong dispersion).
	var diamond: Resource = SpeciesScript.new()
	diamond.species_id = &"diamond"
	diamond.display_name = "Diamond (C)"
	diamond.source_note = "Sellmeier: F. Peter, Z. Phys. 15, 358-368 (1923) (refractiveindex.info C/Peter); published poles 0.1060/0.1750 um SQUARED to 0.011236/0.030625 um^2. n_D=2.4173 (lit. 2.41726, JHU/APL Tech. Digest 14-1). Cubic: birefringence 0. Mohs 10. Faint blue fluorescence ~440 nm (N3 centers)."
	diamond.sellmeier_b = Vector3(4.3356, 0.3306, 0.0)
	diamond.sellmeier_c_um2 = Vector3(0.011236, 0.030625, 0.0)
	diamond.birefringence = 0.0
	diamond.uniaxial_positive = true
	diamond.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # cubic: unused
	diamond.base_scatter_per_mm = 0.0005
	diamond.fluorescence_emission_nm = 440.0
	diamond.fluorescence_strength = 0.05
	diamond.hardness_mohs = 10.0
	diamond.inclusions.append(_archetype(&"diamond_pinpoint", ArchetypeScript.Form.CRYSTAL,
		Vector2(0.03, 0.12), 1.0, [], 16.0, Color(1.0, 1.0, 1.0), 1.0, 0.5))
	_save(diamond, DIR_SPECIES + "diamond.tres")
	out[&"diamond"] = diamond

	# --- Fluorite (CaF2, cubic). Malitson 1963; published pole wavelengths
	# 0.050263605 / 0.1003909 / 34.649040 um are SQUARED here. n_D = 1.4338.
	var fluorite: Resource = SpeciesScript.new()
	fluorite.species_id = &"fluorite"
	fluorite.display_name = "Fluorite (CaF2)"
	fluorite.source_note = "Sellmeier: I. H. Malitson, Appl. Opt. 2, 1103-1107 (1963) (refractiveindex.info CaF2/Malitson); published poles 0.050263605/0.1003909/34.649040 um SQUARED to um^2. n_D~1.4338, dispersion 0.007 (low). Cubic: birefringence 0. Mohs 4 — the wear model scratches it honestly. Blue fluorescence ~425 nm (Eu2+ activator; the word 'fluorescence' comes from this mineral). Strong colour banding (zoning)."
	fluorite.sellmeier_b = Vector3(0.5675888, 0.4710914, 3.8484723)
	fluorite.sellmeier_c_um2 = Vector3(0.0025262995, 0.0100783343, 1200.5559999)
	fluorite.birefringence = 0.0
	fluorite.uniaxial_positive = true
	fluorite.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # cubic: unused
	fluorite.base_scatter_per_mm = 0.003
	# Blue fluorescence is real (Eu2+), but the kernel pumps emission from
	# absorbed energy: with a green-window curve (strong 435 nm band) any
	# nonzero strength re-emits the absorbed blue and buries the body colour.
	# Off for gameplay; the UV-lamp read is not part of the board language.
	fluorite.fluorescence_emission_nm = 425.0
	fluorite.fluorescence_strength = 0.0
	fluorite.hardness_mohs = 4.0
	fluorite.zoning_axis = Vector3(0.2, 0.0, 0.98)
	fluorite.zoning_frequency = 5.0
	fluorite.zoning_contrast = 0.5
	# Cleavage flags (perfect octahedral cleavage) + two-phase droplets.
	fluorite.inclusions.append(_archetype(&"fluorite_cleavage_flag", ArchetypeScript.Form.VEIL,
		Vector2(0.35, 1.0), 20.0, [], 10.0, Color(0.96, 0.94, 1.0), 3.0, 0.2))
	fluorite.inclusions.append(_archetype(&"fluorite_droplet_cloud", ArchetypeScript.Form.CLOUD,
		Vector2(0.05, 0.14), 1.0, [], 6.0, Color(0.98, 0.99, 1.0), 1.8, 0.35))
	_save(fluorite, DIR_SPECIES + "fluorite.tres")
	out[&"fluorite"] = fluorite

	# --- Chrysoberyl (BeAl2O4, orthorhombic). No published visible Sellmeier;
	# 2-term fit to n_D = 1.746 (lit. 1.746-1.755) and B-G dispersion 0.015.
	var chrysoberyl: Resource = SpeciesScript.new()
	var chryso_fit := _fit_two_term(1.746, 0.015, 0.025)
	chrysoberyl.species_id = &"chrysoberyl"
	chrysoberyl.display_name = "Chrysoberyl (BeAl2O4)"
	chrysoberyl.source_note = "2-term Sellmeier FIT (this file's generator): targets n_D=1.746 (GIA alexandrite page: RI 1.746-1.755) and B-G dispersion 0.015 (cigem.ca alexandrite report); UV pole 0.025 um^2 + constant term. Biaxial(+), approximated uniaxial(+) with delta-n 0.009 (lit. 0.008-0.010). Mohs 8.5."
	chrysoberyl.sellmeier_b = chryso_fit["b"]
	chrysoberyl.sellmeier_c_um2 = chryso_fit["c"]
	chrysoberyl.birefringence = 0.009
	chrysoberyl.uniaxial_positive = true
	chrysoberyl.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # table ⊥ c
	chrysoberyl.base_scatter_per_mm = 0.001
	chrysoberyl.hardness_mohs = 8.5
	# Fine silk (oriented needle clouds -> cat's-eye in heavy cases) + fingerprints.
	chrysoberyl.inclusions.append(_archetype(&"chrysoberyl_silk", ArchetypeScript.Form.NEEDLE,
		Vector2(0.25, 1.0), 30.0,
		[Vector3(1, 0, 0), Vector3(0.5, 0.866025, 0), Vector3(-0.5, 0.866025, 0)],
		20.0, Color(1.0, 0.97, 0.9), 3.0, 0.15))
	chrysoberyl.inclusions.append(_archetype(&"chrysoberyl_fingerprint", ArchetypeScript.Form.FINGERPRINT,
		Vector2(0.25, 0.65), 10.0, [], 8.0, Color(0.97, 1.0, 0.98), 2.0, 0.3))
	_save(chrysoberyl, DIR_SPECIES + "chrysoberyl.tres")
	out[&"chrysoberyl"] = chrysoberyl

	# --- Garnet, pyralspite solid solution (cubic). Hosts rhodolite
	# (pyrope-almandine Py70Al30) and colour-change pyrope-spessartine.
	# 2-term fit to n_D = 1.760 and B-G dispersion 0.026.
	var garnet: Resource = SpeciesScript.new()
	var garnet_fit := _fit_two_term(1.760, 0.026, 0.025)
	garnet.species_id = &"garnet"
	garnet.display_name = "Garnet, pyralspite (Mg,Fe,Mn)3Al2(SiO4)3"
	garnet.source_note = "2-term Sellmeier FIT (this file's generator): targets n_D=1.760 (rhodolite RI 1.760 +0.010/-0.020, Wikipedia/Chemija 32:4549) and B-G dispersion 0.026 (Wikipedia rhodolite); UV pole 0.025 um^2 + constant term. Cubic: birefringence 0 (anomalous DR ignored). Mohs 7.25 (lit. 7-7.5). Colour-change pyrope-spessartine (~1.76) shares the species at this granularity."
	garnet.sellmeier_b = garnet_fit["b"]
	garnet.sellmeier_c_um2 = garnet_fit["c"]
	garnet.birefringence = 0.0
	garnet.uniaxial_positive = true
	garnet.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # cubic: unused
	garnet.base_scatter_per_mm = 0.002
	garnet.hardness_mohs = 7.25
	# Rutile needle silk + small rounded crystals (apatite/zircon).
	garnet.inclusions.append(_archetype(&"garnet_needle_silk", ArchetypeScript.Form.NEEDLE,
		Vector2(0.3, 1.1), 22.0, [], 14.0, Color(1.0, 0.96, 0.9), 3.0, 0.2))
	garnet.inclusions.append(_archetype(&"garnet_crystal", ArchetypeScript.Form.CRYSTAL,
		Vector2(0.12, 0.4), 1.4, [], 8.0, Color(0.95, 0.96, 0.94), 1.5, 0.4))
	_save(garnet, DIR_SPECIES + "garnet.tres")
	out[&"garnet"] = garnet

	# --- Elbaite tourmaline (complex borosilicate, trigonal). No published
	# visible Sellmeier; 2-term fit to n_D = 1.635 (lit. 1.62-1.64) and B-G
	# dispersion 0.018.
	var elbaite: Resource = SpeciesScript.new()
	var elbaite_fit := _fit_two_term(1.635, 0.018, 0.025)
	elbaite.species_id = &"elbaite"
	elbaite.display_name = "Elbaite tourmaline (Li borosilicate)"
	elbaite.source_note = "2-term Sellmeier FIT (this file's generator): targets n_D=1.635 (gemologyproject.com: usual RI 1.62-1.64) and B-G dispersion 0.018 (same source: 'Low, 0.018'); UV pole 0.025 um^2 + constant term. Uniaxial(-) delta-n 0.018 (lit. 0.014-0.021). Mohs 7.5. Strong colour zoning along c."
	elbaite.sellmeier_b = elbaite_fit["b"]
	elbaite.sellmeier_c_um2 = elbaite_fit["c"]
	elbaite.birefringence = 0.018
	elbaite.uniaxial_positive = false
	elbaite.optic_axis_stone = Vector3(1.0, 0.0, 0.0) # table ∥ c
	elbaite.base_scatter_per_mm = 0.002
	elbaite.hardness_mohs = 7.5
	elbaite.zoning_axis = Vector3(0, 0, 1)
	elbaite.zoning_frequency = 2.5
	elbaite.zoning_contrast = 0.45
	# Trichites: threadlike gas-liquid growth tubes along c + healed cracks
	# ("tear-shaped gas-liquid inclusions", Crystals 13:1461).
	elbaite.inclusions.append(_archetype(&"elbaite_growth_tube", ArchetypeScript.Form.NEEDLE,
		Vector2(0.4, 1.3), 35.0, [Vector3(0, 0, 1)], 16.0, Color(0.96, 1.0, 0.97), 3.5, 0.2))
	elbaite.inclusions.append(_archetype(&"elbaite_trichite_veil", ArchetypeScript.Form.VEIL,
		Vector2(0.3, 0.9), 24.0, [], 8.0, Color(0.95, 1.0, 0.96), 2.0, 0.25))
	_save(elbaite, DIR_SPECIES + "elbaite.tres")
	out[&"elbaite"] = elbaite

	# --- Painite (CaZrAl9O15(BO3), hexagonal). Literature is thin (long the
	# rarest mineral); 2-term fit to n_D = 1.80 (lit. RI ~1.787-1.816) and
	# an assumed corundum-like B-G dispersion 0.018.
	var painite: Resource = SpeciesScript.new()
	var painite_fit := _fit_two_term(1.80, 0.018, 0.025)
	painite.species_id = &"painite"
	painite.display_name = "Painite (CaZrAl9O15(BO3))"
	painite.source_note = "2-term Sellmeier FIT (this file's generator): targets n_D=1.80 (published RI range ~1.787-1.816) and ASSUMED B-G dispersion 0.018 (no published dispersion found; corundum-like oxide assumed). Uniaxial(-) delta-n 0.028. Mohs 8. Sparse literature — constants are best-effort, flagged for revisit."
	painite.sellmeier_b = painite_fit["b"]
	painite.sellmeier_c_um2 = painite_fit["c"]
	painite.birefringence = 0.028
	painite.uniaxial_positive = false
	painite.optic_axis_stone = Vector3(0.0, 0.0, 1.0) # table ⊥ c
	painite.base_scatter_per_mm = 0.001
	painite.hardness_mohs = 8.0
	painite.inclusions.append(_archetype(&"painite_crystal", ArchetypeScript.Form.CRYSTAL,
		Vector2(0.15, 0.45), 1.5, [], 8.0, Color(0.95, 0.93, 0.9), 1.5, 0.4))
	painite.inclusions.append(_archetype(&"painite_feather", ArchetypeScript.Form.VEIL,
		Vector2(0.3, 0.9), 24.0, [], 7.0, Color(1.0, 0.97, 0.93), 2.0, 0.25))
	_save(painite, DIR_SPECIES + "painite.tres")
	out[&"painite"] = painite

	return out


# ------------------------------------------------------------------ chromophores
## Curves: 81 samples 380..780 nm @ 5 nm, absorption coefficient per MILLIMETER
## at reference concentration (concentration = 1.0). Authored as sums of
## Gaussian bands at verified band positions; amplitudes chosen so the canonical
## body colour reads at the stone's size via Beer-Lambert (2 x size_mm path).
## Band-position citations: docs/lapidary-spectra-sources.md.

func _build_chromophores() -> Dictionary:
	var out := {}

	# Cr3+ in corundum (o-ray): Y band ~410 nm, U band ~556 nm, window ~480 nm
	# (slight blue leak -> purplish red), open > 620 nm, weak R-line 694 nm.
	# e-ray: bands shift ~420 / ~552 and the U band weakens -> more orange-red.
	# Concentration 0.40: curves sized for a ~4×size_mm TIR path under the
	# kernel's GIA polarisation mix (face-up ≈ pure o-ray when optic axis ≈ +Z).
	# Was 0.55 against an inverted e-weight that under-used the strong o-ray
	# U band. The 480 nm Cr³⁺ saddle is real (Fritsch & Rossman 1987) but was
	# authored too empty: Y/U Gaussians did not overlap, so the stone leaked
	# cyan and read rhodolite-magenta. B-lines ~468 nm plus a 478 nm fill raise
	# the saddle without closing the >610 nm red window. Daylight fluorescence
	# 0.05 (UV-lamp 0.5 lives on the species).
	out[&"ruby_cr"] = _chromophore(&"ruby_cr", "Chromium (ruby, corundum)",
		"Cr3+ in corundum. o-ray (E⊥c): Y band ~410 nm, U band ~556 nm (GIA G&G Spring 2020 Dubinsky et al.), B-lines ~468-475 nm, ~480 nm transmission saddle, R-line 694 nm. e-ray (E∥c): ~420/~552 with weaker U band. Curves authored for the kernel's GIA polarisation mix. Concentration 0.40 for a 5.4 mm stone. Daylight fluorescence override 0.05 @ 693 nm.",
		_curve(0.05, [[1.55, 410.0, 28.0], [1.72, 556.0, 38.0], [0.42, 478.0, 18.0], [0.22, 468.0, 8.0], [0.35, 380.0, 30.0], [0.05, 694.0, 6.0]]),
		_curve(0.05, [[1.40, 420.0, 28.0], [1.35, 552.0, 34.0], [0.22, 478.0, 16.0], [0.30, 380.0, 30.0], [0.05, 694.0, 6.0]]),
		Color(0.88, 0.11, 0.25), 0.05, 693.0, 0.40)

	# Fe2+-Ti4+ IVCT: broad band ~580 nm reaching 700, blue window 440-480,
	# weak Fe3+ features ~377/388/450.
	out[&"sapphire_fe_ti"] = _chromophore(&"sapphire_fe_ti", "Iron-titanium (blue sapphire)",
		"Fe2+-Ti4+ intervalence charge transfer in corundum: broad band ~580 nm extending toward 700 nm (GIA G&G Spring 2020; Molecules 27:4716 FORS ~570 nm), blue window 440-480 nm, weak Fe3+ bands 377/388/450 nm. Isotropic approximation (no e-ray curve). Fluorescence override 0: iron QUENCHES the corundum Cr glow (blue sapphire is inert).",
		_curve(0.05, [[0.75, 580.0, 55.0], [0.55, 700.0, 80.0], [0.12, 450.0, 12.0], [0.35, 388.0, 10.0], [0.20, 377.0, 8.0]]),
		PackedFloat32Array(),
		Color(0.15, 0.35, 0.85), 0.0, 0.0)

	# Cr3+ in beryl: bands ~430 and ~615 nm, green window 500-550, partial deep
	# red return (Chelsea-filter red flash). Fluorescence override: Cr3+ glows
	# in beryl too, but far weaker than in corundum (0.06 @ 683 nm R-line).
	out[&"emerald_cr"] = _chromophore(&"emerald_cr", "Chromium (emerald, beryl)",
		"Cr3+ in beryl: bands ~430 nm and ~600-630 nm (o-ray 430/610, Minerals 13:1260 Kagem; Cryst. Res. Technol. 2300052 keeps ~500 nm transmission), green window 500-550 nm, partial deep-red transmission (Chelsea filter). Isotropic approximation. Weak Cr3+ R-line fluorescence 683 nm.",
		_curve(0.05, [[1.10, 430.0, 30.0], [1.00, 615.0, 40.0], [0.28, 380.0, 25.0]]),
		PackedFloat32Array(),
		Color(0.10, 0.72, 0.45), 0.06, 683.0)

	# Fe4+ hole centre in irradiated quartz: broad band centred ~545 nm;
	# transmits violet-blue and some red -> purple.
	out[&"amethyst_fe_quartz"] = _chromophore(&"amethyst_fe_quartz", "Iron colour centre (amethyst)",
		"O2- -> Fe4+ charge transfer in irradiated quartz, centred in the yellow-green ~545 nm (GIA G&G 24(1) Fritsch & Rossman part 2; Cox 1977). Transmits violet-blue and some red -> purple. UV shoulder toward the ~357 nm band.",
		_curve(0.04, [[0.85, 545.0, 50.0], [0.30, 380.0, 28.0]]),
		PackedFloat32Array(),
		Color(0.62, 0.35, 0.92))

	# Fe2+ in olivine: narrow bands 453/477/497 nm plus the tail of the broad
	# Fe2+ band near 1000 nm rising past 700 nm; window 520-600 green-yellow.
	out[&"peridot_fe2"] = _chromophore(&"peridot_fe2", "Iron (peridot, olivine)",
		"Fe2+ in olivine: diagnostic bands 453/477/497 nm (GIA Gem Encyclopedia; globalgemology.com), UV charge-transfer edge, and the visible tail of the broad Fe2+ band near ~1000 nm (modelled as a Gaussian at 900 nm) warming the deep red. Green-yellow window 520-600 nm.",
		_curve(0.06, [[0.55, 453.0, 10.0], [0.50, 477.0, 9.0], [0.55, 497.0, 11.0], [1.20, 395.0, 38.0], [0.22, 900.0, 160.0]]),
		PackedFloat32Array(),
		Color(0.62, 0.78, 0.20))

	# Imperial topaz: colour centres + Cr3+ give a gentle absorption rise from
	# red toward blue; golden-orange body with a pink hint.
	out[&"topaz_imperial"] = _chromophore(&"topaz_imperial", "Imperial topaz centres",
		"Imperial (precious) topaz: colour centres plus Cr3+ (Ouro Preto type is Cr-bearing, gemsociety.org) produce a smooth absorption rise from red toward violet-blue; no sharp visible bands. Authored as two broad blue-green Gaussians + UV edge for a golden-orange body.",
		_curve(0.03, [[0.34, 415.0, 52.0], [0.16, 500.0, 50.0], [0.30, 380.0, 20.0]]),
		PackedFloat32Array(),
		Color(0.95, 0.62, 0.25))

	# ---- Alternate-ladder chromophores ------------------------------------

	# Pale green fluorite: gentle broad bands leaving a wide green window.
	# Fluorite colour agents vary (REE / colour centres); authored broad-band.
	out[&"fluorite_green"] = _chromophore(&"fluorite_green", "Green fluorite centres",
		"Green fluorite: absorption in violet-blue and orange-red leaving a green window (colour centres / REE, variable by locality — authored broad-band, not a single verified ion). Band strengths tuned at 4.5 mm Beer-Lambert path: earlier 0.10/0.13 amps were too weak/broad to carve the window and the stone read neutral blue-grey.",
		_curve(0.015, [[0.45, 435.0, 40.0], [0.35, 630.0, 45.0], [0.20, 380.0, 22.0]]),
		PackedFloat32Array(),
		Color(0.55, 0.85, 0.55))

	# Smoky quartz: Al3+ + irradiation hole colour centre (O- adjacent to
	# substitutional Al). Smooth absorption rising toward UV -> brown-grey.
	out[&"smoky_al_hole"] = _chromophore(&"smoky_al_hole", "Smoky quartz (Al hole centre)",
		"Al-O- hole colour centre in irradiated quartz (minsocam.org Color in Minerals: substitutional Al3+ + ionizing radiation; heat-bleachable). Smooth featureless absorption strongest toward violet/UV -> smoky brown-grey. No sharp visible bands.",
		_curve(0.02, [[0.45, 380.0, 55.0], [0.18, 480.0, 80.0], [0.08, 620.0, 100.0]]),
		PackedFloat32Array(),
		Color(0.45, 0.38, 0.32))

	# Verdelite (green Fe-bearing elbaite): Fe2+ Y/Z-site band ~720 nm with
	# ~670 shoulder, weak Mn3+/Fe3+ 415/470 nm, weak 583 nm, window 510-550.
	out[&"verdelite_fe"] = _chromophore(&"verdelite_fe", "Iron (verdelite, green tourmaline)",
		"Fe2+ in elbaite: broad Y/Z-octahedra band ~720 nm + 670 nm shoulder (Crystals 13:1461; BJGEO Serido elbaites 720-730 nm), weak 415/470 (Mn3+/Fe3+), weak 583 nm, UV edge 300-400. Green window 510-550 nm; red end closes -> deep bottle green.",
		_curve(0.03, [[0.75, 720.0, 55.0], [0.30, 670.0, 28.0], [0.28, 415.0, 25.0], [0.18, 470.0, 25.0], [0.12, 583.0, 25.0], [0.55, 380.0, 30.0]]),
		PackedFloat32Array(),
		Color(0.20, 0.65, 0.40))

	# Rhodolite (pyrope-almandine): Fe2+ triplet 504/520/573 + weak lines.
	out[&"rhodolite_fe2"] = _chromophore(&"rhodolite_fe2", "Iron (rhodolite garnet)",
		"Fe2+ in pyrope-almandine: diagnostic bands 504/520/573 nm with weak 423/460/610/685 nm (Wikipedia rhodolite; Chemija 32:4549; GIA G&G 21(4) garnet classification). Transmits violet-blue and red -> purplish raspberry red.",
		_curve(0.025, [[0.55, 504.0, 12.0], [0.60, 520.0, 12.0], [0.70, 573.0, 18.0], [0.15, 423.0, 10.0], [0.12, 460.0, 12.0], [0.10, 610.0, 12.0], [0.12, 685.0, 12.0], [0.40, 380.0, 25.0]]),
		PackedFloat32Array(),
		Color(0.78, 0.30, 0.45))

	# Aquamarine: Fe2+ NIR band ~820 nm tailing into deep red, Fe2+-Fe3+ IVCT
	# ~620 nm (the blue maker), weak Fe3+ 427 nm. Pale by nature.
	out[&"aquamarine_fe"] = _chromophore(&"aquamarine_fe", "Iron (aquamarine, beryl)",
		"Fe in beryl: dominant Fe2+ band ~820-825 nm (NIR, visible tail past 700; GIA G&G 44(3) Adamo et al.), Fe2+-Fe3+ IVCT ~620-640 nm absorbing orange-red (blue maker; Sci. Rep. 12:11916), weak Fe3+ 427 nm (slight yellow), UV Fe3+ edge. Blue window 460-500 nm. Amplitudes kept low: aquamarine is pale.",
		_curve(0.012, [[0.15, 820.0, 80.0], [0.14, 620.0, 60.0], [0.06, 427.0, 10.0], [0.25, 380.0, 25.0]]),
		PackedFloat32Array(),
		Color(0.55, 0.80, 0.92))

	# Alexandrite: Cr3+ in chrysoberyl. Blue-violet band ~415, yellow-green
	# ~580; windows green ~520 and red > 640 -> colour change with the rig.
	# e-ray: U band shifts down and weakens (strong pleochroism).
	out[&"alexandrite_cr"] = _chromophore(&"alexandrite_cr", "Chromium (alexandrite)",
		"Cr3+ in chrysoberyl: bands ~415 nm (blue-violet 410-450) and ~580 nm yellow-green (GIA alexandrite page: 580 nm band drives the colour change; cigem.ca), transmission windows ~520 green and >640 red. Pleochroic: e-ray band shifted/weakened (green vs red axes). Weak Cr red fluorescence ~680 nm.",
		_curve(0.035, [[0.70, 415.0, 30.0], [0.65, 580.0, 30.0], [0.25, 380.0, 25.0]]),
		_curve(0.035, [[0.62, 425.0, 30.0], [0.48, 560.0, 32.0], [0.25, 380.0, 25.0]]),
		Color(0.35, 0.70, 0.55), 0.12, 680.0)

	# Painite: V3+/Cr3+ bearing borate — orange-red to brownish red body.
	out[&"painite_v_cr"] = _chromophore(&"painite_v_cr", "Vanadium-chromium (painite)",
		"Painite body colour orange-red to brownish (V3+/Cr3+ reported as chromophores; literature sparse). Authored: blue-green absorption bands ~440/560 nm + UV edge, red open -> deep orange-red. Best-effort curve, flagged for revisit with published spectra.",
		_curve(0.03, [[0.55, 440.0, 45.0], [0.40, 560.0, 45.0], [0.50, 380.0, 30.0]]),
		PackedFloat32Array(),
		Color(0.85, 0.35, 0.20))

	# Colour-change pyrope-spessartine ("blue garnet", Bekily type): merged
	# 407-430 bands -> 435 nm cutoff + broadened strengthened V3+ 573 nm band.
	out[&"bluegarnet_v"] = _chromophore(&"bluegarnet_v", "Vanadium (colour-change garnet)",
		"Colour-change pyrope-spessartine: 435 nm cutoff from merged 407/411/421/430 bands, broad strengthened ~573 nm band (V3+ ~0.6 wt%; GIA G&G 21(4); Caltech mineral spectra GRR 2225 Tunduru), weak 504/520. Windows blue-green 460-500 and red >640 -> teal-blue in daylight, purple-red under warm light.",
		_curve(0.03, [[1.20, 405.0, 18.0], [0.80, 421.0, 10.0], [0.70, 430.0, 8.0], [0.55, 573.0, 45.0], [0.15, 504.0, 10.0], [0.15, 520.0, 10.0], [0.45, 380.0, 20.0]]),
		PackedFloat32Array(),
		Color(0.35, 0.50, 0.85))

	return out


# ------------------------------------------------------------------ grades
## Four axes, 1.0 = exceptional. Compressed floor: T1 sits near the old T5
## (sapphire-class rounding / translucency / inclusion load) and the ramp
## still widens toward T8, which stays pristine.

const GRADE_TABLE := {
	&"t1": [0.62, 0.58, 0.62, 0.66],
	&"t2": [0.67, 0.64, 0.67, 0.71],
	&"t3": [0.73, 0.70, 0.72, 0.76],
	&"t4": [0.79, 0.76, 0.78, 0.81],
	&"t5": [0.85, 0.82, 0.84, 0.86],
	&"t6": [0.91, 0.88, 0.90, 0.91],
	&"t7": [0.96, 0.94, 0.95, 0.96],
	&"t8": [1.0, 1.0, 1.0, 1.0],
}


func _build_grades() -> Dictionary:
	var out := {}
	for grade_id: StringName in GRADE_TABLE:
		var axes: Array = GRADE_TABLE[grade_id]
		var grade: Resource = GradeScript.new()
		grade.grade_id = grade_id
		grade.cut = axes[0]
		grade.clarity = axes[1]
		grade.surface = axes[2]
		grade.crystal = axes[3]
		_save(grade, DIR_GRADES + String(grade_id) + ".tres")
		out[grade_id] = grade
	return out


# ------------------------------------------------------------------ stones
## stone_id == tile_id (data/tiles/*.tres). Silhouette from the tier taxonomy;
## the ALTERNATE ladder (fluorite -> blue garnet) shares per-tier silhouettes,
## grades and sizes with the main ladder. Cut: brilliant everywhere except the
## T6 rectangle tier, which carries the step cut (emerald cut IS the step cut;
## alexandrite follows for tier consistency). size_mm rises with tier
## (4.5 -> 5.5); seeds are distinct small primes.

const CUT_PATHS := {
	&"brilliant": "res://data/lapidary/cuts/brilliant.tres",
	&"step": "res://data/lapidary/cuts/step.tres",
}

const STONE_TABLE := [
	# tile_id, species, chromophore (or empty), grade, silhouette, cut, seed, size_mm
	[&"quartz", &"quartz", &"", &"t1", &"round", &"brilliant", 11, 4.5],
	[&"amethyst", &"quartz", &"amethyst_fe_quartz", &"t2", &"square", &"brilliant", 13, 4.65],
	[&"peridot", &"olivine", &"peridot_fe2", &"t3", &"triangle", &"brilliant", 17, 4.8],
	[&"topaz", &"topaz", &"topaz_imperial", &"t4", &"oval", &"brilliant", 19, 4.95],
	[&"sapphire", &"corundum", &"sapphire_fe_ti", &"t5", &"diamond", &"brilliant", 23, 5.1],
	[&"emerald", &"beryl", &"emerald_cr", &"t6", &"rectangle", &"step", 29, 5.25],
	[&"ruby", &"corundum", &"ruby_cr", &"t7", &"marquise", &"brilliant", 31, 5.4],
	[&"diamond", &"diamond", &"", &"t8", &"pear", &"brilliant", 37, 5.5],
	[&"fluorite", &"fluorite", &"fluorite_green", &"t1", &"round", &"brilliant", 41, 4.5],
	[&"smoky_quartz", &"quartz", &"smoky_al_hole", &"t2", &"square", &"brilliant", 43, 4.65],
	[&"tourmaline", &"elbaite", &"verdelite_fe", &"t3", &"triangle", &"brilliant", 47, 4.8],
	[&"rhodolite", &"garnet", &"rhodolite_fe2", &"t4", &"oval", &"brilliant", 53, 4.95],
	[&"aquamarine", &"beryl", &"aquamarine_fe", &"t5", &"diamond", &"brilliant", 59, 5.1],
	[&"alexandrite", &"chrysoberyl", &"alexandrite_cr", &"t6", &"rectangle", &"step", 61, 5.25],
	[&"painite", &"painite", &"painite_v_cr", &"t7", &"marquise", &"brilliant", 67, 5.4],
	[&"blue_garnet", &"garnet", &"bluegarnet_v", &"t8", &"pear", &"brilliant", 71, 5.5],
]


func _build_stones(species: Dictionary, chromophores: Dictionary, grades: Dictionary) -> Array:
	var cuts := {}
	for cut_id: StringName in CUT_PATHS:
		cuts[cut_id] = load(CUT_PATHS[cut_id])
		assert(cuts[cut_id] != null, "missing cut template %s" % CUT_PATHS[cut_id])
	var out := []
	for row: Array in STONE_TABLE:
		var stone: Resource = StoneScript.new()
		stone.stone_id = row[0]
		stone.material.species = species[row[1]]
		stone.material.chromophore = chromophores[row[2]] if row[2] != &"" else null
		stone.grade = grades[row[3]]
		stone.shape = GemShape.faceted_outline(row[4])
		stone.cut = cuts[row[5]]
		stone.seed = row[6]
		stone.size_mm = row[7]
		_save(stone, DIR_STONES + String(row[0]) + ".tres")
		out.append(stone)
	return out


# ------------------------------------------------------------------ helpers

func _archetype(id: StringName, form: int, size_range: Vector2, aspect: float,
		axes: Array, density: float, tint: Color, weight: float, bias: float) -> Resource:
	var arch: Resource = ArchetypeScript.new()
	arch.archetype_id = id
	arch.form = form
	arch.size_mm_range = size_range
	arch.aspect = aspect
	for axis: Vector3 in axes:
		arch.orientation_axes.append(axis)
	arch.scatter_density = density
	arch.tint = tint
	arch.weight = weight
	arch.center_bias = bias
	return arch


func _chromophore(id: StringName, display_name: String, note: String,
		curve: PackedFloat32Array, eray: PackedFloat32Array, ui: Color,
		fluor_strength_override := -1.0, fluor_nm_override := 0.0,
		concentration := 1.0) -> Resource:
	var chromo: Resource = ChromophoreScript.new()
	chromo.chromophore_id = id
	chromo.display_name = display_name
	chromo.source_note = note
	chromo.absorption_mm = curve
	chromo.absorption_eray_mm = eray
	chromo.concentration = concentration
	chromo.ui_color = ui
	chromo.fluorescence_strength_override = fluor_strength_override
	chromo.fluorescence_emission_nm_override = fluor_nm_override
	_save(chromo, DIR_CHROMO + String(id) + ".tres")
	return chromo


## Sum of Gaussian bands [amplitude_per_mm, center_nm, sigma_nm] + flat base,
## sampled 380..780 nm at 5 nm (81 values), snapped for clean .tres diffs.
func _curve(base: float, bands: Array) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(81)
	for i in 81:
		var wl := 380.0 + 5.0 * float(i)
		var a := base
		for band: Array in bands:
			var t := (wl - float(band[1])) / float(band[2])
			a += float(band[0]) * exp(-0.5 * t * t)
		samples[i] = snappedf(maxf(a, 0.0), 0.00001)
	return samples


## 2-term Sellmeier fit: one UV pole at c1_um2 plus a constant term (C = 0).
## Solves B1 by bisection so n(430.8) - n(686.7) hits the published gemological
## (B-G) dispersion exactly, then B2 from n_D. Both B stay positive, which the
## GemSpecies.ior_at() term guards require.
func _fit_two_term(n_d: float, disp_bg: float, c1_um2: float) -> Dictionary:
	var f_d := _pole(WL_D * 1e-3, c1_um2)
	var f_g := _pole(WL_G * 1e-3, c1_um2)
	var f_b := _pole(WL_B * 1e-3, c1_um2)
	var nd2 := n_d * n_d
	var lo := 0.0
	var hi := 8.0
	for i in 100:
		var mid := (lo + hi) * 0.5
		var n_g := sqrt(nd2 + mid * (f_g - f_d))
		var n_b := sqrt(nd2 - mid * (f_d - f_b))
		if n_g - n_b < disp_bg:
			lo = mid
		else:
			hi = mid
	var b1 := (lo + hi) * 0.5
	var b2 := nd2 - 1.0 - b1 * f_d
	assert(b2 > 0.0, "fit produced non-positive constant term; raise c1_um2")
	return {
		"b": Vector3(snappedf(b1, 0.0000001), snappedf(b2, 0.0000001), 0.0),
		"c": Vector3(c1_um2, 0.0, 0.0),
	}


func _pole(l_um: float, c_um2: float) -> float:
	var l2 := l_um * l_um
	return l2 / (l2 - c_um2)


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	assert(err == OK, "failed to save %s (err %d)" % [path, err])
	# Register the saved path on the instance so resources saved later reference
	# it as an ext_resource instead of embedding a duplicated sub-resource.
	res.take_over_path(path)
	print("  wrote %s" % path)


# ------------------------------------------------------------------ reporting

func _print_species_table(species: Dictionary) -> void:
	print("\nspecies      n_D      n(F)     n(C)     F-C      B-G (gemological)")
	for id: StringName in species:
		var sp: Resource = species[id]
		var n_d: float = sp.ior_at(WL_D)
		var n_f: float = sp.ior_at(WL_F)
		var n_c: float = sp.ior_at(WL_C)
		var n_g: float = sp.ior_at(WL_G)
		var n_b: float = sp.ior_at(WL_B)
		print("%-12s %.4f   %.4f   %.4f   %.4f   %.4f" % [id, n_d, n_f, n_c, n_f - n_c, n_g - n_b])


## Beer-Lambert audit at key wavelengths: T = exp(-alpha * 2 * size_mm).
const BL_KEYS := {
	&"ruby_cr": [480.0, 556.0, 620.0, 650.0],
	&"sapphire_fe_ti": [460.0, 580.0, 700.0],
	&"emerald_cr": [430.0, 510.0, 615.0, 700.0],
	&"amethyst_fe_quartz": [420.0, 545.0, 660.0],
	&"peridot_fe2": [460.0, 550.0, 650.0],
	&"topaz_imperial": [450.0, 530.0, 620.0],
	&"fluorite_green": [420.0, 530.0, 640.0],
	&"smoky_al_hole": [430.0, 530.0, 650.0],
	&"verdelite_fe": [430.0, 530.0, 660.0, 720.0],
	&"rhodolite_fe2": [460.0, 520.0, 573.0, 650.0],
	&"aquamarine_fe": [427.0, 480.0, 620.0, 700.0],
	&"alexandrite_cr": [415.0, 520.0, 580.0, 660.0],
	&"painite_v_cr": [440.0, 560.0, 650.0],
	&"bluegarnet_v": [420.0, 480.0, 573.0, 660.0],
}


func _print_beer_lambert(chromophores: Dictionary, stones: Array) -> void:
	print("\nBeer-Lambert check, T2 = exp(-alpha * 2 * size_mm), T4 = 4×size TIR path:")
	for stone: Resource in stones:
		if stone.material.chromophore == null:
			continue
		var chromo: Resource = stone.material.chromophore
		var keys: Array = BL_KEYS.get(chromo.chromophore_id, [])
		var parts := PackedStringArray()
		for wl: float in keys:
			var idx := clampi(int(round((wl - 380.0) / 5.0)), 0, 80)
			var alpha: float = chromo.absorption_mm[idx] * chromo.concentration
			var t := exp(-alpha * 2.0 * stone.size_mm)
			var t4 := exp(-alpha * 4.0 * stone.size_mm)
			parts.append("%dnm a=%.3f T2=%.3f T4=%.3f" % [int(wl), alpha, t, t4])
		print("  %-10s (%.2f mm): %s" % [stone.stone_id, stone.size_mm, "; ".join(parts)])
