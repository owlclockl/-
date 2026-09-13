## Climate: temperature and precipitation — port of `src/generators/temperature-generator.ts` and
## `src/generators/precipitation-generator.ts` (Azgaar, MIT).
class_name GenClimate
extends RefCounted

const SEA_LEVEL := 20

## precipitation modifier per 5° latitude band: x4 rising zone 0–5°, x2 wet summer / dry winter,
## x1 dry all year, x3 wet all year, x2 60–70°, x1 70–85°, x0.5 polar
const LATITUDE_MODIFIER := [4.0, 2.0, 2.0, 2.0, 1.0, 1.0, 2.0, 2.0, 2.0, 2.0, 3.0, 3.0, 2.0, 2.0, 1.0, 1.0, 1.0, 0.5]
const MAX_PASSABLE_ELEVATION := 85


# ------------------------------------------------------------------ temperature

## Temperature of every grid cell from its latitude and altitude (FMG Temperature.generate)
static func generate_temperature(map: MapData) -> void:
	var cells: Dictionary = map.grid["cells"]
	var cells_x: int = map.grid["cellsX"]
	var points: PackedVector2Array = map.grid["points"]
	var heights: PackedInt32Array = cells["h"]
	var temp := PackedInt32Array()
	temp.resize(points.size())

	var climate: Dictionary = map.options.get("climate", {}).get("temperature", {})
	var temperature_equator := float(climate.get("equator", 27.0))
	var temperature_north := float(climate.get("northPole", -20.0))
	var temperature_south := float(climate.get("southPole", -25.0))
	var tropics := [16.0, -20.0]
	var tropical_gradient := 0.15

	var temp_north_tropic := temperature_equator - tropics[0] * tropical_gradient
	var northern_gradient := (temp_north_tropic - temperature_north) / (90.0 - tropics[0])
	var temp_south_tropic := temperature_equator + tropics[1] * tropical_gradient
	var southern_gradient := (temp_south_tropic - temperature_south) / (90.0 + tropics[1])

	var exponent := float(map.options.get("units", {}).get("height", {}).get("exponent", 1.8))
	var geography: Dictionary = map.options["geography"]
	var coordinates: Dictionary = geography["coordinates"]
	var lat_n := float(coordinates.get("latN", 90.0))
	var lat_t := float(coordinates.get("latT", 180.0))
	var graph_height := float(map.options["graph"]["height"])

	for row_cell_id in range(0, points.size(), cells_x):
		var y := points[row_cell_id].y
		var row_latitude := lat_n - (y / graph_height) * lat_t # [90; -90]
		var sea_level_temp := _sea_level_temperature(row_latitude, temperature_equator, tropics, tropical_gradient, temp_north_tropic, northern_gradient, temp_south_tropic, southern_gradient)
		for cell_id in range(row_cell_id, mini(row_cell_id + cells_x, points.size())):
			var height := float(heights[cell_id])
			var altitude_drop := 0.0
			if height >= SEA_LEVEL:
				altitude_drop = FmgUtils.rn((pow(height - 18.0, exponent) / 1000.0) * 6.5)
			temp[cell_id] = int(FmgUtils.minmax(sea_level_temp - altitude_drop, -128.0, 127.0))
	cells["temp"] = temp


static func _sea_level_temperature(
	latitude: float, equator: float, tropics: Array, tropical_gradient: float,
	temp_north_tropic: float, northern_gradient: float, temp_south_tropic: float, southern_gradient: float
) -> float:
	if latitude <= tropics[0] and latitude >= tropics[1]:
		return equator - absf(latitude) * tropical_gradient
	if latitude > 0.0:
		return temp_north_tropic - (latitude - tropics[0]) * northern_gradient
	return temp_south_tropic + (latitude - tropics[1]) * southern_gradient


# ------------------------------------------------------------------ precipitation

## winds: rows the westerly/easterly winds enter through, and how many rows are driven from the
## North/South. Randomness-free, so the renderer can query it at any time (FMG Precipitation.getWinds)
static func get_winds(map: MapData) -> Dictionary:
	var cells: Dictionary = map.grid["cells"]
	var cells_x: int = map.grid["cellsX"]
	var cells_y: int = map.grid["cellsY"]
	var count: int = cells["i"].size()
	var westerly: Array = [] # [cellId, latitudeModifier, tier]
	var easterly: Array = []
	var northerly := 0
	var southerly := 0
	var coordinates: Dictionary = map.options["geography"]["coordinates"]
	var lat_n := float(coordinates.get("latN", 90.0))
	var lat_t := float(coordinates.get("latT", 180.0))
	var winds: Array = map.options.get("climate", {}).get("winds", [90, 210, 150, 100, 270, 300])

	var row_id := 0
	for cell_id in range(0, count, cells_x):
		var lat := lat_n - (float(row_id) / float(cells_y)) * lat_t
		var band := int((absf(lat) - 1.0) / 5.0)
		var lat_mod: float = LATITUDE_MODIFIER[FmgUtils.clamp_int(band, 0, LATITUDE_MODIFIER.size() - 1)]
		var tier := int(absf(lat - 89.0) / 30.0) # 30° tiers from 0 to 5, north to south
		var angle := float(winds[FmgUtils.clamp_int(tier, 0, winds.size() - 1)]) if not winds.is_empty() else 90.0

		if angle > 40.0 and angle < 140.0:
			westerly.append([cell_id, lat_mod, tier])
		if angle > 220.0 and angle < 320.0:
			easterly.append([cell_id + cells_x - 1, lat_mod, tier])
		if angle > 100.0 and angle < 260.0:
			northerly += 1
		if angle > 280.0 or angle < 80.0:
			southerly += 1
		row_id += 1

	return {"westerly": westerly, "easterly": easterly, "northerly": northerly, "southerly": southerly}


