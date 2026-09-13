## The world map screen: generates a map from the Fantasy Map Generator pipeline and shows it.
## Generation runs stage by stage with a frame in between, so the progress bar stays alive.
extends Control

const MINI_MAP_SCENE := "res://main.tscn"

var map: MapData
var renderer: MapRenderer

var _seed_input: LineEdit
var _generate_button: Button
var _progress: ProgressBar
var _status: Label
var _view_select: OptionButton
var _rivers_check: CheckBox
var _burgs_check: CheckBox
var _labels_check: CheckBox
var _generating := false


func _ready() -> void:
	_build_ui()
	_generate()


func _build_ui() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)

	renderer = MapRenderer.new()
	renderer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(renderer)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(268, 0)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Генератор мира"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	var seed_row := HBoxContainer.new()
	box.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Сид:"
	seed_row.add_child(seed_label)
	_seed_input = LineEdit.new()
	_seed_input.text = "123456"
	_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_input)

	_generate_button = Button.new()
	_generate_button.text = "Сгенерировать карту"
	_generate_button.pressed.connect(_generate)
	box.add_child(_generate_button)

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

	var view_row := HBoxContainer.new()
	box.add_child(view_row)
	var view_label := Label.new()
	view_label.text = "Слой:"
	view_row.add_child(view_label)
	_view_select = OptionButton.new()
	_view_select.add_item("Природа", MapRenderer.VIEW_BIOMES)
	_view_select.add_item("Государства", MapRenderer.VIEW_STATES)
	_view_select.add_item("Религии", MapRenderer.VIEW_RELIGIONS)
	_view_select.add_item("Зоны", MapRenderer.VIEW_ZONES)
	_view_select.item_selected.connect(func(index: int) -> void:
		renderer.set_view(_view_select.get_item_id(index)))
	view_row.add_child(_view_select)

	_rivers_check = CheckBox.new()
	_rivers_check.text = "Реки"
	_rivers_check.button_pressed = true
	_rivers_check.toggled.connect(func(pressed: bool) -> void:
		renderer.show_rivers = pressed
		renderer.queue_redraw())
	box.add_child(_rivers_check)

	_burgs_check = CheckBox.new()
	_burgs_check.text = "Города"
	_burgs_check.button_pressed = true
	_burgs_check.toggled.connect(func(pressed: bool) -> void:
		renderer.show_burgs = pressed
		renderer.queue_redraw())
	box.add_child(_burgs_check)

	_labels_check = CheckBox.new()
	_labels_check.text = "Названия"
	_labels_check.button_pressed = true
	_labels_check.toggled.connect(func(pressed: bool) -> void:
		renderer.show_labels = pressed
		renderer.queue_redraw())
	box.add_child(_labels_check)

	var hint := Label.new()
	hint.text = "Колесо мыши — масштаб, перетаскивание — сдвиг,\nправая кнопка — сброс."
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)

	var back := Button.new()
	back.text = "К мини-карте"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MINI_MAP_SCENE))
	box.add_child(back)


## Generate a map stage by stage, yielding a frame between stages
func _generate() -> void:
	if _generating:
		return
	_generating = true
	_generate_button.disabled = true
	_progress.value = 0
	_status.text = "Подготовка…"

	var seed_text := _seed_input.text.strip_edges()
	if seed_text == "":
		seed_text = str(FmgRandom.rand_i(100000, 999999))
		_seed_input.text = seed_text

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
		_status.text = "%d/%d · %s" % [index + 1, stages.size(), _stage_title(stage)]
		_progress.value = float(index) / float(stages.size()) * 100.0
		await get_tree().process_frame
		GenPipeline.run_stage(map, stage)

	_progress.value = 100.0
	var burgs: int = map.pack.get("burgs", []).size() - 1
	var states: int = map.pack.get("states", []).size() - 1
	_status.text = "Готово: сид %s, городов %d, государств %d" % [seed_text, maxi(burgs, 0), maxi(states, 0)]
	renderer.setup(map)
	_generate_button.disabled = false
	_generating = false


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
