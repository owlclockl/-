## Draws a generated map: biomes or states, rivers, coastlines, burgs and labels.
## Keeps the heavy geometry in cached arrays so redrawing after a pan or a zoom stays cheap.
class_name MapRenderer
extends Control

# view layers (plain ints so they can be passed around without enum casts)
const VIEW_BIOMES := 0
const VIEW_STATES := 1
const VIEW_RELIGIONS := 2
const VIEW_ZONES := 3

const WATER_COLOR := Color("#466eab")
const DEEP_WATER_COLOR := Color("#33598f")
const RIVER_COLOR := Color("#4a7fb5")
const COAST_COLOR := Color("#4b4b3f")
const BORDER_COLOR := Color("#332f2b")
const LABEL_COLOR := Color("#1b1b1b")
const BURG_COLOR := Color("#3b2c24")

var map: MapData
var view := VIEW_BIOMES
var show_rivers := true
var show_burgs := true
var show_labels := true

var _cell_polygons: Array = [] # PackedVector2Array per pack cell
var _cell_colors: Array = [] # Color per pack cell (biomes)
var _cell_state_colors: Array = [] # Color per pack cell (politics)
var _cell_religion_colors: Array = []
var _cell_zone_colors: Array = []
var _river_paths: Array = [] # {points, width}
var _coast_edges: Array = [] # PackedVector2Array of two points
var _state_edges: Array = []
var _burgs: Array = [] # {point, capital, name}
var _labels: Array = [] # {point, text, size}

var _pan := Vector2.ZERO
var _zoom := 1.0
var _dragging := false
var _drag_start := Vector2.ZERO


## Prepare the caches from a generated map
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func setup(map_data: MapData) -> void:
	map = map_data
	_cell_polygons.clear()
	_cell_colors.clear()
	_cell_state_colors.clear()
	_cell_religion_colors.clear()
	_cell_zone_colors.clear()
	_river_paths.clear()
	_coast_edges.clear()
	_state_edges.clear()
	_burgs.clear()
	_labels.clear()
	if map == null or map.pack.is_empty():
		queue_redraw()
		return

	var cells: Dictionary = map.pack["cells"]
	var vertices: PackedVector2Array = map.pack["vertices"]["p"]
	var cell_vertices: Array = cells["v"]
	var neighbours: Array = cells["c"]
	var heights: PackedInt32Array = cells["h"]
	var biomes: PackedInt32Array = cells["biome"]
	var states: PackedInt32Array = cells["state"]
	var religions: PackedInt32Array = cells["religion"]
	var state_list: Array = map.pack.get("states", [])
	var religion_list: Array = map.pack.get("religions", [])

	for cell_id in cells["p"].size():
		var polygon := PackedVector2Array()
		for vertex in cell_vertices[cell_id]:
			if vertex >= 0 and vertex < vertices.size():
				polygon.append(vertices[vertex])
		_cell_polygons.append(polygon)
		var color := DEEP_WATER_COLOR
		if heights[cell_id] >= MapData.SEA_LEVEL:
			var biome_id: int = biomes[cell_id]
			color = Color("#c8d68f")
			if biome_id >= 0 and biome_id < map.biomes.size():
				color = FmgUtils.color_from_any(map.biomes[biome_id].get("color", "#c8d68f"))
		elif cells["t"][cell_id] == -1:
			color = WATER_COLOR
		_cell_colors.append(color)

		var state_color := color
		var state_id: int = states[cell_id] if cell_id < states.size() else 0
		if state_id > 0 and state_id < state_list.size():
			state_color = _mix(color, FmgUtils.color_from_any(state_list[state_id].get("color", "#ffffff")), 0.55)
		_cell_state_colors.append(state_color)

		var religion_color := color
		var religion_id: int = religions[cell_id] if cell_id < religions.size() else 0
		if religion_id > 0 and religion_id < religion_list.size():
			religion_color = _mix(color, _religion_color(religion_id), 0.55)
		_cell_religion_colors.append(religion_color)
		_cell_zone_colors.append(_zone_color(map, cell_id))

	# shared edges: coastline when land meets water, state border when states differ
	for cell_id in cells["p"].size():
		for neighbour in neighbours[cell_id]:
			if neighbour <= cell_id:
				continue
			var edge := _shared_edge(cell_vertices, vertices, cell_id, neighbour)
			if edge.size() == 0:
				continue
			var land_a := heights[cell_id] >= MapData.SEA_LEVEL
			var land_b := heights[neighbour] >= MapData.SEA_LEVEL
			if land_a != land_b:
				_coast_edges.append(edge)
			elif land_a and land_b and cell_id < states.size() and neighbour < states.size() and states[cell_id] != states[neighbour]:
				if states[cell_id] != 0 and states[neighbour] != 0:
					_state_edges.append(edge)

	# rivers
	for river in map.pack.get("rivers", []):
		var river_cells: PackedInt32Array = river.get("cells", PackedInt32Array())
		if river_cells.size() < 2:
			continue
		var points := PackedVector2Array()
		for cell in river_cells:
			if cell >= 0 and cell < cells["p"].size():
				points.append(cells["p"][cell])
		_river_paths.append({"points": points, "width": maxf(float(river.get("width", 0.5)), 0.4)})

	# burgs and labels
	for burg in map.pack.get("burgs", []):
		if int(burg.get("i", 0)) == 0 or burg.get("removed", false):
			continue
		var cell_id := int(burg.get("cell", 0))
		if cell_id < 0 or cell_id >= cells["p"].size():
			continue
		_burgs.append({
			"point": cells["p"][cell_id],
			"capital": bool(burg.get("capital", false)),
			"name": str(burg.get("name", "")),
		})

	for state in map.pack.get("states", []):
		var state_id := int(state.get("i", 0))
		if state_id == 0:
			continue
		var center := int(state.get("center", 0))
		if center < 0 or center >= cells["p"].size():
			continue
		_labels.append({"point": cells["p"][center], "text": str(state.get("name", "")), "size": 13})

	queue_redraw()


