## Religions and provinces.
## Ports of Fantasy Map Generator's `src/generators/religions-generator.ts` and
## `src/generators/provinces-generator.ts` (Azgaar, MIT), reduced to the provinces/religions
## layers that do not depend on the economical and heraldic modules.
class_name GenReligions
extends RefCounted


# ------------------------------------------------------------------ religions

## Folk religions of every culture, then organized religions in the biggest burgs
static func generate(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var religions: Array = [{"i": 0, "name": "No religion", "type": "Folk", "culture": 0}]
	var culture_of: PackedInt32Array = cells["culture"]
	var cell_count := culture_of.size()

	for culture in map.pack.get("cultures", []):
		var culture_id := int(culture.get("i", 0))
		if culture_id == 0:
			continue
		religions.append({
			"i": religions.size(),
			"name": str(culture.get("name", "Culture")),
			"type": "Folk",
			"culture": culture_id,
			"center": int(culture.get("center", 0)),
			"expansionism": float(culture.get("expansionism", 1.0)),
		})

	var religion_of := PackedInt32Array()
	religion_of.resize(cell_count)
	for cell_id in cell_count:
		var culture_id := culture_of[cell_id]
		if culture_id <= 0:
			continue
		for i in range(1, religions.size()):
			if int(religions[i].get("culture", 0)) == culture_id:
				religion_of[cell_id] = i
				break

	# organized religions: strongest burgs of the map become their cores
	var cults_number := maxi(int(float(religions.size()) * FmgRandom.rand_float_between(0.1, 0.4)), 0)
	var burgs := Array(map.pack.get("burgs", []))
	burgs = burgs.filter(func(b: Dictionary): return int(b.get("i", 0)) != 0 and not b.get("removed", false))
	burgs.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("population", 0.0)) > float(b.get("population", 0.0)))
	var limit := int(float(burgs.size()) / 10.0)
	if limit < 0:
		limit = 0
	if cults_number < limit:
		limit = cults_number
	for i in limit:
		var burg: Dictionary = burgs[i]
		var culture_id := int(burg.get("culture", 0))
		var name := GenNames.get_short_name(int(map.pack["cultures"][culture_id].get("base", 0)) if culture_id < map.pack["cultures"].size() else 0, culture_id)
		religions.append({
			"i": religions.size(),
			"name": name,
			"type": "Organized",
			"culture": culture_id,
			"center": int(burg["cell"]),
			"expansionism": FmgUtils.rn(FmgRandom.next() * 2.0 + 1.0, 1),
		})

	cells["religion"] = religion_of
	map.pack["religions"] = religions
	expand(map)


