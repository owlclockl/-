## The map atlas: the generated map rasterized once into a single texture.
##
## Every view layer takes one horizontal band of the same image — that is what makes it an atlas.
## Switching a layer becomes a sub-rectangle blit and panning or zooming becomes a single quad,
## instead of re-drawing ~10000 Voronoi polygons on every frame. The same pass also keeps a cell id
## mask, so the interface can pick the cell under the mouse in constant time, and the whole image
## can be exported to a PNG.
##
## The bake is CPU-only and split into steps (`bake_step`) so the generation screen can stay
## responsive and report progress; it also runs headless, which lets `tests/test_generation.gd`
## check the pixels without a renderer.
class_name MapAtlas
extends RefCounted

# view layers (plain ints so they can be passed around without enum casts)
const VIEW_BIOMES := 0
const VIEW_STATES := 1
const VIEW_RELIGIONS := 2
const VIEW_ZONES := 3
const VIEW_HEIGHTS := 4
const LAYERS := 5

## Pixels per map unit, from a draft preview to a printable map
const LEVELS := [1.0, 2.0, 3.0]

## Budget for the whole atlas (all bands together), in pixels
const MAX_ATLAS_PIXELS := 16000000

## Cells rasterized between two progress updates
const CELLS_PER_STEP := 1200

const OCEAN_DEEP_COLOR := Color("#22406b")
const OCEAN_SHALLOW_COLOR := Color("#466eab")
const LAKE_COLOR := Color("#4a7fb5")
const LAND_FALLBACK_COLOR := Color("#c8d68f")

## Heightmap ramp, sea level first and snow last
const HEIGHT_RAMP: Array = [
	Color("#22406b"), Color("#466eab"), Color("#c9d39a"), Color("#a8bd7c"),
	Color("#8faa6a"), Color("#a99a7e"), Color("#c8bfae"), Color("#f2f0e8"),
]

const LABELS: Array = ["Природа", "Государства", "Религии", "Зоны", "Высоты"]

var map: MapData

## Effective resolution of the atlas in pixels per map unit
var level := 2.0
var width := 0
var band_height := 0
var texture: ImageTexture

var _image: Image
var _mask := PackedInt32Array() # pack cell id of every atlas pixel, -1 outside the map
var _bytes := PackedByteArray() # RGBA8 of all bands, the atlas itself
var _table := PackedByteArray() # RGBA8 of every cell of every layer, LAYERS * cells * 4
var _cell_count := 0
var _cursor := 0
var _baking := false
var _baked := {} # layer -> true when its band is filled
var _scaled := PackedVector2Array() # scratch for the current cell polygon
var _hits := PackedFloat32Array() # scratch for scanline intersections


## Point the atlas at a generated map and drop everything baked so far
func setup(map_data: MapData) -> void:
	map = map_data
	_cell_count = 0 if map == null or map.pack.is_empty() else map.pack_cell_count()
	_mask = PackedInt32Array()
	_bytes = PackedByteArray()
	_table = PackedByteArray()
	_image = null
	_baked.clear()
	_cursor = 0
	_baking = false
	width = 0
	band_height = 0
	texture = null
	if _cell_count == 0:
		return
	level = clampf(minf(level, max_level()), float(LEVELS[0]), float(LEVELS[LEVELS.size() - 1]))
	_build_tables()


## The highest level that still fits into the pixel budget of this map
func max_level() -> float:
	if map == null:
		return float(LEVELS[0])
	var area := maxf(map.width(), 1.0) * maxf(map.height(), 1.0) * float(LAYERS)
	var limit := sqrt(float(MAX_ATLAS_PIXELS) / maxf(area, 1.0))
	var best := float(LEVELS[0])
	for index in LEVELS.size():
		var candidate := float(LEVELS[index])
		if candidate <= limit and candidate > best:
			best = candidate
	return best


## Request a resolution; returns true when the change invalidates the baked atlas
func set_level(value: float) -> bool:
	var clamped := clampf(value, float(LEVELS[0]), float(LEVELS[LEVELS.size() - 1]))
	if is_equal_approx(clamped, level):
		return false
	level = clamped
	return true


func is_ready() -> bool:
	return texture != null and not _baked.is_empty()


