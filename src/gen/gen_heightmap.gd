## Heightmap generation — port of Fantasy Map Generator's `src/generators/heightmap-generator.ts`
## (Azgaar, MIT). Templates are data (data/heightmap_templates.json), each line is a step:
##   Tool count height rangeX rangeY
## and the tools are Hill, Pit, Range, Trough, Strait, Mask, Invert, Add, Multiply, Smooth.
class_name GenHeightmap
extends RefCounted

## blob / line powers FMG tunes per requested cell count (they control how fast a feature fades out)
const BLOB_POWER := {
	1000: 0.93, 2000: 0.95, 5000: 0.97, 10000: 0.98, 20000: 0.99, 30000: 0.991,
	40000: 0.993, 50000: 0.994, 60000: 0.995, 70000: 0.9955, 80000: 0.996,
	90000: 0.9964, 100000: 0.9973,
}
const LINE_POWER := {
	1000: 0.75, 2000: 0.77, 5000: 0.79, 10000: 0.81, 20000: 0.82, 30000: 0.83,
	40000: 0.84, 50000: 0.86, 60000: 0.87, 70000: 0.88, 80000: 0.91,
	90000: 0.92, 100000: 0.93,
}

var map: MapData
var heights: PackedInt32Array = PackedInt32Array()
var blob_power := 0.98
var line_power := 0.81


static func power_from(table: Dictionary, cells: int, fallback: float) -> float:
	if table.has(cells):
		return float(table[cells])
	return fallback


func _init(map_ref: MapData) -> void:
	map = map_ref


func set_graph() -> void:
	var cells: Dictionary = map.grid["cells"]
	heights = cells["h"].duplicate()
	var requested := map.points_desired()
	blob_power = power_from(BLOB_POWER, requested, 0.98)
	line_power = power_from(LINE_POWER, requested, 0.81)


func _range_point(range_text: String, length: float) -> float:
	if not range_text.contains("-"):
		return FmgRandom.rand_float_between(0.0, length)
	var parts := range_text.split("-")
	var min_part := parts[0].to_float() / 100.0
	var max_part := min_part
	if parts.size() > 1:
		max_part = parts[1].to_float() / 100.0
	return FmgRandom.rand_float_between(min_part * length, max_part * length)


## add a single hill: raise the cell, then spread the change over its neighbours
func add_hill(count: String, height: String, range_x: String, range_y: String) -> void:
	var desired := int(FmgUtils.get_number_in_range(count))
	for _i in desired:
		var change := PackedFloat32Array()
		change.resize(heights.size())
		var h := FmgUtils.lim(FmgUtils.get_number_in_range(height))
		var start := 0
		var limit := 0
		while limit < 50:
			var x := _range_point(range_x, map.width())
			var y := _range_point(range_y, map.height())
			start = map.find_grid_cell(x, y)
			limit += 1
			if float(heights[start]) + h <= 90.0:
				break
		change[start] = h
		var queue := PackedInt32Array([start])
		while not queue.is_empty():
			var q: int = queue[0]
			queue.remove_at(0)
			for neighbour in map.grid["cells"]["c"][q]:
				if change[neighbour] != 0.0:
					continue
				change[neighbour] = pow(change[q], blob_power) * (FmgRandom.next() * 0.2 + 0.9)
				if change[neighbour] > 1.0:
					queue.append(neighbour)
		for i in heights.size():
			heights[i] = int(FmgUtils.lim(float(heights[i]) + change[i]))


func add_pit(count: String, height: String, range_x: String, range_y: String) -> void:
	var desired := int(FmgUtils.get_number_in_range(count))
	for _i in desired:
		var used := PackedByteArray()
		used.resize(heights.size())
		used.fill(0)
		var h := FmgUtils.lim(FmgUtils.get_number_in_range(height))
		var start := 0
		var limit := 0
		while limit < 50:
			var x := _range_point(range_x, map.width())
			var y := _range_point(range_y, map.height())
			start = map.find_grid_cell(x, y)
			limit += 1
			if heights[start] >= 20:
				break
		var queue := PackedInt32Array([start])
		while not queue.is_empty():
			var q: int = queue[0]
			queue.remove_at(0)
			h = pow(h, blob_power) * (FmgRandom.next() * 0.2 + 0.9)
			if h < 1.0:
				break
			for neighbour in map.grid["cells"]["c"][q]:
				if used[neighbour] == 1:
					continue
				heights[neighbour] = int(FmgUtils.lim(float(heights[neighbour]) - h * (FmgRandom.next() * 0.2 + 0.9)))
				used[neighbour] = 1
				queue.append(neighbour)


