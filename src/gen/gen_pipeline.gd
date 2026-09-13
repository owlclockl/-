## The generation pipeline: the same order of stages as Fantasy Map Generator's
## `src/generators/generation-pipeline.ts` (Azgaar, MIT).
class_name GenPipeline
extends RefCounted

signal stage_started(stage_name: String)
signal stage_finished(stage_name: String)

var map: MapData


func _init(map_data: MapData) -> void:
	map = map_data


## Order of the stages, as in the web app's generation pipeline
const STAGES: Array = [
	"grid", "heightmap", "features", "coordinates", "climate", "pack",
	"rivers", "biomes", "population", "cultures", "burgs", "states",
	"routes", "religions", "provinces", "extras",
]


## Run every stage. `progress` receives (stage name, index, total).
func run(progress: Callable = Callable()) -> void:
	var total := STAGES.size()
	for index in total:
		var stage := str(STAGES[index])
		stage_started.emit(stage)
		if progress.is_valid():
			progress.call(stage, index, total)
		run_stage(map, stage)
		stage_finished.emit(stage)


## Run one stage by name
static func run_stage(map: MapData, stage: String) -> void:
	match stage:
		"grid":
			FmgRandom.seed_with(map.seed_text)
			GenGrid.generate(map)
		"heightmap":
			GenHeightmap.generate(map)
		"features":
			GenFeatures.markup_grid(map)
			GenGrid.add_deep_depression_lakes(map)
			GenGrid.open_near_sea_lakes(map)
		"coordinates":
			GenCoordinates.generate(map)
		"climate":
			GenClimate.generate_temperature(map)
			GenClimate.generate_precipitation(map)
		"pack":
			GenPack.generate(map)
			GenFeatures.markup_pack(map)
			GenFeatures.define_groups(map)
			GenPopulation.create_default_ruler(map)
		"rivers":
			GenLakes.detect_close_lakes(map)
			GenRivers.generate(map)
			GenLakes.define_names(map)
		"biomes":
			GenBiomes.generate(map)
		"population":
			GenPopulation.rank_cells(map)
		"cultures":
			GenCultures.generate(map)
			GenCultures.expand(map)
			GenCultures.collect_statistics(map)
		"burgs":
			GenBurgs.generate(map)
		"states":
			GenStates.generate(map)
			GenStates.assign_colors(map)
			GenBurgs.specify(map)
			GenPopulation.regenerate(map)
			GenStates.collect_statistics(map)
		"routes":
			GenRoutes.generate(map)
		"religions":
			GenReligions.generate(map)
		"provinces":
			GenReligions.generate_provinces(map)
		"extras":
			GenExtras.generate_ice(map)
			GenExtras.generate_goods(map)
			GenExtras.generate_zones(map)
			GenExtras.generate_markers(map)
			GenExtras.define_state_forms(map)
			map.invalidate_caches()
		_:
			push_warning("GenPipeline: unknown stage %s" % stage)


# ------------------------------------------------------------------ convenience

## Generate a map from a seed and (optionally) options overrides.
static func generate_map(map: MapData, progress: Callable = Callable()) -> MapData:
	var pipeline := GenPipeline.new(map)
	pipeline.run(progress)
	return map
