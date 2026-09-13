## Shared helpers ported from Fantasy Map Generator's `src/utils` (MIT licensed, Azgaar).
## Names keep the original short forms (rn, lim, minmax, ra, rw, P...) so ported generator code
## can be compared with the TypeScript sources line by line.
class_name FmgUtils
extends RefCounted

const SEA_LEVEL := 20
const UINT16_MAX_VALUE := 65535
const INT8_MAX_VALUE := 127


## Math.round for a value scaled to `decimals` decimals (matches JS Math.round, i.e. floor(v + 0.5))
static func rn(v: float, decimals: int = 0) -> float:
	var m := pow(10.0, float(decimals))
	return floor(v * m + 0.5) / m


static func lim(v: float) -> float:
	return minmax(v, 0.0, 100.0)


static func minmax(value: float, min_value: float, max_value: float) -> float:
	return min(max(value, min_value), max_value)


static func clamp_int(value: int, min_value: int, max_value: int) -> int:
	return min(max(value, min_value), max_value)


static func normalize_value(value: float, min_value: float, max_value: float) -> float:
	if is_equal_approx(max_value, min_value):
		return 0.0
	return minmax((value - min_value) / (max_value - min_value), 0.0, 1.0)


static func lerp_value(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


## number from a template string like "1-3", "2" or "0.5" (see FMG getNumberInRange)
static func get_number_in_range(range_text: String) -> float:
	var text := range_text.strip_edges()
	if text.is_valid_float():
		var value := text.to_float()
		var whole := floorf(value)
		var fraction := value - whole
		if fraction > 0.0 and FmgRandom.next() < fraction:
			return whole + 1.0
		return whole
	if text.is_valid_int():
		return text.to_float()

	var sign_value := -1.0 if text.begins_with("-") else 1.0
	if text.length() and not text[0].is_valid_int():
		text = text.substr(1)
	if not text.contains("-"):
		return 0.0
	var parts := text.split("-")
	if parts.size() < 2:
		return 0.0
	var min_value := parts[0].to_float() * sign_value
	var max_value := parts[1].to_float() * sign_value
	return FmgRandom.rand_float_between(min_value, max_value)


static func distance_squared(a: Vector2, b: Vector2) -> float:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy


static func mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return (float(sorted[middle - 1]) + float(sorted[middle])) / 2.0


static func sum(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total


static func max_of(values: Array) -> float:
	var best := -INF
	for value in values:
		best = max(best, float(value))
	return best


static func min_of(values: Array) -> float:
	var best := INF
	for value in values:
		best = min(best, float(value))
	return best


static func unique_ints(values: Array) -> PackedInt32Array:
	var seen := {}
	var result := PackedInt32Array()
	for value in values:
		var int_value := int(value)
		if seen.has(int_value):
			continue
		seen[int_value] = true
		result.append(int_value)
	return result


static func last_int(values: PackedInt32Array) -> int:
	return values[values.size() - 1] if values.size() > 0 else 0


static func capitalize(input: String) -> String:
	if input.is_empty():
		return input
	return input.substr(0, 1).to_upper() + input.substr(1)


static func is_vowel(character: String) -> bool:
	const VOWELS := "aeiouyɑ'əøɛœæɶɒɨɪɔɐʊɤɯаоиеёэыуюяàèìòùỳẁȁȅȉȍȕáéíóúýẃőűâêîôûŷŵäëïöüÿẅãẽĩõũỹąęįǫųāēīōūȳăĕĭŏŭǎěǐǒǔȧėȯẏẇạẹịọụỵẉḛḭṵṳ"
	return VOWELS.contains(character.to_lower())


## See FMG languageUtils.abbreviate: two-letter code used for culture codes
static func abbreviate(name: String, restricted: Array = []) -> String:
	var parsed := name.replace("Old ", "O ").replace("(", "").replace(")", "")
	var words := parsed.split(" ", false)
	if words.is_empty():
		return ""
	var letters := ""
	for word in words:
		letters += word
	var code := ""
	if words.size() == 2:
		code = words[0].substr(0, 1) + words[1].substr(0, 1)
	else:
		code = letters.substr(0, min(2, letters.length()))
	var i := 1
	while i < letters.length() - 1 and restricted.has(code):
		code = letters.substr(0, 1) + letters.substr(i, 1).to_upper()
		i += 1
	return code


## Shoelace formula, same as d3.polygonArea: positive for counter-clockwise rings
static func polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var total := 0.0
	var count := points.size()
	for i in count:
		var p := points[i]
		var next := points[(i + 1) % count]
		total += p.x * next.y - next.x * p.y
	return total / 2.0


static func polygon_area_abs(points: PackedVector2Array) -> float:
	return absf(polygon_area(points))


static func polygon_centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var area := polygon_area(points)
	if is_zero_approx(area):
		var total := Vector2.ZERO
		for p in points:
			total += p
		return total / float(points.size())
	var cx := 0.0
	var cy := 0.0
	var count := points.size()
	for i in count:
		var p := points[i]
		var next := points[(i + 1) % count]
		var cross := p.x * next.y - next.x * p.y
		cx += (p.x + next.x) * cross
		cy += (p.y + next.y) * cross
	var factor := 1.0 / (6.0 * area)
	return Vector2(cx * factor, cy * factor)


static func point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var inside := false
	var count := polygon.size()
	var j := count - 1
	for i in count:
		var pi := polygon[i]
		var pj := polygon[j]
		if ((pi.y > point.y) != (pj.y > point.y)) and point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x:
			inside = not inside
		j = i
	return inside


## Colour helpers, ported from FMG colorUtils (d3 interpolate replaced with a plain RGB mix)
static func color_to_hex(color: Color) -> String:
	return "#" + color.to_html(false)


static func color_from_any(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if value is Color:
		return value
	var text := str(value)
	if text.is_empty():
		return fallback
	if text.begins_with("#") and Color.html_is_valid(text):
		return Color.html(text)
	if Color.html_is_valid(text):
		return Color.html(text)
	return fallback


static func get_mixed_color(base: Color, mix := 0.2, bright := 0.3) -> Color:
	var random_color := get_random_color()
	var mixed := base.lerp(random_color, mix)
	return Color(
		clampf(mixed.r + bright * 0.35, 0.0, 1.0),
		clampf(mixed.g + bright * 0.35, 0.0, 1.0),
		clampf(mixed.b + bright * 0.35, 0.0, 1.0),
		base.a
	)


static func get_random_color() -> Color:
	return Color.from_hsv(FmgRandom.next(), FmgRandom.rand_float_between(0.35, 0.75), FmgRandom.rand_float_between(0.6, 1.0))


## Palette of 12 distinct pastel colours (C_12 from FMG), shuffled the same way FMG does
const C_12 := [
	"#dababf", "#fb8072", "#80b1d3", "#fdb462", "#b3de69", "#fccde5",
	"#c6b9c1", "#bc80bd", "#ccebc5", "#ffed6f", "#8dd3c7", "#eb8de7"
]


static func get_colors(count: int) -> Array:
	var colors: Array = []
	for i in count:
		if i < C_12.size():
			colors.append(Color.html(C_12[i]))
		else:
			var t := float(i - C_12.size()) / maxf(1.0, float(count - C_12.size()))
			colors.append(Color.from_hsv(fmod(t * 0.85 + 0.05, 1.0), 0.55, 0.9))
	# Fisher-Yates shuffle with the seeded RNG (d3.shuffler equivalent)
	for i in range(colors.size() - 1, 0, -1):
		var j := FmgRandom.rand_i(0, i)
		var tmp: Variant = colors[i]
		colors[i] = colors[j]
		colors[j] = tmp
	return colors


## Boundary rings of a union of polygons: edges that appear once belong to the outline.
## Returns an array of rings (each a PackedVector2Array). Rings of cells touching the map
## border stay closed because every cell polygon is finite.
static func build_boundary_rings(polygons: Array, vertices: Array) -> Array:
	var directed := {} # "a_b" -> true for every directed edge of the union
	var order: Array = []
	for polygon in polygons:
		var ids: PackedInt32Array = polygon
		var count := ids.size()
		for i in count:
			var a := ids[i]
			var b := ids[(i + 1) % count]
			var key := "%d_%d" % [a, b]
			if not directed.has(key):
				directed[key] = true
				order.append([a, b])
	# outline edges are the ones whose reverse is missing
	var next_of := {}
	for edge in order:
		var a: int = edge[0]
		var b: int = edge[1]
		if directed.has("%d_%d" % [b, a]):
			continue
		next_of[a] = b
	var rings: Array = []
	var visited := {}
	for start in next_of.keys():
		if visited.has(start):
			continue
		var ring := PackedVector2Array()
		var current: int = start
		var guard := 0
		while not visited.has(current) and guard < next_of.size() + 2:
			visited[current] = true
			ring.append(vertices[current])
			if not next_of.has(current):
				break
			current = next_of[current]
			guard += 1
		if ring.size() >= 3:
			rings.append(ring)
	return rings


## Read a JSON array shipped with the project (data/*.json)
static func load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("FmgUtils.load_json_array: %s was not found" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("FmgUtils.load_json_array: cannot open %s" % path)
		return []
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed
	push_warning("FmgUtils.load_json_array: %s does not hold an array" % path)
	return []


## Polyline for open outlines (used when a chain is not closed)
static func rings_to_polyline(rings: Array) -> Array:
	var lines: Array = []
	for ring in rings:
		var points: PackedVector2Array = ring
		if points.size() < 2:
			continue
		var closed := points[0].distance_squared_to(points[points.size() - 1]) < 0.01
		lines.append({"points": points, "closed": closed})
	return lines
