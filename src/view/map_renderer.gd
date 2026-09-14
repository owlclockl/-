## Draws a generated map. The fills come from the atlas (one blitted texture per view layer),
## the crisp details — coastline, rivers, borders, towns, labels — are still drawn as vectors so
## they stay sharp at any zoom. Heavy geometry is kept in cached arrays, so a pan or a zoom costs a
## single quad plus a few hundred polylines instead of ~10000 polygons.
class_name MapRenderer
extends Control

# view layers, kept in sync with MapAtlas
const VIEW_BIOMES := MapAtlas.VIEW_BIOMES
const VIEW_STATES := MapAtlas.VIEW_STATES
const VIEW_RELIGIONS := MapAtlas.VIEW_RELIGIONS
const VIEW_ZONES := MapAtlas.VIEW_ZONES
const VIEW_HEIGHTS := MapAtlas.VIEW_HEIGHTS
const VIEWS: Array = [VIEW_BIOMES, VIEW_STATES, VIEW_RELIGIONS, VIEW_ZONES, VIEW_HEIGHTS]

const RIVER_COLOR := Color("#3f6fa4")
const COAST_COLOR := Color("#4b4b3f")
const BORDER_COLOR := Color("#332f2b")
const LABEL_COLOR := Color("#1b1b1b")
const BURG_COLOR := Color("#3b2c24")
const CAPITAL_COLOR := Color("#f6e27a")
const BACKDROP_COLOR := Color("#22406b")
const HOVER_COLOR := Color("#fff9d6")

const ZOOM_MIN := 0.4
const ZOOM_MAX := 14.0

signal cell_hovered(cell_id: int)

var atlas := MapAtlas.new()
var map: MapData
var view := VIEW_BIOMES
var show_rivers := true
var show_coast := true
var show_borders := true
var show_burgs := true
var show_labels := true

var _river_paths: Array = [] # {points, width}
var _coast_edges: Array = [] # PackedVector2Array of two points
var _state_edges: Array = []
var _burgs: Array = [] # {point, capital, name, population}
var _labels: Array = [] # {point, text, size}

var _pan := Vector2.ZERO
var _zoom := 1.0
var _dragging := false
var _drag_start := Vector2.ZERO
var _hovered := -1


## Prepare the caches from a generated map. The atlas is baked separately, see `bake`.
func setup(map_data: MapData) -> void:
	map = map_data
	_pan = Vector2.ZERO
	_zoom = 1.0
	_hovered = -1
	atlas.setup(map_data)
	_river_paths.clear()
	_coast_edges.clear()
	_state_edges.clear()
	_burgs.clear()
	_labels.clear()
	if map == null or map.pack.is_empty():
		queue_redraw()
		return
	_build_edges()
	_build_rivers()
	_build_burgs()
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_exited.connect(func() -> void: _update_hover(Vector2(-1000.0, -1000.0)))


# ------------------------------------------------------------------ atlas


## Is the atlas of the current layer ready to be drawn?
func is_ready() -> bool:
	return atlas.is_baked(view)


func needs_bake() -> bool:
	return atlas.needs_geometry() or not atlas.is_baked(view)


## One slice of the geometry pass; returns true while there is more to do
func bake_geometry_step() -> bool:
	if atlas.needs_geometry():
		atlas.begin_bake()
	atlas.bake_step()
	return atlas.is_baking()


func bake_progress() -> float:
	return atlas.bake_progress()


## Fill the band of a layer (cheap once the geometry is baked)
func bake(layer: int) -> void:
	if atlas.needs_geometry():
		atlas.bake_geometry()
	atlas.bake_layer(layer)
	set_view(layer)


func set_level(value: float) -> bool:
	return atlas.set_level(value)


func level() -> float:
	return atlas.level


func max_level() -> float:
	return atlas.max_level()


func atlas_pixels_text() -> String:
	return atlas.pixels_text()


func set_view(new_view: int) -> void:
	view = new_view
	queue_redraw()


func view_title(new_view: int) -> String:
	var index: int = VIEWS.find(new_view)
	if index < 0 or index >= MapAtlas.LABELS.size():
		return "Слой"
	return str(MapAtlas.LABELS[index])


# ------------------------------------------------------------------ vector caches


