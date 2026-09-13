extends Node2D

# Цивилизация мудрецов — минималистичный игровой прототип стратегии
const W := 1280.0
const H := 760.0
const BOARD_ORIGIN := Vector2(52, 142)
const HEX_R := 42.0
const COLS := 8
const ROWS := 6

var turn := 12
var wisdom := 284
var food := 176
var crystals := 43
var selected := Vector2i(3, 2)
var selected_name := "Сад созерцания"
var selected_desc := "Тихая роща, где ученики постигают язык звёзд."
var selected_kind := "forest"
var event_text := "Ветер принёс аромат дождя. Урожай мудрости увеличен."
var event_timer := 0.0
var log_lines: Array[String] = ["Ход 12: Совет проснулся", "Построен Сад созерцания", "Открыт путь к северным рунам"]
var tiles := {}
var font: Font

var palette := {
	"bg": Color("#0b1020"), "panel": Color("#111a2d"), "panel2": Color("#16223a"),
	"line": Color("#263653"), "text": Color("#e9f1ff"), "muted": Color("#8294b5"),
	"gold": Color("#f4c96b"), "cyan": Color("#62d9dc"), "green": Color("#80d39b"),
	"purple": Color("#ac91f5"), "danger": Color("#ec7d8f")
}

func _ready() -> void:
	font = ThemeDB.fallback_font
	_init_tiles()
	queue_redraw()

func _init_tiles() -> void:
	for y in ROWS:
		for x in COLS:
			var kinds := ["plain", "plain", "forest", "plain", "water", "plain", "mountain"]
			var kind: String = kinds[(x * 3 + y * 5) % kinds.size()]
			if Vector2i(x, y) == Vector2i(3, 2): kind = "garden"
			if Vector2i(x, y) == Vector2i(1, 1): kind = "city"
			if Vector2i(x, y) == Vector2i(5, 4): kind = "library"
			tiles[Vector2i(x, y)] = kind

func _process(delta: float) -> void:
	if event_timer > 0:
		event_timer -= delta
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), palette.bg)
	_draw_background()
	_draw_header()
	_draw_board()
	_draw_right_panel()
	_draw_bottom_bar()
	if event_timer > 0: _draw_toast()

func _draw_background() -> void:
	for i in range(12):
		var p := Vector2(90 + i * 113, 90 + sin(i * 2.7) * 30)
		draw_circle(p, 1.5, Color(0.35, 0.55, 0.8, 0.25))
	for i in range(5):
		draw_line(Vector2(0, 102 + i * 116), Vector2(W, 102 + i * 116), Color(0.15, 0.22, 0.36, 0.12), 1)

func _draw_header() -> void:
	draw_rect(Rect2(0, 0, W, 82), palette.panel)
	draw_line(Vector2(0, 81), Vector2(W, 81), palette.line, 1)
	draw_circle(Vector2(48, 40), 22, palette.gold)
	_draw_text(Vector2(39, 48), "✦", 23, palette.bg)
	_draw_text(Vector2(84, 35), "ЦИВИЛИЗАЦИЯ", 12, palette.muted)
	_draw_text(Vector2(84, 59), "Мудрецов", 24, palette.text)
	_draw_text(Vector2(430, 35), "ЭРА ПРОЗРЕНИЯ", 11, palette.muted)
	_draw_text(Vector2(430, 59), "Ход %02d" % turn, 22, palette.gold)
	_draw_resource(Vector2(630, 28), "✦", str(wisdom), palette.purple)
	_draw_resource(Vector2(760, 28), "♨", str(food), palette.green)
	_draw_resource(Vector2(880, 28), "◇", str(crystals), palette.cyan)
	_draw_text(Vector2(1020, 36), "СОВЕТ  7 / 10", 11, palette.muted)
	draw_rect(Rect2(1020, 46, 200, 6), palette.line, true)
	draw_rect(Rect2(1020, 46, 140, 6), palette.gold, true)
	_draw_text(Vector2(1190, 51), "70%", 11, palette.gold)

func _draw_resource(pos: Vector2, icon: String, value: String, color: Color) -> void:
	_draw_text(pos, icon, 20, color)
	_draw_text(pos + Vector2(27, 1), value, 20, palette.text)