## walk from `start` to `end` picking the neighbour closest to the end (optionally jittered)
func _ridge(start: int, end: int, used: PackedByteArray, randomness: float) -> PackedInt32Array:
	var range_cells := PackedInt32Array([start])
	var points: PackedVector2Array = map.grid["points"]
	var neighbours: Array = map.grid["cells"]["c"]
	used[start] = 1
	var current := start
	var guard := 0
	while current != end and guard < 100000:
		guard += 1
		var best := -1
		var best_distance := INF
		for neighbour in neighbours[current]:
			if used[neighbour] == 1:
				continue
			var dx := points[end].x - points[neighbour].x
			var dy := points[end].y - points[neighbour].y
			var diff := dx * dx + dy * dy
			if FmgRandom.next() > 1.0 - randomness:
				diff = diff / 2.0
			if diff < best_distance:
				best_distance = diff
				best = neighbour
		if best == -1:
			break
		current = best
		range_cells.append(current)
		used[current] = 1
	return range_cells


func add_range(count: String, height: String, range_x: String, range_y: String, randomness := 0.15) -> void:
	var desired := int(FmgUtils.get_number_in_range(count))
	for _i in desired:
		var used := PackedByteArray()
		used.resize(heights.size())
		used.fill(0)
		var h := FmgUtils.lim(FmgUtils.get_number_in_range(height))
		var start_cell := 0
		var end_cell := 0
		if not range_x.is_empty() and not range_y.is_empty():
			var start_x := _range_point(range_x, map.width())
			var start_y := _range_point(range_y, map.height())
			var end_x := 0.0
			var end_y := 0.0
			var distance := 0.0
			var limit := 0
			while limit < 50:
				end_x = FmgRandom.next() * map.width() * 0.8 + map.width() * 0.1
				end_y = FmgRandom.next() * map.height() * 0.7 + map.height() * 0.15
				distance = abs(end_y - start_y) + abs(end_x - start_x)
				limit += 1
				if distance >= map.width() / 8.0 and distance <= map.width() / 3.0:
					break
			start_cell = map.find_grid_cell(start_x, start_y)
			end_cell = map.find_grid_cell(end_x, end_y)

		var ridge := _ridge(start_cell, end_cell, used, randomness)
		var queue := ridge.duplicate()
		var iterations := 0
		while not queue.is_empty():
			var frontier := queue.duplicate()
			queue = PackedInt32Array()
			iterations += 1
			for cell_id in frontier:
				heights[cell_id] = int(FmgUtils.lim(float(heights[cell_id]) + h * (FmgRandom.next() * 0.3 + 0.85)))
			h = pow(h, line_power) - 1.0
			if h < 2.0:
				break
			for cell_id in frontier:
				for neighbour in map.grid["cells"]["c"][cell_id]:
					if used[neighbour] == 0:
						queue.append(neighbour)
						used[neighbour] = 1

		# generate prominences
		var index := 0
		for cell_id in ridge:
			if index % 6 == 0:
				var current := cell_id
				for _step in max(iterations, 1):
					var lowest := -1
					var lowest_height := 1000
					for neighbour in map.grid["cells"]["c"][current]:
						if heights[neighbour] < lowest_height:
							lowest_height = heights[neighbour]
							lowest = neighbour
					if lowest == -1:
						break
					heights[lowest] = int((float(heights[current]) * 2.0 + float(heights[lowest])) / 3.0)
					current = lowest
			index += 1


