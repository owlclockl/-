## The packed graph: the second Voronoi diagram the map is actually drawn from.
## Port of Fantasy Map Generator's `src/generators/pack-generator.ts` (Azgaar, MIT).
class_name GenPack
extends RefCounted


## Build the packed graph from the grid (FMG Pack.generate)
static func generate(map: MapData) -> void:
	var grid_cells: Dictionary = map.grid["cells"]
	var points: PackedVector2Array = map.grid["points"]
	var features: Array = map.grid["features"]
	var spacing := float(map.grid.get("spacing", 1.0))
	var boundary: PackedVector2Array = map.grid["boundary"]
	var spacing2 := spacing * spacing

	var new_points := PackedVector2Array()
	var new_grid_cells := PackedInt32Array() # parent grid cell of every packed cell
	var new_heights := PackedInt32Array()

	var grid_heights: PackedInt32Array = grid_cells["h"]
	var grid_types: PackedInt32Array = grid_cells["t"]
	var grid_features: PackedInt32Array = grid_cells["f"]
	var grid_borders: PackedByteArray = grid_cells["b"]
	var grid_neighbours: Array = grid_cells["c"]

	for i in points.size():
		var height := grid_heights[i]
		var type := grid_types[i]

		if height < MapData.SEA_LEVEL and type != -1 and type != -2:
			continue # all deep ocean points are dropped
		if type == -2:
			var feature: Dictionary = features[grid_features[i]]
			if i % 4 == 0 or feature.get("type", "") == "lake":
				continue # non-coastal lake and deep-water points

		new_points.append(points[i])
		new_grid_cells.append(i)
		new_heights.append(height)

		# cells along the coast get an extra point, so the packed graph is finer there
		if type == 1 or type == -1:
			if grid_borders[i] == 1:
				continue # not for near-border cells
			for neighbour in grid_neighbours[i]:
				if i > neighbour:
					continue
				if grid_types[neighbour] != type:
					continue
				var dx := points[i].x - points[neighbour].x
				var dy := points[i].y - points[neighbour].y
				if dx * dx + dy * dy < spacing2:
					continue # too close to each other
				new_points.append(Vector2(
					FmgUtils.rn((points[i].x + points[neighbour].x) / 2.0, 1),
					FmgUtils.rn((points[i].y + points[neighbour].y) / 2.0, 1)
				))
				new_grid_cells.append(i)
				new_heights.append(height)

	var diagram := FmgVoronoi.calculate(new_points, boundary)

	map.pack = {
		"points": new_points,
		"vertices": {"p": diagram.vertices_p, "v": diagram.vertices_v, "c": diagram.vertices_c},
		"cells": {
			"p": new_points,
			"g": new_grid_cells,
			"h": new_heights,
			"v": diagram.cells_v,
			"c": diagram.cells_c,
			"b": diagram.cells_b,
			"i": _range(new_points.size()),
			"t": PackedInt32Array(),
			"f": PackedInt32Array(),
			"haven": PackedInt32Array(),
			"harbor": PackedByteArray(),
			"area": PackedInt32Array(),
			"fl": PackedInt32Array(),
			"conf": PackedInt32Array(),
			"s": PackedInt32Array(),
			"pop": PackedFloat32Array(),
			"r": PackedInt32Array(),
			"biome": PackedInt32Array(),
			"burg": PackedInt32Array(),
			"culture": PackedInt32Array(),
			"state": PackedInt32Array(),
			"religion": PackedInt32Array(),
			"province": PackedInt32Array(),
			"good": PackedInt32Array(),
		},
		"features": [],
		"rivers": [],
		"routes": [],
		"burgs": [],
		"states": [],
		"cultures": [],
		"religions": [],
		"provinces": [],
		"markers": [],
		"zones": [],
		"lakes": [],
	}
	calculate_areas(map)
	map.invalidate_caches()


## Area of every packed cell, capped like FMG's Uint16 areas
static func calculate_areas(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var vertices: PackedVector2Array = map.pack["vertices"]["p"]
	var cell_vertices: Array = cells["v"]
	var count: int = cells["p"].size()
	var areas := PackedInt32Array()
	areas.resize(count)
	for cell_id in count:
		var polygon := PackedVector2Array()
		for vertex in cell_vertices[cell_id]:
			if vertex >= 0 and vertex < vertices.size():
				polygon.append(vertices[vertex])
		areas[cell_id] = mini(int(absf(FmgUtils.polygon_area(polygon))), 65535)
	cells["area"] = areas


static func _range(count: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(count)
	for i in count:
		result[i] = i
	return result