func _draw_board() -> void:
	_draw_text(Vector2(52, 115), "ЗЕМЛИ СЕВЕРНОГО СВЕТА", 12, palette.muted)
	_draw_text(Vector2(390, 115), "Нажмите на клетку, чтобы изучить её", 12, Color("#526785"))
	for y in ROWS:
		for x in COLS:
			var cell := Vector2i(x, y)
			var center := _hex_center(cell)
			var kind: String = tiles[cell]
			var fill := _tile_color(kind)
			var points := _hex_points(center, HEX_R)
			draw_colored_polygon(points, fill)
			var outline := PackedVector2Array(points)
			outline.append(points[0])
			draw_polyline(outline, palette.line if cell != selected else palette.gold, 2.0)
			_draw_tile_icon(center, kind)
			if cell == selected:
				draw_arc(center, HEX_R + 5, 0, TAU, 6, Color(0.95, 0.79, 0.42, 0.85), 2)
	# roads between settlements
	_draw_road(_hex_center(Vector2i(1, 1)), _hex_center(Vector2i(3, 2)))
	_draw_road(_hex_center(Vector2i(3, 2)), _hex_center(Vector2i(5, 4)))

func _hex_center(cell: Vector2i) -> Vector2:
	return BOARD_ORIGIN + Vector2(cell.x * 82.0 + (41 if cell.y % 2 else 0), cell.y * 68.0)

func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6: pts.append(center + Vector2.from_angle(PI / 6 + i * PI / 3) * radius)
	return pts

func _tile_color(kind: String) -> Color:
	match kind:
		"water": return Color("#152d4b")
		"mountain": return Color("#29314a")
		"forest": return Color("#173b3a")
		"garden": return Color("#25443f")
		"city": return Color("#3b304d")
		"library": return Color("#3f3541")
	return Color("#182b3a")

func _draw_tile_icon(center: Vector2, kind: String) -> void:
	var c := palette.muted
	match kind:
		"water":
			c = palette.cyan; draw_arc(center, 12, 0.2, 2.9, 12, c, 2); draw_arc(center + Vector2(0, 7), 10, 0.2, 2.9, 12, c, 2)
		"mountain":
			c = Color("#8792b2"); draw_colored_polygon(PackedVector2Array([center + Vector2(-17, 12), center + Vector2(0, -15), center + Vector2(17, 12)]), c)
		"forest":
			c = palette.green; draw_circle(center + Vector2(-7, -3), 8, c); draw_circle(center + Vector2(7, -7), 10, c); draw_line(center + Vector2(0, 0), center + Vector2(0, 14), c, 3)
		"garden":
			c = palette.gold; draw_circle(center, 15, Color(0.95, 0.79, 0.42, 0.18)); draw_circle(center, 6, c); draw_line(center + Vector2(-15, 0), center + Vector2(15, 0), c, 2); draw_line(center + Vector2(0, -15), center + Vector2(0, 15), c, 2)
		"city":
			c = palette.purple; draw_rect(Rect2(center - Vector2(13, 10), Vector2(26, 20)), c); draw_rect(Rect2(center - Vector2(6, 18), Vector2(12, 8)), c); draw_rect(Rect2(center - Vector2(4, 5), Vector2(4, 5)), palette.panel)
		"library":
			c = palette.gold; draw_rect(Rect2(center - Vector2(15, 11), Vector2(30, 21)), c); draw_line(center + Vector2(-9, -9), center + Vector2(-9, 10), palette.panel, 3); draw_line(center + Vector2(0, -9), center + Vector2(0, 10), palette.panel, 3); draw_line(center + Vector2(9, -9), center + Vector2(9, 10), palette.panel, 3)

func _draw_road(a: Vector2, b: Vector2) -> void:
	draw_dashed_line(a, b, Color(0.95, 0.75, 0.35, 0.42), 2, 5)

func _draw_right_panel() -> void:
	var r := Rect2(790, 105, 438, 490)
	draw_rect(r, palette.panel, true); draw_rect(r, palette.line, false, 1)
	_draw_text(Vector2(820, 140), "ИЗУЧЕНИЕ ЗЕМЛИ", 11, palette.muted)
	_draw_text(Vector2(820, 180), selected_name, 26, palette.text)
	_draw_text(Vector2(820, 210), selected_desc, 14, palette.muted)
	draw_line(Vector2(820, 235), Vector2(1198, 235), palette.line, 1)
	_draw_text(Vector2(820, 266), "ПРОИЗВОДСТВО", 11, palette.muted)
	_draw_stat(Vector2(820, 292), "✦  Мудрость", "+12 / ход", palette.purple)
	_draw_stat(Vector2(820, 330), "♨  Пища", "+8 / ход", palette.green)
	_draw_stat(Vector2(820, 368), "◇  Открытие", "доступно", palette.cyan)
	_draw_text(Vector2(820, 416), "ДЕЙСТВИЯ", 11, palette.muted)
	_button(Rect2(820, 438, 174, 42), "ПОСТРОИТЬ", palette.gold, true)
	_button(Rect2(1005, 438, 193, 42), "ИЗУЧИТЬ РУНЫ", palette.cyan, false)
	_draw_text(Vector2(820, 530), "Совет мудрецов", 14, palette.gold)
	_draw_text(Vector2(820, 554), "«Истинная сила — в вопросах,", 13, palette.muted)
	_draw_text(Vector2(820, 574), "на которые мы ещё не ответили.»", 13, palette.muted)

