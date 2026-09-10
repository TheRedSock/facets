class_name GemDefect
extends Resource
## A real closed boundary in physical millimeters, clipped to the host.
## Null filling = air/void. Overlap priority follows the authored array order.
@export_enum("fracture", "chip", "crystal") var kind := "fracture"
@export var center_mm := Vector3.ZERO
@export var orientation := Quaternion.IDENTITY
## Half-widths. For fractures, z is half the maximum physical aperture.
@export var half_extent_mm := Vector3(0.8, 0.5, 0.003)
@export var filling: GemMaterial
@export var finish: GemSurface = GemSurface.new()
@export var seed := 1
## Correlated front and surface variation, not independent primitive placement.
@export_range(0.0, 1.0) var irregularity := 0.4
@export_range(8, 128) var radial_segments := 32
@export_range(2, 32) var radial_rings := 8
@export var enabled := true
@export_multiline var source_note := "Authored procedural defect; not a fracture-mechanics prediction."
