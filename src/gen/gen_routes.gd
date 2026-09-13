## Routes: land roads between burgs and sea routes between ports.
## Port of Fantasy Map Generator's `src/generators/routes-generator.ts` (Azgaar, MIT).
## The map is a graph of burgs: roads follow the Urquhart graph of the Delaunay triangulation,
## sea routes are the shortest navigable paths.
class_name GenRoutes
extends RefCounted

const MIN_PASSABLE_SEA_TEMP := -4
const ROUTE_TYPE_MODIFIERS := {"ocean": 1, "sea": 1, "gulf": 1, "lake": 3, "default": 1}
const MIN_NAVIGABLE_FLUX := 100


static func generate(map: MapData) -> void:
	var burgs: Array = map.pack.get("burgs", [])
	var points := PackedVector2Array()
	var burg_order := PackedInt32Array()
	for burg in burgs:
		var burg_id := int(burg.get("i", 0))
		if burg_id == 0 or burg.get("removed", false):
			continue
		points.append(Vector2(float(burg.get("x", 0.0)), float(burg.get("y", 0.0))))
		burg_order.append(burg_id)

	map.pack["routes"] = []
	if points.size() < 2:
		return

	var delaunay := FmgDelaunay.new(points)
	var halfedges := delaunay.halfedges
	var triangles := delaunay.triangles
	var removed := PackedByteArray()
	removed.resize(triangles.size())

	var score := func(a: int, b: int) -> float: return points[a].distance_squared_to(points[b])
	for e in range(0, triangles.size(), 3):
		var p0 := triangles[e]
		var p1 := triangles[e + 1]
		var p2 := triangles[e + 2]
		var p01: float = score.call(p0, p1)
		var p12: float = score.call(p1, p2)
		var p20: float = score.call(p2, p0)
		var edge := e if not (p20 > p01 and p20 > p12) and not (p12 > p01 and p12 > p20) else (e + 1 if p12 > p01 and p12 > p20 else e + 2)
		var opposite: int = halfedges[edge]
		removed[maxi(edge, opposite if opposite != -1 else edge)] = 1

	var land_routes: Array = []
	var sea_routes: Array = []
	var connections := {}

	for e in triangles.size():
		if halfedges[e] != -1 and e <= halfedges[e]:
			continue
		if removed[e] == 1:
			continue
		var from_id: int = burg_order[triangles[e]]
		var next_edge := (e - 2) if e % 3 == 2 else (e + 1)
		var to_id: int = burg_order[triangles[next_edge]]
		if from_id == to_id:
			continue
		var key := "%d-%d" % [mini(from_id, to_id), maxi(from_id, to_id)]
		if connections.has(key):
			continue
		connections[key] = true
		var route := _build_route(map, from_id, to_id, false)
		if not route.is_empty():
			land_routes.append(route)

	# sea routes: connect ports that have no road to each other
	var ports: Array = []
	for burg in burgs:
		if int(burg.get("i", 0)) != 0 and int(burg.get("port", 0)) != 0 and not burg.get("removed", false):
			ports.append(burg)
	for i in ports.size():
		for j in range(i + 1, ports.size()):
			var from_burg: Dictionary = ports[i]
			var to_burg: Dictionary = ports[j]
			if float(map.pack["cells"]["p"][int(from_burg["cell"])].distance_to(map.pack["cells"]["p"][int(to_burg["cell"])])) > 400.0:
				continue
			var route := _build_route(map, int(from_burg["i"]), int(to_burg["i"]), true)
			if route.is_empty():
				continue
			var already_connected := false
			for land_route in land_routes:
				if int(land_route.get("from", 0)) == int(from_burg["i"]) and int(land_route.get("to", 0)) == int(to_burg["i"]):
					already_connected = true
					break
			if already_connected:
				continue
			sea_routes.append(route)

	var routes: Array = []
	for route in land_routes + sea_routes:
		route["i"] = routes.size() + 1
		route["group"] = "roads" if route.get("type", "") == "land" else "searoutes"
		routes.append(route)
	map.pack["routes"] = routes


