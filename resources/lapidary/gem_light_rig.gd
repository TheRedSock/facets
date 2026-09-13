class_name GemLightRig
extends Resource
## A designed lighting language: named roles, not environment clones.
## Rig rotation and per-role power envelopes are RENDER PARAMETERS
## (clip tracks), never file forks.

@export var rig_id: StringName
@export var display_name := ""
@export var lights: Array[GemRigLight] = []

@export_group("Background")
@export var bg_zenith := 0.30
@export var bg_horizon := 0.16
@export var bg_below := 0.05
@export var background_spectrum: GemSpectrum = GemSpectrum.new()

@export_group("White balance")
## As-shot neutral spectrum. Null leaves scene XYZ unadapted; otherwise its
## integrated XYZ is adapted to D65 by the print, independently of transport.
@export var white_spectrum: GemSpectrum
