## States: capitals, expansion, naming and colours.
## Port of Fantasy Map Generator's `src/generators/states-generator.ts` (Azgaar, MIT).
class_name GenStates
extends RefCounted

const STATE_COLORS: Array = ["#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f"]


static func generate(map: MapData) -> void:
	recreate(map)
	expand_states(map)
	normalize(map)
	collect_statistics(map)


## Create states from the capitals placed by the burg generator (FMG States.recreate)
static func recreate(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var burgs: Array = map.pack["burgs"]
	var states: Array = [{"i": 0, "name": "Neutrals"}] # dummy state

	var count := 0
	var valid_burgs: Array = []
	for burg in burgs:
		var burg_id := int(burg.get("i", 0))
		if burg_id == 0 or burg.get("removed", false):
			continue
		if not burg.get("capital", false):
			continue
		valid_burgs.append(burg)
		count += 1
	if count == 0:
		map.pack["states"] = states
		cells["state"] = PackedInt32Array()
		cells["state"].resize(cells["h"].size())
		return

	var colors := FmgUtils.get_colors(count)
	var centers := FmgQuadTree.new(maxf(1.0, float(map.grid.get("spacing", 8.0))))
	var sorted := valid_burgs.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("population", 0.0)) * FmgRandom.next() > float(b.get("population", 0.0)) * FmgRandom.next())

	var state_of := PackedInt32Array()
	state_of.resize(cells["h"].size())

	var index := 0
	for burg in sorted:
		var new_id := index + 1
		var cell_id := int(burg["cell"])
		var culture_id := int(burg.get("culture", 0))
		var culture: Dictionary = map.pack["cultures"][culture_id] if culture_id < map.pack["cultures"].size() else {}
		var base := int(culture.get("base", culture_id))
		var name := GenNames.get_state_name(base, culture_id)
		var states_names: Array = []
		for state in states:
			states_names.append(str(state.get("name", "")))
		while states_names.has(name):
			name = GenNames.get_state_name(base, culture_id)
		var type := "Nomadic" if [1, 2, 3, 4].has(cells["biome"][cell_id]) else "Generic"
		var expansionism := FmgUtils.rn(FmgRandom.next() * float(map.options.get("generation", {}).get("states", {}).get("sizeVariety", 1.0)) + 1.0, 1)
		states.append({
			"i": new_id,
			"name": name,
			"capital": int(burg["i"]),
			"center": cell_id,
			"culture": culture_id,
			"type": type,
			"expansionism": expansionism,
			"color": colors[index % colors.size()] if colors.size() > 0 else FmgUtils.get_random_color(),
			"cells": 0,
			"area": 0.0,
			"rural": 0.0,
			"urban": 0.0,
			"burgs": 0,
		})
		state_of[cell_id] = new_id
		centers.add(cells["p"][cell_id], new_id)
		index += 1

	cells["state"] = state_of
	map.pack["states"] = states


static func get_biome_cost(map: MapData, native_biome: int, biome: int, type: String) -> float:
	var cost := float(map.biomes[biome].get("cost", 50)) if biome < map.biomes.size() else 50.0
	if native_biome == biome:
		return 10.0
	if type == "Hunting":
		return cost * 2.0
	if type == "Nomadic" and biome > 4 and biome < 10:
		return cost * 3.0
	return cost


static func get_height_cost(map: MapData, feature: Dictionary, height: float, type: String) -> float:
	if type == "Lake" and feature.get("type", "") == "lake":
		return 10.0
	if type == "Naval" and height < 20.0:
		return 300.0
	if type == "Nomadic" and height < 20.0:
		return 10000.0
	if height < 20.0:
		return 1000.0
	if type == "Highland" and height < 62.0:
		return 1100.0
	if type == "Highland":
		return 0.0
	if height >= 67.0:
		return 2200.0
	if height >= 44.0:
		return 300.0
	return 0.0


static func get_river_cost(river_id: int, flux: float) -> float:
	if river_id == 0:
		return 0.0
	return FmgUtils.minmax(flux / 10.0, 20.0, 100.0)


static func get_type_cost(cell_type: int, type: String) -> float:
	if cell_type == 1:
		if type == "Naval" or type == "Lake":
			return 0.0
		return 60.0 if type == "Nomadic" else 20.0
	if cell_type == 2:
		return 30.0 if (type == "Naval" or type == "Nomadic") else 0.0
	if cell_type != -1:
		return 100.0 if (type == "Naval" or type == "Lake") else 0.0
	return 0.0


