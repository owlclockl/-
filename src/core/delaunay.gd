## Delaunay triangulation.
##
## GDScript port of Delaunator (https://github.com/mapbox/delaunator, ISC licence, © Mapbox) — the
## very same triangulator Fantasy Map Generator uses for its Voronoi graphs. The port keeps the
## algorithm unchanged, so a triangulation comes out with the same vertices and the same half-edge
## links as the JavaScript library.
##
## Usage:
##   var d := FmgDelaunay.new(points)
##   d.triangles  # PackedInt32Array, three vertex ids per triangle (clockwise, Delaunator order)
##   d.halfedges  # PackedInt32Array, opposite half-edge or -1 on the convex hull
##   d.hull       # PackedInt32Array, hull vertex ids
class_name FmgDelaunay
extends RefCounted

const EPSILON := 2.220446049250313e-16 # 2^-52, same as Delaunator
const EDGE_STACK_SIZE := 512

var triangles: PackedInt32Array = PackedInt32Array()
var halfedges: PackedInt32Array = PackedInt32Array()
var hull: PackedInt32Array = PackedInt32Array()
var points_count := 0

var _coords: PackedFloat64Array = PackedFloat64Array()
var _triangles: PackedInt32Array = PackedInt32Array()
var _halfedges: PackedInt32Array = PackedInt32Array()
var _hull_prev: PackedInt32Array = PackedInt32Array()
var _hull_next: PackedInt32Array = PackedInt32Array()
var _hull_tri: PackedInt32Array = PackedInt32Array()
var _hull_hash: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt32Array = PackedInt32Array()
var _dists: PackedFloat64Array = PackedFloat64Array()
var _edge_stack: PackedInt32Array = PackedInt32Array()
var _hash_size := 1
var _triangles_len := 0
var _cx := 0.0
var _cy := 0.0
var _hull_start := 0


func _init(points: PackedVector2Array) -> void:
	points_count = points.size()
	_coords.resize(points_count * 2)
	for i in points_count:
		_coords[2 * i] = points[i].x
		_coords[2 * i + 1] = points[i].y

	var max_triangles := maxi(2 * points_count - 5, 0)
	_triangles.resize(max_triangles * 3)
	_halfedges.resize(max_triangles * 3)
	_halfedges.fill(-1)

	_hash_size = maxi(1, int(ceil(sqrt(float(points_count)))))
	_hull_prev.resize(points_count)
	_hull_next.resize(points_count)
	_hull_tri.resize(points_count)
	_hull_hash.resize(_hash_size)
	__hull_hash.fill(-1)
	_ids.resize(points_count)
	_dists.resize(points_count)
	_edge_stack.resize(EDGE_STACK_SIZE)

	update()


# ------------------------------------------------------------------ the algorithm

