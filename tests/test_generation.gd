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

	# ---------------------------------------------------------------- the map atlas
	_check_atlas(map)
	_check_renderer(map)

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


## The atlas is pure CPU work, so it can be checked without a renderer: geometry, colors,
## picking, determinism and the PNG export.
func _check_atlas(map: MapData) -> void:
	print("atlas:")
	var atlas := MapAtlas.new()
	atlas.level = 1.0
	atlas.setup(map)
	check(atlas.width == int(map.width()) and atlas.band_height == int(map.height()),
		"the atlas covers the whole map (%d×%d per layer)" % [atlas.width, atlas.band_height])
	check(is_equal_approx(atlas.level, 1.0), "the requested level is kept (1×)")

	atlas.bake(MapAtlas.VIEW_BIOMES)
	check(atlas.texture != null, "the atlas builds a texture")
	check(atlas.is_baked(MapAtlas.VIEW_BIOMES), "the requested layer is baked")
	check(atlas.layer_count_baked() == 1, "only the requested layer is baked (%d)" % atlas.layer_count_baked())
	var zone_region := atlas.region_of(MapAtlas.VIEW_ZONES)
	check(zone_region == Rect2(0.0, float(3 * atlas.band_height), float(atlas.width), float(atlas.band_height)),
		"every layer takes one band of the atlas")

	var cells: Dictionary = map.pack["cells"]
	var points: PackedVector2Array = cells["p"]
	var heights: PackedInt32Array = cells["h"]
	var states: PackedInt32Array = cells["state"]

	# picking: the site of a cell lies inside the polygon that was rasterized for it
	var step := maxi(1, int(float(points.size()) / 400.0))
	var sampled := 0
	var matched := 0
	for index in range(0, points.size(), step):
		sampled += 1
		if atlas.cell_at(points[index]) == index:
			matched += 1
	check(sampled > 20 and float(matched) > float(sampled) * 0.97,
		"the mask picks the cell under a point (%d/%d)" % [matched, sampled])
	check(atlas.cell_at(Vector2(-64.0, -64.0)) == -1, "points outside the map pick nothing")

	var land_cell := -1
	var sea_cell := -1
	var state_cell := -1
	for index in heights.size():
		if heights[index] >= MapData.SEA_LEVEL and land_cell < 0:
			land_cell = index
		if heights[index] < 10 and sea_cell < 0:
			sea_cell = index
		if state_cell < 0 and index < states.size() and states[index] > 0 and heights[index] >= MapData.SEA_LEVEL:
			state_cell = index
	check(land_cell >= 0 and sea_cell >= 0, "the map has both land and deep water")
	var land_color := atlas.color_of(MapAtlas.VIEW_BIOMES, land_cell)
	var sea_color := atlas.color_of(MapAtlas.VIEW_BIOMES, sea_cell)
	check(land_color != sea_color, "the biome layer separates land and water")
	check(land_color.a > 0.9 and sea_color.a > 0.9, "the map pixels are opaque")

	atlas.bake_layer(MapAtlas.VIEW_STATES)
	var state_color := atlas.color_of(MapAtlas.VIEW_STATES, state_cell)
	var biome_color := atlas.color_of(MapAtlas.VIEW_BIOMES, state_cell)
	check(state_color != biome_color, "the political layer tints cells of a state")

	for layer in MapAtlas.LAYERS:
		atlas.bake_layer(layer)
	check(atlas.layer_count_baked() == MapAtlas.LAYERS, "all %d layers are baked" % MapAtlas.LAYERS)

	var again := MapAtlas.new()
	again.level = 1.0
	again.setup(map)
	again.bake(MapAtlas.VIEW_BIOMES)
	var first_image := atlas.layer_image(MapAtlas.VIEW_BIOMES)
	var second_image := again.layer_image(MapAtlas.VIEW_BIOMES)
	check(first_image != null and second_image != null, "a layer can be read back as an image")
	check(first_image.get_data() == second_image.get_data(), "the atlas is deterministic")

	var path := "user://atlas_check.png"
	check(atlas.save_png(MapAtlas.VIEW_BIOMES, path), "a layer is saved as a PNG")
	check(FileAccess.file_exists(path), "the PNG file is on disk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The renderer drives the atlas and keeps the sharp details as vectors.
func _check_renderer(map: MapData) -> void:
	print("renderer:")
	var renderer := MapRenderer.new()
	renderer.set_level(1.0)
	renderer.setup(map)
	check(not renderer.is_ready(), "nothing is drawn before the atlas is baked")

	var slices := 0
	while renderer.bake_geometry_step():
		slices += 1
		if slices > 4000:
			break
	check(slices > 1, "the geometry is baked in slices (%d)" % slices)
	check(renderer.bake_progress() > 0.999, "the bake reports its progress")

	renderer.bake(MapAtlas.VIEW_BIOMES)
	check(renderer.is_ready(), "the renderer draws the baked layer")
	check(renderer.atlas.cell_at(Vector2(-32.0, -32.0)) == -1, "hovering off the map reports no cell")
	check(renderer.view_title(MapAtlas.VIEW_HEIGHTS) == "Высоты", "layers are named for the interface")
	renderer.free()