static func _build_route(map: MapData, from_id: int, to_id: int, sea: bool) -> Dictionary:
	var burgs: Array = map.pack.get("burgs", [])
	var start := int(burgs[from_id].get("cell", 0))
	var end := int(burgs[to_id].get("cell", 0))
	if sea:
		var from_haven := _haven_of(map, start)
		var to_haven := _haven_of(map, end)
		if from_haven < 0 or to_haven < 0:
			return {}
		start = from_haven
		end = to_haven
		if start == end:
			return {}

	var cells: Dictionary = map.pack["cells"]
	var neighbours: Array = cells["c"]
	var get_cost := func(current: int, next: int) -> float: return _water_cost(map, current, next) if sea else _land_cost(map, current, next)
	var is_exit := func(cell: int, _previous: int) -> bool: return cell == end
	var path: PackedInt32Array = FmgPath.find_path(start, is_exit, get_cost, func(cell: int) -> PackedInt32Array: return neighbours[cell])
	if path.is_empty():
		return {}
	var points := PackedVector2Array()
	for cell_id in path:
		points.append(cells["p"][cell_id])
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return {
		"from": from_id,
		"to": to_id,
		"cells": path,
		"points": points,
		"length": FmgUtils.rn(length, 2),
		"type": "sea" if sea else "land",
	}


static func _land_cost(map: MapData, _current: int, next: int) -> float:
	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var biomes: PackedInt32Array = cells["biome"]
	if heights[next] < MapData.SEA_LEVEL:
		return INF
	if biomes[next] < map.biomes.size() and float(map.biomes[biomes[next]].get("habitability", 0)) == 0.0:
		return INF # uninhabitable
	var habitability := 100.0
	if biomes[next] < map.biomes.size():
		habitability = float(map.biomes[biomes[next]].get("habitability", 100))
	var points: PackedVector2Array = cells["p"]
	var distance := points[_current].distance_squared_to(points[next])
	var multiplier := 1.0 + maxf(100.0 - habitability, 0.0) / 1000.0
	multiplier *= 1.0 + maxf(float(heights[next]) - 25.0, 25.0) / 25.0
	multiplier *= 0.5 if cells["r"][next] != 0 else 1.0
	multiplier *= 1.0 if cells["burg"][next] != 0 else 3.0
	return distance * multiplier


static func _water_cost(map: MapData, current: int, next: int) -> float:
	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var rivers: PackedInt32Array = cells["r"]
	var flux: PackedInt32Array = cells["fl"]
	var grid_reference: PackedInt32Array = cells["g"]
	var grid_temp: PackedInt32Array = map.grid["cells"]["temp"]
	var points: PackedVector2Array = cells["p"]
	var distance := points[current].distance_squared_to(points[next])

	if heights[next] >= MapData.SEA_LEVEL:
		if rivers[next] == 0 or flux[next] < MIN_NAVIGABLE_FLUX:
			return INF # only navigable rivers are passable from the water side
		return distance
	var temperature := float(grid_temp[grid_reference[next]])
	if temperature < float(MIN_PASSABLE_SEA_TEMP):
		return INF
	var feature: Dictionary = map.pack["features"][cells["f"][next]]
	var modifier := float(ROUTE_TYPE_MODIFIERS.get(str(feature.get("group", "default")), ROUTE_TYPE_MODIFIERS["default"]))
	if feature.get("type", "") == "lake":
		modifier = float(ROUTE_TYPE_MODIFIERS["lake"])
	return distance * modifier


static func _haven_of(map: MapData, cell_id: int) -> int:
	var haven: PackedInt32Array = map.pack["cells"]["haven"]
	if cell_id >= 0 and cell_id < haven.size() and haven[cell_id] != 0:
		return haven[cell_id]
	return -1