func set_view(new_view: int) -> void:
	view = new_view
	queue_redraw()


func _mix(a: Color, b: Color, t: float) -> Color:
	return Color(
		lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), 1.0
	)


func _religion_color(religion_id: int) -> Color:
	var hue := fmod(float(religion_id) * 0.37, 1.0)
	return Color.from_hsv(hue, 0.45, 0.85)


func _zone_color(map: MapData, cell_id: int) -> Color:
	var zones: Array = map.pack.get("zones", [])
	if zones.is_empty():
		return Color.WHITE
	var zone_index := cell_id % zones.size()
	return FmgUtils.color_from_any(zones[zone_index].get("color", "#ffffff"))


## The edge both cells share (two Voronoi vertices, in the order of the first cell)
func _shared_edge(cell_vertices: Array, points: PackedVector2Array, a: int, b: int) -> PackedVector2Array:
	var shared := PackedInt32Array()
	for vertex in cell_vertices[a]:
		if (cell_vertices[b] as PackedInt32Array).has(vertex):
			shared.append(vertex)
	if shared.size() < 2:
		return PackedVector2Array()
	return PackedVector2Array([points[shared[0]], points[shared[1]]])


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if map == null or _cell_polygons.is_empty():
		return
	var transform := _map_transform()
	for cell_id in _cell_polygons.size():
		var polygon := _transform_polygon(_cell_polygons[cell_id], transform)
		if polygon.size() < 3:
			continue
		draw_colored_polygon(polygon, _color_of(cell_id))

	if show_rivers:
		for river in _river_paths:
			var points := _transform_polygon(river["points"], transform)
			if points.size() >= 2:
				draw_polyline(points, RIVER_COLOR, maxf(float(river["width"]) * transform.z, 1.0), true)

	for edge in _coast_edges:
		draw_line(transform * edge[0], transform * edge[1], COAST_COLOR, 1.6, true)
	for edge in _state_edges:
		draw_line(transform * edge[0], transform * edge[1], BORDER_COLOR, 1.2, true)

	if show_burgs:
		var font := ThemeDB.fallback_font
		for burg in _burgs:
			var point := transform * burg["point"]
			var radius := 3.0 if burg["capital"] else 2.0
			draw_circle(point, radius, BURG_COLOR)
			if burg["capital"]:
				draw_circle(point, radius + 1.5, Color("#f6e27a"))
				draw_circle(point, radius, BURG_COLOR)
			if show_labels and burg["capital"]:
				draw_string(font, point + Vector2(6, 4), burg["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LABEL_COLOR)

	if show_labels:
		var font := ThemeDB.fallback_font
		for label in _labels:
			var point := transform * label["point"]
			var text: String = label["text"]
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label["size"]).x
			draw_string(font, point - Vector2(width / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, label["size"], LABEL_COLOR)


func _color_of(cell_id: int) -> Color:
	match view:
		VIEW_STATES:
			return _cell_state_colors[cell_id]
		VIEW_RELIGIONS:
			return _cell_religion_colors[cell_id]
		VIEW_ZONES:
			return _cell_zone_colors[cell_id]
		_:
			return _cell_colors[cell_id]


func _map_transform() -> Transform2D:
	var view_size := get_viewport_rect().size
	var map_size := Vector2(map.width(), map.height())
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return Transform2D.IDENTITY
	var fit := minf(view_size.x / map_size.x, view_size.y / map_size.y)
	var scale := fit * _zoom
	var offset := (view_size - map_size * scale) / 2.0 + _pan
	return Transform2D(0.0, Vector2(scale, scale), 0.0, offset)


func _transform_polygon(points: PackedVector2Array, transform: Transform2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for i in points.size():
		result[i] = transform * points[i]
	return result


# ------------------------------------------------------------------ interaction

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_drag_start = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_pan = Vector2.ZERO
			_zoom = 1.0
			queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		_pan += event.position - _drag_start
		_drag_start = event.position
		queue_redraw()


func _zoom_at(position: Vector2, factor: float) -> void:
	var transform := _map_transform()
	var map_point := transform.affine_inverse() * position
	_zoom *= factor
	var new_transform := _map_transform()
	_pan += position - new_transform * map_point
	queue_redraw()
