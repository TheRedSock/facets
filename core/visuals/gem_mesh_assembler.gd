class_name GemMeshAssembler
extends RefCounted

## Converts canonical 3D cut models directly into tracer mesh resources.

const GemMeshResourceScript = preload("res://resources/visuals/gem_mesh_resource.gd")


static func assemble(model):
	var mesh = GemMeshResourceScript.new()
	if model == null:
		return mesh
	mesh.spec_id = model.spec_id
	mesh.cut_id = model.cut_id
	mesh.display_name = model.display_name
	mesh.geometry_signature = model.geometry_signature
	for facet_index in model.facet_count():
		var zone = model.facet_zones[facet_index] if facet_index < model.facet_zones.size() else ""
		mesh.add_facet(model.facet_vertices[facet_index], zone)
	return mesh
