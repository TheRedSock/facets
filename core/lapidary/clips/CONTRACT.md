# Authored optical motion

`GemClip` has one orientation grammar: an ordered array of `GemOrientationKey`
resources. Keys contain normalized time and an absolute unit quaternion. One key
at time zero is a still; moving tracks explicitly span zero to one. Empty tracks,
duplicate/reversed times and nonunit quaternions fail admission. Old motion-mode
resources lack the required keys and are not admitted. There is no compatibility
loader or alternate turntable sampler.

`GemClipSampler` interpolates each interval by shortest-arc SLERP. A half-turn
interval is ambiguous and must be subdivided. Full turns therefore use explicit
quarter-turn keys; the catalog `turn` demonstrates this. Repeated orientations
at different times create holds. `tilt_return` demonstrates an eased small tilt
and return using the same grammar. A key's quaternion sign does not select a
long arc.

An optional `time_curve` remaps orientation time only. It preserves zero/one
endpoints and uses monotone cubic Bezier controls. Admission checks continuous
control bounds, rather than checking only the baked frame times. This is a
deliberately sufficient bounded subset of Godot's Curve language. Rig yaw remains
linear in normalized clip time; exposure/key/rim curves independently sample that
same unremapped time. All envelope controls stay finite and nonnegative.
The curve-to-control conversion follows
[Godot 4.6 Curve sampling](https://github.com/godotengine/godot/blob/4.6-stable/scene/resources/curve.cpp#L374).

Loops require matching orientation and envelope endpoints and a closed rig orbit.
They sample `frame / frame_count`, excluding the duplicated endpoint. Oneshots
sample `frame / (frame_count-1)` and hold the last image for its final `1/fps`
interval. Frame count is `max(1, round(duration_s * fps))`; the delivered duration
is therefore `frame_count / fps`. A still samples zero. Delivery's semantic
oneshot completion/restart/interruption and return-to-rest rules are defined in
`core/delivery/CONTRACT.md`; no simulation logic reads clip time.

Atelier edits quaternions as absolute Euler degrees (Godot YXZ order) and stores
normalized quaternions. Its curve editor uses `Vector4(time, value, incoming
slope, outgoing slope)` entries. Zero slopes ease at a point; equal secant slopes
produce linear intervals. Clip and Curve resources save/reopen through shared
authoring admission. Invalid drafts remain editable but cannot be published.

Presentation prepares framing and pivot once from the initial pose. Sampling
does not recenter the gem independently per frame. Board translations, swaps,
convergence, squash and removal remain ordinary scene animation.

The sampler and clip/key schemas affect full worker provenance; optical result
keys use the concrete sampled pose/lighting/exposure values. Dependency tests
cover that distinction. `test_clips` checks arbitrary axes, holds, timing, curve
bounds and loop failures; `test_atelier_document_ui` authors and saves real tracks
through the controls. The migration audit captured 304 existing catalog jobs:
all remain exactly identical, including camera offsets, with matching playback
timing. That preservation does not replace the final appearance/performance gates.
