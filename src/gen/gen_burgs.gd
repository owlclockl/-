## Burgs: capitals, towns, and ports.
## Port of Fantasy Map Generator's `src/generators/burg-generator.ts` (Azgaar, MIT).
class_name GenBurgs
extends RefCounted


static func generate(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var culture_of: PackedInt32Array = cells["culture"]
	var total_cells: int = culture_of.size()
	var burgs: Array = [{"i": 0, "name": "", "cell": 0, "population": 0.0, "type": "", "port": 0}] # dummy burg

	map.pack["burgs"] = burgs
	map.pack["portCandidates"] = []

	var populated := PackedInt32Array()
	for cell_id in total_cells:
		if cells["s"][cell_id] > 0 and culture_of[cell_id] != 0:
			populated.append(cell_id)
	if populated.is_empty():
		return

	# capitals number follows the requested number of states (FMG getCapitalsNumber)
	var generations: Dictionary = map.options.get("generation", {})
	var states_options: Dictionary = generations.get("states", {})
	var capitals_number := int(states_options.get("limit", states_options.get("count", 30)))
	if populated.size() < capitals_number * 10:
		capitals_number = int(float(populated.size()) / 10.0)
	if capitals_number <= 0:
		return

	place_capitals(map, populated, capitals_number)
	place_towns(map, populated)
	assign_ports(map)


## Spread capitals over the map, preferring the best cells (FMG generateCapitals)
static func place_capitals(map: MapData, populated: PackedInt32Array, count: int) -> void:
	var cells: Dictionary = map.pack["cells"]
	var burgs: Array = map.pack["burgs"]
	var suitability: PackedInt32Array = cells["s"]
	var points: PackedVector2Array = cells["p"]
	var spacing := (map.width() + map.height()) / 2.0 / float(count)
	var tree := FmgQuadTree.new(maxf(1.0, float(map.grid.get("spacing", 8.0))))

	# score is randomized so capitals are not always placed on the very best cell
	var score := PackedFloat64Array()
	score.resize(suitability.size())
	for cell_id in suitability.size():
		score[cell_id] = float(suitability[cell_id]) * (0.5 + FmgRandom.next() * 0.5)
	var sorted := Array(populated)
	sorted.sort_custom(func(a: int, b: int): return score[a] > score[b])

	var rounds := 0
	var index := 0
	while burgs.size() <= count and rounds < 20:
		if index >= sorted.size():
			# all cells were checked: retry with a smaller spacing (FMG does the same)
			tree = FmgQuadTree.new(maxf(1.0, float(map.grid.get("spacing", 8.0))))
			spacing *= 0.8
			index = 0
			rounds += 1
			continue
		var cell_id: int = sorted[index]
		index += 1
		if cells["h"][cell_id] < MapData.SEA_LEVEL:
			continue
		if tree.find(points[cell_id].x, points[cell_id].y, spacing) != -1:
			continue
		tree.add(points[cell_id], burgs.size())
		_add_burg(map, cell_id, burgs.size(), true)


static func _add_burg(map: MapData, cell_id: int, burg_id: int, capital: bool) -> void:
	var cells: Dictionary = map.pack["cells"]
	var burgs: Array = map.pack["burgs"]
	var culture_id: int = cells["culture"][cell_id]
	var base := 0
	var cultures: Array = map.pack.get("cultures", [])
	if culture_id < cultures.size():
		base = int(cultures[culture_id].get("base", 0))
	var name := GenNames.get_short_name(base, culture_id)
	var harbour: int = cells["harbor"][cell_id]
	var population := 0.0
	var burg := {
		"i": burg_id,
		"name": name,
		"cell": cell_id,
		"culture": culture_id,
		"cultureCenter": culture_id,
		"state": 0,
		"feature": cells["f"][cell_id],
		"capital": capital,
		"port": 1 if harbour == 1 else 0,
		"type": "Generic",
		"population": population,
		"x": cells["p"][cell_id].x,
		"y": cells["p"][cell_id].y,
	}
	burgs.append(burg)
	var burg_of: PackedInt32Array = cells["burg"]
	burg_of[cell_id] = burg_id
	cells["burg"] = burg_of


## Fill the rest of the map with towns (FMG generateTowns)
static func place_towns(map: MapData, populated: PackedInt32Array) -> void:
	var cells: Dictionary = map.pack["cells"]
	var burgs: Array = map.pack["burgs"]
	var points: PackedVector2Array = cells["p"]
	var suitability: PackedInt32Array = cells["s"]

	var cities_limit := int(map.options.get("generation", {}).get("burgs", {}).get("limit", 1000))
	var towns_number := cities_limit
	if cities_limit >= 1000:
		# auto mode, as in the web app
		towns_number = int(FmgUtils.rn(float(populated.size()) / 5.0 / pow(float(map.points_desired()) / 10000.0, 0.8)))
	towns_number = mini(towns_number, populated.size())
	if towns_number <= 0:
		return

	var spacing := (map.width() + map.height()) / 150.0 / pow(float(towns_number), 0.7 / 66.0)
	var tree := FmgQuadTree.new(maxf(1.0, float(map.grid.get("spacing", 8.0))))
	for burg in burgs:
		if int(burg.get("i", 0)) != 0:
			tree.add(points[int(burg["cell"])], int(burg["i"]))

	var score := PackedFloat64Array()
	score.resize(suitability.size())
	for cell_id in suitability.size():
		score[cell_id] = float(suitability[cell_id]) * FmgRandom.gauss(1.0, 3.0, 0.0, 20.0, 3)
	var sorted := Array(populated)
	sorted.sort_custom(func(a: int, b: int): return score[a] > score[b])

	var capitals := _capitals_count(burgs)
	var index := 0
	var rounds := 0
	while (burgs.size() - 1 - capitals) < towns_number and rounds < 20:
		if index >= sorted.size():
			spacing *= 0.8
			index = 0
			rounds += 1
			continue
		var cell_id: int = sorted[index]
		index += 1
		if cells["burg"][cell_id] != 0 or cells["h"][cell_id] < MapData.SEA_LEVEL:
			continue
		var min_spacing := spacing * FmgRandom.gauss(1.0, 0.3, 0.2, 2.0, 2)
		if tree.find(points[cell_id].x, points[cell_id].y, min_spacing) != -1:
			continue
		var burg_id := burgs.size()
		tree.add(points[cell_id], burg_id)
		_add_burg(map, cell_id, burg_id, false)


static func _capitals_count(burgs: Array) -> int:
	var count := 0
	for burg in burgs:
		if burg.get("capital", false):
			count += 1
	return count


## Give coastal burgs a role: ports are not created, they are assigned to suitable burgs
static func assign_ports(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var burgs: Array = map.pack["burgs"]
	for burg in burgs:
		var burg_id := int(burg.get("i", 0))
		if burg_id == 0:
			continue
		var cell_id := int(burg["cell"])
		var harbor: int = cells["harbor"][cell_id]
		if harbor == 0:
			continue
		burg["port"] = 1
		if harbor == 1:
			burg["type"] = "Naval"


## Burgs of a culture and their population (FMG Burgs.specify)
static func specify(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var burgs: Array = map.pack["burgs"]
	var cultures: Array = map.pack.get("cultures", [])
	var states: Array = map.pack.get("states", [])
	for burg in burgs:
		var burg_id := int(burg.get("i", 0))
		if burg_id == 0:
			continue
		var cell_id := int(burg["cell"])
		burg["state"] = cells["state"][cell_id]
		burg["culture"] = cells["culture"][cell_id]
		var name_base := 0
		var culture_id := int(burg["culture"])
		if culture_id < cultures.size():
			name_base = int(cultures[culture_id].get("base", 0))
		burg["name"] = GenNames.get_short_name(name_base, culture_id)
		if int(burg["state"]) > 0 and int(burg["state"]) < states.size():
			var state: Dictionary = states[int(burg["state"])]
			if state.get("capital", 0) == burg_id and state.get("name", "") != "":
				burg["capital"] = true