## Spread religions from their cores with a least-cost search (FMG Religions.expand)
static func expand(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var religions: Array = map.pack["religions"]
	var neighbours: Array = cells["c"]
	var religion_of: PackedInt32Array = cells["religion"]
	var cell_count := religion_of.size()

	var growth_rate := float(cell_count) / 20.0 * float(map.options.get("generation", {}).get("religions", {}).get("growthRate", 1.0))
	var cost := PackedFloat64Array()
	cost.resize(cell_count)

	var queue: Array = []
	for religion in religions:
		var religion_id := int(religion.get("i", 0))
		if religion_id == 0 or str(religion.get("type", "")) != "Organized":
			continue
		queue.append([0.0, int(religion.get("center", 0)), religion_id])
		cost[int(religion.get("center", 0))] = 1.0

	while not queue.is_empty():
		queue.sort_custom(func(a: Array, b: Array): return float(a[0]) < float(b[0]))
		var entry: Array = queue.pop_front()
		var priority := float(entry[0])
		var cell_id: int = entry[1]
		var religion_id: int = entry[2]
		var religion: Dictionary = religions[religion_id]
		var expansionism := float(religion.get("expansionism", 1.0))

		for neighbour in neighbours[cell_id]:
			var cell_cost := 0.0
			if cells["h"][neighbour] < MapData.SEA_LEVEL:
				cell_cost = 50.0 if cells["t"][neighbour] == -1 else 500.0
			elif int(religions[religion_of[neighbour]].get("culture", 0)) == int(religion.get("culture", 0)):
				cell_cost = 20.0
			else:
				cell_cost = float(map.biomes[cells["biome"][neighbour]].get("cost", 50)) / 3.0 if cells["biome"][neighbour] < map.biomes.size() else 20.0
			var total_cost := priority + cell_cost / expansionism
			if total_cost > growth_rate:
				continue
			if cost[neighbour] == 0.0 or total_cost < cost[neighbour]:
				religion_of[neighbour] = religion_id
				cost[neighbour] = total_cost
				queue.append([total_cost, neighbour, religion_id])

	cells["religion"] = religion_of


# ------------------------------------------------------------------ provinces

## Provinces are the second level of the state hierarchy (FMG Provinces.generate)
static func generate_provinces(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var states: Array = map.pack["states"]
	var burgs: Array = map.pack["burgs"]
	var provinces: Array = [{"i": 0, "name": "Wildlands", "state": 0}]
	var province_of := PackedInt32Array()
	province_of.resize(cells["h"].size())
	var cells_of_state := {}

	for burg in burgs:
		var burg_id := int(burg.get("i", 0))
		if burg_id == 0 or burg.get("removed", false):
			continue
		var state_id := int(burg.get("state", 0))
		if state_id <= 0:
			continue
		if not cells_of_state.has(state_id):
			cells_of_state[state_id] = 0
		cells_of_state[state_id] += 1

	for state in states:
		var state_id := int(state.get("i", 0))
		if state_id == 0:
			continue
		var state_cells := int(state.get("cells", 0))
		var count := maxi(1, int(sqrt(float(maxi(state_cells, 0))) / 2.0))
		var provinces_names: Array = []
		for i in count:
			var culture_id := int(state.get("culture", 0))
			var base := int(map.pack["cultures"][culture_id].get("base", 0)) if culture_id < map.pack["cultures"].size() else 0
			var name := GenNames.get_short_name(base, culture_id)
			while provinces_names.has(name):
				name = GenNames.get_short_name(base, culture_id)
			provinces_names.append(name)
			var center := _pick_center(map, state_id, province_of, i, count)
			if center < 0:
				continue
			provinces.append({
				"i": provinces.size(),
				"name": name,
				"state": state_id,
				"center": center,
				"culture": culture_id,
				"cells": 0,
				"area": 0.0,
				"rural": 0.0,
				"urban": 0.0,
				"burgs": 0,
			})
			province_of[center] = provinces.size() - 1

	expand_provinces(map, province_of)
	cells["province"] = province_of
	map.pack["provinces"] = provinces


static func _pick_center(map: MapData, state_id: int, province_of: PackedInt32Array, index: int, count: int) -> int:
	var cells: Dictionary = map.pack["cells"]
	var state_of: PackedInt32Array = cells["state"]
	var candidates := PackedInt32Array()
	for cell_id in state_of.size():
		if state_of[cell_id] == state_id and cells["h"][cell_id] >= MapData.SEA_LEVEL and province_of[cell_id] == 0:
			candidates.append(cell_id)
	if candidates.is_empty():
		return -1
	return candidates[FmgRandom.rand_i(0, candidates.size() - 1)]


## Provinces grow inside their state (FMG Provinces.expandProvinces)
static func expand_provinces(map: MapData, province_of: PackedInt32Array) -> void:
	var cells: Dictionary = map.pack["cells"]
	var provinces: Array = map.pack["provinces"]
	var state_of: PackedInt32Array = cells["state"]
	var neighbours: Array = cells["c"]
	var queue: Array = []
	var cost := {}
	for province in provinces:
		var province_id := int(province.get("i", 0))
		if province_id == 0:
			continue
		var center := int(province.get("center", 0))
		queue.append([0.0, center, province_id, int(province.get("state", 0))])
		cost[center] = 0.0

	while not queue.is_empty():
		queue.sort_custom(func(a: Array, b: Array): return float(a[0]) < float(b[0]))
		var entry: Array = queue.pop_front()
		var priority := float(entry[0])
		var cell_id: int = entry[1]
		var province_id: int = entry[2]
		var state_id: int = entry[3]
		for neighbour in neighbours[cell_id]:
			if state_of[neighbour] != state_id or cells["h"][neighbour] < MapData.SEA_LEVEL:
				continue
			var total_cost := priority + 1.0 + float(map.biomes[cells["biome"][neighbour]].get("cost", 50)) / 100.0
			if not cost.has(neighbour) or total_cost < float(cost[neighbour]):
				cost[neighbour] = total_cost
				province_of[neighbour] = province_id
				queue.append([total_cost, neighbour, province_id, state_id])

	# any cell without a province joins a neighbour
	for cell_id in province_of.size():
		if province_of[cell_id] != 0 or state_of[cell_id] == 0 or cells["h"][cell_id] < MapData.SEA_LEVEL:
			continue
		for neighbour in neighbours[cell_id]:
			if province_of[neighbour] != 0:
				province_of[cell_id] = province_of[neighbour]
				break
