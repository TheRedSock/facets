class_name GemRigLight
extends Resource
## One role in a lighting rig. Angular sizes and temperatures are chosen for
## gem photography; a BLOCKER darkens a solid-angle region (dark-field
## contrast for step cuts).

enum Role { KEY, FILL, RIM, BOUNCE, BLOCKER }

@export var role := Role.KEY
## Direction TOWARD the light, world space, degrees.
@export var azimuth_deg := 0.0
@export var elevation_deg := 45.0
## Cone half-angles: soft edge between inner (full) and outer (zero).
@export var angular_radius_deg := 12.0
@export var inner_fraction := 0.6
@export var spectrum: GemSpectrum = GemSpectrum.new()
## Radiance multiplier. BLOCKER uses power as darkening strength (0..1).
@export var power := 1.0
@export var enabled := true


func direction() -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()
