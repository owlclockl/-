## The generated world: options, grid graph, packed graph and all generated entities.
##
## Mirrors Fantasy Map Generator's global `options` / `grid` / `pack` objects, but as one object so
## maps can be generated, saved, loaded and compared without global state.
##
## Grid graph (`grid`): the high-resolution jittered Voronoi graph used for climate and height.
## Packed graph (`pack`): the map the user actually sees — cells, features, cultures, states, burgs,
## rivers, routes, markers. Every pack cell points back at its grid cell through `cells.g`.
class_name MapData
extends RefCounted

const SEA_LEVEL := 20

var seed_text := "123456"
var options: Dictionary = {}
var grid: Dictionary = {}
var pack: Dictionary = {}
var biomes: Array = []
var notes: Array = []

# caches (not stored in saved maps)
var _pack_tree: FmgQuadTree = null
var _grid_tree: FmgQuadTree = null
var _pack_polygons: Array = []
var _grid_polygons: Array = []


func width() -> float:
	return float(options.get("graph", {}).get("width", 1000.0))


func height() -> float:
	return float(options.get("graph", {}).get("height", 600.0))


func points_desired() -> int:
	return int(options.get("graph", {}).get("points", 10000))


# ---------------------------------------------------------------- grid graph access

func grid_cells() -> Dictionary:
	return grid["cells"]


func grid_h() -> PackedInt32Array:
	return grid["cells"]["h"]


func grid_points() -> PackedVector2Array:
	return grid["points"]


func grid_cell_count() -> int:
	return grid["points"].size()


func is_land_grid(cell_id: int) -> bool:
	return grid["cells"]["h"][cell_id] >= SEA_LEVEL


func grid_polygon(cell_id: int) -> PackedVector2Array:
	if _grid_polygons.is_empty():
		_build_polygons_cache()
	if cell_id < 0 or cell_id >= _grid_polygons.size():
		return PackedVector2Array()
	return _grid_polygons[cell_id]


func find_grid_cell(x: float, y: float) -> int:
	# the grid keeps its cells on a regular square lattice, so the lookup is arithmetic (as in FMG)
	var spacing := float(grid.get("spacing", 1.0))
	var cells_x := int(grid.get("cellsX", 1))
	var cells_y := int(grid.get("cellsY", 1))
	var cy := int(floor(min(y / spacing, float(cells_y - 1))))
	var cx := int(floor(min(x / spacing, float(cells_x - 1))))
	var id := cy * cells_x + cx
	return FmgUtils.clamp_int(id, 0, max(0, grid_cell_count() - 1))


# ---------------------------------------------------------------- packed graph access

func pack_cells() -> Dictionary:
	return pack["cells"]


func pack_h() -> PackedInt32Array:
	return pack["cells"]["h"]


func pack_points() -> PackedVector2Array:
	return pack["cells"]["p"]


func pack_cell_count() -> int:
	return pack["cells"]["p"].size()


func is_land(cell_id: int) -> bool:
	return pack["cells"]["h"][cell_id] >= SEA_LEVEL


func is_water(cell_id: int) -> bool:
	return pack["cells"]["h"][cell_id] < SEA_LEVEL


func pack_neighbours(cell_id: int) -> PackedInt32Array:
	return pack["cells"]["c"][cell_id]


func pack_polygon(cell_id: int) -> PackedVector2Array:
	if _pack_polygons.is_empty():
		_build_polygons_cache()
	if cell_id < 0 or cell_id >= _pack_polygons.size():
		return PackedVector2Array()
	return _pack_polygons[cell_id]


func pack_polygon_ids(cell_id: int) -> PackedInt32Array:
	var cells: Dictionary = pack["cells"]
	var v: Array = cells.get("v", [])
	if cell_id < 0 or cell_id >= v.size():
		return PackedInt32Array()
	var ids: PackedInt32Array = v[cell_id]
	return ids if ids != null else PackedInt32Array()


## nearest pack cell to a point, -1 when there is none within `radius`
func find_pack_cell(x: float, y: float, radius: float = INF) -> int:
	if _pack_tree == null:
		_build_pack_tree()
	return _pack_tree.find(x, y, radius)


func find_pack_cells(x: float, y: float, radius: float) -> PackedInt32Array:
	if _pack_tree == null:
		_build_pack_tree()
	return _pack_tree.find_all(x, y, radius)


func pack_features() -> Array:
	return pack["features"]


