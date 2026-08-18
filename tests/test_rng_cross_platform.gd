extends SceneTree

## Cross-platform RNG reference value test.
## Run on each target platform and compare outputs.
## If outputs match across platforms, integer RNG is cross-platform safe.
##
## Run: godot --headless --script tests/test_rng_cross_platform.gd

func _init() -> void:
	print("\n=== RNG Cross-Platform Reference Values ===\n")

	var rng := SeededRng.new()

	# Test 1: Integer range values
	rng.reseed(42)
	var int_values: Array[int] = []
	for i in 100:
		int_values.append(rng.randi_range(0, 999999))
	print("INT_REFERENCE_SEED_42: %s" % str(int_values))

	# Test 2: Integer weighted pick simulation (what SpawnResolver does)
	rng.reseed(42)
	var pick_values: Array[int] = []
	# Simulate weighted pick with weights [4, 3, 2, 1] (total=10)
	for i in 100:
		var roll := rng.randi_range(0, 9)
		var result: int
		if roll < 4:
			result = 1
		elif roll < 7:
			result = 2
		elif roll < 9:
			result = 3
		else:
			result = 4
		pick_values.append(result)
	print("PICK_REFERENCE_SEED_42: %s" % str(pick_values))

	# Test 3: Verify determinism within this run
	rng.reseed(42)
	var verify_values: Array[int] = []
	for i in 100:
		verify_values.append(rng.randi_range(0, 999999))

	var values_match := true
	for i in 100:
		if int_values[i] != verify_values[i]:
			values_match = false
			break

	if values_match:
		print("\nSame-run determinism: PASS")
	else:
		print("\nSame-run determinism: FAIL")

	print("\n=== Compare these values across platforms ===")
	print("If INT_REFERENCE and PICK_REFERENCE match on all platforms,")
	print("integer RNG is cross-platform deterministic.\n")

	quit(0)