## Grow states from their capitals with a least-cost search (FMG States.expandStates)
static func expand_states(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var states: Array = map.pack["states"]
	var burgs: Array = map.pack["burgs"]
	var neighbours: Array = cells["c"]
	var cell_count: int = cells["h"].size()

	var state_of := PackedInt32Array()
	state_of.resize(cell_count)
	cells["state"] = state_of

	var growth_rate := float(cell_count) / 2.0 * float(map.options.get("generation", {}).get("states", {}).get("growthRate", 1.0))
	var cost := PackedFloat64Array()
	cost.resize(cell_count)

	var queue: Array = []
	for state in states:
		var state_id := int(state.get("i", 0))
		if state_id == 0:
			continue
		var capital_cell := int(burgs[int(state["capital"])]["cell"])
		state_of[capital_cell] = state_id
		var center := int(state.get("center", capital_cell))
		var culture_id := int(state.get("culture", 0))
		var culture_center := int(map.pack["cultures"][culture_id].get("center", center)) if culture_id < map.pack["cultures"].size() else center
		var native_biome: int = cells["biome"][culture_center]
		queue.append([0.0, center, state_id, native_biome])
		cost[center] = 1.0

	while not queue.is_empty():
		queue.sort_custom(func(a: Array, b: Array): return float(a[0]) < float(b[0]))
		var entry: Array = queue.pop_front()
		var priority := float(entry[0])
		var cell_id: int = entry[1]
		var state_id: int = entry[2]
		var native_biome: int = entry[3]
		var state: Dictionary = states[state_id]
		var type := str(state.get("type", "Generic"))
		var culture_id := int(state.get("culture", 0))
		var expansionism := float(state.get("expansionism", 1.0))

		for neighbour in neighbours[cell_id]:
			var culture_cost := -9.0 if cells["culture"][neighbour] == culture_id else 100.0
			var population_cost := 0.0
			if cells["h"][neighbour] >= MapData.SEA_LEVEL:
				population_cost = maxf(20.0 - float(cells["s"][neighbour]), 0.0) if cells["s"][neighbour] != 0 else 5000.0
			var biome_cost := get_biome_cost(map, native_biome, cells["biome"][neighbour], type)
			var feature: Dictionary = map.pack["features"][cells["f"][neighbour]]
			var height_cost := get_height_cost(map, feature, float(cells["h"][neighbour]), type)
			var river_cost := get_river_cost(cells["r"][neighbour], float(cells["fl"][neighbour]))
			var type_cost := get_type_cost(cells["t"][neighbour], type)
			var cell_cost := maxf(culture_cost + population_cost + biome_cost + height_cost + river_cost + type_cost, 0.0)
			var total_cost := priority + 10.0 + cell_cost / expansionism
			if total_cost > growth_rate:
				continue
			if cost[neighbour] == 0.0 or total_cost < cost[neighbour]:
				if cells["h"][neighbour] >= MapData.SEA_LEVEL:
					state_of[neighbour] = state_id
				cost[neighbour] = total_cost
				queue.append([total_cost, neighbour, state_id, native_biome])

	cells["state"] = state_of
	for burg in burgs:
		var burg_id := int(burg.get("i", 0))
		if burg_id == 0:
			continue
		burg["state"] = state_of[int(burg["cell"])]


## Cells surrounded by foreign states go back home (FMG States.normalize)
static func normalize(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var state_of: PackedInt32Array = cells["state"]
	var neighbours: Array = cells["c"]
	var heights: PackedInt32Array = cells["h"]
	for cell_id in state_of.size():
		var state_id := state_of[cell_id]
		if state_id == 0 or heights[cell_id] < MapData.SEA_LEVEL:
			continue
		var adversaries := 0
		var buddies := 0
		for neighbour in neighbours[cell_id]:
			if heights[neighbour] < MapData.SEA_LEVEL:
				continue
			if state_of[neighbour] == state_id:
				buddies += 1
			else:
				adversaries += 1
		if adversaries >= 2 and buddies <= 2:
			for neighbour in neighbours[cell_id]:
				if state_of[neighbour] != state_id and heights[neighbour] >= MapData.SEA_LEVEL:
					state_of[cell_id] = state_of[neighbour]
					break
	cells["state"] = state_of


## Cells, area and population per state (FMG States.collectStatistics)
static func collect_statistics(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var states: Array = map.pack["states"]
	for state in states:
		state["cells"] = 0
		state["area"] = 0.0
		state["rural"] = 0.0
		state["urban"] = 0.0
		state["burgs"] = 0
	var state_of: PackedInt32Array = cells["state"]
	for cell_id in state_of.size():
		var state_id := state_of[cell_id]
		if state_id <= 0 or state_id >= states.size():
			continue
		states[state_id]["cells"] = int(states[state_id]["cells"]) + 1
		states[state_id]["area"] = float(states[state_id]["area"]) + float(cells["area"][cell_id])
		states[state_id]["rural"] = float(states[state_id]["rural"]) + float(cells["pop"][cell_id])
	for burg in map.pack.get("burgs", []):
		var state_id := int(burg.get("state", 0))
		if state_id > 0 and state_id < states.size():
			states[state_id]["urban"] = float(states[state_id]["urban"]) + float(burg.get("population", 0.0))
			states[state_id]["burgs"] = int(states[state_id]["burgs"]) + 1


## States in the neighbourhood of a state (FMG States.findNeighbors)
static func find_neighbors(map: MapData) -> Dictionary:
	var cells: Dictionary = map.pack["cells"]
	var state_of: PackedInt32Array = cells["state"]
	var neighbours: Array = cells["c"]
	var result := {}
	for cell_id in state_of.size():
		var state_id := state_of[cell_id]
		if state_id == 0:
			continue
		if not result.has(state_id):
			result[state_id] = {}
		for neighbour in neighbours[cell_id]:
			var neighbour_state := state_of[neighbour]
			if neighbour_state != 0 and neighbour_state != state_id:
				result[state_id][neighbour_state] = true
	return result


## Colour states so neighbours never share the same colour (FMG States.assignColors)
static func assign_colors(map: MapData) -> void:
	var states: Array = map.pack["states"]
	var neighbours := find_neighbors(map)
	var colors := FmgUtils.get_colors(maxi(states.size(), 1))
	for state in states:
		var state_id := int(state.get("i", 0))
		if state_id == 0:
			continue
		var used: Array = []
		for neighbour in neighbours.get(state_id, {}).keys():
			if neighbour < states.size():
				used.append(str(states[neighbour].get("color", "")))
		var picked := ""
		for color in colors:
			var hex := FmgUtils.color_to_hex(color)
			if not used.has(hex):
				picked = hex
				break
		if picked == "":
			picked = FmgUtils.color_to_hex(FmgUtils.get_random_color())
		state["color"] = picked