func add_trough(count: String, height: String, range_x: String, range_y: String, randomness := 0.2) -> void:
	var desired := int(FmgUtils.get_number_in_range(count))
	for _i in desired:
		var used := PackedByteArray()
		used.resize(heights.size())
		used.fill(0)
		var h := FmgUtils.lim(FmgUtils.get_number_in_range(height))
		var start_cell := 0
		var end_cell := 0
		if not range_x.is_empty() and not range_y.is_empty():
			var start_x := 0.0
			var start_y := 0.0
			var limit := 0
			while limit < 50:
				start_x = _range_point(range_x, map.width())
				start_y = _range_point(range_y, map.height())
				start_cell = map.find_grid_cell(start_x, start_y)
				limit += 1
				if heights[start_cell] >= 20:
					break
			var end_x := 0.0
			var end_y := 0.0
			var distance := 0.0
			limit = 0
			while limit < 50:
				end_x = FmgRandom.next() * map.width() * 0.8 + map.width() * 0.1
				end_y = FmgRandom.next() * map.height() * 0.7 + map.height() * 0.15
				distance = abs(end_y - start_y) + abs(end_x - start_x)
				limit += 1
				if distance >= map.width() / 8.0 and distance <= map.width() / 2.0:
					break
			end_cell = map.find_grid_cell(end_x, end_y)

		var ridge := _ridge(start_cell, end_cell, used, randomness)
		var queue := ridge.duplicate()
		var iterations := 0
		while not queue.is_empty():
			var frontier := queue.duplicate()
			queue = PackedInt32Array()
			iterations += 1
			for cell_id in frontier:
				heights[cell_id] = int(FmgUtils.lim(float(heights[cell_id]) - h * (FmgRandom.next() * 0.3 + 0.85)))
			h = pow(h, line_power) - 1.0
			if h < 2.0:
				break
			for cell_id in frontier:
				for neighbour in map.grid["cells"]["c"][cell_id]:
					if used[neighbour] == 0:
						queue.append(neighbour)
						used[neighbour] = 1

		var index := 0
		for cell_id in ridge:
			if index % 6 == 0:
				var current := cell_id
				for _step in max(iterations, 1):
					var lowest := -1
					var lowest_height := 1000
					for neighbour in map.grid["cells"]["c"][current]:
						if heights[neighbour] < lowest_height:
							lowest_height = heights[neighbour]
							lowest = neighbour
					if lowest == -1:
						break
					heights[lowest] = int((float(heights[current]) * 2.0 + float(heights[lowest])) / 3.0)
					current = lowest
			index += 1


func add_strait(width_text: String, direction := "vertical") -> void:
	var desired_width := min(FmgUtils.get_number_in_range(width_text), float(map.grid["cellsX"]) / 3.0)
	if desired_width < 1.0 and FmgRandom.p(desired_width):
		return
	var used := PackedByteArray()
	used.resize(heights.size())
	used.fill(0)
	var vertical := direction == "vertical"
	var start_x := float(floor(FmgRandom.next() * map.width() * 0.4 + map.width() * 0.3)) if vertical else 5.0
	var start_y := 5.0 if vertical else float(floor(FmgRandom.next() * map.height() * 0.4 + map.height() * 0.3))
	var end_x := (
		float(floor(map.width() - start_x - map.width() * 0.1 + FmgRandom.next() * map.width() * 0.2))
		if vertical
		else map.width() - 5.0
	)
	var end_y := (
		map.height() - 5.0
		if vertical
		else float(floor(map.height() - start_y - map.height() * 0.1 + FmgRandom.next() * map.height() * 0.2))
	)

	var start_cell := map.find_grid_cell(start_x, start_y)
	var end_cell := map.find_grid_cell(end_x, end_y)
	var points: PackedVector2Array = map.grid["points"]
	var neighbours: Array = map.grid["cells"]["c"]

	var range_cells := PackedInt32Array()
	var current := start_cell
	var guard := 0
	while current != end_cell and guard < 100000:
		guard += 1
		var best := -1
		var best_distance := INF
		for neighbour in neighbours[current]:
			var dx := points[end_cell].x - points[neighbour].x
			var dy := points[end_cell].y - points[neighbour].y
			var diff := dx * dx + dy * dy
			if FmgRandom.next() > 0.8:
				diff = diff / 2.0
			if diff < best_distance:
				best_distance = diff
				best = neighbour
		if best == -1:
			break
		current = best
		range_cells.append(current)

	var query := PackedInt32Array()
	var step := 0.1 / max(desired_width, 0.1)
	var width_index := 0.0
	while width_index < desired_width:
		var remaining := desired_width - width_index
		var exponent := 0.9 - step * remaining
		for cell_id in range_cells:
			for neighbour in neighbours[cell_id]:
				if used[neighbour] == 1:
					continue
				used[neighbour] = 1
				query.append(neighbour)
				heights[neighbour] = int(pow(float(heights[neighbour]), exponent))
				if heights[neighbour] > 100:
					heights[neighbour] = 5
		range_cells = query.duplicate()
		query = PackedInt32Array()
		width_index += 1.0


func modify(range_text: String, add: float, mult: float, power := 0.0) -> void:
	var min_height := 0
	var max_height := 100
	if range_text == "land":
		min_height = 20
	elif range_text == "all":
		min_height = 0
	else:
		var parts := range_text.split("-")
		min_height = int(parts[0].to_float())
		max_height = 100 if parts.size() < 2 else int(parts[1].to_float())
	var is_land := min_height == 20
	for i in heights.size():
		var h := float(heights[i])
		if h < float(min_height) or h > float(max_height):
			continue
		if add != 0.0:
			h = max(h + add, 20.0) if is_land else h + add
		if mult != 1.0:
			h = (h - 20.0) * mult + 20.0 if is_land else h * mult
		if power != 0.0:
			h = pow(h - 20.0, power) + 20.0 if is_land else pow(h, power)
		heights[i] = int(FmgUtils.lim(h))


