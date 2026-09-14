extends "res://tests/game/game_test.gd"

func _initialize() -> void:
	test_catalog()
	test_rng()
	test_codec()
	test_snapshot()
	finish("test_game_state")

func test_catalog() -> void:
	var admitted := GameBootstrap.catalog()
	check(admitted.ok, "starter catalog admits")
	var catalog: GameCatalog = admitted.catalog
	var data := catalog.to_dict()
	data.weights[0] = -1
	check(not GameCatalog.admit(data).ok, "negative supply rejects")
	check(catalog.to_dict().weights[0] == 4, "catalog detached from exported copy")
	data = catalog.to_dict()
	data.definitions.quartz.tier = 2
	check(not GameCatalog.admit(data).ok, "tier mismatch rejects")
	data = catalog.to_dict()
	data.weights = [2147483647, 1, 1, 1]
	check(not GameCatalog.admit(data).ok, "weight sum overflow rejects")
	data = catalog.to_dict()
	data.roster[4] = "aquamarine"
	data.definitions.erase("sapphire")
	data.definitions.aquamarine = {"id": "aquamarine", "tier": 5, "match_group": "tier_5", "family_tags": ["beryl"]}
	var alternative: GameCatalog = GameCatalog.admit(data).catalog
	var tile := alternative.create_tile(5)
	tile.instance_id = "test/1"
	check(alternative.promote(tile) and tile.tile_id == &"emerald" and tile.instance_id == "test/1", "active roster promotes Aquamarine to Emerald preserving instance")
	check(catalog.definition(1).is_read_only() and catalog.definition(1).family_tags.is_read_only(), "nested catalog records immutable")
	var rng := SeededRng.new()
	rng.reseed(5)
	var before := rng.capture()
	var invalid_supply := SpawnTableResource.new()
	invalid_supply.allowed_tiers = [1, 2, 3]
	invalid_supply.weights = [-1, 2, 3]
	check(SpawnResolver.new(catalog)._spawn_tile(rng, invalid_supply) == null and rng.capture() == before, "bad supply cannot draw or fall back")
	check(SpawnResolver.new()._spawn_tile(rng, catalog.supply()) == null, "missing catalog cannot produce debug tile")

func test_rng() -> void:
	var vectors := [
		[0, 671865582784734479, 925954744150238037, 179648950383801398, 210157295527772394],
		[-1, 428633132656618941, 909297538988474945, 122354975701732150, 415566801207083906],
		[9007199254740993, 685390487296650209, 845880540848656724, 28596188333169921, 155293766637300714],
	]
	for row in vectors:
		for i in 4: check(RngStreamBank.derive(row[0], RngStreamBank.IDS[i]) == row[i + 1], "independent SHA256 derivation vector")
	var bank := RngStreamBank.new(-1)
	for i in 13: bank.stream("board").randi_range(0, 100)
	var snapshot := bank.capture()
	var restored: RngStreamBank = RngStreamBank.restored(snapshot).bank
	bank.stream("rewards").randi_range(0, 100)
	for i in 30: check(bank.stream("board").randi_range(0, 100) == restored.stream("board").randi_range(0, 100), "full RNG position restores; streams independent")

func test_codec() -> void:
	var goldens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/goldens/codec-v1.json"))
	var cases := {"integers": [null,false,true,0,-1,-9223372036854775807 - 1,9223372036854775807,9007199254740993], "ordered_map": {"z": Vector2i(2,-1),"a": ["ø",17]}}
	for id in cases:
		var bytes := CanonicalCodec.encode(cases[id])
		check(bytes.hex_encode() == goldens[id], "independent byte golden " + id)
		var decoded := CanonicalCodec.decode(bytes)
		check(decoded.ok and CanonicalCodec.encode(decoded.value) == bytes, "exact round trip " + id)
		for cut in [0,1,3,4,bytes.size()-1]: check(not CanonicalCodec.decode(bytes.slice(0,cut)).ok, "truncated codec rejects")
		bytes.append(0)
		check(not CanonicalCodec.decode(bytes).ok, "trailing byte rejects")
	check(CanonicalCodec.encode({"a":1,"b":2}) == CanonicalCodec.encode({"b":2,"a":1}), "map insertion order invariant")
	check(CanonicalCodec.digest([1,2]) != CanonicalCodec.digest([2,1]), "ordered sequence changes digest")
	check(CanonicalCodec.encode(1.5).is_empty() and CanonicalCodec.encode(Resource.new()).is_empty(), "floats/objects unsupported")
	check(not CanonicalCodec.decode("46414331050500000000000000".hex_decode()).ok, "impossible array count rejects")
	check(not CanonicalCodec.decode("464143310102".hex_decode()).ok, "invalid boolean rejects")
	for invalid in ["c0af","eda080","f4908080","80","e282"]:
		var bytes := CanonicalCodec.encode("x")
		bytes.resize(13); bytes.encode_s64(5,invalid.length()/2); bytes.append_array(invalid.hex_decode())
		check(not CanonicalCodec.decode(bytes).ok,"invalid UTF8 rejects without engine errors")

