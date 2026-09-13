## Generation options — the subset of Fantasy Map Generator's options that drives map generation.
## Stored as a plain dictionary so maps can be saved and re-generated with the same settings.
class_name GenOptions
extends RefCounted


static func defaults() -> Dictionary:
	return {
		"seed": "123456",
		"graph": {"width": 1000.0, "height": 600.0, "points": 10000, "density": "normal"},
		"generation": {
			"template": "continents",
			"lakeElevationLimit": 80,
			"cultures": {"set": "world", "limit": 12, "sizeVariety": 1.0, "growthRate": 1.0},
			"states": {"limit": 30, "sizeVariety": 1.0, "growthRate": 1.0},
			"burgs": {"limit": 1000},
			"religions": {"limit": 6},
		},
		"climate": {
			"temperature": {"equator": 27.0, "northPole": -20.0, "southPole": -25.0},
			"precipitation": 100.0,
			"winds": [90.0, 210.0, 150.0, 100.0, 270.0, 300.0],
		},
		"geography": {
			"coordinates": {"latN": 90.0, "latS": 90.0, "latT": 180.0, "lonW": 180.0, "lonE": 180.0, "lonT": 360.0},
			"mapSize": 1.0,
			"distanceScale": 1.0,
		},
		"units": {"height": {"exponent": 1.8, "unit": "m"}},
		"map": {
			"cultures": {"set": "world"},
			"graph": {"width": 1000.0, "height": 600.0, "points": 10000},
		},
	}


## Names of the heightmap templates shipped in data/heightmap_templates.json
static func template_names() -> Array:
	var data := load_json("res://data/heightmap_templates.json")
	var names: Array = []
	for key in data.keys():
		names.append({"id": key, "name": data[key].get("name", key), "probability": data[key].get("probability", 1)})
	names.sort_custom(func(a, b): return int(a["probability"]) > int(b["probability"]))
	return names


## A random template weighted by FMG's probabilities (used when the user asks for "Random")
static func random_template() -> String:
	var data := load_json("res://data/heightmap_templates.json")
	var pool: Array = []
	for key in data.keys():
		for _i in int(data[key].get("probability", 1)):
			pool.append(key)
	if pool.is_empty():
		return "continents"
	return pool[FmgRandom.rand_to(pool.size() - 1)]


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open data file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


static func clone_with_seed(source: Dictionary, seed_value: String) -> Dictionary:
	var copy: Dictionary = source.duplicate(true)
	copy["seed"] = seed_value
	copy["map"] = {"cultures": {"set": copy["generation"]["cultures"]["set"]}, "graph": copy["graph"].duplicate(true)}
	return copy
