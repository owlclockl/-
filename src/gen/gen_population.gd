## Cell suitability and population.
## Port of Fantasy Map Generator's `src/generators/population-generator.ts` (Azgaar, MIT).
class_name GenPopulation
extends RefCounted

## Coast bonuses by the subtype of the opposite water body (FMG COAST_SCORES)
const COAST_SCORES := {
	"estuary": 15,
	"ocean_coast": 5,
	"save_harbor": 20,
	"freshwater": 30,
	"salt": 10,
	"frozen": 1,
	"dry": -5,
	"sinkhole": -5,
	"lava": -30,
}


## Rank every cell by habitability and calculate its rural population (FMG rankCells)
static func rank_cells(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var features: Array = map.pack["features"]
	var heights: PackedInt32Array = cells["h"]
	var flux: PackedInt32Array = cells["fl"]
	var confidence: PackedInt32Array = cells["conf"]
	var types: PackedInt32Array = cells["t"]
	var haven: PackedInt32Array = cells["haven"]
	var harbor: PackedByteArray = cells["harbor"]
	var feature_ids: PackedInt32Array = cells["f"]
	var area: PackedInt32Array = cells["area"]
	var biomes: PackedInt32Array = cells["biome"]
	var rivers: PackedInt32Array = cells["r"]
	var neighbours: Array = cells["c"]

	var total := heights.size()
	var suitability := PackedInt32Array()
	suitability.resize(total)
	var population := PackedFloat32Array()
	population.resize(total)

	var flux_values: Array = []
	for value in flux:
		if value != 0:
			flux_values.append(float(value))
	var mean_flux := FmgUtils.median(flux_values)
	var max_flux := FmgUtils.max_of(Array(flux)) + FmgUtils.max_of(Array(confidence))
	var mean_area := FmgUtils.mean(Array(area))

	for cell_id in total:
		if heights[cell_id] < MapData.SEA_LEVEL:
			continue # no population in water
		var biome_id := biomes[cell_id]
		if biome_id < 0 or biome_id >= map.biomes.size():
			continue
		var score := float(map.biomes[biome_id].get("habitability", 0))
		if score == 0.0:
			continue # uninhabitable biomes

		if mean_flux != 0.0:
			score += FmgUtils.normalize_value(float(flux[cell_id] + confidence[cell_id]), mean_flux, max_flux) * 250.0
		score -= (float(heights[cell_id]) - 50.0) / 5.0 # low elevation is valued

		if types[cell_id] == 1:
			if rivers[cell_id] != 0:
				score += float(COAST_SCORES["estuary"])
			var opposite: Dictionary = features[feature_ids[haven[cell_id]]]
			if opposite.get("type", "") == "lake":
				score += float(COAST_SCORES.get(str(opposite.get("subtype", "")), 0))
			else:
				score += float(COAST_SCORES["ocean_coast"])
				if harbor[cell_id] == 1:
					score += float(COAST_SCORES["save_harbor"])

		suitability[cell_id] = int(score / 5.0)
		population[cell_id] = (score / 5.0) * float(area[cell_id]) / mean_area if score > 0.0 else 0.0

	cells["s"] = suitability
	cells["pop"] = population


## Towns and cities get their population from the cell they sit in (FMG Population.regenerate)
static func regenerate(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var suitability: PackedInt32Array = cells["s"]
	var burgs: Array = map.pack.get("burgs", [])
	for burg in burgs:
		var burg_id := int(burg.get("i", 0))
		if burg_id == 0 or burg.get("removed", false) or burg.get("lock", false):
			continue
		var cell_id := int(burg.get("cell", 0))
		if cell_id < 0 or cell_id >= suitability.size():
			continue
		var population := maxf(float(suitability[cell_id]) / 8.0 + float(burg_id) / 1000.0 + float(cell_id % 100) / 1000.0, 0.1)
		if burg.get("capital", false):
			population *= 1.3
		if burg.get("port", false):
			population *= 1.3
		burg["population"] = FmgUtils.rn(population * FmgRandom.gauss(2.0, 3.0, 0.6, 20.0, 3), 3)


## The map ruler and other measurements (FMG Measurers.createDefaultRuler)
static func create_default_ruler(map: MapData) -> void:
	var features: Array = map.pack["features"]
	var largest := -1
	for feature in features:
		if not feature.get("land", false):
			continue
		if largest == -1 or float(feature.get("area", 0)) > float(features[largest].get("area", 0)):
			largest = int(feature.get("i", -1))
	if largest < 0:
		return
	var largest_feature: Dictionary = features[largest]
	var vertices: PackedInt32Array = largest_feature.get("vertices", PackedInt32Array())
	var points: PackedVector2Array = map.pack["vertices"]["p"]
	var left := -1
	var right := -1
	var min_x := INF
	var max_x := -INF
	for vertex in vertices:
		var point := points[vertex]
		if point.x < min_x:
			min_x = point.x
			left = vertex
		if point.x > max_x:
			max_x = point.x
			right = vertex
	map.notes = [{"type": "Ruler", "points": PackedInt32Array([left, right])}]
