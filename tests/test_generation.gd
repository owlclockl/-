## Headless self-check of the map generation pipeline.
##
## Run it with:  godot --headless --path . --script res://tests/test_generation.gd
## It generates a few small maps and checks the invariants the rest of the game relies on.
extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	print("Fantasy Map Generator port — self check")
	var start := Time.get_ticks_msec()

	var map := generate_map("123456", 3000)
	check(map.pack["cells"]["p"].size() > 0, "the packed graph has cells")
	check(map.grid["points"].size() > 0, "the grid has points")

	# heights
	var grid_heights: PackedInt32Array = map.grid["cells"]["h"]
	var land := 0
	var water := 0
	for height in grid_heights:
		if height >= MapData.SEA_LEVEL:
			land += 1
		else:
			water += 1
	check(land > 0, "the map has land (%d cells)" % land)
	check(water > 0, "the map has water (%d cells)" % water)

	# neighbours are symmetric
	var neighbours: Array = map.grid["cells"]["c"]
	var asymmetric := 0
	for cell_id in mini(neighbours.size(), 2000):
		for neighbour in neighbours[cell_id]:
			if not (neighbours[neighbour] as PackedInt32Array).has(cell_id):
				asymmetric += 1
	check(asymmetric == 0, "grid neighbours are symmetric (%d violations)" % asymmetric)

	# climate
	var temperatures: PackedInt32Array = map.grid["cells"]["temp"]
	var precipitation: PackedInt32Array = map.grid["cells"]["prec"]
	var cold := 0
	var warm := 0
	for temperature in temperatures:
		if temperature < 0:
			cold += 1
		else:
			warm += 1
	check(cold > 0 and warm > 0, "both cold (%d) and warm (%d) cells exist" % [cold, warm])
	var dry := 0
	for value in precipitation:
		if value == 0:
			dry += 1
	check(dry < precipitation.size(), "precipitation covers the map")

	# biomes: every land packed cell gets a biome
	var biomes: PackedInt32Array = map.pack["cells"]["biome"]
	var heights: PackedInt32Array = map.pack["cells"]["h"]
	var missing_biomes := 0
	for cell_id in heights.size():
		if heights[cell_id] >= MapData.SEA_LEVEL and (biomes[cell_id] <= 0 or biomes[cell_id] >= map.biomes.size()):
			missing_biomes += 1
	check(missing_biomes == 0, "every land cell has a biome (%d missing)" % missing_biomes)

	# rivers, cultures, burgs and states
	check(map.pack["rivers"].size() > 0, "rivers were generated (%d)" % map.pack["rivers"].size())
	check(map.pack["cultures"].size() > 1, "cultures were generated (%d)" % (map.pack["cultures"].size() - 1))
	check(map.pack["burgs"].size() > 1, "burgs were generated (%d)" % (map.pack["burgs"].size() - 1))
	check(map.pack["states"].size() > 1, "states were generated (%d)" % (map.pack["states"].size() - 1))
	check(map.pack["religions"].size() > 1, "religions were generated (%d)" % (map.pack["religions"].size() - 1))
	check(map.pack["provinces"].size() > 1, "provinces were generated (%d)" % (map.pack["provinces"].size() - 1))
	check(map.pack["routes"].size() > 0, "routes were generated (%d)" % map.pack["routes"].size())

	# every state has a capital with a name
	var nameless := 0
	for state in map.pack["states"]:
		if int(state.get("i", 0)) != 0 and str(state.get("name", "")) == "":
			nameless += 1
	check(nameless == 0, "every state has a name (%d nameless)" % nameless)

	# determinism: the same seed has to give the same map
	var first := generate_map("determinism", 2000)
	var second := generate_map("determinism", 2000)
	check(_same_ints(first.grid["cells"]["h"], second.grid["cells"]["h"]), "heightmaps are deterministic")
	check(_same_points(first.pack["points"], second.pack["points"]), "packed graphs are deterministic")
	check(_same_ints(first.pack["cells"]["biome"], second.pack["cells"]["biome"]), "biomes are deterministic")
	check(first.pack["states"].size() == second.pack["states"].size(), "state counts are deterministic")

	var names_a: Array = []
	for burg in first.pack["burgs"]:
		names_a.append(str(burg.get("name", "")))
	var names_b: Array = []
	for burg in second.pack["burgs"]:
		names_b.append(str(burg.get("name", "")))
	check(names_a == names_b, "names are deterministic")

	var elapsed := Time.get_ticks_msec() - start
	print("checked %d invariants in %d ms" % [checks, elapsed])
	if failures == 0:
		print("ALL CHECKS PASSED")
		quit(0)
	else:
		print("%d CHECKS FAILED" % failures)
		quit(1)


func generate_map(seed_text: String, points: int) -> MapData:
	var map := MapData.new()
	map.seed_text = seed_text
	map.options = GenOptions.defaults()
	map.options["seed"] = seed_text
	map.options["graph"]["width"] = 1000.0
	map.options["graph"]["height"] = 600.0
	map.options["graph"]["points"] = points
	GenPipeline.generate_map(map)
	return map


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % description)
	else:
		failures += 1
		print("  FAIL %s" % description)


func _same_ints(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _same_points(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true
