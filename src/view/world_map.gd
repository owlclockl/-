## The world map screen: generates a map with the ported Fantasy Map Generator pipeline and draws
## it through the atlas. Generation runs stage by stage with a frame in between — and so does the
## atlas bake — so the progress bar and the interface stay alive on a map of 10000 points.
##
## The panel on the left drives the generator, the layers and the atlas resolution; the "Атлас" box
## in the corner reports everything the packed graph knows about the cell under the cursor, like
## the atlas panel of the web application does.
extends Control

const MINI_MAP_SCENE := "res://main.tscn"
const EXPORT_DIR := "user://maps"

## File name slugs of the layers, in the MapAtlas order
const VIEW_SLUGS: Array = ["biomes", "states", "religions", "zones", "heights"]

var map: MapData
var renderer: MapRenderer

var _seed_input: LineEdit
var _generate_button: Button
var _progress: ProgressBar
var _status: Label
var _view_select: OptionButton
var _level_select: OptionButton
var _stats_label: Label
var _zoom_label: Label
var _atlas_panel: PanelContainer
var _atlas_info: Label
var _rivers_check: CheckBox
var _coast_check: CheckBox
var _borders_check: CheckBox
var _burgs_check: CheckBox
var _labels_check: CheckBox
var _generating := false
var _generation_ms := 0


func _ready() -> void:
	_build_ui()
	_generate()


func _process(_delta: float) -> void:
	if renderer == null or _zoom_label == null:
		return
	var text := "масштаб %.2f× · %s · слоёв атласа %d/%d" % [
		renderer.zoom_value(), renderer.atlas_pixels_text(),
		renderer.atlas.layer_count_baked(), MapAtlas.LAYERS
	]
	if text != _zoom_label.text:
		_zoom_label.text = text


# ------------------------------------------------------------------ interface


func _build_ui() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)

	renderer = MapRenderer.new()
	renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(renderer)
	renderer.cell_hovered.connect(_on_cell_hovered)

	_build_control_panel()
	_build_atlas_panel()


func _build_control_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(286, 0)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Генератор мира"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	box.add_child(_build_seed_row())
	box.add_child(_build_view_row())
	box.add_child(_build_switches())
	box.add_child(_build_tools_row())

	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.value = 0
	_progress.show_percentage = false
	box.add_child(_progress)

	_status = Label.new()
	_status.text = "Готово"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	_zoom_label = Label.new()
	_zoom_label.add_theme_font_size_override("font_size", 11)
	_zoom_label.modulate = Color(1, 1, 1, 0.72)
	box.add_child(_zoom_label)

	box.add_child(HSeparator.new())

	_stats_label = Label.new()
	_stats_label.text = "мир ещё не собран"
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_stats_label)

	var back := Button.new()
	back.text = "К мини-карте  (M)"
	back.pressed.connect(_back_to_game)
	box.add_child(back)

	var hint := Label.new()
	hint.text = "колесо — масштаб, перетаскивание — сдвиг, правая кнопка — сброс вида;\nклавиши G, R, S, 1…5, M и Esc"
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(1, 1, 1, 0.55)
	box.add_child(hint)


func _build_seed_row() -> Control:
	var row := HBoxContainer.new()
	var seed_label := Label.new()
	seed_label.text = "Сид:"
	row.add_child(seed_label)

	_seed_input = LineEdit.new()
	_seed_input.text = "123456"
	_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_input.tooltip_text = "Один и тот же сид даёт один и тот же мир"
	_seed_input.text_submitted.connect(func(_text: String) -> void: _generate())
	row.add_child(_seed_input)

	var dice := Button.new()
	dice.text = "🎲"
	dice.tooltip_text = "Случайный сид"
	dice.pressed.connect(func() -> void:
		_seed_input.text = str(randi_range(100000, 999999)))
	row.add_child(dice)

	_generate_button = Button.new()
	_generate_button.text = "Сгенерировать  (G)"
	_generate_button.tooltip_text = "Прогнать весь конвейер и пересобрать атлас"
	_generate_button.pressed.connect(_generate)

	var box := VBoxContainer.new()
	box.add_child(row)
	box.add_child(_generate_button)
	return box


