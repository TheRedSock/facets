extends Node

## Deprecated legacy performance monitor.
## This file is intentionally kept for reference only and is no longer wired
## into `project.godot` or used by the active gameplay flow.

# ---- Public read-only state for HUD ----

## Pre-formatted FPS string updated every frame, ready for display.
var fps_text: String = ""

# ---- Configuration ----

## FPS below this for a single frame triggers a spike warning.
const SPIKE_FPS_THRESHOLD := 55.0
## Corresponding frame time in msec.
const SPIKE_FRAME_MS := 1000.0 / SPIKE_FPS_THRESHOLD

## FPS below this sustained over SUSTAINED_DROP_WINDOW frames triggers a warning.
const SUSTAINED_FPS_THRESHOLD := 57.0
const SUSTAINED_DROP_WINDOW := 5

## Span duration (msec) above this threshold triggers a console warning.
const SPAN_WARN_MS := 8.0

# ---- Internal state ----

var _frame_times: PackedFloat64Array = PackedFloat64Array()  # ring buffer
var _ring_index: int = 0
const RING_SIZE := 60

var _sustained_bad_count: int = 0
var _last_spike_logged_frame: int = -100

## Active timing spans: label -> start_usec
var _active_spans: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_frame_times.resize(RING_SIZE)
	_frame_times.fill(16.67)


func _process(_delta: float) -> void:
	var frame_ms := _delta * 1000.0
	_frame_times[_ring_index] = frame_ms
	_ring_index = (_ring_index + 1) % RING_SIZE

	# Current instantaneous FPS
	var fps := Engine.get_frames_per_second()
	fps_text = "%d FPS" % fps

	_check_spike(frame_ms)
	_check_sustained(fps)


# ---- Spike / sustained drop detection ----

func _check_spike(frame_ms: float) -> void:
	if frame_ms < SPIKE_FRAME_MS:
		return
	var current_frame := Engine.get_process_frames()
	# Skip early frames (scene loading / initial board resolution)
	if current_frame < 120:
		return
	# Throttle: don't spam more than once per 30 frames
	if current_frame - _last_spike_logged_frame < 30:
		return
	_last_spike_logged_frame = current_frame
	push_warning("[PerfMonitor] Frame spike: %.1f ms (%.0f FPS) at engine frame %d"
		% [frame_ms, 1000.0 / frame_ms, current_frame])


func _check_sustained(fps: float) -> void:
	# Skip early frames (scene loading)
	if Engine.get_process_frames() < 120:
		return
	if fps < SUSTAINED_FPS_THRESHOLD:
		_sustained_bad_count += 1
	else:
		_sustained_bad_count = 0

	if _sustained_bad_count == SUSTAINED_DROP_WINDOW:
		push_warning("[PerfMonitor] Sustained low FPS: %d frames below %.0f FPS"
			% [SUSTAINED_DROP_WINDOW, SUSTAINED_FPS_THRESHOLD])
		# Reset so we warn again if it persists another window
		_sustained_bad_count = 0


# ---- Labelled timing spans ----

## Call before a measured block.  Returns the start time (usec) for convenience.
func begin_span(label: String) -> int:
	var t := Time.get_ticks_usec()
	_active_spans[label] = t
	return t


## Call after a measured block.  Returns elapsed milliseconds.
## Prints a console warning if the span exceeded SPAN_WARN_MS.
func end_span(label: String) -> float:
	var end_usec := Time.get_ticks_usec()
	var start_usec: int = _active_spans.get(label, end_usec)
	_active_spans.erase(label)
	var elapsed_ms := (end_usec - start_usec) / 1000.0
	if elapsed_ms >= SPAN_WARN_MS:
		push_warning("[PerfMonitor] Slow span '%s': %.2f ms" % [label, elapsed_ms])
	return elapsed_ms


# ---- Utilities ----

## Returns the average frame time (ms) over the ring buffer.
func avg_frame_ms() -> float:
	var total := 0.0
	for t in _frame_times:
		total += t
	return total / float(RING_SIZE)
