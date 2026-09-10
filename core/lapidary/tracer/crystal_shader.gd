class_name GemCrystalShader
extends RefCounted
## One Maxwell implementation, compiled at the selected precision. Float64 is
## required by crystal transport until a mixed-precision alternative passes
## the critical-angle/optic-axis tests. It is not a silent device fallback.
static func module(fp64 := true) -> String:
	return at_precision(FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_crystal.glsl"), fp64)

static func at_precision(source: String, fp64 := true) -> String:
	if not fp64:
		return source
	var pattern := RegEx.new()
	for pair in [["float", "double"], ["vec2", "dvec2"], ["vec3", "dvec3"], ["vec4", "dvec4"]]:
		pattern.compile("\\b" + pair[0] + "\\b")
		source = pattern.sub(source, pair[1], true)
	return source.replace("<1e-12", "<1e-22")

## Reuse the geometry algorithms and float32 wire structs, but retain ray
## positions/intersections in float64. Small facets must not disappear behind
## the much larger offset used by the fast float32 renderer.
static func geometry() -> String:
	var source := FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_mesh.glsl")
	source = source.substr(source.find("bool mesh_box("))
	source = source.substr(0, source.find("bool body_entry("))
	var pattern := RegEx.new()
	pattern.compile("layout\\(set = 0, binding = 13[^\\n]*\\n")
	source = pattern.sub(source, "", true)
	for name in ["mesh_box", "mesh_triangle", "mesh_hit", "mesh_normal", "quadric_roots", "cabochon_hit", "boundary_hit", "boundary_normal", "boundary_surface_slot", "region_medium", "cross_region", "physical_boundary", "physical_hit"]:
		pattern.compile("\\b" + name + "\\b")
		source = pattern.sub(source, "crystal_geo_" + name, true)
	for pair in [["float", "double"], ["vec2", "dvec2"], ["vec3", "dvec3"], ["vec4", "dvec4"]]:
		pattern.compile("\\b" + pair[0] + "\\b")
		source = pattern.sub(source, pair[1], true)
	source = source.replace("T_EPS", "CRYSTAL_GEO_EPS")
	source = source.replace("cross(triangle.b.xyz - triangle.a.xyz, triangle.c.xyz - triangle.a.xyz)", "cross(dvec3(triangle.b.xyz) - dvec3(triangle.a.xyz), dvec3(triangle.c.xyz) - dvec3(triangle.a.xyz))")
	return "const double CRYSTAL_GEO_EPS=1e-10;\n" + source