## Coastline and state borders, from the edges cells share
func _build_edges() -> void:
	var cells: Dictionary = map.pack["cells"]
	var vertices: PackedVector2Array = map.pack["vertices"]["p"]
	var cell_vertices: Array = cells["v"]
	var neighbours: Array = cells["c"]
	var heights: PackedInt32Array = cells["h"]
	var states: PackedInt32Array = cells["state"]
	var points: PackedVector2Array = cells["p"]
	for cell_id in points.size():
		var ring: PackedInt32Array = neighbours[cell_id]
		for neighbour in ring:
			var neighbour_id := int(neighbour)
			if neighbour_id <= cell_id:
				continue
			var edge := _shared_edge(cell_vertices, vertices, cell_id, neighbour_id)
			if edge.size() == 0:
				continue
			var land_a := heights[cell_id] >= MapData.SEA_LEVEL
			var land_b := heights[neighbour_id] >= MapData.SEA_LEVEL
			if land_a != land_b:
				_coast_edges.append(edge)
			elif land_a and land_b and cell_id < states.size() and neighbour_id < states.size():
				if states[cell_id] != 0 and states[neighbour_id] != 0 and states[cell_id] != states[neighbour_id]:
					_state_edges.append(edge)


func _build_rivers() -> void:
	var cells: Dictionary = map.pack["cells"]
	var points: PackedVector2Array = cells["p"]
	for river: Dictionary in map.rivers():
		if int(river.get("i", 0)) == 0:
			continue
		var river_cells: PackedInt32Array = river.get("cells", PackedInt32Array())
		if river_cells.size() < 2:
			continue
		var path := PackedVector2Array()
		for cell in river_cells:
			var cell_id := int(cell)
			if cell_id >= 0 and cell_id < points.size():
				path.append(points[cell_id])
		if path.size() >= 2:
			var width := maxf(float(river.get("width", 0.5)), 0.4)
			_river_paths.append({"points": path, "width": width})


func _build_burgs() -> void:
	var cells: Dictionary = map.pack["cells"]
	var points: PackedVector2Array = cells["p"]
	for burg: Dictionary in map.burgs():
		if int(burg.get("i", 0)) == 0 or bool(burg.get("removed", false)):
			continue
		var cell_id := int(burg.get("cell", 0))
		if cell_id < 0 or cell_id >= points.size():
			continue
		_burgs.append({
			"point": points[cell_id],
			"capital": int(burg.get("capital", 0)) > 0,
			"name": str(burg.get("name", "")),
			"population": float(burg.get("population", 0.0)),
		})
	for state: Dictionary in map.states():
		var state_id := int(state.get("i", 0))
		if state_id == 0:
			continue
		var center := int(state.get("center", 0))
		if center < 0 or center >= points.size():
			continue
		_labels.append({"point": points[center], "text": str(state.get("name", "")), "size": 13})


## The edge both cells share (two Voronoi vertices, in the order of the first cell)
func _shared_edge(cell_vertices: Array, points: PackedVector2Array, a: int, b: int) -> PackedVector2Array:
	var ids_a: PackedInt32Array = cell_vertices[a]
	var ids_b: PackedInt32Array = cell_vertices[b]
	var shared := PackedInt32Array()
	for vertex in ids_a:
		if ids_b.has(vertex):
			shared.append(vertex)
	if shared.size() < 2:
		return PackedVector2Array()
	return PackedVector2Array([points[shared[0]], points[shared[1]]])


## Cheap culling test for a segment against the visible rectangle of the control
func _in_view(a: Vector2, b: Vector2, bounds: Rect2) -> bool:
	var margin := 8.0
	if maxf(a.x, b.x) < bounds.position.x - margin or minf(a.x, b.x) > bounds.end.x + margin:
		return false
	if maxf(a.y, b.y) < bounds.position.y - margin or minf(a.y, b.y) > bounds.end.y + margin:
		return false
	return true


# ------------------------------------------------------------------ drawing


func _draw() -> void:
	if map == null:
		return
	var transform := _map_transform()
	var scale := transform.get_scale()
	var map_rect := Rect2(transform * Vector2.ZERO, Vector2(map.width() * scale.x, map.height() * scale.y))
	draw_rect(map_rect, BACKDROP_COLOR)
	if atlas.texture != null and atlas.is_baked(view):
		draw_texture_rect_region(atlas.texture, map_rect, atlas.region_of(view))
	_draw_details(transform)


