## Lakes: shoreline, height, temperature, flux and names.
## Port of Fantasy Map Generator's `src/generators/lakes.ts` (Azgaar, MIT).
class_name GenLakes
extends RefCounted

const LAKE_ELEVATION_DELTA := 0.1


## Cells of the lake that touch land (FMG Lakes.defineShoreline)
static func define_shoreline(map: MapData, feature: Dictionary) -> PackedInt32Array:
	var vertices_c: Array = map.pack["vertices"]["c"]
	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var feature_id: int = feature.get("i", 0)
	var unique := PackedInt32Array()
	for vertex in feature.get("vertices", PackedInt32Array()):
		if vertex < 0 or vertex >= vertices_c.size():
			continue
		for cell_id in vertices_c[vertex]:
			if heights[cell_id] >= MapData.SEA_LEVEL and not unique.has(cell_id):
				unique.append(cell_id)
	return unique


## Height of a lake: a bit below its lowest shore (FMG Lakes.getHeight)
static func get_height(map: MapData, feature: Dictionary) -> float:
	var heights: PackedInt32Array = map.pack["cells"]["h"]
	var shoreline: PackedInt32Array = feature.get("shoreline", PackedInt32Array())
	var minimum := 20.0
	for cell_id in shoreline:
		if cell_id < heights.size():
			minimum = minf(minimum, float(heights[cell_id]))
	return FmgUtils.rn(minimum - LAKE_ELEVATION_DELTA, 2)


## Name every lake after the culture of a shore cell (FMG Lakes.defineNames)
static func define_names(map: MapData) -> void:
	var cultures: PackedInt32Array = map.pack["cells"]["culture"]
	for feature in map.pack["features"]:
		if feature.get("type", "") != "lake":
			continue
		var shoreline: PackedInt32Array = feature.get("shoreline", PackedInt32Array())
		var land_cell: int = shoreline[0] if shoreline.size() > 0 else -1
		var culture: int = cultures[land_cell] if land_cell >= 0 and land_cell < cultures.size() else 0
		feature["name"] = GenNames.get_culture_name(culture)


## Temperature, flux and evaporation of every lake; returns the outlet cell of each lake
static func define_climate_data(map: MapData) -> PackedInt32Array:
	var cells: Dictionary = map.pack["cells"]
	var features: Array = map.pack["features"]
	var heights: PackedInt32Array = cells["h"]
	var grid_cells: PackedInt32Array = cells["g"]
	var grid_prec: PackedInt32Array = map.grid["cells"]["prec"]
	var grid_temp: PackedInt32Array = map.grid["cells"]["temp"]
	var exponent := float(map.options.get("units", {}).get("height", {}).get("exponent", 1.8))

	var lake_out_cells := PackedInt32Array()
	lake_out_cells.resize(heights.size())

	for feature in features:
		if feature.get("type", "") != "lake":
			continue
		var shoreline: PackedInt32Array = feature.get("shoreline", PackedInt32Array())

		var flux := 0
		for cell_id in shoreline:
			flux += grid_prec[grid_cells[cell_id]]
		feature["flux"] = flux

		if int(feature.get("cells", 0)) < 6:
			feature["temp"] = grid_temp[grid_cells[feature.get("firstCell", 0)]]
		else:
			var temps := []
			for cell_id in shoreline:
				temps.append(float(grid_temp[grid_cells[cell_id]]))
			feature["temp"] = FmgUtils.rn(FmgUtils.mean(temps), 1)

		var height := pow(maxf(float(feature.get("height", 20.0)) - 18.0, 0.0), exponent)
		var temperature := float(feature.get("temp", 20.0))
		var evaporation := ((700.0 * (temperature + 0.006 * height)) / 50.0 + 75.0) / (80.0 - temperature)
		feature["evaporation"] = FmgUtils.rn(evaporation * float(feature.get("cells", 0)))

		if feature.get("closed", false):
			continue # a lake in a closed depression has no outlet

		var lowest := shoreline[0] if shoreline.size() > 0 else 0
		for cell_id in shoreline:
			if heights[cell_id] < heights[lowest]:
				lowest = cell_id
		feature["outCell"] = lowest
		lake_out_cells[lowest] = feature.get("i", 0)

	return lake_out_cells


## Whether a lake sits in a deep depression with no way out (FMG Lakes.detectCloseLakes)
static func detect_close_lakes(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var neighbours: Array = cells["c"]
	var heights: PackedInt32Array = cells["h"]
	var features: Array = map.pack["features"]
	var feature_ids: PackedInt32Array = cells["f"]
	var elevation_limit := float(map.options.get("generation", {}).get("lakeElevationLimit", 80))

	for feature in features:
		if feature.get("type", "") != "lake":
			continue
		feature.erase("closed")
		var max_elevation := float(feature.get("height", 20.0)) + elevation_limit
		if max_elevation > 99.0:
			feature["closed"] = false
			continue

		var shoreline: PackedInt32Array = feature.get("shoreline", PackedInt32Array())
		if shoreline.is_empty():
			feature["closed"] = false
			continue
		var lowest := shoreline[0]
		for cell_id in shoreline:
			if heights[cell_id] < heights[lowest]:
				lowest = cell_id

		var is_deep := true
		var queue := PackedInt32Array([lowest])
		var checked := {}
		checked[lowest] = true
		while not queue.is_empty() and is_deep:
			var cell_id: int = queue[queue.size() - 1]
			queue.resize(queue.size() - 1)
			for neighbour in neighbours[cell_id]:
				if checked.has(neighbour):
					continue
				if float(heights[neighbour]) >= max_elevation:
					continue
				if heights[neighbour] < MapData.SEA_LEVEL:
					var neighbour_feature: Dictionary = features[feature_ids[neighbour]]
					if neighbour_feature.get("type", "") == "ocean" or float(feature.get("height", 0.0)) > float(neighbour_feature.get("height", 0.0)):
						is_deep = false
				checked[neighbour] = true
				queue.append(neighbour)
		feature["closed"] = is_deep


## Drop the data left over from a previous generation (FMG Lakes.cleanupLakeData)
static func cleanup_lake_data(map: MapData) -> void:
	var rivers: Array = map.pack.get("rivers", [])
	for feature in map.pack["features"]:
		if feature.get("type", "") != "lake":
			continue
		feature.erase("river")
		feature.erase("enteringFlux")
		feature.erase("outCell")
		feature.erase("closed")
		feature["height"] = FmgUtils.rn(float(feature.get("height", 20.0)), 3)

		var inlets: PackedInt32Array = feature.get("inlets", PackedInt32Array())
		if inlets.size() > 0:
			var kept := PackedInt32Array()
			for river_id in inlets:
				for river in rivers:
					if river.get("i", -1) == river_id:
						kept.append(river_id)
						break
			if kept.is_empty():
				feature.erase("inlets")
			else:
				feature["inlets"] = kept
		var outlet: int = feature.get("outlet", -1)
		if outlet != -1:
			var exists := false
			for river in rivers:
				if river.get("i", -1) == outlet:
					exists = true
					break
			if not exists:
				feature.erase("outlet")
