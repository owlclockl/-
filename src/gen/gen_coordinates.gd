## Where the map sits on the globe — port of `src/generators/coordinates.ts` (Azgaar, MIT).
## Gives the map a latitude span and a longitude span, which temperature and precipitation need.
class_name GenCoordinates
extends RefCounted

## [size in % of the world, North-South shift in %, West-East shift in %] per real-world template
const TEMPLATE_POSITIONS := {
	"africa-centric": [45, 53, 38],
	"arabia": [20, 35, 35],
	"atlantics": [42, 23, 65],
	"britain": [7, 20, 51.3],
	"caribbean": [15, 40, 74.8],
	"east-asia": [11, 28, 9.4],
	"eurasia": [38, 19, 27],
	"europe": [20, 16, 44.8],
	"europe-accented": [14, 22, 44.8],
	"europe-and-central-asia": [25, 10, 39.5],
	"europe-central": [11, 22, 46.4],
	"europe-north": [7, 18, 48.9],
	"greenland": [22, 7, 55.8],
	"hellenica": [8, 27, 43.5],
	"iceland": [2, 15, 55.3],
	"indian-ocean": [45, 55, 14],
	"mediterranean-sea": [10, 29, 45.8],
	"middle-east": [8, 31, 34.4],
	"north-america": [37, 17, 87],
	"us-centric": [66, 27, 100],
	"us-mainland": [16, 30, 77.5],
	"world": [78, 27, 40],
	"world-from-pacific": [75, 32, 30],
}

## chance for a random map to cover the whole world when the land does not reach the borders
const WHOLE_WORLD_CHANCE := {
	"pangea": 1.0, "shattered": 0.7, "continents": 0.5,
	"archipelago": 0.35, "highIsland": 0.25, "lowIsland": 0.1,
}

## size distribution [expected, deviation, min, max] for a random map
const RANDOM_SIZE := {
	"pangea": [70.0, 20.0, 30.0, 100.0],
	"volcano": [20.0, 20.0, 10.0, 100.0],
	"mediterranean": [25.0, 30.0, 15.0, 80.0],
	"peninsula": [15.0, 15.0, 5.0, 80.0],
	"isthmus": [15.0, 20.0, 3.0, 80.0],
	"atoll": [3.0, 2.0, 1.0, 5.0],
}


## Pick size/position for a template and apply it to the map (FMG Coordinates.generate)
static func generate(map: MapData) -> void:
	var partial := false
	for feature in map.grid.get("features", []):
		if feature.get("land", false) and feature.get("border", false):
			partial = true
			break

	var template := str(map.options.get("generation", {}).get("template", "continents"))
	var size_and_position := _get_size_and_position(template, partial)
	var geography: Dictionary = map.options["geography"]
	var requested: Dictionary = map.options.get("generation", {}).get("geography", {})
	geography["mapSize"] = requested.get("mapSize", size_and_position[0])
	geography["latitude"] = requested.get("latitude", size_and_position[1])
	geography["longitude"] = requested.get("longitude", size_and_position[2])
	calculate(map)


## Turn size/position percentages into the lat/lon box (FMG Coordinates.calculate)
static func calculate(map: MapData) -> void:
	var geography: Dictionary = map.options["geography"]
	var size_fraction := float(geography.get("mapSize", 100.0)) / 100.0
	var lat_shift := float(geography.get("latitude", 50.0)) / 100.0
	var lon_shift := float(geography.get("longitude", 50.0)) / 100.0

	var lat_t := FmgUtils.rn(size_fraction * 180.0, 1)
	var lat_n := FmgUtils.rn(90.0 - (180.0 - lat_t) * lat_shift, 1)
	var lat_s := FmgUtils.rn(lat_n - lat_t, 1)

	var graph: Dictionary = map.options["graph"]
	var lon_t := FmgUtils.rn(min((float(graph["width"]) / float(graph["height"])) * lat_t, 360.0), 1)
	var lon_e := FmgUtils.rn(180.0 - (360.0 - lon_t) * lon_shift, 1)
	var lon_w := FmgUtils.rn(lon_e - lon_t, 1)

	geography["coordinates"] = {
		"latT": lat_t, "latN": lat_n, "latS": lat_s,
		"lonT": lon_t, "lonW": lon_w, "lonE": lon_e,
	}


static func _get_size_and_position(template: String, partial: bool) -> Array:
	if TEMPLATE_POSITIONS.has(template):
		return TEMPLATE_POSITIONS[template]
	if not partial and FmgRandom.p(float(WHOLE_WORLD_CHANCE.get(template, 0.0))):
		return [100.0, 50.0, 50.0]

	var max_size := 80.0 if partial else 100.0
	var distribution: Array = RANDOM_SIZE.get(template, [30.0, 20.0, 15.0, max_size])
	var digits := 1 if template == "atoll" else 0
	var size := FmgRandom.gauss(distribution[0], distribution[1], distribution[2], min(distribution[3], max_size), digits)
	var latitude := FmgRandom.gauss(40.0 if FmgRandom.p(0.5) else 60.0, 20.0, 25.0, 75.0)
	return [size, latitude, 50.0]
