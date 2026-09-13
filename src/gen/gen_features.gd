## Features: islands, lakes and oceans, coastline distance fields, havens and harbours.
## Port of Fantasy Map Generator's `src/generators/features.ts` (Azgaar, MIT).
class_name GenFeatures
extends RefCounted

const SEA_LEVEL := 20

const DEEPER_LAND := 3
const LANDLOCKED := 2
const LAND_COAST := 1
const UNMARKED := 0
const WATER_COAST := -1
const DEEP_WATER := -2

## feature groups, keyed by the group name (FMG Feature.defineGroups)
const CONTINENT_MIN_SIZE := 10.0 # % of the map cells
const ISLAND_MIN_SIZE := 0.1
const SEA_MIN_SIZE := 0.1
const OCEAN_MIN_SIZE := 4.0


# ------------------------------------------------------------------ grid markup

## Mark grid features (oceans, lakes, islands) and calculate the distance field (FMG markupGrid)
static func markup_grid(map: MapData) -> void:
	var cells: Dictionary = map.grid["cells"]
	var heights: PackedInt32Array = cells["h"]
	var neighbours: Array = cells["c"]
	var border_cells: PackedByteArray = cells["b"]
	var count := heights.size()

	var distance_field := PackedInt32Array()
	distance_field.resize(count)
	var feature_ids := PackedInt32Array()
	feature_ids.resize(count)
	var features: Array = []

	var queue := PackedInt32Array([0])
	var feature_id := 1
	while queue[0] != -1:
		var first_cell := queue[0]
		feature_ids[first_cell] = feature_id
		var land := heights[first_cell] >= SEA_LEVEL
		var border := false

		while not queue.is_empty():
			var cell_id: int = queue[queue.size() - 1]
			queue.resize(queue.size() - 1)
			if not border and border_cells[cell_id] == 1:
				border = true
			for neighbour in neighbours[cell_id]:
				var neighbour_is_land := heights[neighbour] >= SEA_LEVEL
				if land == neighbour_is_land and feature_ids[neighbour] == UNMARKED:
					feature_ids[neighbour] = feature_id
					queue.append(neighbour)
				elif land and not neighbour_is_land:
					distance_field[cell_id] = LAND_COAST
					distance_field[neighbour] = WATER_COAST

		var type := "island" if land else ("ocean" if border else "lake")
		features.append({"i": feature_id, "land": land, "border": border, "type": type})

		# find the next unmarked cell
		queue = PackedInt32Array([-1])
		for i in count:
			if feature_ids[i] == UNMARKED:
				queue[0] = i
				break
		feature_id += 1

	# mark up the deep ocean
	distance_field = markup_field(distance_field, neighbours, DEEP_WATER, -1, -10)
	cells["t"] = distance_field
	cells["f"] = feature_ids
	features.insert(0, {"i": 0, "land": false, "border": false, "type": ""})
	map.grid["features"] = features


## Walk a distance value through the unmarked cells until nothing new is marked (FMG markup)
## Packed arrays are value types in GDScript, so the caller has to take the returned array back.
static func markup_field(distance_field: PackedInt32Array, neighbours: Array, start: int, increment: int, limit := 127) -> PackedInt32Array:
	var distance := start
	var marked := INF
	while marked > 0.0 and distance != limit:
		marked = 0.0
		var previous_distance := distance - increment
		for cell_id in neighbours.size():
			if distance_field[cell_id] != previous_distance:
				continue
			for neighbour in neighbours[cell_id]:
				if distance_field[neighbour] != UNMARKED:
					continue
				distance_field[neighbour] = distance
				marked += 1.0
		distance += increment
	return distance_field


# ------------------------------------------------------------------ pack markup