## Pass every wind over the cells it reaches, filling grid.cells.prec (FMG Precipitation.generate)
static func generate_precipitation(map: MapData) -> void:
	var cells: Dictionary = map.grid["cells"]
	var cells_x: int = map.grid["cellsX"]
	var cells_y: int = map.grid["cellsY"]
	var heights: PackedInt32Array = cells["h"]
	var temp: PackedInt32Array = cells["temp"]
	var prec := PackedInt32Array()
	prec.resize(heights.size())

	var cells_number_modifier := pow(float(map.points_desired()) / 10000.0, 0.25)
	var modifier := cells_number_modifier * (float(map.options.get("climate", {}).get("precipitation", 100.0)) / 100.0)

	var winds := get_winds(map)

	if not winds["westerly"].is_empty():
		_pass_wind(map, winds["westerly"], 120.0 * modifier, 1, cells_x)
	if not winds["easterly"].is_empty():
		_pass_wind(map, winds["easterly"], 120.0 * modifier, -1, cells_x)

	var northerly: int = winds["northerly"]
	var southerly: int = winds["southerly"]
	var vertical := southerly + northerly
	var coordinates: Dictionary = map.options["geography"]["coordinates"]
	var lat_t := float(coordinates.get("latT", 180.0))

	if northerly > 0 and vertical > 0:
		var band_n := int((absf(float(coordinates.get("latN", 90.0))) - 1.0) / 5.0)
		var lat_mod_n: float = FmgUtils.mean(LATITUDE_MODIFIER) if lat_t > 60.0 else LATITUDE_MODIFIER[FmgUtils.clamp_int(band_n, 0, LATITUDE_MODIFIER.size() - 1)]
		var sources: Array = []
		for i in cells_x:
			sources.append(i)
		_pass_wind(map, sources, (float(northerly) / float(vertical)) * 60.0 * modifier * lat_mod_n, cells_x, cells_y)

	if southerly > 0 and vertical > 0:
		var band_s := int((absf(float(coordinates.get("latS", -90.0))) - 1.0) / 5.0)
		var lat_mod_s: float = FmgUtils.mean(LATITUDE_MODIFIER) if lat_t > 60.0 else LATITUDE_MODIFIER[FmgUtils.clamp_int(band_s, 0, LATITUDE_MODIFIER.size() - 1)]
		var sources: Array = []
		for i in range(heights.size() - cells_x, heights.size()):
			sources.append(i)
		_pass_wind(map, sources, (float(southerly) / float(vertical)) * 60.0 * modifier * lat_mod_s, -cells_x, cells_y)

	cells["prec"] = prec


static func _precipitation(humidity: float, i: int, n: int, heights: PackedInt32Array, modifier: float) -> float:
	var normal_loss := maxf(humidity / (10.0 * modifier), 1.0)
	var diff := maxf(float(heights[i + n] - heights[i]), 0.0)
	var mod := pow(float(heights[i + n]) / 70.0, 2.0)
	return FmgUtils.minmax(normal_loss + diff * mod, 1.0, humidity)


static func _pass_wind(map: MapData, sources: Array, initial_max_prec: float, next: int, steps: int) -> void:
	var cells: Dictionary = map.grid["cells"]
	var heights: PackedInt32Array = cells["h"]
	var temp: PackedInt32Array = cells["temp"]
	var prec: PackedInt32Array = cells["prec"]
	var modifier := pow(float(map.points_desired()) / 10000.0, 0.25) * (float(map.options.get("climate", {}).get("precipitation", 100.0)) / 100.0)
	var max_prec := initial_max_prec

	for source in sources:
		var first := 0
		if source is Array:
			if int(source[0]) == 0:
				continue # legacy quirk: a band starting at cell 0 is skipped, fixing it changes every map
			max_prec = min(initial_max_prec * float(source[1]), 255.0)
			first = int(source[0])
		else:
			first = int(source)

		var humidity := max_prec - float(heights[first])
		if humidity <= 0.0:
			continue

		var current := first
		for _step in steps:
			if current + next < 0 or current + next >= heights.size():
				break
			if temp[current] < -5:
				current += next
				continue # no flux in permafrost

			if heights[current] < SEA_LEVEL:
				if heights[current + next] >= SEA_LEVEL:
					prec[current + next] += int(maxf(humidity / FmgRandom.rand_i(10, 20), 1.0)) # coastal precipitation
				else:
					humidity = min(humidity + 5.0 * modifier, max_prec) # wind gets more humid over water
					prec[current] += int(5.0 * modifier)
				current += next
				continue

			var is_passable := heights[current + next] <= MAX_PASSABLE_ELEVATION
			var precipitation := _precipitation(humidity, current, next, heights, modifier) if is_passable else humidity
			prec[current] += int(precipitation)
			var evaporation := 1.0 if precipitation > 1.5 else 0.0
			humidity = FmgUtils.minmax(humidity - precipitation + evaporation, 0.0, max_prec) if is_passable else 0.0
			current += next

	cells["prec"] = prec