func is_baked(layer: int) -> bool:
	return bool(_baked.get(layer, false))


func is_baking() -> bool:
	return _baking


func needs_geometry() -> bool:
	return _cell_count > 0 and _mask.is_empty()


## 0..1 progress of the geometry pass
func bake_progress() -> float:
	if _cell_count == 0:
		return 1.0
	return float(_cursor) / float(_cell_count)


func pixels_text() -> String:
	if width == 0:
		return "атлас не собран"
	return "%d×%d на слой, %d Мпикс всего" % [width, band_height, int(float(width * band_height * LAYERS) / 1000000.0)]


## Allocate the mask and the atlas buffer, then rasterize the cell polygons into the mask
func begin_bake() -> void:
	if _cell_count == 0:
		return
	width = int(ceilf(map.width() * level))
	band_height = int(ceilf(map.height() * level))
	var mask := PackedInt32Array()
	mask.resize(width * band_height)
	mask.fill(-1)
	_mask = mask
	var bytes := PackedByteArray()
	bytes.resize(width * band_height * LAYERS * 4)
	_bytes = bytes
	_baked.clear()
	_cursor = 0
	_baking = true


## Rasterize the next slice of cells; call it once per frame while `is_baking()` is true
func bake_step() -> void:
	if not _baking:
		return
	var target := mini(_cursor + CELLS_PER_STEP, _cell_count)
	while _cursor < target:
		_raster_cell(_cursor)
		_cursor += 1
	if _cursor >= _cell_count:
		_baking = false


## Geometry pass in one call (used by the tests and by the "пересобрать" button)
func bake_geometry() -> void:
	begin_bake()
	while _baking:
		var before := _cursor
		bake_step()
		if _cursor == before:
			break


## Fill the band of one layer from the mask and refresh the texture
func bake_layer(layer: int) -> void:
	if _mask.is_empty() or _table.is_empty() or layer < 0 or layer >= LAYERS:
		return
	var total := width * band_height
	var base := layer * total * 4
	var band := layer * _cell_count * 4
	for index in total:
		var cell := int(_mask[index])
		if cell < 0:
			continue
		var offset := base + (index << 2)
		var color := band + (cell << 2)
		_bytes[offset] = _table[color]
		_bytes[offset + 1] = _table[color + 1]
		_bytes[offset + 2] = _table[color + 2]
		_bytes[offset + 3] = 255
	_baked[layer] = true
	_rebuild_texture()


## Bake the geometry and one layer at once
func bake(layer: int) -> void:
	if needs_geometry():
		bake_geometry()
	bake_layer(layer)


func layer_count_baked() -> int:
	return _baked.size()


## Pixel rectangle of a layer inside the atlas
func region_of(layer: int) -> Rect2:
	return Rect2(0.0, float(layer * band_height), float(width), float(band_height))


## The pack cell drawn under a point in map coordinates (-1 outside the map)
func cell_at(point: Vector2) -> int:
	if _mask.is_empty():
		return -1
	var x := int(floorf(point.x * level))
	var y := int(floorf(point.y * level))
	if x < 0 or y < 0 or x >= width or y >= band_height:
		return -1
	return int(_mask[y * width + x])


## Color the atlas gives to a cell in a layer — also used by the tests
func color_of(layer: int, cell_id: int) -> Color:
	if layer < 0 or layer >= LAYERS or cell_id < 0 or cell_id >= _cell_count:
		return Color.TRANSPARENT
	var offset := (layer * _cell_count + cell_id) << 2
	return Color(
		float(_table[offset]) / 255.0, float(_table[offset + 1]) / 255.0, float(_table[offset + 2]) / 255.0, 1.0
	)


func layer_image(layer: int) -> Image:
	if _image == null:
		return null
	return _image.get_region(Rect2i(0, layer * band_height, width, band_height))


## Save a layer (or the whole atlas) as a PNG; `path` may be a user:// one
func save_png(layer: int, path: String) -> bool:
	if _image == null:
		return false
	var image := _image if layer < 0 else layer_image(layer)
	if image == null:
		return false
	var target := path if path.begins_with("/") else ProjectSettings.globalize_path(path)
	var directory := target.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var error := image.save_png(target)
	if error != OK:
		push_warning("MapAtlas: cannot write %s (%d)" % [target, error])
		return false
	return true