## Mark pack features and calculate havens, harbours and the pack distance field (FMG markupPack)
static func markup_pack(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var features: Array = map.pack["features"]
	var vertices: Dictionary = map.pack["vertices"]
	var neighbours: Array = cells["c"]
	var border_cells: PackedByteArray = cells["b"]
	var heights: PackedInt32Array = cells["h"]
	var count := heights.size()

	var distance_field := PackedInt32Array()
	distance_field.resize(count)
	var feature_ids := PackedInt32Array()
	feature_ids.resize(count)
	var haven := PackedInt32Array()
	haven.resize(count)
	var harbor := PackedByteArray()
	harbor.resize(count)

	var queue := PackedInt32Array([0])
	var feature_id := 1
	while queue[0] != -1:
		var first_cell := queue[0]
		feature_ids[first_cell] = feature_id
		var land := heights[first_cell] >= SEA_LEVEL
		var border := border_cells[first_cell] == 1
		var total_cells := 1

		while not queue.is_empty():
			var cell_id: int = queue[queue.size() - 1]
			queue.resize(queue.size() - 1)
			if border_cells[cell_id] == 1:
				border = true
			for neighbour in neighbours[cell_id]:
				var neighbour_is_land := heights[neighbour] >= SEA_LEVEL
				if land and not neighbour_is_land:
					distance_field[cell_id] = LAND_COAST
					distance_field[neighbour] = WATER_COAST
					if haven[cell_id] == 0:
						var haven_data := _define_haven(cell_id, neighbours, cells)
						haven[cell_id] = int(haven_data.get("haven", 0))
						harbor[cell_id] = int(haven_data.get("harbor", 0))
				elif land and neighbour_is_land:
					if distance_field[neighbour] == UNMARKED and distance_field[cell_id] == LAND_COAST:
						distance_field[neighbour] = LANDLOCKED
					elif distance_field[cell_id] == UNMARKED and distance_field[neighbour] == LAND_COAST:
						distance_field[cell_id] = LANDLOCKED

				if feature_ids[neighbour] == 0 and land == neighbour_is_land:
					queue.append(neighbour)
					feature_ids[neighbour] = feature_id
					total_cells += 1
		var type := "island" if land else ("ocean" if border else "lake")
		var feature := _add_feature(map, type, land, border, feature_id, first_cell, total_cells, feature_ids, neighbours, border_cells, vertices)
		features.append(feature)
		feature_id += 1

		queue = PackedInt32Array([-1])
		for i in count:
			if feature_ids[i] == 0:
				queue[0] = i
				break

	distance_field = markup_field(distance_field, neighbours, DEEPER_LAND, 1)
	distance_field = markup_field(distance_field, neighbours, DEEP_WATER, -1, -10)

	cells["t"] = distance_field
	cells["f"] = feature_ids
	cells["haven"] = haven
	cells["harbor"] = harbor
	features.insert(0, {"i": 0, "type": "", "land": false, "border": false, "cells": 0, "name": ""})
	map.pack["features"] = features


static func _define_haven(cell_id: int, neighbours: Array, cells: Dictionary) -> Dictionary:
	var points: PackedVector2Array = cells["p"]
	var heights: PackedInt32Array = cells["h"]
	var water_cells := PackedInt32Array()
	for neighbour in neighbours[cell_id]:
		if heights[neighbour] < SEA_LEVEL:
			water_cells.append(neighbour)
	if water_cells.is_empty():
		return {"haven": 0, "harbor": 0}
	var closest := water_cells[0]
	var min_distance := INF
	for water_cell in water_cells:
		var distance := points[cell_id].distance_squared_to(points[water_cell])
		if distance < min_distance:
			min_distance = distance
			closest = water_cell
	return {"haven": closest, "harbor": water_cells.size()}


static func _add_feature(
	map: MapData, type: String, land: bool, border: bool, feature_id: int, first_cell: int,
	total_cells: int, feature_ids: PackedInt32Array, neighbours: Array, border_cells: PackedByteArray, vertices: Dictionary
) -> Dictionary:
	var start_cell := first_cell
	var feature_vertices := PackedInt32Array()

	if type != "ocean":
		var of_same_type := func(cell_id: int) -> bool: return feature_ids[cell_id] == feature_id
		start_cell = _find_on_border_cell(first_cell, feature_ids, feature_id, neighbours, border_cells)
		var cells_vertices: Array = map.pack["cells"]["v"]
		var starting_vertex := -1
		for vertex in cells_vertices[start_cell]:
			var cells_in_vertex: PackedInt32Array = vertices["c"][vertex]
			for cell in cells_in_vertex:
				if not of_same_type.call(cell):
					starting_vertex = vertex
					break
			if starting_vertex >= 0:
				break
		if starting_vertex >= 0:
			feature_vertices = FmgPath.connect_vertices(vertices["c"], vertices["v"], starting_vertex, of_same_type, false)

	var points := PackedVector2Array()
	var vertices_points: PackedVector2Array = map.pack["vertices"]["p"]
	for vertex in feature_vertices:
		if vertex >= 0 and vertex < vertices_points.size():
			points.append(vertices_points[vertex])
	var clipped := FmgPath.clip_polygon(points, map.width(), map.height())
	var area := absf(FmgUtils.rn(FmgUtils.polygon_area(clipped)))

	var feature := {
		"i": feature_id,
		"type": type,
		"land": land,
		"border": border,
		"cells": total_cells,
		"firstCell": start_cell,
		"vertices": feature_vertices,
		"area": area,
		"shoreline": PackedInt32Array(),
		"height": 0,
		"temp": 0,
		"flux": 0,
		"evaporation": 0,
		"name": "",
	}

	if type == "lake":
		if FmgUtils.polygon_area(points) > 0.0:
			var reversed := PackedInt32Array()
			for i in range(feature_vertices.size() - 1, -1, -1):
				reversed.append(feature_vertices[i])
			feature["vertices"] = reversed
		feature["shoreline"] = GenLakes.define_shoreline(map, feature)
		feature["height"] = GenLakes.get_height(map, feature)

	return feature


static func _find_on_border_cell(first_cell: int, feature_ids: PackedInt32Array, feature_id: int, neighbours: Array, border_cells: PackedByteArray) -> int:
	var is_on_border := func(cell_id: int) -> bool:
		if border_cells[cell_id] == 1:
			return true
		for neighbour in neighbours[cell_id]:
			if feature_ids[neighbour] != feature_id:
				return true
		return false

	if is_on_border.call(first_cell):
		return first_cell
	for cell_id in feature_ids.size():
		if feature_ids[cell_id] == feature_id and is_on_border.call(cell_id):
			return cell_id
	return first_cell


# ------------------------------------------------------------------ feature groups

## Decide which feature is a continent, which is an island and so on (FMG defineGroups)
static func define_groups(map: MapData) -> void:
	var features: Array = map.pack["features"]
	var grid_cells_number: int = map.grid["cells"]["h"].size()
	var ocean_min_size := grid_cells_number / 25.0
	var sea_min_size := grid_cells_number / 1000.0
	var continent_min_size := grid_cells_number / 10.0
	var island_min_size := grid_cells_number / 1000.0

	var land_features: Array = []
	for feature in features:
		feature["group"] = ""

		var type: String = feature.get("type", "")
		if type == "ocean":
			feature["group"] = "ocean"
			continue
		if type == "lake":
			feature["group"] = "freshwater" if _is_freshwater_lake(feature) else "salt"
			continue
		if not feature.get("land", false):
			continue
		var height := GenLakes.get_height(map, feature)
		feature["height"] = height
		if feature["area"] > continent_min_size * 1.5 and height > 40.0:
			feature["group"] = "continent"
		elif feature["area"] > island_min_size:
			feature["group"] = "island"
		elif feature["area"] > sea_min_size:
			feature["group"] = "isle"
		else:
			feature["group"] = "islet"
		land_features.append(feature)



static func _is_freshwater_lake(feature: Dictionary) -> bool:
	return feature.get("height", 0) > SEA_LEVEL or float(feature.get("area", 0)) < 1000.0


# ------------------------------------------------------------------ helpers

static func is_land_cell(map: MapData, cell_id: int) -> bool:
	return map.pack["cells"]["h"][cell_id] >= SEA_LEVEL


static func feature_of(map: MapData, cell_id: int) -> Dictionary:
	var features: Array = map.pack["features"]
	var feature_id: int = map.pack["cells"]["f"][cell_id]
	if feature_id < 0 or feature_id >= features.size():
		return {}
	return features[feature_id]
