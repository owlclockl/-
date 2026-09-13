## Spatial index used where Fantasy Map Generator relies on d3.quadtree:
## `Pack.findCell(x, y)` (nearest cell to a point), `findAll(x, y, radius)` and the
## "minimum distance between capitals" checks during burg / state / religion placement.
##
## A uniform hash grid is a natural fit here because map points are almost evenly spaced
## (a jittered square grid), so lookups stay cheap while the code stays small.
class_name FmgQuadTree
extends RefCounted

var cell_size: float = 16.0

var _buckets: Dictionary = {}
var _points: Array = [] # Array[Vector2], index == insertion order
var _ids: PackedInt32Array = PackedInt32Array()


func _init(bucket_size: float = 16.0) -> void:
	cell_size = max(bucket_size, 0.0001)


func add(point: Vector2, id: int = -1) -> void:
	var point_id := id if id >= 0 else _points.size()
	_points.append(point)
	_ids.append(point_id)
	var key := _key(int(floor(point.x / cell_size)), int(floor(point.y / cell_size)))
	if not _buckets.has(key):
		_buckets[key] = PackedInt32Array()
	_buckets[key].append(_points.size() - 1)


func _key(cx: int, cy: int) -> String:
	return "%d_%d" % [cx, cy]


## id of the nearest point within `radius`, or -1 when there is none (d3 quadtree.find)
func find(x: float, y: float, radius: float = INF) -> int:
	var point := Vector2(x, y)
	var best_id := -1
	var best_distance := radius * radius if radius != INF else INF
	var cx := int(floor(x / cell_size))
	var cy := int(floor(y / cell_size))
	var limit := int(ceil(radius / cell_size)) + 1 if radius != INF else 64

	for ring in range(0, limit + 1):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(abs(dx), abs(dy)) != ring:
					continue
				var index_list: Variant = _buckets.get(_key(cx + dx, cy + dy))
				if index_list == null:
					continue
				for index in index_list:
					var distance := FmgUtils.distance_squared(_points[index], point)
					if distance < best_distance:
						best_distance = distance
						best_id = _ids[index]
		if best_id != -1 and best_distance <= pow(float(ring) * cell_size, 2.0):
			return best_id
		if radius != INF and float(ring) * cell_size > radius:
			return best_id

	if best_id == -1 and radius == INF:
		# sparse index (few points over a large area): fall back to a linear scan
		for index in _points.size():
			var distance := FmgUtils.distance_squared(_points[index], point)
			if distance < best_distance:
				best_distance = distance
				best_id = _ids[index]
	return best_id


## every point id within `radius`
func find_all(x: float, y: float, radius: float) -> PackedInt32Array:
	var point := Vector2(x, y)
	var result := PackedInt32Array()
	var radius_squared := radius * radius
	var cx := int(floor(x / cell_size))
	var cy := int(floor(y / cell_size))
	var rings := int(ceil(radius / cell_size))
	for dx in range(-rings, rings + 1):
		for dy in range(-rings, rings + 1):
			var index_list: Variant = _buckets.get(_key(cx + dx, cy + dy))
			if index_list == null:
				continue
			for index in index_list:
				if FmgUtils.distance_squared(_points[index], point) <= radius_squared:
					result.append(_ids[index])
	return result


func size() -> int:
	return _points.size()


func is_empty() -> bool:
	return _points.is_empty()


func clear() -> void:
	_buckets.clear()
	_points.clear()
	_ids.clear()
