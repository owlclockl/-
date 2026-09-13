## Voronoi diagram built on top of the Delaunay triangulation.
##
## Port of Fantasy Map Generator's `src/generators/voronoi.ts` (Azgaar, MIT). The diagram stores,
## for every point (cell):
##   cells_v[cell]  the triangle ids around it — a triangle is a Voronoi vertex, because its
##                  circumcentre is a Voronoi vertex
##   cells_c[cell]  the neighbouring cells
##   cells_b[cell]  1 when the cell touches the outer boundary
## and for every triangle (Voronoi vertex):
##   vertices_p[vertex]  the circumcentre
##   vertices_v[vertex]  the neighbouring vertices
##   vertices_c[vertex]  the cells that meet in the vertex
class_name FmgVoronoi
extends RefCounted

const MAX_EDGES_AROUND_POINT := 20

var cells_v: Array = [] # Array[PackedInt32Array], Voronoi vertex ids per cell
var cells_c: Array = [] # Array[PackedInt32Array], neighbours per cell
var cells_b: PackedByteArray = PackedByteArray()
var vertices_p: PackedVector2Array = PackedVector2Array()
var vertices_v: Array = [] # Array[PackedInt32Array]
var vertices_c: Array = [] # Array[PackedInt32Array]

var points: PackedVector2Array = PackedVector2Array() # cell points + boundary pseudo-points
var points_n := 0
var triangles: PackedInt32Array = PackedInt32Array()
var halfedges: PackedInt32Array = PackedInt32Array()


## points get cells, boundary pseudo-points only clip the outer cells
static func calculate(points_in: PackedVector2Array, boundary: PackedVector2Array) -> FmgVoronoi:
	var diagram := FmgVoronoi.new()
	diagram.points_n = points_in.size()
	var all_points := PackedVector2Array()
	all_points.append_array(points_in)
	all_points.append_array(boundary)
	diagram._build(all_points)
	return diagram


func _build(all_points: PackedVector2Array) -> void:
	points = all_points
	var delaunay := FmgDelaunay.new(all_points)
	triangles = delaunay.triangles
	halfedges = delaunay.halfedges

	var triangles_count := triangles.size() / 3
	cells_v.resize(points_n)
	cells_c.resize(points_n)
	cells_b.resize(points_n)
	cells_b.fill(0)
	vertices_p.resize(triangles_count)
	vertices_p.fill(Vector2.ZERO)
	vertices_v.resize(triangles_count)
	vertices_c.resize(triangles_count)

	for e in triangles.size():
		var p := triangles[next_halfedge(e)]
		if p < points_n and cells_c[p] == null:
			var edges := edges_around_point(e)
			var vertex_ids := PackedInt32Array()
			var neighbours := PackedInt32Array()
			for edge in edges:
				vertex_ids.append(triangle_of_edge(edge))
				var neighbour := triangles[edge]
				if neighbour < points_n:
					neighbours.append(neighbour)
			cells_v[p] = vertex_ids
			cells_c[p] = neighbours
			cells_b[p] = 1 if edges.size() > neighbours.size() else 0

		var t := triangle_of_edge(e)
		if vertices_c[t] == null:
			vertices_p[t] = triangle_center(t)
			vertices_v[t] = triangles_adjacent_to_triangle(t)
			vertices_c[t] = points_of_triangle(t)

	for i in points_n:
		if cells_v[i] == null:
			cells_v[i] = PackedInt32Array()
		if cells_c[i] == null:
			cells_c[i] = PackedInt32Array()
		if cells_b[i] == 1 and cells_v[i].size() > 0 and cells_c[i].size() == 0:
			cells_b[i] = 1


# ------------------------------------------------------------------ half-edge helpers (Delaunator docs)

static func next_halfedge(e: int) -> int:
	return e - 2 if e % 3 == 2 else e + 1


static func triangle_of_edge(e: int) -> int:
	return e / 3


static func edges_of_triangle(triangle_index: int) -> PackedInt32Array:
	return PackedInt32Array([3 * triangle_index, 3 * triangle_index + 1, 3 * triangle_index + 2])


## Ids of the points that form the triangle
func points_of_triangle(triangle_index: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for edge in edges_of_triangle(triangle_index):
		if edge < triangles.size():
			result.append(triangles[edge])
	return result


## Triangle ids adjacent to the given triangle; -1 stands for "the hull"
func triangles_adjacent_to_triangle(triangle_index: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for edge in edges_of_triangle(triangle_index):
		var opposite := halfedges[edge]
		result.append(triangle_of_edge(opposite))
	return result


## All half-edges that end in the point the given half-edge leads to
func edges_around_point(start: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var incoming := start
	while true:
		result.append(incoming)
		var outgoing := next_halfedge(incoming)
		incoming = halfedges[outgoing]
		if incoming == -1 or incoming == start or result.size() >= MAX_EDGES_AROUND_POINT:
			break
	return result


## Circumcentre of a triangle — the Voronoi vertex
func triangle_center(triangle_index: int) -> Vector2:
	var ids := points_of_triangle(triangle_index)
	if ids.size() < 3:
		return Vector2.ZERO
	return circumcenter(points[ids[0]], points[ids[1]], points[ids[2]])


static func circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var ad := a.x * a.x + a.y * a.y
	var bd := b.x * b.x + b.y * b.y
	var cd := c.x * c.x + c.y * c.y
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-12:
		return (a + b + c) / 3.0
	return Vector2(
		(ad * (b.y - c.y) + bd * (c.y - a.y) + cd * (a.y - b.y)) / d,
		(ad * (c.x - b.x) + bd * (a.x - c.x) + cd * (b.x - a.x)) / d
	)


# ------------------------------------------------------------------ convenience

## Polygon of a cell as the circumcentres of the triangles around it
func get_polygon(cell_id: int) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if cell_id < 0 or cell_id >= points_n or cells_v[cell_id] == null:
		return polygon
	for vertex in cells_v[cell_id]:
		if vertex >= 0 and vertex < vertices_p.size():
			polygon.append(vertices_p[vertex])
	return polygon


## Cell outline as vertex ids (used when building shorelines and boundaries)
func get_polygon_ids(cell_id: int) -> PackedInt32Array:
	if cell_id < 0 or cell_id >= points_n or cells_v[cell_id] == null:
		return PackedInt32Array()
	return cells_v[cell_id]