func _build_view_row() -> Control:
	var row := HBoxContainer.new()
	var view_label := Label.new()
	view_label.text = "Слой:"
	row.add_child(view_label)

	_view_select = OptionButton.new()
	_view_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in MapAtlas.LABELS.size():
		_view_select.add_item(str(MapAtlas.LABELS[index]), index)
	_view_select.select(0) # do not rely on the widget picking a default for us
	_view_select.item_selected.connect(_on_view_selected)
	row.add_child(_view_select)

	var level_label := Label.new()
	level_label.text = "Атлас:"
	row.add_child(level_label)

	_level_select = OptionButton.new()
	_level_select.tooltip_text = "Пикселей атласа на единицу карты"
	for index in MapAtlas.LEVELS.size():
		_level_select.add_item("%d×" % (index + 1), index)
	_level_select.item_selected.connect(_on_level_selected)
	row.add_child(_level_select)
	return row


func _build_switches() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	_rivers_check = _switch(grid, "Реки", true)
	_coast_check = _switch(grid, "Берега", true)
	_burgs_check = _switch(grid, "Города", true)
	_borders_check = _switch(grid, "Границы", true)
	_labels_check = _switch(grid, "Названия", true)
	return grid


func _switch(parent: Control, text: String, pressed: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = pressed
	check.toggled.connect(_on_switches_changed)
	parent.add_child(check)
	return check


func _build_tools_row() -> Control:
	var row := HBoxContainer.new()
	row.add_child(_tool_button("−", "Отдалить", func() -> void: renderer.zoom_by(1.0 / 1.25)))
	row.add_child(_tool_button("+", "Приблизить", func() -> void: renderer.zoom_by(1.25)))
	row.add_child(_tool_button("⟲", "Сбросить вид (R)", renderer.reset_view))
	row.add_child(_tool_button("⤓", "Сохранить слой в PNG (S)", _save_png))
	return row


func _tool_button(text: String, tooltip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button


func _build_atlas_panel() -> void:
	_atlas_panel = PanelContainer.new()
	_atlas_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_atlas_panel.offset_left = -338
	_atlas_panel.offset_top = -186
	_atlas_panel.offset_right = -12
	_atlas_panel.offset_bottom = -12
	_atlas_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atlas_panel.visible = false
	add_child(_atlas_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_atlas_panel.add_child(box)

	var title := Label.new()
	title.text = "Атлас"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.98, 0.89, 0.62)
	box.add_child(title)

	_atlas_info = Label.new()
	_atlas_info.text = "—"
	_atlas_info.add_theme_font_size_override("font_size", 11)
	_atlas_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_atlas_info)


# ------------------------------------------------------------------ generation


## Generate a map stage by stage, yielding a frame between stages
func _generate() -> void:
	if _generating:
		return
	_generating = true
	_generate_button.disabled = true
	_progress.value = 0
	_status.text = "Подготовка…"

	var seed_text := _seed_input.text.strip_edges()
	if seed_text.is_empty():
		seed_text = str(randi_range(100000, 999999))
		_seed_input.text = seed_text

	var started := Time.get_ticks_msec()
	map = MapData.new()
	map.seed_text = seed_text
	map.options = GenOptions.defaults()
	map.options["seed"] = seed_text
	map.options["graph"]["width"] = 1000.0
	map.options["graph"]["height"] = 600.0
	map.options["graph"]["points"] = 10000

	var stages: Array = GenPipeline.STAGES
	for index in stages.size():
		var stage := str(stages[index])
		_status.text = "генерация %d/%d · %s" % [index + 1, stages.size(), _stage_title(stage)]
		_progress.value = float(index) / float(stages.size()) * 75.0
		await get_tree().process_frame
		GenPipeline.run_stage(map, stage)

	_status.text = "атлас: геометрия слоёв…"
	await get_tree().process_frame
	renderer.setup(map)
	while renderer.bake_geometry_step():
		_progress.value = 75.0 + 20.0 * renderer.bake_progress()
		await get_tree().process_frame

	var first_layer := _view_select.get_selected_id()
	await _bake_layer(first_layer if first_layer >= 0 else MapAtlas.VIEW_BIOMES)
	_generation_ms = Time.get_ticks_msec() - started
	_refresh_summary()
	_generate_button.disabled = false
	_generating = false


## Rasterize one layer band; the status line keeps the wait honest
func _bake_layer(layer: int) -> void:
	if layer < 0 or renderer.atlas.is_baked(layer):
		return
	_status.text = "атлас: слой «%s»…" % renderer.view_title(layer)
	_progress.value = 96.0
	await get_tree().process_frame
	renderer.bake(layer)
	_progress.value = 100.0


func _refresh_summary() -> void:
	if map == null or map.pack.is_empty():
		return
	var burgs: int = maxi(map.burgs().size() - 1, 0)
	var states: int = maxi(map.states().size() - 1, 0)
	_status.text = "сид %s · %d городов · %d государств · атлас %s" % [
		map.seed_text, burgs, states, renderer.view_title(renderer.view)
	]
	_stats_label.text = _stats_text()
	_refresh_level_select()


func _refresh_level_select() -> void:
	var maximum := renderer.max_level()
	for index in MapAtlas.LEVELS.size():
		_level_select.set_item_disabled(index, float(MapAtlas.LEVELS[index]) > maximum)
	for index in MapAtlas.LEVELS.size():
		if is_equal_approx(float(MapAtlas.LEVELS[index]), renderer.level()):
			_level_select.select(index)
			break


# ------------------------------------------------------------------ layer and atlas controls


func _on_view_selected(index: int) -> void:
	var layer := _view_select.get_item_id(index)
	_view_select.select(index)
	renderer.set_view(layer)
	await _bake_layer(layer)
	_refresh_summary()


func _on_level_selected(index: int) -> void:
	var level := float(MapAtlas.LEVELS[_level_select.get_item_id(index)])
	if not renderer.set_level(level):
		return
	_status.text = "атлас пересобирается в %d×…" % int(level)
	await get_tree().process_frame
	renderer.setup(map)
	while renderer.bake_geometry_step():
		_progress.value = 20.0 * renderer.bake_progress()
		await get_tree().process_frame
	await _bake_layer(renderer.view)
	_refresh_summary()


func _select_layer(index: int) -> void:
	if index < 0 or index >= _view_select.item_count:
		return
	_view_select.select(index)
	_on_view_selected(index)


func _on_switches_changed(_pressed: bool) -> void:
	if renderer == null:
		return
	renderer.show_rivers = _rivers_check.button_pressed
	renderer.show_coast = _coast_check.button_pressed
	renderer.show_borders = _borders_check.button_pressed
	renderer.show_burgs = _burgs_check.button_pressed
	renderer.show_labels = _labels_check.button_pressed
	renderer.queue_redraw()


func _save_png() -> void:
	if renderer == null or not renderer.atlas.is_ready():
		_status.text = "атлас ещё не собран — нечего сохранять"
		return
	var index: int = MapRenderer.VIEWS.find(renderer.view)
	var slug := "layer%d" % index
	if index >= 0 and index < VIEW_SLUGS.size():
		slug = str(VIEW_SLUGS[index])
	var path := "%s/world_%s_%s.png" % [EXPORT_DIR, _safe_name(map.seed_text), slug]
	if renderer.atlas.save_png(renderer.view, path):
		_status.text = "сохранено: %s" % ProjectSettings.globalize_path(path)
	else:
		_status.text = "не удалось записать %s" % path


func _back_to_game() -> void:
	get_tree().change_scene_to_file(MINI_MAP_SCENE)


# ------------------------------------------------------------------ the atlas box


func _on_cell_hovered(cell_id: int) -> void:
	if _atlas_info == null:
		return
	if cell_id < 0:
		_atlas_panel.visible = false
		return
	_atlas_panel.visible = true
	_atlas_info.text = _describe_cell(cell_id)


## Everything the packed graph knows about one cell. The generators fill the arrays stage by
## stage, so a mid-generation hover has to survive missing layers — hence the bounds helpers.
func _describe_cell(cell_id: int) -> String:
	if map == null or map.pack.is_empty():
		return "—"
	var cells: Dictionary = map.pack["cells"]
	var points: PackedVector2Array = cells["p"]
	if cell_id < 0 or cell_id >= points.size():
		return "—"
	var heights: PackedInt32Array = cells["h"]
	var grid_ids: PackedInt32Array = cells["g"]
	var point := points[cell_id]
	var height := _int_at(heights, cell_id, 0)
	var grid_id := _int_at(grid_ids, cell_id, -1)
	var temperature := 0
	var precipitation := 0
	if map.grid.has("cells") and grid_id >= 0:
		var grid_cells: Dictionary = map.grid["cells"]
		temperature = _int_at(grid_cells.get("temp", PackedInt32Array()), grid_id, 0)
		precipitation = _int_at(grid_cells.get("prec", PackedInt32Array()), grid_id, 0)

	var lines := PackedStringArray()
	lines.append("клетка %d · %.1f : %.1f" % [cell_id, point.x, point.y])
	if height >= MapData.SEA_LEVEL:
		var meters := 0
		if grid_id >= 0 and grid_id < map.grid_cell_count():
			meters = int(GenHeightmap.elevation_meters(map, grid_id))
		lines.append("высота %d м · %d° · осадки %d" % [meters, temperature, precipitation])
		lines.append("биом: %s" % _entity_name(map.biomes, _int_at(cells.get("biome", PackedInt32Array()), cell_id, 0), "name", "—"))
	else:
		lines.append("глубина %d · %d° · осадки %d" % [MapData.SEA_LEVEL - height, temperature, precipitation])
		lines.append("вода: %s" % ("озеро" if _is_lake(cell_id) else "океан"))

	lines.append("государство: %s" % _entity_name(map.states(), _int_at(cells.get("state", PackedInt32Array()), cell_id, 0), "fullName", "дикие земли"))
	lines.append("культура: %s · религия: %s" % [
		_entity_name(map.cultures(), _int_at(cells.get("culture", PackedInt32Array()), cell_id, 0), "name", "—"),
		_entity_name(map.religions(), _int_at(cells.get("religion", PackedInt32Array()), cell_id, 0), "name", "нет"),
	])
	lines.append("провинция: %d · податное население: %d" % [
		_int_at(cells.get("province", PackedInt32Array()), cell_id, 0),
		int(_float_at(cells.get("pop", PackedFloat32Array()), cell_id, 0.0)),
	])

	var burg_id := _int_at(cells.get("burg", PackedInt32Array()), cell_id, 0)
	if burg_id > 0:
		var burg: Dictionary = _list_entry(map.burgs(), burg_id)
		lines.append("поселение: %s · %d жителей · %s" % [
			str(burg.get("name", "—")), int(float(burg.get("population", 0.0))), str(burg.get("type", "Generic"))
		])
	var river_id := _int_at(cells.get("r", PackedInt32Array()), cell_id, 0)
	if river_id > 0:
		var river: Dictionary = _list_entry(map.rivers(), river_id)
		lines.append("река: %s · расход %d · длина %d · приток %d" % [
			str(river.get("name", "—")), int(float(river.get("discharge", 0))),
			int(float(river.get("length", 0))), int(river.get("parent", 0))
		])
	return "\n".join(lines)


func _int_at(values: PackedInt32Array, index: int, fallback: int) -> int:
	if index < 0 or index >= values.size():
		return fallback
	return int(values[index])


func _float_at(values: PackedFloat32Array, index: int, fallback: float) -> float:
	if index < 0 or index >= values.size():
		return fallback
	return float(values[index])


func _is_lake(cell_id: int) -> bool:
	var cells: Dictionary = map.pack["cells"]
	var features: Array = map.pack.get("features", [])
	var feature_ids: PackedInt32Array = cells.get("f", PackedInt32Array())
	if feature_ids.is_empty() or features.is_empty() or cell_id >= feature_ids.size():
		return false
	var feature_id := int(feature_ids[cell_id])
	if feature_id <= 0 or feature_id >= features.size():
		return false
	var feature: Dictionary = features[feature_id]
	return str(feature.get("type", "")) == "lake"


func _stats_text() -> String:
	if map == null or map.pack.is_empty():
		return "мир ещё не собран"
	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var land := 0
	for height in heights:
		if int(height) >= MapData.SEA_LEVEL:
			land += 1
	var share := 100.0 * float(land) / float(maxi(heights.size(), 1))
	var rows := PackedStringArray()
	rows.append("клеток %s · суши %.0f%%" % [_group(heights.size()), share])
	rows.append("рек %d · городов %d · государств %d" % [
		maxi(map.rivers().size(), 0),
		maxi(map.burgs().size() - 1, 0),
		maxi(map.states().size() - 1, 0),
	])
	rows.append("культур %d · религий %d · провинций %d" % [
		maxi(map.cultures().size() - 1, 0),
		maxi(map.religions().size() - 1, 0),
		maxi(map.provinces().size() - 1, 0),
	])
	rows.append("дорог %d · маркеров %d · генерация %d мс" % [
		map.routes().size(), map.markers().size(), _generation_ms
	])
	return "\n".join(rows)


## Only characters that are safe in a file name, on a file system we do not choose
func _safe_name(value: String) -> String:
	var out := ""
	for character in value.to_lower():
		var keep := character == "." or character == "-" or character == "_"
		if not keep and character.length() == 1:
			var code := character.unicode_at(0)
			keep = (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
		out += character if keep else "-"
	if out.is_empty():
		return "map"
	return out.substr(0, 32)


## Thousands separated by thin spaces, the way the panel reads better
func _group(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	var digits := 0
	for index in range(text.length() - 1, -1, -1):
		out = text[index] + out
		digits += 1
		if digits % 3 == 0 and index > 0:
			out = " " + out
	return ("-" + out) if value < 0 else out


# ------------------------------------------------------------------ helpers


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_1 + MapAtlas.LAYERS - 1:
		_select_layer(key.physical_keycode - KEY_1)
		return
	match key.physical_keycode:
		KEY_G:
			_generate()
		KEY_R:
			renderer.reset_view()
		KEY_S:
			_save_png()
		KEY_M, KEY_ESCAPE:
			_back_to_game()


## The entry of a list whose `i` field is the id (rivers and provinces are compacted)
func _list_entry(list: Array, id: int) -> Dictionary:
	if id <= 0 or id > list.size():
		return {}
	var candidate: Dictionary = list[id - 1]
	if int(candidate.get("i", -1)) == id:
		return candidate
	for entry: Dictionary in list:
		if int(entry.get("i", -1)) == id:
			return entry
	return {}


func _entity_name(list: Array, id: int, key: String, fallback: String) -> String:
	var entry: Dictionary = _list_entry(list, id)
	if entry.is_empty():
		return fallback
	return str(entry.get(key, fallback))


func _stage_title(stage: String) -> String:
	match stage:
		"grid":
			return "сетка"
		"heightmap":
			return "высоты"
		"features":
			return "берега и озёра"
		"coordinates":
			return "координаты"
		"climate":
			return "климат"
		"pack":
			return "граф карты"
		"rivers":
			return "реки"
		"biomes":
			return "биомы"
		"population":
			return "население"
		"cultures":
			return "культуры"
		"burgs":
			return "города"
		"states":
			return "государства"
		"routes":
			return "дороги"
		"religions":
			return "религии"
		"provinces":
			return "провинции"
		_:
			return "детали"