func feature_of_cell(cell_id: int) -> Dictionary:
	var cells: Dictionary = pack["cells"]
	var feature_id: int = cells["f"][cell_id]
	var features: Array = pack["features"]
	if feature_id < 0 or feature_id >= features.size():
		return {}
	return features[feature_id]


func _build_pack_tree() -> void:
	var cells: Dictionary = pack["cells"]
	var points: PackedVector2Array = cells["p"]
	_pack_tree = FmgQuadTree.new(max(1.0, float(grid.get("spacing", 8.0))))
	for i in points.size():
		_pack_tree.add(points[i], i)


func _build_polygons_cache() -> void:
	_pack_polygons.clear()
	var cells: Dictionary = pack.get("cells", {})
	if cells.has("v") and pack.has("vertices"):
		var vertices: PackedVector2Array = pack["vertices"]["p"]
		var v: Array = cells["v"]
		for cell_id in v.size():
			var ids: PackedInt32Array = v[cell_id]
			var polygon := PackedVector2Array()
			if ids != null:
				for vertex in ids:
					if vertex >= 0 and vertex < vertices.size():
						polygon.append(vertices[vertex])
			_pack_polygons.append(polygon)
	_grid_polygons.clear()
	var grid_cells: Dictionary = grid.get("cells", {})
	if grid_cells.has("v") and grid.has("vertices"):
		var g_vertices: PackedVector2Array = grid["vertices"]["p"]
		var gv: Array = grid_cells["v"]
		for cell_id in gv.size():
			var ids: PackedInt32Array = gv[cell_id]
			var polygon := PackedVector2Array()
			if ids != null:
				for vertex in ids:
					if vertex >= 0 and vertex < g_vertices.size():
						polygon.append(g_vertices[vertex])
			_grid_polygons.append(polygon)


## Outline rings of a group of pack cells (a state, a culture, a lake...) — used by the renderer
## and by the feature/settlement naming code.
func build_outline(cell_ids: PackedInt32Array, only_land := false) -> Array:
	if cell_ids.is_empty():
		return []
	if _pack_polygons.is_empty():
		_build_polygons_cache()
	var cells: Dictionary = pack["cells"]
	var vertices: PackedVector2Array = pack["vertices"]["p"]
	var v: Array = cells["v"]
	var polygons: Array = []
	for cell_id in cell_ids:
		if only_land and is_water(cell_id):
			continue
		if cell_id < 0 or cell_id >= v.size():
			continue
		var ids: PackedInt32Array = v[cell_id]
		if ids != null and ids.size() >= 3:
			polygons.append(ids)
	return FmgUtils.build_boundary_rings(polygons, vertices)


# ---------------------------------------------------------------- statistics helpers

func states() -> Array:
	return pack.get("states", [])


func burgs() -> Array:
	return pack.get("burgs", [])


func cultures() -> Array:
	return pack.get("cultures", [])


func religions() -> Array:
	return pack.get("religions", [])


func provinces() -> Array:
	return pack.get("provinces", [])


func rivers() -> Array:
	return pack.get("rivers", [])


func routes() -> Array:
	return pack.get("routes", [])


func markers() -> Array:
	return pack.get("markers", [])


## cell count, area, rural and urban population of a state (FMG collectStatistics)
func state_statistics(state_id: int) -> Dictionary:
	var cells: Dictionary = pack["cells"]
	var states_array: Array = states()
	if state_id < 0 or state_id >= states_array.size():
		return {}
	var result := {"cells": 0, "area": 0.0, "burgs": 0, "rural": 0.0, "urban": 0.0, "name": states_array[state_id].get("name", "")}
	var h: PackedInt32Array = cells["h"]
	var area: PackedInt32Array = cells["area"]
	var pop: PackedFloat32Array = cells["pop"]
	var state_ids: PackedInt32Array = cells["state"]
	var burg_ids: PackedInt32Array = cells["burg"]
	var burgs_array: Array = burgs()
	for i in state_ids.size():
		if h[i] < SEA_LEVEL or state_ids[i] != state_id:
			continue
		result["cells"] = int(result["cells"]) + 1
		result["area"] = float(result["area"]) + float(area[i])
		result["rural"] = float(result["rural"]) + float(pop[i])
		var burg_id: int = burg_ids[i]
		if burg_id > 0 and burg_id < burgs_array.size():
			result["burgs"] = int(result["burgs"]) + 1
			result["urban"] = float(result["urban"]) + float(burgs_array[burg_id].get("population", 0.0))
	return result


func invalidate_caches() -> void:
	_pack_tree = null
	_grid_tree = null
	_pack_polygons.clear()
	_grid_polygons.clear()