# ------------------------------------------------------------------ colors


## Per cell colors of every layer, computed once per map
func _build_tables() -> void:
	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var biomes: PackedInt32Array = cells.get("biome", PackedInt32Array())
	var states: PackedInt32Array = cells.get("state", PackedInt32Array())
	var religions: PackedInt32Array = cells.get("religion", PackedInt32Array())
	var zones := _zone_ids()
	# resize on a local and assign: a packed array read out of a container is a copy, so the
	# table is filled by index through the member from here on
	var table := PackedByteArray()
	table.resize(_cell_count * 4 * LAYERS)
	_table = table

	# packed arrays are copied when they are read out of a dictionary, so they are read once here
	var feature_ids: PackedInt32Array = cells.get("f", PackedInt32Array())
	var features: Array = map.pack.get("features", [])

	for cell_id in _cell_count:
		var height := int(heights[cell_id])
		var lake := _is_lake(feature_ids, features, cell_id)
		var base := _terrain_color(height, biomes, lake, cell_id)
		var zone_color := _zone_color(zones, cell_id)
		_put(0, cell_id, base)
		_put(1, cell_id, _tint(base, map.states(), states, cell_id, 0.55, false))
		_put(2, cell_id, _tint(base, map.religions(), religions, cell_id, 0.55, true))
		_put(3, cell_id, zone_color)
		_put(4, cell_id, _height_color(height))


func _put(layer: int, cell_id: int, color: Color) -> void:
	var offset := (layer * _cell_count + cell_id) << 2
	_table[offset] = color.r8
	_table[offset + 1] = color.g8
	_table[offset + 2] = color.b8
	_table[offset + 3] = 255


## Biome color shaded by height, water shaded by depth, lakes separated from the ocean
func _terrain_color(height: int, biomes: PackedInt32Array, lake: bool, cell_id: int) -> Color:
	if height < MapData.SEA_LEVEL:
		if lake:
			return LAKE_COLOR
		var depth := clampf(float(height) / float(MapData.SEA_LEVEL), 0.0, 1.0)
		return OCEAN_DEEP_COLOR.lerp(OCEAN_SHALLOW_COLOR, depth)
	var color := LAND_FALLBACK_COLOR
	if biomes.size() > cell_id:
		var biome_id := int(biomes[cell_id])
		if biome_id > 0 and biome_id < map.biomes.size():
			var biome: Dictionary = map.biomes[biome_id]
			color = FmgUtils.color_from_any(biome.get("color", ""), LAND_FALLBACK_COLOR)
	var ratio := clampf(float(height - MapData.SEA_LEVEL) / 72.0, 0.0, 1.0)
	return _shade(color, lerpf(-0.12, 0.16, ratio))


## Hypsometric tinting: two sea bands and six land bands, from shore to snow
func _height_color(height: int) -> Color:
	if height < MapData.SEA_LEVEL:
		var depth := clampf(float(height) / float(MapData.SEA_LEVEL), 0.0, 1.0)
		var sea: Color = HEIGHT_RAMP[0]
		var shore: Color = HEIGHT_RAMP[1]
		return sea.lerp(shore, depth)
	var ratio := clampf(float(height - MapData.SEA_LEVEL) / 80.0, 0.0, 0.999)
	var steps := HEIGHT_RAMP.size() - 2
	var color: Color = HEIGHT_RAMP[2 + int(ratio * float(steps))]
	return color


static func _is_lake(feature_ids: PackedInt32Array, features: Array, cell_id: int) -> bool:
	if feature_ids.is_empty() or features.is_empty() or cell_id >= feature_ids.size():
		return false
	var feature_id := int(feature_ids[cell_id])
	if feature_id <= 0 or feature_id >= features.size():
		return false
	var feature: Dictionary = features[feature_id]
	return str(feature.get("type", "")) == "lake"


