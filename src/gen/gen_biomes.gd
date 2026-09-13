## Biomes: climate zones of every packed cell.
## Port of Fantasy Map Generator's `src/generators/biomes-generator.ts` (Azgaar, MIT).
## The default biome list is loaded from `res://data/biomes.json`, extracted from the web app.
class_name GenBiomes
extends RefCounted

const MIN_LAND_HEIGHT := 20

## hot ↔ cold [>19°C; <−4°C]; dry ↔ wet (FMG biomesMatrix, rows = moisture band)
const BIOMES_MATRIX: Array = [
	[1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 10],
	[3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 9, 9, 9, 9, 10, 10, 10],
	[5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 9, 9, 9, 9, 9, 10, 10, 10],
	[5, 6, 6, 6, 6, 6, 6, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 10, 10, 10],
	[7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 10, 10],
]


## Load the default biome list (names, colours, habitability, costs) from data/biomes.json
static func get_default() -> Array:
	var biomes: Array = FmgUtils.load_json_array("res://data/biomes.json")
	if biomes.is_empty():
		push_warning("GenBiomes: data/biomes.json is missing, is the data folder imported?")
	return biomes


static func generate(map: MapData) -> void:
	map.biomes = get_default()
	define(map)


## Assign the biome of every packed cell (FMG Biomes.define)
static func define(map: MapData) -> void:
	if map.biomes.is_empty():
		map.biomes = get_default()

	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var neighbours: Array = cells["c"]
	var grid_reference: PackedInt32Array = cells["g"]
	var flux: PackedInt32Array = cells["fl"]
	var rivers: PackedInt32Array = cells["r"]
	var grid_prec: PackedInt32Array = map.grid["cells"]["prec"]
	var grid_temp: PackedInt32Array = map.grid["cells"]["temp"]

	var biomes := PackedInt32Array()
	biomes.resize(heights.size())

	for cell_id in heights.size():
		var height := heights[cell_id]
		var moisture := 0.0
		if height >= MIN_LAND_HEIGHT:
			moisture = _calculate_moisture(cell_id, neighbours, heights, grid_reference, grid_prec, flux, rivers)
		var temperature := float(grid_temp[grid_reference[cell_id]])
		biomes[cell_id] = get_id(moisture, temperature, float(height), rivers[cell_id] != 0)

	cells["biome"] = biomes
	map.invalidate_caches()


## 4 + the mean precipitation of the cell itself and of its land neighbours (FMG calculateMoisture)
static func _calculate_moisture(
	cell_id: int, neighbours: Array, heights: PackedInt32Array, grid_reference: PackedInt32Array,
	grid_prec: PackedInt32Array, flux: PackedInt32Array, rivers: PackedInt32Array
) -> float:
	var moisture := float(grid_prec[grid_reference[cell_id]])
	if rivers[cell_id] != 0:
		moisture += maxf(float(flux[cell_id]) / 10.0, 2.0)

	var values: Array = [moisture]
	for neighbour in neighbours[cell_id]:
		if heights[neighbour] >= MIN_LAND_HEIGHT:
			values.append(float(grid_prec[grid_reference[neighbour]]))
	return FmgUtils.rn(4.0 + FmgUtils.mean(values))


static func get_id(moisture: float, temperature: float, height: float, has_river: bool) -> int:
	if height < MIN_LAND_HEIGHT:
		return 0 # all water cells: marine biome
	if temperature < -5.0:
		return 11 # too cold: permafrost
	if temperature >= 25.0 and not has_river and moisture < 8.0:
		return 1 # too hot and dry: hot desert
	if is_wetland(moisture, temperature, height):
		return 12

	var moisture_band := mini(int(moisture / 5.0), 4)
	var temperature_band := mini(maxi(int(20.0 - temperature), 0), 25)
	return int(BIOMES_MATRIX[moisture_band][temperature_band])


static func is_wetland(moisture: float, temperature: float, height: float) -> bool:
	if temperature <= -2.0:
		return false # too cold
	if moisture > 40.0 and height < 25.0:
		return true # near the coast
	if moisture > 24.0 and height > 24.0 and height < 60.0:
		return true # off the coast
	return false


static func biome_of(map: MapData, cell_id: int) -> Dictionary:
	var biome_id: int = map.pack["cells"]["biome"][cell_id] if map.pack["cells"]["biome"].size() > cell_id else 0
	if biome_id < 0 or biome_id >= map.biomes.size():
		return {}
	return map.biomes[biome_id]