func _draw_details(transform: Transform2D) -> void:
	var scale := transform.get_scale().x
	var bounds := get_rect()
	if show_coast:
		for edge: PackedVector2Array in _coast_edges:
			var a := transform * edge[0]
			var b := transform * edge[1]
			if _in_view(a, b, bounds):
				draw_line(a, b, COAST_COLOR, 1.6, true)
	if show_borders:
		for edge: PackedVector2Array in _state_edges:
			var left := transform * edge[0]
			var right := transform * edge[1]
			if _in_view(left, right, bounds):
				draw_line(left, right, BORDER_COLOR, 1.2, true)
	if show_rivers:
		for river: Dictionary in _river_paths:
			var source: PackedVector2Array = river["points"]
			var width: float = river["width"]
			var points := _transform_polygon(source, transform)
			if points.size() >= 2:
				draw_polyline(points, RIVER_COLOR, maxf(width * scale, 1.0), true)

	if _hovered >= 0 and atlas.is_ready():
		var highlighted := _transform_polygon(map.pack_polygon(_hovered), transform)
		if highlighted.size() >= 3:
			highlighted.append(highlighted[0])
			draw_polyline(highlighted, HOVER_COLOR, 2.0, true)

	if not show_burgs and not show_labels:
		return
	var font := ThemeDB.fallback_font
	if show_burgs:
		for burg: Dictionary in _burgs:
			var capital: bool = burg["capital"]
			var point := transform * (burg["point"] as Vector2)
			var radius := 3.0 if capital else 2.0
			if capital:
				draw_circle(point, radius + 1.5, CAPITAL_COLOR)
			draw_circle(point, radius, BURG_COLOR)
			if capital and show_labels:
				_draw_text(font, point + Vector2(6, 4), str(burg["name"]), 10, HORIZONTAL_ALIGNMENT_LEFT)
	if show_labels:
		for label: Dictionary in _labels:
			var center := transform * (label["point"] as Vector2)
			_draw_text(font, center, str(label["text"]), int(label["size"]), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_text(font: Font, center: Vector2, text: String, size: int, alignment: int) -> void:
	if text.is_empty():
		return
	var width := font.get_string_size(text, alignment, -1, size).x
	var start := center
	if alignment == HORIZONTAL_ALIGNMENT_CENTER:
		start = center - Vector2(width / 2.0, 0.0)
	draw_string_outline(font, start, text, alignment, -1, size, 3, Color(0.0, 0.0, 0.0, 0.28))
	draw_string(font, start, text, alignment, -1, size, LABEL_COLOR)


func _transform_polygon(points: PackedVector2Array, transform: Transform2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for index in points.size():
		result[index] = transform * points[index]
	return result


func _map_transform() -> Transform2D:
	var view_size := get_viewport_rect().size
	var map_size := Vector2(map.width(), map.height())
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return Transform2D.IDENTITY
	var fit := minf(view_size.x / map_size.x, view_size.y / map_size.y)
	var scale := clampf(fit * _zoom, 0.01, 400.0)
	var offset := (view_size - map_size * scale) / 2.0 + _pan
	return Transform2D(0.0, Vector2(scale, scale), 0.0, offset)


# ------------------------------------------------------------------ interaction


## The pack cell drawn under a control-local point (-1 when there is none)
func cell_at(position: Vector2) -> int:
	if map == null:
		return -1
	return atlas.cell_at(_map_transform().affine_inverse() * position)


func zoom_value() -> float:
	return _zoom


func zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	queue_redraw()


func reset_view() -> void:
	_pan = Vector2.ZERO
	_zoom = 1.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(button.position, 1.15)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(button.position, 1.0 / 1.15)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			_drag_start = button.position
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			reset_view()
		_update_hover(button.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging:
			_pan += motion.position - _drag_start
			_drag_start = motion.position
			queue_redraw()
		_update_hover(motion.position)


func _update_hover(position: Vector2) -> void:
	var cell_id := cell_at(position)
	if cell_id == _hovered:
		return
	_hovered = cell_id
	cell_hovered.emit(cell_id)
	queue_redraw()


func _zoom_at(position: Vector2, factor: float) -> void:
	var transform := _map_transform()
	var map_point := transform.affine_inverse() * position
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var new_transform := _map_transform()
	_pan += position - new_transform * map_point
	queue_redraw()