## Recolor a layer with the color of an entity of the cell (a state, a religion)
func _tint(base: Color, list: Array, ids: PackedInt32Array, cell_id: int, weight: float, hue_fallback: bool) -> Color:
	if cell_id >= ids.size():
		return base
	var entity_id := int(ids[cell_id])
	if entity_id <= 0 or entity_id >= list.size():
		return base
	var entry: Dictionary = list[entity_id]
	var color := FmgUtils.color_from_any(entry.get("color", ""), Color.TRANSPARENT)
	if color == Color.TRANSPARENT:
		if not hue_fallback:
			return base
		color = _religion_color(entity_id)
	return _mix(base, color, weight)


func _religion_color(religion_id: int) -> Color:
	var hue := fmod(float(religion_id) * 0.37, 1.0)
	return Color.from_hsv(hue, 0.45, 0.85)


## Zones keep their cells, not the other way round — invert the list once for the atlas
func _zone_ids() -> PackedInt32Array:
	var zones: Array = map.pack.get("zones", [])
	var result := PackedInt32Array()
	result.resize(_cell_count)
	result.fill(-1)
	for index in zones.size():
		var zone: Dictionary = zones[index]
		var cells_of_zone: PackedInt32Array = zone.get("cells", PackedInt32Array())
		for cell_id in cells_of_zone:
			if cell_id >= 0 and cell_id < _cell_count:
				result[cell_id] = index
	return result


func _zone_color(ids: PackedInt32Array, cell_id: int) -> Color:
	var list: Array = map.pack.get("zones", [])
	var zone_id := int(ids[cell_id]) if cell_id < ids.size() else -1
	if zone_id < 0 or zone_id >= list.size():
		return Color("#e8e2cf")
	var zone: Dictionary = list[zone_id]
	return _mix(Color("#e8e2cf"), FmgUtils.color_from_any(zone.get("color", ""), Color.WHITE), 0.55)


static func _mix(a: Color, b: Color, weight: float) -> Color:
	return Color(lerpf(a.r, b.r, weight), lerpf(a.g, b.g, weight), lerpf(a.b, b.b, weight), 1.0)


static func _shade(color: Color, amount: float) -> Color:
	if amount >= 0.0:
		return _mix(color, Color.WHITE, amount)
	return _mix(color, Color("#2b2a26"), -amount)


# ------------------------------------------------------------------ rasterizer


## Scanline fill of one cell polygon into the mask
func _raster_cell(cell_id: int) -> void:
	var polygon: PackedVector2Array = map.pack_polygon(cell_id)
	var count := polygon.size()
	if count < 3:
		return
	_scaled.resize(count)
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for index in count:
		var point := polygon[index] * level
		_scaled[index] = point
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	var y_from := maxi(int(floorf(min_y)), 0)
	var y_to := mini(int(ceilf(max_y)), band_height) - 1
	if y_to < y_from:
		return
	for y in range(y_from, y_to + 1):
		_scanline(cell_id, y, count)


## Intersections of the cell polygon with a scanline, then fill the spans between them
func _scanline(cell_id: int, y: int, count: int) -> void:
	var scan := float(y) + 0.5
	_hits.resize(0)
	for index in count:
		var a: Vector2 = _scaled[index]
		var b: Vector2 = _scaled[(index + 1) % count]
		if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
			_hits.append(a.x + (scan - a.y) * (b.x - a.x) / (b.y - a.y))
	if _hits.size() < 2:
		return
	_hits.sort()
	var position := 0
	while position + 1 < _hits.size():
		var x_from := maxi(int(ceilf(float(_hits[position]) - 0.5)), 0)
		var x_to := mini(int(ceilf(float(_hits[position + 1]) - 0.5)) - 1, width - 1)
		var row := y * width
		for x in range(x_from, x_to + 1):
			_mask[row + x] = cell_id
		position += 2


func _rebuild_texture() -> void:
	# Image.create_from_data() is a static factory in Godot 4.7: it gives back the image or null
	var image := Image.create_from_data(width, band_height * LAYERS, false, Image.FORMAT_RGBA8, _bytes)
	if image == null:
		push_warning("MapAtlas: the atlas image could not be created (%d×%d)" % [width, band_height * LAYERS])
		return
	if texture != null and _image != null and _image.get_size() == image.get_size():
		texture.update(image)  # same shape, only the pixels changed — no reallocation
	else:
		texture = ImageTexture.create_from_image(image)
	_image = image