func update() -> void:
	var n := points_count
	if n == 0:
		return
	var coords := _coords # read only, so a copy-on-write alias is fine

	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for i in n:
		var x := coords[2 * i]
		var y := coords[2 * i + 1]
		if x < min_x:
			min_x = x
		if y < min_y:
			min_y = y
		if x > max_x:
			max_x = x
		if y > max_y:
			max_y = y
		_ids[i] = i
	_cx = (min_x + max_x) / 2.0
	_cy = (min_y + max_y) / 2.0

	var i0 := 0
	var i1 := 0
	var i2 := 0

	# seed point close to the centre
	var min_dist := INF
	for i in n:
		var d := _dist(_cx, _cy, coords[2 * i], coords[2 * i + 1])
		if d < min_dist:
			i0 = i
			min_dist = d
	var i0x := coords[2 * i0]
	var i0y := coords[2 * i0 + 1]

	# point closest to the seed
	min_dist = INF
	for i in n:
		if i == i0:
			continue
		var d := _dist(i0x, i0y, coords[2 * i], coords[2 * i + 1])
		if d < min_dist and d > 0.0:
			i1 = i
			min_dist = d
	var i1x := coords[2 * i1]
	var i1y := coords[2 * i1 + 1]

	# third point forming the smallest circumcircle with the first two
	var min_radius := INF
	for i in n:
		if i == i0 or i == i1:
			continue
		var r := _circumradius(i0x, i0y, i1x, i1y, coords[2 * i], coords[2 * i + 1])
		if r < min_radius:
			i2 = i
			min_radius = r

	if min_radius == INF:
		# all points are collinear: the hull is the sorted list and there is no triangulation
		for i in n:
			_dists[i] = (coords[2 * i] - coords[0])
			if _dists[i] == 0.0:
				_dists[i] = coords[2 * i + 1] - coords[1]
		_quicksort(0, n - 1)
		var collinear_hull := PackedInt32Array()
		var d0 := -INF
		for i in n:
			var id := _ids[i]
			var d := _dists[id]
			if d > d0:
				collinear_hull.append(id)
				d0 = d
		hull = collinear_hull
		triangles = PackedInt32Array()
		halfedges = PackedInt32Array()
		_triangles_len = 0
		return

	var i2x := coords[2 * i2]
	var i2y := coords[2 * i2 + 1]

	# swap the seed points so the triangle comes out clockwise (the Delaunator convention)
	if _orient2d(i0x, i0y, i1x, i1y, i2x, i2y) > 0.0:
		var ti := i1
		i1 = i2
		i2 = ti
		var tx := i1x
		i1x = i2x
		i2x = tx
		var ty := i1y
		i1y = i2y
		i2y = ty

	var center := _circumcenter(i0x, i0y, i1x, i1y, i2x, i2y)
	_cx = center.x
	_cy = center.y

	for i in n:
		_dists[i] = _dist(coords[2 * i], coords[2 * i + 1], _cx, _cy)

	# points sorted by distance from the seed circumcentre
	_quicksort(0, n - 1)

	_hull_start = i0
	var hull_size := 3

	_hull_next[i0] = i1
	_hull_prev[i2] = i1
	_hull_next[i1] = i2
	_hull_prev[i0] = i2
	_hull_next[i2] = i0
	_hull_prev[i1] = i0

	_hull_tri[i0] = 0
	_hull_tri[i1] = 1
	_hull_tri[i2] = 2

	_hull_hash.fill(-1)
	_hull_hash[hash_key(i0x, i0y)] = i0
	_hull_hash[hash_key(i1x, i1y)] = i1
	_hull_hash[hash_key(i2x, i2y)] = i2

	_triangles_len = 0
	add_triangle(i0, i1, i2, -1, -1, -1)

	var xp := 0.0
	var yp := 0.0
	for k in n:
		var i := _ids[k]
		var x := coords[2 * i]
		var y := coords[2 * i + 1]

		if k > 0 and absf(x - xp) <= EPSILON and absf(y - yp) <= EPSILON:
			continue
		xp = x
		yp = y

		if i == i0 or i == i1 or i == i2:
			continue

		# visible edge on the convex hull, found through the edge hash
		var start := 0
		var key := hash_key(x, y)
		for j in _hash_size:
			start = _hull_hash[(key + j) % _hash_size]
			if start != -1 and start != _hull_next[start]:
				break

		start = _hull_prev[start]
		var e := start
		var q := 0
		while true:
			q = _hull_next[e]
			if _orient2d(x, y, coords[2 * e], coords[2 * e + 1], coords[2 * q], coords[2 * q + 1]) < 0.0:
				break
			e = q
			if e == start:
				e = -1
				break
		if e == -1:
			continue # near-duplicate point, skip it

		# first triangle from the new point
		var t := add_triangle(e, i, _hull_next[e], -1, -1, _hull_tri[e])

		_hull_tri[i] = legalize(t + 2)
		_hull_tri[e] = t
		hull_size += 1

		# walk forward, adding triangles and flipping
		var next_point := _hull_next[e]
		while true:
			q = _hull_next[next_point]
			if _orient2d(x, y, coords[2 * next_point], coords[2 * next_point + 1], coords[2 * q], coords[2 * q + 1]) >= 0.0:
				break
			t = add_triangle(next_point, i, q, _hull_tri[i], -1, _hull_tri[next_point])
			_hull_tri[i] = legalize(t + 2)
			_hull_next[next_point] = next_point # removed from the hull
			hull_size -= 1
			next_point = q

		# walk backward from the other side
		if e == start:
			while true:
				q = _hull_prev[e]
				if _orient2d(x, y, coords[2 * q], coords[2 * q + 1], coords[2 * e], coords[2 * e + 1]) >= 0.0:
					break
				t = add_triangle(q, i, e, -1, _hull_tri[e], _hull_tri[q])
				legalize(t + 2)
				_hull_tri[q] = t
				_hull_next[e] = e # removed from the hull
				hull_size -= 1
				e = q

		# update the hull indices
		_hull_start = e
		_hull_prev[i] = e
		_hull_next[e] = i
		_hull_prev[next_point] = i
		_hull_next[i] = next_point

		_hull_hash[hash_key(x, y)] = i
		_hull_hash[hash_key(coords[2 * e], coords[2 * e + 1])] = e

	var out_hull := PackedInt32Array()
	out_hull.resize(maxi(hull_size, 0))
	var e2 := _hull_start
	for i in maxi(hull_size, 0):
		out_hull[i] = e2
		e2 = _hull_next[e2]
	hull = out_hull

	triangles = _triangles.slice(0, _triangles_len)
	halfedges = _halfedges.slice(0, _triangles_len)