func smooth(fr := 2.0, add := 0.0) -> void:
	var neighbours: Array = map.grid["cells"]["c"]
	var result := heights.duplicate()
	for i in heights.size():
		var values: Array = [float(heights[i])]
		for neighbour in neighbours[i]:
			values.append(float(heights[neighbour]))
		var mean_value := FmgUtils.mean(values)
		if is_equal_approx(fr, 1.0):
			result[i] = int(mean_value + add)
		else:
			result[i] = int(FmgUtils.lim((float(heights[i]) * (fr - 1.0) + mean_value + add) / fr))
	heights = result


func mask(power := 1.0) -> void:
	var fr := abs(power) if power != 0.0 else 1.0
	var points: PackedVector2Array = map.grid["points"]
	var width := map.width()
	var height := map.height()
	for i in heights.size():
		var h := float(heights[i])
		var nx := (2.0 * points[i].x) / width - 1.0
		var ny := (2.0 * points[i].y) / height - 1.0
		var distance := (1.0 - nx * nx) * (1.0 - ny * ny)
		if power < 0.0:
			distance = 1.0 - distance
		var masked := h * distance
		heights[i] = int(FmgUtils.lim((h * (fr - 1.0) + masked) / fr))


func invert(count: float, axes: String) -> void:
	if not FmgRandom.p(count):
		return
	var invert_x := axes != "y"
	var invert_y := axes != "x"
	var cells_x: int = map.grid["cellsX"]
	var cells_y: int = map.grid["cellsY"]
	var result := heights.duplicate()
	for i in heights.size():
		var x := i % cells_x
		var y := i / cells_x
		var nx := cells_x - x - 1 if invert_x else x
		var ny := cells_y - y - 1 if invert_y else y
		var source := nx + ny * cells_x
		if source >= 0 and source < heights.size():
			result[i] = heights[source]
	heights = result


## run a single template step: "Hill 1 90-100 44-56 40-60"
func add_step(tool: String, a2: String, a3: String, a4: String, a5: String) -> void:
	match tool:
		"Hill":
			add_hill(a2, a3, a4, a5)
		"Pit":
			add_pit(a2, a3, a4, a5)
		"Range":
			add_range(a2, a3, a4, a5)
		"Trough":
			add_trough(a2, a3, a4, a5)
		"Strait":
			add_strait(a2, a3)
		"Mask":
			mask(a2.to_float())
		"Invert":
			invert(a2.to_float(), a3)
		"Add":
			modify(a3, a2.to_float(), 1.0)
		"Multiply":
			modify(a3, 0.0, a2.to_float())
		"Smooth":
			smooth(max(a2.to_float(), 1.0))
		_:
			push_warning("Unknown heightmap tool: %s" % tool)


## Build the heightmap from a template (FMG HeightmapGenerator.fromTemplate)
func from_template(template_id: String) -> void:
	var templates := GenOptions.load_json("res://data/heightmap_templates.json")
	var template: Dictionary = templates.get(template_id, {})
	var script: String = str(template.get("template", ""))
	if script.strip_edges().is_empty():
		push_warning("Heightmap template '%s' is missing, falling back to continents" % template_id)
		template = templates.get("continents", {})
		script = str(template.get("template", ""))
	set_graph()
	for line in script.split("\n"):
		var elements := line.strip_edges().split(" ", false)
		if elements.size() < 2:
			continue
		while elements.size() < 5:
			elements.append("")
		add_step(elements[0], elements[1], elements[2], elements[3], elements[4])
	var cells: Dictionary = map.grid["cells"]
	cells["h"] = heights


## Generate heights for the whole map (seeds the PRNG so the result only depends on the seed)
static func generate(map: MapData) -> void:
	FmgRandom.seed_with(map.seed_text)
	var generator := GenHeightmap.new(map)
	generator.from_template(str(map.options.get("generation", {}).get("template", "continents")))
	map.invalidate_caches()


## Turn a generated heightmap into the elevation in metres (used by the UI and the climate model)
static func elevation_meters(map: MapData, cell_id: int) -> float:
	var height := float(map.grid["cells"]["h"][cell_id])
	if height < MapData.SEA_LEVEL:
		return 0.0
	var exponent := float(map.options.get("units", {}).get("height", {}).get("exponent", 1.8))
	return pow(height - 18.0, exponent)
