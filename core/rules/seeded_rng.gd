class_name SeededRng
extends RefCounted

## Deterministic RNG wrapper for reproducible gameplay.
## All randomness in the game must flow through this.

var _rng := RandomNumberGenerator.new()
var current_seed: int = 0

func capture() -> Dictionary:
	return {"seed": current_seed, "state": _rng.state}

func restore(snapshot: Dictionary) -> bool:
	if snapshot.size() != 2 or not snapshot.get("seed") is int or not snapshot.get("state") is int: return false
	reseed(snapshot.seed)
	_rng.state = snapshot.state
	return true


func reseed(new_seed: int) -> void:
	current_seed = new_seed
	_rng.seed = new_seed


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## Returns a shuffled copy of the input array (does not modify original).
func shuffle(array: Array) -> Array:
	var copy := array.duplicate()
	for i in range(copy.size() - 1, 0, -1):
		var j := self.randi_range(0, i)
		var tmp = copy[i]
		copy[i] = copy[j]
		copy[j] = tmp
	return copy