## Angle-based key for the edge hash used when advancing the convex hull
func hash_key(x: float, y: float) -> int:
	return int(floor(_pseudo_angle(x - _cx, y - _cy) * float(_hash_size))) % _hash_size


## Flip an edge in a pair of triangles while it does not satisfy the Delaunay condition
func legalize(a_in: int) -> int:
	var a := a_in
	var i := 0
	var ar := 0

	while true:
		var b := _halfedges[a]
		var a0 := a - a % 3
		ar = a0 + (a + 2) % 3

		if b == -1: # convex hull edge
			if i == 0:
				break
			i -= 1
			a = _edge_stack[i]
			continue

		var b0 := b - b % 3
		var al := a0 + (a + 1) % 3
		var bl := b0 + (b + 2) % 3

		var p0 := _triangles[ar]
		var pr := _triangles[a]
		var pl := _triangles[al]
		var p1 := _triangles[bl]

		var illegal := _in_circle(
			_coords[2 * p0], _coords[2 * p0 + 1],
			_coords[2 * pr], _coords[2 * pr + 1],
			_coords[2 * pl], _coords[2 * pl + 1],
			_coords[2 * p1], _coords[2 * p1 + 1])

		if illegal:
			_triangles[a] = p1
			_triangles[b] = p0

			var hbl := _halfedges[bl]
			# the swapped edge lies on the hull: fix the hull triangle reference
			if hbl == -1:
				var e := _hull_start
				while true:
					if _hull_tri[e] == bl:
						_hull_tri[e] = a
						break
					e = _hull_prev[e]
					if e == _hull_start:
						break
			link(a, hbl)
			link(b, _halfedges[ar])
			link(ar, bl)

			var br := b0 + (b + 1) % 3
			if i < EDGE_STACK_SIZE:
				_edge_stack[i] = br
				i += 1
		else:
			if i == 0:
				break
			i -= 1
			a = _edge_stack[i]

	return ar


func link(a: int, b: int) -> void:
	_halfedges[a] = b
	if b != -1:
		_halfedges[b] = a


func add_triangle(i0: int, i1: int, i2: int, a: int, b: int, c: int) -> int:
	var t := _triangles_len
	_triangles[t] = i0
	_triangles[t + 1] = i1
	_triangles[t + 2] = i2
	link(t, a)
	link(t + 1, b)
	link(t + 2, c)
	_triangles_len += 3
	return t


