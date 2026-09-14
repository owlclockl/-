## Graph helpers: vertex chains, path finding, poles of inaccessibility and polygon clipping.
## Ports of `connectVertices`, `findPath` and `getPolesOfInaccessibility` from Fantasy Map
## Generator's `src/utils/pathUtils.ts` (Azgaar, MIT), plus Sutherland–Hodgman clipping that
## replaces the `lineclip` dependency of `src/utils/commonUtils.ts`.
class_name FmgPath
extends RefCounted


## Chain of vertices that walks around cells of the same type through the Voronoi vertex graph.
## `of_same_type` receives a cell id, `vertices_c[vertex]` holds the cells meeting in a vertex.
static func connect_vertices(vertices_c: Array, vertices_v: Array, starting_vertex: int, of_same_type: Callable, close_ring := false) -> PackedInt32Array:
	var chain := PackedInt32Array()
	var max_iterations := vertices_c.size()
	var next_vertex := starting_vertex
	var i := 0
	while true:
		var previous := -1
		if not chain.is_empty():
			previous = chain[chain.size() - 1]
		var current := next_vertex
		chain.append(current)

		var neighbours: PackedInt32Array = vertices_c[current]
		var c1: bool = bool(of_same_type.call(neighbours[0])) if neighbours.size() > 0 else false
		var c2: bool = bool(of_same_type.call(neighbours[1])) if neighbours.size() > 1 else false
		var c3: bool = bool(of_same_type.call(neighbours[2])) if neighbours.size() > 2 else false
		var v: PackedInt32Array = vertices_v[current]
		var v1 := v[0] if v.size() > 0 else -1
		var v2 := v[1] if v.size() > 1 else -1
		var v3 := v[2] if v.size() > 2 else -1

		if v1 != previous and c1 != c2:
			next_vertex = v1
		elif v2 != previous and c2 != c3:
			next_vertex = v2
		elif v3 != previous and c1 != c3:
			next_vertex = v3

		# a hull half-edge has no opposite triangle, so its vertex id is -1
		if next_vertex < 0 or next_vertex >= vertices_c.size():
			push_warning("connect_vertices: the next vertex is out of bounds")
			break
		if next_vertex == current:
			push_warning("connect_vertices: the next vertex was not found")
			break

		i += 1
		if next_vertex == starting_vertex:
			break
		if i > max_iterations:
			push_warning("connect_vertices: maximum iterations reached")
			break

	if close_ring:
		chain.append(starting_vertex)
	return chain


## Shortest path between two cells, cost-based (FMG findPath). Returns [] when there is none.
## is_exit(cell, current) -> bool, get_cost(current, next) -> float (INFINITY blocks the step).
static func find_path(start: int, is_exit: Callable, get_cost: Callable, neighbours_of: Callable) -> PackedInt32Array:
	if is_exit.call(start, -1):
		return PackedInt32Array()
	var costs := {start: 0.0}
	var previous := {start: -1}
	var processed := {}
	var queue: Array = [[0.0, start]] # a binary heap would be faster, this keeps the port simple

	while not queue.is_empty():
		queue.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		var entry: Array = queue.pop_front()
		var cell: int = entry[1]
		if processed.has(cell):
			continue
		processed[cell] = true
		if cell != start and is_exit.call(cell, previous.get(cell, -1)):
			var path := PackedInt32Array([cell])
			var step: int = previous[cell]
			while step != -1:
				path.append(step)
				step = previous[step]
			path.reverse()
			return path

		var neighbours: PackedInt32Array = neighbours_of.call(cell)
		for next_cell in neighbours:
			if processed.has(next_cell):
				continue
			var cost := float(get_cost.call(cell, next_cell))
			if is_inf(cost):
				continue
			var total: float = float(costs[cell]) + cost
			if not costs.has(next_cell) or total < float(costs[next_cell]):
				costs[next_cell] = total
				previous[next_cell] = cell
				queue.append([total, next_cell])
	return PackedInt32Array()


## Pole of inaccessibility: the cell of `cells` farthest from any cell outside the set.
## Replaces FMG's polylabel-based `getPolesOfInaccessibility` with a cheaper distance field.
static func get_poles_of_inaccessibility(cells: PackedInt32Array, neighbours_of: Callable) -> Dictionary:
	var inside := {}
	for cell in cells:
		inside[cell] = true
	if inside.is_empty():
		return {}
	var distance := {}
	var queue := PackedInt32Array()
	for cell in cells:
		var is_border := false
		for neighbour in neighbours_of.call(cell):
			if not inside.has(neighbour):
				is_border = true
				break
		if is_border:
			distance[cell] = 0
			queue.append(cell)
	var best_cell: int = cells[0]
	var best_distance := 0
	var head := 0
	while head < queue.size():
		var cell: int = queue[head]
		head += 1
		var d: int = distance[cell]
		if d > best_distance:
			best_distance = d
			best_cell = cell
		for neighbour in neighbours_of.call(cell):
			if inside.has(neighbour) and not distance.has(neighbour):
				distance[neighbour] = d + 1
				queue.append(neighbour)

	return {"cell": best_cell, "distance": best_distance}


## Sutherland–Hodgman clipping of a polygon to the map rectangle (the `lineclip` dependency)
static func clip_polygon(points: PackedVector2Array, width: float, height: float) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var output := points.duplicate()
	# left, right, top, bottom
	for edge in 4:
		if output.is_empty():
			return PackedVector2Array()
		var input := output
		output = PackedVector2Array()
		for i in input.size():
			var current := input[i]
			var previous := input[(i - 1 + input.size()) % input.size()]
			var current_inside := _inside_edge(current, edge, width, height)
			var previous_inside := _inside_edge(previous, edge, width, height)
			if current_inside:
				if not previous_inside:
					output.append(_edge_intersection(previous, current, edge, width, height))
				output.append(current)
			elif previous_inside:
				output.append(_edge_intersection(previous, current, edge, width, height))
	return output


## clipPoly with the "secure" flag: boundary points are duplicated, so a spline stays on the map edge
static func clip_poly(points: PackedVector2Array, width: float, height: float, secure := false) -> PackedVector2Array:
	var clipped := clip_polygon(points, width, height)
	if not secure or clipped.is_empty():
		return clipped
	var secured := PackedVector2Array()
	for point in clipped:
		secured.append(point)
		if point.x == 0.0 or point.x == width or point.y == 0.0 or point.y == height:
			secured.append(point)
			secured.append(point)
	return secured


static func _inside_edge(point: Vector2, edge: int, width: float, height: float) -> bool:
	match edge:
		0:
			return point.x >= 0.0
		1:
			return point.x <= width
		2:
			return point.y >= 0.0
		_:
			return point.y <= height


static func _edge_intersection(a: Vector2, b: Vector2, edge: int, width: float, height: float) -> Vector2:
	match edge:
		0, 1:
			var x := 0.0 if edge == 0 else width
			var t := 0.0 if b.x == a.x else (x - a.x) / (b.x - a.x)
			return Vector2(x, a.y + (b.y - a.y) * t)
		_:
			var y := 0.0 if edge == 2 else height
			var t := 0.0 if b.y == a.y else (y - a.y) / (b.y - a.y)
			return Vector2(a.x + (b.x - a.x) * t, y)
