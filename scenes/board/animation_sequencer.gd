class_name AnimationSequencer
extends RefCounted

## Timing variables for animation phases.
## These control the visual feel of the game — tunable at runtime via debug panel.

## Brief flash on matched tiles before removal.
static var match_highlight_duration := 0.12

## Fade-out / shrink duration for removed tiles.
static var removal_duration := 0.18

## Scale pulse duration for upgraded tiles (each direction: up then down).
static var upgrade_scale_duration := 0.15

## Scale factor for the upgrade pulse peak.
static var upgrade_scale_factor := 1.3

## Minimum fall duration (even for 1-cell falls).
static var min_fall_duration := 0.10

## Gravity acceleration constant for fall duration calculation.
## Higher = faster falls. Tune for feel.
static var gravity_accel := 50.0

## Brief pause between cascade steps for readability.
static var cascade_pause := 0.05

## How many seconds before the removal fadeout finishes to start gravity.
## Gravity begins at (removal_duration - removal_gravity_overlap) into phase 2,
## so tiles start falling while the removed gems are still fading out.
static var removal_gravity_overlap := 0.10

## Brief pause between upgrade chain rounds within a single cascade step.
static var chain_pause := 0.02

## Duration of the swap slide animation between two tiles.
static var swap_duration := 0.15

## Duration of the invalid swap bounce animation (each direction).
static var invalid_swap_duration := 0.12


## Computes fall duration from distance using physics-based formula.
## t = sqrt(2 * distance / gravity_accel)
static func fall_duration(distance: int) -> float:
	if distance <= 0:
		return min_fall_duration
	return maxf(min_fall_duration, sqrt(2.0 * float(distance) / gravity_accel))


## Computes the distance between two cells in grid units.
## Uses Chebyshev distance (max of dx, dy) for diagonal moves.
static func cell_distance(from: Vector2i, to: Vector2i) -> int:
	var diff := (to - from).abs()
	return maxi(diff.x, diff.y)