## Insertion sort on tiny ranges, Hoare partitioning above (identical to Delaunator's)
func _quicksort(left: int, right: int) -> void:
	if right - left <= 20:
		for i in range(left + 1, right + 1):
			var temp := _ids[i]
			var temp_dist := _dists[temp]
			var j := i - 1
			while j >= left and _dists[_ids[j]] > temp_dist:
				_ids[j + 1] = _ids[j]
				j -= 1
			_ids[j + 1] = temp
	else:
		var median := (left + right) / 2
		var i := left + 1
		var j := right
		_swap(median, i)
		if _dists[_ids[left]] > _dists[_ids[right]]:
			_swap(left, right)
		if _dists[_ids[i]] > _dists[_ids[right]]:
			_swap(i, right)
		if _dists[_ids[left]] > _dists[_ids[i]]:
			_swap(left, i)

		var temp := _ids[i]
		var temp_dist := _dists[temp]
		while true:
			i += 1
			while _dists[_ids[i]] < temp_dist:
				i += 1
			j -= 1
			while _dists[_ids[j]] > temp_dist:
				j -= 1
			if j < i:
				break
			_swap(i, j)
		_ids[left + 1] = _ids[j]
		_ids[j] = temp

		if right - i + 1 >= j - left:
			_quicksort(i, right)
			_quicksort(left, j - 1)
		else:
			_quicksort(left, j - 1)
			_quicksort(i, right)


func _swap(i: int, j: int) -> void:
	var tmp := _ids[i]
	_ids[i] = _ids[j]
	_ids[j] = tmp


# ------------------------------------------------------------------ helpers (same maths as Delaunator)

static func _pseudo_angle(dx: float, dy: float) -> float:
	var p := dx / (absf(dx) + absf(dy))
	return (3.0 - p if dy > 0.0 else 1.0 + p) / 4.0


static func _dist(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := ax - bx
	var dy := ay - by
	return dx * dx + dy * dy


## Delaunator's orientation predicate (opposite sign to the usual cross product)
static func _orient2d(ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> float:
	return (ay - cy) * (bx - cx) - (ax - cx) * (by - cy)


static func _in_circle(ax: float, ay: float, bx: float, by: float, cx: float, cy: float, px: float, py: float) -> bool:
	var dx := ax - px
	var dy := ay - py
	var ex := bx - px
	var ey := by - py
	var fx := cx - px
	var fy := cy - py
	var ap := dx * dx + dy * dy
	var bp := ex * ex + ey * ey
	var cp := fx * fx + fy * fy
	return dx * (ey * cp - bp * fy) - dy * (ex * cp - bp * fx) + ap * (ex * fy - ey * fx) < 0.0


static func _circumradius(ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	var ex := cx - ax
	var ey := cy - ay
	var bl := dx * dx + dy * dy
	var cl := ex * ex + ey * ey
	var d := 0.5 / (dx * ey - dy * ex)
	var x := (ey * bl - dy * cl) * d
	var y := (dx * cl - ex * bl) * d
	return x * x + y * y


static func _circumcenter(ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> Vector2:
	var dx := bx - ax
	var dy := by - ay
	var ex := cx - ax
	var ey := cy - ay
	var bl := dx * dx + dy * dy
	var cl := ex * ex + ey * ey
	var d := 0.5 / (dx * ey - dy * ex)
	return Vector2(ax + (ey * bl - dy * cl) * d, ay + (dx * cl - ex * bl) * d)


# ------------------------------------------------------------------ convenience

static func next_edge(e: int) -> int:
	return e - 2 if e % 3 == 2 else e + 1


static func prev_edge(e: int) -> int:
	return e + 2 if e % 3 == 0 else e - 1


static func triangle_of_edge(e: int) -> int:
	return e / 3


## Whether a triangulation was produced at all (all input points collinear gives none)
func has_triangles() -> bool:
	return triangles.size() > 0
