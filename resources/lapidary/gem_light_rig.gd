class_name GemLightRig
extends Resource
## A designed lighting language: named roles, not environment clones.
## Rig rotation and per-role power envelopes are RENDER PARAMETERS
## (clip tracks), never file forks.

@export var rig_id: StringName
@export var display_name := ""
@export var lights: Array[GemRigLight] = []

@export_group("Background")
## Flat-spectrum gradient intensities (chromatic backgrounds via kelvin below).
@export var bg_zenith := 0.30
@export var bg_horizon := 0.16
@export var bg_below := 0.05
## 0 = neutral flat spectrum; otherwise Planckian tint of the background.
@export var bg_kelvin := 0.0

@export_group("Evaluation")
## Secondary illuminant kelvin for color-change A/B views (0 = disabled).
## This is an evaluation/phenomenon view, not a baked rig property.
@export var dual_illuminant_kelvin := 0.0
