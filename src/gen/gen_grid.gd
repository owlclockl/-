## Initial graph — port of Fantasy Map Generator's `src/generators/grid-generator.ts` (Azgaar, MIT).
##
## A rectangle is filled with a jittered square grid of points, pseudo-points are placed along the
## map edge to clip the outer Voronoi cells, and the Voronoi diagram of all of them becomes the grid
## graph. `Grid.findCell` is a plain arithmetic lookup because the points keep their lattice order.
class_name GenGrid
extends RefCounted


## Number of cells fitting the map dimension (FMG getCellsCount)
static func cells_count(spacing: float, size: float) -> int:
	return int(floor((size + 0.5 * spacing - 1e-10) / spacing))


## Distance between points before jittering (FMG getSpacing)
static func spacing_for(cells_desired: int, width: float, height: float) -> float:
	return FmgUtils.rn(sqrt((width * height) / float(max(cells_desired, 1))), 2)


## Pseudo-points along the map edge: they clip outer Voronoi cells but get no cells of their own
static func boundary_points(width: float, height: float, spacing: float) -> PackedVector2Array:
	var offset := FmgUtils.rn(-1.0 * spacing)
	var b_spacing := spacing * 2.0
	var w := width - offset * 2.0
	var h := height - offset * 2.0
	var number_x := int(ceil(w / b_spacing) - 1.0)
	var number_y := int(ceil(h / b_spacing) - 1.0)
	var points := PackedVector2Array()
	var i := 0.5
	while i < float(number_x):
		var x := ceil((w * i) / float(number_x) + offset)
		points.append(Vector2(x, offset))
		points.append(Vector2(x, h + offset))
		i += 1.0
	i = 0.5
	while i < float(number_y):
		var y := ceil((h * i) / float(number_y) + offset)
		points.append(Vector2(offset, y))
		points.append(Vector2(w + offset, y))
		i += 1.0
	return points


## Points of a square grid, each one randomly shifted inside its square
static func jittered_points(width: float, height: float, spacing: float) -> PackedVector2Array:
	var radius := spacing / 2.0
	var jittering := radius * 0.9
	var double_jittering := jittering * 2.0
	var points := PackedVector2Array()
	var y := radius
	while y < height:
		var x := radius
		while x < width:
			var jx := x + FmgRandom.next() * double_jittering - jittering
			var jy := y + FmgRandom.next() * double_jittering - jittering
			points.append(Vector2(min(FmgUtils.rn(jx, 2), width), min(FmgUtils.rn(jy, 2), height)))
			x += spacing
		y += spacing
	return points


## Build the grid graph: seeds the PRNG, places points, calculates the Voronoi diagram (FMG Grid.generate)
## Build the grid graph. Width, height and the desired number of cells come from the options unless
## they are passed explicitly.
static func generate(map: MapData, seed_text := "", width := 0.0, height := 0.0, cells_desired := 0) -> void:
	if seed_text == "":
		seed_text = map.seed_text
	if width <= 0.0:
		width = map.width()
	if height <= 0.0:
		height = map.height()
	if cells_desired <= 0:
		cells_desired = map.points_desired()
	FmgRandom.seed_with(seed_text)
	var spacing := spacing_for(cells_desired, width, height)
	var boundary := boundary_points(width, height, spacing)
	var points := jittered_points(width, height, spacing)
	var diagram := FmgVoronoi.calculate(points, boundary)

	var cells := {
		"v": diagram.cells_v,
		"c": diagram.cells_c,
		"b": diagram.cells_b,
		"i": PackedInt32Array(),
		"h": PackedInt32Array(),
		"t": PackedInt32Array(),
		"f": PackedInt32Array(),
		"temp": PackedInt32Array(),
		"prec": PackedInt32Array(),
	}
	var indices := PackedInt32Array()
	var heights := PackedInt32Array()
	var distance_field := PackedInt32Array()
	var feature_ids := PackedInt32Array()
	var temp := PackedInt32Array()
	var prec := PackedInt32Array()
	indices.resize(points.size())
	heights.resize(points.size())
	distance_field.resize(points.size())
	feature_ids.resize(points.size())
	temp.resize(points.size())
	prec.resize(points.size())
	for i in points.size():
		indices[i] = i
	cells["i"] = indices
	cells["h"] = heights
	cells["t"] = distance_field
	cells["f"] = feature_ids
	cells["temp"] = temp
	cells["prec"] = prec

	map.grid = {
		"spacing": spacing,
		"cellsX": cells_count(spacing, width),
		"cellsY": cells_count(spacing, height),
		"boundary": boundary,
		"points": points,
		"cells": cells,
		"vertices": {"p": diagram.vertices_p, "v": diagram.vertices_v, "c": diagram.vertices_c},
		"features": [],
	}
	map.invalidate_caches()


