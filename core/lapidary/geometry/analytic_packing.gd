class_name GemAnalyticPacking
extends RefCounted
## Candidate primitive representation for numerical admission experiments.
## 64B: center/radius, normal/spare, cylinder-end/spare, ivec4 metadata.
## Metadata = facet, kind(1..3)|(clip_count<<8), clip_offset, local region.
## Clip vec4s use coordinates relative to the primitive center to reduce loss.
const V := preload("res://core/lapidary/geometry/geometry64.gd")
static func pack(solid: GemRoundedSolid) -> Dictionary:
	if solid==null or not solid.error.is_empty(): return {}
	var primitives:=StreamPeerBuffer.new()
	var clips:=PackedFloat32Array()
	for patch in solid.patches:
		var groups:=[patch.center,patch.axis,patch.end]
		for i in groups.size():
			var group:PackedFloat64Array=groups[i]
			for component in group:primitives.put_float(component)
			primitives.put_float(patch.radius if i==0 else 0.0)
		primitives.put_32(patch.facet)
		primitives.put_32((patch.kind+1)|(patch.clips.size()<<8))
		primitives.put_32(clips.size()/4)
		primitives.put_32(0)
		for halfspace in patch.clips:
			clips.append_array(PackedFloat32Array([halfspace[0],halfspace[1],halfspace[2],halfspace[3]-V.dot(halfspace,patch.center)]))
	return {"primitives":primitives.data_array,"clips":clips.to_byte_array(),"count":solid.patches.size()}
