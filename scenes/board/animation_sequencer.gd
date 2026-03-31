class_name AnimationSequencer
extends RefCounted

## Timing variables for animation phases.
## These control the visual feel of the game — tunable at runtime via debug panel.

## Brief flash on matched tiles before removal.
static var match_highlight_duration := 0.12

## Fade-out / shrink duration for removed tiles.
static var removal_duration := 0.18

## Total scale-pulse duration for upgraded tiles.
static var upgrade_scale_duration := 0.15

## Peak scale factor reached midway through the upgrade pulse.
static var upgrade_scale_factor := 1.3

## Minimum fall duration (even for 1-cell falls).
static var min_fall_duration := 0.10

## Gravity strength constant for fall duration calculation.
## Higher = faster falls. Tune for feel.
##
## With TRANS_CUBIC, this is the "jerk" (rate of acceleration increase).
## The derived acceleration at absolute time t is:  a(t) = gravity_accel * t
## This means gravity starts at zero and ramps up linearly — slow start,
## fast finish — while remaining identical for all tiles at any given instant
## regardless of their fall distance.
static var gravity_accel := 750.0

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

## Transition curve for gravity falls.
## TRANS_CUBIC produces p(t) = t³ which gives a dramatic slow-start / fast-finish
## feel while maintaining consistent perceived acceleration across all fall distances.
##
## The duration formula in fall_duration() is derived specifically for TRANS_CUBIC:
##   x(t) = D * (t/T)³  →  a(t) = 6D·t/T³
##   Setting T³ = 6D/g  →  a(t) = g·t  (independent of D)
##
## This means at any absolute time t, ALL tiles have the same instantaneous
## acceleration (g·t) regardless of how far they're falling.  Tiles viewed side
## by side during a cascade accelerate identically — no more visual inconsistency
## between short and long falls.
##
## If gravity_trans is changed to a different curve, the formula in fall_duration()
## must also be updated to match.  For TRANS_QUAD (constant acceleration):
##   T = sqrt(2D/g), gravity_accel ≈ 50.
static var gravity_trans := Tween.TRANS_CUBIC

## Per-position stagger delay for column falls (seconds).
## Tiles closer to the destination start falling first; each subsequent tile
## in the same column starts this much later, creating a cascading ripple.
static var gravity_stagger_delay := 0.012

## Maximum total stagger delay per column (seconds).
static var gravity_stagger_max := 0.06

## Duration of the async landing bounce (seconds). Fire-and-forget.
static var landing_bounce_duration := 0.12


## Computes fall duration from distance using the physics formula matched to
## the gravity easing curve (TRANS_CUBIC).
##
## Formula: T = cbrt(6 * distance / gravity_accel)
##
## Derivation for TRANS_CUBIC (p = t³):
##   Position:      x(t) = D * (t/T)³
##   Acceleration:  a(t) = 6D * t / T³
##   Set T³ = 6D/g: a(t) = g * t    ← same for all D at any absolute time t
##
## This ensures tiles falling different distances accelerate identically when
## viewed simultaneously.  The acceleration ramps from 0 (at rest) to g*T
## (at landing), giving the dramatic slow-start / fast-finish feel of cubic
## easing without the visual inconsistency of mismatched curve/formula pairing.
static func fall_duration(distance: int) -> float:
	if distance <= 0:
		return min_fall_duration
	return maxf(min_fall_duration, pow(6.0 * float(distance) / gravity_accel, 1.0 / 3.0))


## Computes the distance between two cells in grid units.
## Uses Chebyshev distance (max of dx, dy) for diagonal moves.
static func cell_distance(from: Vector2i, to: Vector2i) -> int:
	var diff := (to - from).abs()
	return maxi(diff.x, diff.y)