## Turn depressions that cannot pour to water into lakes (FMG Grid.addDeepDepressionLakes)
static func add_deep_depression_lakes(map: MapData) -> void:
	var elevation_limit := int(map.options.get("generation", {}).get("lakeElevationLimit", 80))
	if elevation_limit == 80:
		return
	var cells: Dictionary = map.grid["cells"]
	var features: Array = map.grid["features"]
	var c: Array = cells["c"] # arrays are references, packed arrays are copied on write
	var h: PackedInt32Array = cells["h"] # read only
	var b: PackedByteArray = cells["b"] # read only
	var t: PackedInt32Array = cells["t"] # read only
	var f: PackedInt32Array = cells["f"] # read only

	# visit stamps instead of clearing a full flag array for every candidate (same result, O(1) reset)
	var stamp := PackedInt32Array()
	stamp.resize(h.size())
	stamp.fill(0)
	var visit := 0

	for i in h.size():
		if b[i] == 1 or h[i] < MapData.SEA_LEVEL:
			continue
		var lowest := 1000
		for neighbour in c[i]:
			lowest = mini(lowest, h[neighbour])
		if h[i] > lowest:
			continue

		var deep := true
		var threshold := h[i] + elevation_limit
		var queue := PackedInt32Array([i])
		visit += 1
		stamp[i] = visit
		while deep and not queue.is_empty():
			var q: int = queue[queue.size() - 1]
			queue.resize(queue.size() - 1)
			for neighbour in c[q]:
				if stamp[neighbour] == visit:
					continue
				if h[neighbour] >= threshold:
					continue
				if h[neighbour] < MapData.SEA_LEVEL:
					deep = false
					break
				stamp[neighbour] = visit
				queue.append(neighbour)

		if not deep:
			continue
		var lake_cells := PackedInt32Array([i])
		for neighbour in c[i]:
			if h[neighbour] == h[i]:
				lake_cells.append(neighbour)
		var feature_id := features.size()
		for cell_id in lake_cells:
			h[cell_id] = 19
			t[cell_id] = -1
			f[cell_id] = feature_id
			for neighbour in c[cell_id]:
				if not lake_cells.has(neighbour):
					t[neighbour] = 1 # the lake shore is a coastline now
		# packed arrays are value types: the edited copies go back into the graph
		cells["h"] = h
		cells["t"] = t
		cells["f"] = f
		features.append({"i": feature_id, "land": false, "border": false, "type": "lake"})


## Near-sea lakes break their threshold and flow out to sea (FMG Grid.openNearSeaLakes)
static func open_near_sea_lakes(map: MapData) -> void:
	var template := str(map.options.get("generation", {}).get("template", ""))
	if template == "atoll" or template == "Atoll":
		return
	var cells: Dictionary = map.grid["cells"]
	var features: Array = map.grid["features"]
	var has_lake := false
	for feature in features:
		if feature.get("type", "") == "lake":
			has_lake = true
			break
	if not has_lake:
		return

	var c: Array = cells["c"]
	var h: PackedInt32Array = cells["h"] # read only
	var t: PackedInt32Array = cells["t"] # read only
	var f: PackedInt32Array = cells["f"] # read only
	const LIMIT := 22

	for i in h.size():
		var lake_feature_id: int = f[i]
		if lake_feature_id >= features.size() or features[lake_feature_id].get("type", "") != "lake":
			continue
		for threshold_cell in c[i]:
			if t[threshold_cell] != 1 or h[threshold_cell] > LIMIT:
				continue
			var ocean_feature := -1
			for neighbour in c[threshold_cell]:
				var candidate: int = f[neighbour]
				if candidate < features.size() and features[candidate].get("type", "") == "ocean":
					ocean_feature = candidate
					break
			if ocean_feature == -1:
				continue
			h[threshold_cell] = 19
			t[threshold_cell] = -1
			f[threshold_cell] = ocean_feature
			for neighbour in c[threshold_cell]:
				if h[neighbour] >= MapData.SEA_LEVEL:
					t[neighbour] = 1
			for cell_id in h.size():
				if f[cell_id] == lake_feature_id:
					f[cell_id] = ocean_feature
			features[lake_feature_id]["type"] = "ocean"
			cells["h"] = h
			cells["t"] = t
			cells["f"] = f
			break