func _draw_stat(pos: Vector2, label: String, val: String, color: Color) -> void:
	_draw_text(pos, label, 14, color); _draw_text(pos + Vector2(225, 0), val, 14, palette.text)

func _button(rect: Rect2, text: String, color: Color, filled: bool) -> void:
	draw_rect(rect, Color(color, 0.18) if filled else Color(0, 0, 0, 0), true)
	draw_rect(rect, color, false, 1)
	_draw_text(rect.position + Vector2(18, 27), text, 12, color)

func _draw_bottom_bar() -> void:
	draw_rect(Rect2(52, 604, 1176, 112), palette.panel, true)
	draw_rect(Rect2(52, 604, 1176, 112), palette.line, false, 1)
	_draw_text(Vector2(76, 633), "ХРОНИКА СОБЫТИЙ", 11, palette.muted)
	for i in min(3, log_lines.size()):
		_draw_text(Vector2(76, 659 + i * 17), "•  " + log_lines[i], 12, palette.muted if i > 0 else palette.text)
	_button(Rect2(1000, 638, 198, 52), "ЗАВЕРШИТЬ ХОД  [ПРОБЕЛ]", palette.gold, true)
	_button(Rect2(760, 638, 220, 52), "КАРТА МИРА  [M]", palette.text, false)

func _draw_toast() -> void:
	var rect := Rect2(390, 92, 360, 40)
	draw_rect(rect, Color("#253858"), true); draw_rect(rect, palette.gold, false, 1)
	_draw_text(rect.position + Vector2(16, 25), event_text, 12, palette.text)

func _draw_text(pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_end_turn(); get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		get_tree().change_scene_to_file("res://src/view/world_map.tscn")
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := event.position
		for y in ROWS:
			for x in COLS:
				var cell := Vector2i(x, y)
				if mouse.distance_to(_hex_center(cell)) < HEX_R:
					_select_cell(cell); return
			if Rect2(1000, 638, 198, 52).has_point(mouse): _end_turn()
			if Rect2(820, 438, 174, 42).has_point(mouse): _build()
			if Rect2(760, 638, 220, 52).has_point(mouse): get_tree().change_scene_to_file("res://src/view/world_map.tscn")

func _select_cell(cell: Vector2i) -> void:
	selected = cell
	selected_kind = tiles[cell]
	var names := {"plain":"Равнина спокойствия", "forest":"Лес шёпота", "water":"Озеро памяти", "mountain":"Горы испытаний", "garden":"Сад созерцания", "city":"Город Астерион", "library":"Великая библиотека"}
	var descs := {"plain":"Просторная земля для будущих свершений.", "forest":"Древние деревья хранят голоса первых мудрецов.", "water":"Чистая вода отражает созвездия грядущего.", "mountain":"Камень и высота закаляют дух исследователя.", "garden":"Тихая роща, где ученики постигают язык звёзд.", "city":"Первый город, объединивший семь школ мысли.", "library":"Здесь собраны свитки всех известных цивилизаций."}
	selected_name = names[selected_kind]
	selected_desc = descs[selected_kind]
	queue_redraw()

func _end_turn() -> void:
	turn += 1; wisdom += 12; food += 8; crystals += 1
	log_lines.push_front("Ход %02d: мудрость течёт по землям" % turn)
	if log_lines.size() > 3:
		log_lines.pop_back()
	event_text = "Ход %d завершён · Совет получил новые знания" % turn
	event_timer = 3.0; queue_redraw()

func _build() -> void:
	if wisdom >= 30:
		wisdom -= 30
		log_lines.push_front("Построено новое святилище")
		if log_lines.size() > 3:
			log_lines.pop_back()
		event_text = "Святилище возведено! +12 мудрости каждый ход"; event_timer = 3.0; queue_redraw()
