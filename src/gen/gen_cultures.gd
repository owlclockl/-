## Cultures: cultures, their types, expansionism and the expansion of their lands.
## Port of Fantasy Map Generator's `src/generators/cultures-generator.ts` (Azgaar, MIT).
class_name GenCultures
extends RefCounted

const DEFAULT_CULTURE_TYPE := "Generic"
const CULTURE_TYPES: Array = ["Generic", "Hunting", "Highland", "River", "Lake", "Naval", "Nomadic"]

## culture sets from the web app: how many cultures they hold and how likely they are to be picked
const CULTURE_SETS := {
	"world": {"max": 32, "probability": 10},
	"european": {"max": 15, "probability": 10},
	"oriental": {"max": 13, "probability": 2},
	"english": {"max": 10, "probability": 5},
	"antique": {"max": 10, "probability": 3},
	"highFantasy": {"max": 17, "probability": 11},
	"darkFantasy": {"max": 18, "probability": 3},
	"random": {"max": 100, "probability": 1},
}


static func generate(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var suitability: PackedInt32Array = cells["s"]
	var cell_count := suitability.size()

	var culture_ids := PackedInt32Array()
	culture_ids.resize(cell_count)

	var counts: Dictionary = map.options.get("generation", {}).get("cultures", {})
	var input_number := int(counts.get("limit", 12))
	var set_name := str(counts.get("set", "world"))
	var set_max := int(CULTURE_SETS.get(set_name, {"max": 32}).get("max", 32))
	var count := mini(input_number, set_max)

	var populated := PackedInt32Array()
	for cell_id in cell_count:
		if suitability[cell_id] != 0:
			populated.append(cell_id)

	if populated.size() < count * 25:
		count = int(populated.size() / 50)
		if count == 0:
			map.pack["cultures"] = [{"name": "Wildlands", "i": 0, "base": 1, "type": DEFAULT_CULTURE_TYPE}]
			cells["culture"] = culture_ids
			return

	var cultures := _select_cultures(count)
	var centers := FmgQuadTree.new(maxf(1.0, float(map.grid.get("spacing", 8.0))))
	var colors := FmgUtils.get_colors(count)
	var codes: Array = []

	for i in cultures.size():
		var culture: Dictionary = cultures[i]
		var new_id := i + 1
		var sorting := func(cell_id: int) -> float: return float(suitability[cell_id])
		var center := _place_center(map, populated, sorting, centers, count)
		centers.add(cells["p"][center])
		culture["center"] = center
		culture["i"] = new_id
		culture.erase("odd")
		culture.erase("sort")
		culture["color"] = colors[i]
		culture["type"] = define_culture_type(map, center)
		culture["expansionism"] = define_culture_expansionism(map, culture["type"])
		culture["origins"] = PackedInt32Array([0])
		culture["code"] = FmgUtils.abbreviate(str(culture.get("name", "")), codes)
		codes.append(culture["code"])
		culture_ids[center] = new_id
		culture["base"] = int(culture.get("base", i)) % maxi(1, GenNames.get_name_bases().size())

	cells["culture"] = culture_ids
	cultures.insert(0, {"name": "Wildlands", "i": 0, "base": 1, "origins": [0], "type": DEFAULT_CULTURE_TYPE, "cells": 0, "area": 0, "rural": 0, "urban": 0})
	map.pack["cultures"] = cultures
	map.invalidate_caches()


## The cultures of a set: FMG takes them from its default list, here they come from the name bases
static func _select_cultures(count: int) -> Array:
	var bases := GenNames.get_name_bases()
	var cultures: Array = []
	for i in count:
		var base := i % maxi(1, bases.size())
		var name := str(bases[base].get("name", "Culture %d" % i)) if base < bases.size() else "Culture %d" % i
		cultures.append({"name": name, "base": base, "odd": 1})
	return cultures


## Pick a culture center far enough from the other ones (FMG placeCenter)
static func _place_center(map: MapData, populated: PackedInt32Array, sorting: Callable, centers: FmgQuadTree, count: int) -> int:
	var max_attempts := 100
	var spacing := (map.width() + map.height()) / 2.0 / float(count)
	var points: PackedVector2Array = map.pack["cells"]["p"]

	var sorted := Array(populated)
	sorted.sort_custom(func(a: int, b: int): return float(sorting.call(a)) > float(sorting.call(b)))
	var half := maxi(int(sorted.size() / 2), 1)

	var cell_id: int = sorted[0] if sorted.size() > 0 else 0
	for _i in max_attempts:
		cell_id = sorted[mini(FmgRandom.biased(0, half - 1, 5), sorted.size() - 1)]
		spacing *= 0.9
		var taken: bool = centers.find(points[cell_id].x, points[cell_id].y, spacing) != -1
		if not taken:
			break
	return cell_id


static func define_culture_type(map: MapData, cell_id: int) -> String:
	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var biomes: PackedInt32Array = cells["biome"]
	var types: PackedInt32Array = cells["t"]
	var haven: PackedInt32Array = cells["haven"]
	var harbor: PackedByteArray = cells["harbor"]
	var feature_ids: PackedInt32Array = cells["f"]
	var features: Array = map.pack["features"]
	var rivers: PackedInt32Array = cells["r"]
	var flux: PackedInt32Array = cells["fl"]

	if heights[cell_id] < 70 and [1, 2, 4].has(biomes[cell_id]):
		return "Nomadic" # high penalty in forest biomes and near the coastline
	if heights[cell_id] > 50:
		return "Highland" # no penalty for hills and mountains
	var opposite: Dictionary = features[feature_ids[haven[cell_id]]]
	if opposite.get("type", "") == "lake" and int(opposite.get("cells", 0)) > 5:
		return "Lake"
	var own: Dictionary = features[feature_ids[cell_id]]
	if (harbor[cell_id] != 0 and opposite.get("type", "") != "lake" and FmgRandom.p(0.1)) \
		or (harbor[cell_id] == 1 and FmgRandom.p(0.6)) \
		or (own.get("subtype", "") == "isle" and FmgRandom.p(0.4)):
		return "Naval"
	if rivers[cell_id] != 0 and flux[cell_id] > 100:
		return "River"
	if types[cell_id] > 2 and [3, 7, 8, 9, 10, 12].has(biomes[cell_id]):
		return "Hunting"
	return DEFAULT_CULTURE_TYPE


static func define_culture_expansionism(map: MapData, type: String) -> float:
	var base := 1.0
	match type:
		"Lake":
			base = 0.8
		"Naval":
			base = 1.5
		"River":
			base = 0.9
		"Nomadic":
			base = 1.5
		"Hunting":
			base = 0.7
		"Highland":
			base = 1.2
	var size_variety := float(map.options.get("generation", {}).get("cultures", {}).get("sizeVariety", 1.0))
	return FmgUtils.rn((FmgRandom.next() * size_variety / 2.0 + 1.0) * base, 1)


## Spread cultures from their centers with a least-cost search (FMG Cultures.expand)
static func expand(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var cultures: Array = map.pack["cultures"]
	var neighbours: Array = cells["c"]
	var cell_count: int = cells["h"].size()

	var culture_of := PackedInt32Array()
	culture_of.resize(cell_count)
	cells["culture"] = culture_of

	var growth_rate := float(map.options.get("generation", {}).get("cultures", {}).get("growthRate", 1.0))
	var max_expansion_cost := float(cell_count) * 0.6 * growth_rate
	var cost := PackedFloat64Array()
	cost.resize(cell_count)

	# a simple priority queue: (cost, cell, culture), kept sorted on insert
	var queue: Array = []
	var order: Array = []

	for culture in cultures:
		var culture_id := int(culture.get("i", 0))
		if culture_id == 0:
			continue
		var center := int(culture.get("center", 0))
		queue.append([0.0, center, culture_id])
		cost[center] = 1.0
		order.append(culture_id)

	while not queue.is_empty():
		queue.sort_custom(func(a: Array, b: Array): return float(a[0]) < float(b[0]))
		var entry: Array = queue.pop_front()
		var priority := float(entry[0])
		var cell_id: int = entry[1]
		var culture_id: int = entry[2]
		var culture: Dictionary = cultures[culture_id]
		var type := str(culture.get("type", DEFAULT_CULTURE_TYPE))
		var expansionism := float(culture.get("expansionism", 1.0))
		var source_biome: int = cells["biome"][cell_id]

		for neighbour in neighbours[cell_id]:
			var target_biome: int = cells["biome"][neighbour]
			var biome_cost := get_biome_cost(map, culture_id, target_biome, type)
			var biome_change_cost := 0.0 if source_biome == target_biome else 20.0
			var height_cost := get_height_cost(map, neighbour, str(cells["h"][neighbour]), type)
			var river_cost := get_river_cost(cells["r"][neighbour], cells["fl"][neighbour], type)
			var type_cost := get_type_cost(cells["t"][neighbour], type)
			var cell_cost := (biome_cost + biome_change_cost + height_cost + river_cost + type_cost) / expansionism
			var total_cost := priority + cell_cost
			if total_cost > max_expansion_cost:
				continue
			if cost[neighbour] == 0.0 or total_cost < cost[neighbour]:
				if cells["pop"][neighbour] > 0.0:
					culture_of[neighbour] = culture_id
				cost[neighbour] = total_cost
				queue.append([total_cost, neighbour, culture_id])

	cells["culture"] = culture_of
	cells["cultureCost"] = cost


static func get_biome_cost(map: MapData, culture_id: int, biome: int, type: String) -> float:
	var cultures: Array = map.pack["cultures"]
	var cells: Dictionary = map.pack["cells"]
	var native_biome: int = cells["biome"][int(cultures[culture_id].get("center", 0))]
	if native_biome == biome:
		return 10.0 # tiny penalty for the native biome
	var cost := float(map.biomes[biome].get("cost", 50)) if biome < map.biomes.size() else 50.0
	if type == "Hunting":
		return cost * 5.0
	if type == "Nomadic" and biome > 4 and biome < 10:
		return cost * 10.0
	return cost * 2.0


static func get_height_cost(map: MapData, cell_id: int, height: float, type: String) -> float:
	var features: Array = map.pack["features"]
	var feature: Dictionary = features[map.pack["cells"]["f"][cell_id]]
	var area := float(map.pack["cells"]["area"][cell_id])
	if type == "Lake" and feature.get("type", "") == "lake":
		return 10.0
	if type == "Naval" and height < 20.0:
		return area * 2.0
	if type == "Nomadic" and height < 20.0:
		return area * 50.0
	if height < 20.0:
		return area * 6.0
	if type == "Highland" and height < 44.0:
		return 3000.0
	if type == "Highland" and height < 62.0:
		return 200.0
	if type == "Highland":
		return 0.0
	if height >= 67.0:
		return 200.0
	if height >= 44.0:
		return 30.0
	return 0.0


static func get_river_cost(river_id: int, flux: float, type: String) -> float:
	if type == "River":
		return 0.0 if river_id != 0 else 100.0
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


## Cells, area and population per culture (FMG Cultures.collectStatistics)
static func collect_statistics(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var cultures: Array = map.pack["cultures"]
	for culture in cultures:
		culture["cells"] = 0
		culture["area"] = 0.0
		culture["rural"] = 0.0
		culture["urban"] = 0.0
	var culture_of: PackedInt32Array = cells["culture"]
	var area: PackedInt32Array = cells["area"]
	var population: PackedFloat32Array = cells["pop"]
	for cell_id in culture_of.size():
		var culture_id := culture_of[cell_id]
		if culture_id <= 0 or culture_id >= cultures.size():
			continue
		cultures[culture_id]["cells"] = int(cultures[culture_id].get("cells", 0)) + 1
		cultures[culture_id]["area"] = float(cultures[culture_id].get("area", 0.0)) + float(area[cell_id])
		cultures[culture_id]["rural"] = float(cultures[culture_id].get("rural", 0.0)) + float(population[cell_id])
	for burg in map.pack.get("burgs", []):
		var culture_id := int(burg.get("culture", 0))
		if culture_id > 0 and culture_id < cultures.size():
			cultures[culture_id]["urban"] = float(cultures[culture_id].get("urban", 0.0)) + float(burg.get("population", 0.0))