func test_snapshot() -> void:
	var state := RunState.new()
	state.catalog = GameTestCatalog.create()
	var opening := OpeningGenerator.generate(BoardLayoutResource.new(),state.catalog,RngStreamBank.new(4))
	state.board = opening.board; state.streams = opening.streams; state.moves_remaining = 20; state.opening_attempts = opening.attempts
	state.sync_adapters()
	var snapshot := state.to_dict()
	var result := RunState.restored(CanonicalCodec.decode(CanonicalCodec.encode(snapshot)).value)
	check(result.ok, "complete snapshot restores")
	if result.ok:
		check(result.state.digest() == state.digest(), "restored whole-state SHA256")
		result.state.board.get_tile(Vector2i.ZERO).status_flags["counter"] = 7
		check(not state.board.get_tile(Vector2i.ZERO).status_flags.has("counter"), "restored state detached")
	var changed := snapshot.duplicate(true); changed.next_event = 0
	check(not RunState.restored(changed).ok, "invalid allocator rejects")
	changed = snapshot.duplicate(true); changed.schema = 99
	check(not RunState.restored(changed).ok, "unsupported schema rejects")
	changed = snapshot.duplicate(true); changed.board.cells[1].tile.instance_id = changed.board.cells[0].tile.instance_id
	check(not RunState.restored(changed).ok, "duplicate piece IDs reject")
	changed = snapshot.duplicate(true); changed.board.cells[0].tile.tier = 8
	check(not RunState.restored(changed).ok, "definition mismatch rejects")
	changed = snapshot.duplicate(true); changed.board.portals["-1,0,0,1"] = Vector2i.ZERO
	check(not RunState.restored(changed).ok, "malformed snapshot topology rejects")
	changed = snapshot.duplicate(true); changed.rules.matching = "unknown"
	check(not RunState.restored(changed).ok, "unknown policy rejects")
	var before := state.board.digest()
	state.board.get_tile(Vector2i.ZERO).status_flags["counter"] = 1
	var one := state.board.digest()
	state.board.get_tile(Vector2i.ZERO).status_flags["counter"] = 99
	check(one != state.board.digest() and one != before, "status_value_hash frozen fixture")
	state.board.get_tile(Vector2i.ZERO).status_flags.clear()
	state.board.add_portal(Vector2i.ZERO,Vector2i.DOWN,Vector2i(1,1))
	check(before != state.board.digest(), "portal_hash frozen fixture")
	# Every serialized leaf participates, including counters, tags and topology.
	var mutations: Array = []
	collect_leaf_mutations(snapshot, [], mutations)
	var initial := CanonicalCodec.digest(snapshot)
	for path in mutations:
		changed = snapshot.duplicate(true)
		var container: Variant = changed
		for i in path.size()-1: container = container[path[i]]
		var key: Variant = path[-1]
		var value: Variant = container[key]
		if value is int: container[key] = value + 1 if value < 9223372036854775807 else value - 1
		elif value is bool: container[key] = not value
		elif value is Vector2i: container[key] = value + Vector2i.RIGHT
		elif value is String or value is StringName: container[key] = str(value) + "x"
		elif value == null: container[key] = "changed"
		elif value is Dictionary: container[key] = {"probe": 1}
		elif value is Array: container[key] = ["probe"]
		check(CanonicalCodec.digest(changed) != initial, "state leaf affects identity: " + str(path))

func collect_leaf_mutations(value: Variant, path: Array, output: Array) -> void:
	if value is Dictionary and not value.is_empty():
		for key in value: collect_leaf_mutations(value[key],path + [key],output)
	elif value is Array and not value.is_empty():
		for i in value.size(): collect_leaf_mutations(value[i],path + [i],output)
	else: output.append(path)
