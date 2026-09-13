## Rivers: water flux accumulation, river courses, confluences, widths and names.
## Port of Fantasy Map Generator's `src/generators/river-generator.ts` (Azgaar, MIT).
##
## Simplifications compared with the web app: the river course is a straight polyline through the
## cell centers (FMG adds a Catmull–Rom spline) and erosion is not implemented.
##
## Note on GDScript: packed arrays are value types, so the flux/confidence arrays live on the
## instance instead of being passed into helpers.
class_name GenRivers
extends RefCounted

const MIN_NAVIGABLE_FLUX := 100
const MIN_FLUX_TO_FORM_RIVER := 30
const FLUX_FACTOR := 500.0
const MAX_FLUX_WIDTH := 1.0
const LENGTH_FACTOR := 200.0
const LENGTH_STEP_WIDTH := 1.0 / LENGTH_FACTOR
const LENGTH_PROGRESSION: Array = [1.0, 1.0, 2.0, 3.0, 5.0, 8.0, 13.0, 21.0, 34.0]

var flux: PackedInt32Array = PackedInt32Array()
var confidence: PackedInt32Array = PackedInt32Array()
var river_of: PackedInt32Array = PackedInt32Array()
var rivers_data: Dictionary = {} # river id -> cells
var river_parents: Dictionary = {} # tributary id -> main river id
var river_next := 1

var _map: MapData


static func generate(map: MapData) -> void:
	var generator := GenRivers.new()
	generator._map = map
	generator._run()


func _run() -> void:
	FmgRandom.seed_with(_map.seed_text)
	var cells: Dictionary = _map.pack["cells"]
	var neighbours: Array = cells["c"]
	var heights: PackedInt32Array = cells["h"]
	var border: PackedByteArray = cells["b"]
	var haven: PackedInt32Array = cells["haven"]
	var grid_reference: PackedInt32Array = cells["g"]
	var grid_prec: PackedInt32Array = _map.grid["cells"]["prec"]
	var features: Array = _map.pack["features"]
	var count := heights.size()

	flux.resize(count)
	confidence.resize(count)
	river_of.resize(count)
	rivers_data = {}
	river_parents = {}
	river_next = 1

	var lake_out_cells := GenLakes.define_climate_data(_map)
	var cells_number_modifier := pow(float(_map.points_desired()) / 10000.0, 0.25)

	var land := PackedInt32Array()
	for cell_id in count:
		if heights[cell_id] >= MapData.SEA_LEVEL:
			land.append(cell_id)
	var sorted_land := Array(land)
	sorted_land.sort_custom(func(a: int, b: int): return heights[a] > heights[b])

	for i in sorted_land:
		flux[i] += int(float(grid_prec[grid_reference[i]]) / cells_number_modifier)

		# a lake pours its surplus water into its outlet cell
		if i < lake_out_cells.size() and lake_out_cells[i] != 0:
			_pour_lake(lake_out_cells[i], i, features, cells, heights, neighbours)

		# near-border cell: the water leaves the map
		if border[i] == 1 and river_of[i] != 0:
			_add_cell(river_of[i], -1)
			continue

		var downhill := _downhill_cell(i, lake_out_cells, haven, neighbours, heights)
		if downhill == -1 or heights[i] <= heights[downhill]:
			continue # the cell sits in a depression

		if flux[i] < MIN_FLUX_TO_FORM_RIVER:
			if heights[downhill] >= MapData.SEA_LEVEL:
				flux[downhill] += flux[i]
			continue

		if river_of[i] == 0:
			river_of[i] = river_next
			_add_cell(river_next, i)
			river_next += 1
		_flow_down(downhill, flux[i], river_of[i], heights, cells, features)

	define_rivers(cells, heights)

	cells["r"] = river_of
	cells["conf"] = confidence
	cells["fl"] = flux


## Not evaporated lake water drains to the outlet (FMG drainWater, lake part)
func _pour_lake(lake_id: int, cell_id: int, features: Array, cells: Dictionary, heights: PackedInt32Array, neighbours: Array) -> void:
	if lake_id >= features.size():
		return
	var lake: Dictionary = features[lake_id]
	if int(lake.get("flux", 0)) <= int(lake.get("evaporation", 0)):
		return
	var lake_cell := -1
	for neighbour in neighbours[cell_id]:
		if heights[neighbour] < MapData.SEA_LEVEL and cells["f"][neighbour] == lake_id:
			lake_cell = neighbour
			break
	if lake_cell == -1:
		return

	flux[lake_cell] += maxi(int(lake.get("flux", 0)) - int(lake.get("evaporation", 0)), 0)
	if river_of[lake_cell] == 0:
		river_of[lake_cell] = river_next
		_add_cell(river_next, lake_cell)
		river_next += 1
	lake["outlet"] = river_of[lake_cell]
	_flow_down(lake_cell, flux[lake_cell], river_of[lake_cell], heights, cells, features)


func _downhill_cell(cell_id: int, lake_out_cells: PackedInt32Array, haven: PackedInt32Array, neighbours: Array, heights: PackedInt32Array) -> int:
	var lake_id := lake_out_cells[cell_id] if cell_id < lake_out_cells.size() else 0
	if lake_id != 0:
		# from a lake outlet the water flows away from the lake
		var best := -1
		for neighbour in neighbours[cell_id]:
			if heights[neighbour] < MapData.SEA_LEVEL:
				continue
			if best == -1 or heights[neighbour] < heights[best]:
				best = neighbour
		return best
	if haven[cell_id] != 0:
		return haven[cell_id]
	var best_neighbour := neighbours[cell_id][0]
	for neighbour in neighbours[cell_id]:
		if heights[neighbour] < heights[best_neighbour]:
			best_neighbour = neighbour
	return best_neighbour


## Push the water downstream, marking confluences (FMG RiverModule.flowDown)
func _flow_down(to_cell: int, from_flux: int, river: int, heights: PackedInt32Array, cells: Dictionary, features: Array) -> void:
	var to_flux := flux[to_cell] - confidence[to_cell]
	var to_river := river_of[to_cell]
	if to_river != 0:
		if from_flux > to_flux:
			confidence[to_cell] += flux[to_cell]
			if heights[to_cell] >= MapData.SEA_LEVEL:
				river_parents[to_river] = river
			river_of[to_cell] = river
		else:
			confidence[to_cell] += from_flux
			if heights[to_cell] >= MapData.SEA_LEVEL:
				river_parents[river] = to_river
	else:
		river_of[to_cell] = river

	if heights[to_cell] < MapData.SEA_LEVEL:
		var water_body: Dictionary = features[cells["f"][to_cell]]
		if water_body.get("type", "") == "lake":
			if int(water_body.get("river", 0)) == 0 or from_flux > int(water_body.get("enteringFlux", 0)):
				water_body["river"] = river
				water_body["enteringFlux"] = from_flux
			water_body["flux"] = int(water_body.get("flux", 0)) + from_flux
			var inlets: PackedInt32Array = water_body.get("inlets", PackedInt32Array())
			inlets.append(river)
			water_body["inlets"] = inlets
	else:
		flux[to_cell] += from_flux
	_add_cell(river, to_cell)


func _add_cell(river_id: int, cell_id: int) -> void:
	var river_cells: PackedInt32Array = rivers_data.get(river_id, PackedInt32Array())
	river_cells.append(cell_id)
	rivers_data[river_id] = river_cells


## Turn the flux map into river objects with lengths, widths and names (FMG defineRivers)
func define_rivers(cells: Dictionary, heights: PackedInt32Array) -> void:
	var points: PackedVector2Array = cells["p"]
	var river_ids := PackedInt32Array()
	for key in rivers_data.keys():
		river_ids.append(int(key))
	var sorted_ids := Array(river_ids)
	sorted_ids.sort()

	var rivers: Array = []
	for river_id in sorted_ids:
		var river_cells: PackedInt32Array = (rivers_data[river_id] as PackedInt32Array).duplicate()
		var valid_cells := PackedInt32Array()
		for cell_id in river_cells:
			if cell_id >= 0:
				valid_cells.append(cell_id)
		if valid_cells.size() < 3:
			continue # tiny rivers are not drawn

		var placed := 0
		for cell_id in valid_cells:
			if heights[cell_id] < MapData.SEA_LEVEL:
				continue
			if river_of[cell_id] != 0:
				confidence[cell_id] = 1
			else:
				river_of[cell_id] = river_id
			placed += 1
		if placed == 0:
			continue

		var source := valid_cells[0]
		var mouth := valid_cells[maxi(valid_cells.size() - 2, 0)]
		var parent := int(river_parents.get(river_id, 0))
		var default_width_factor := FmgUtils.rn(1.0 / pow(float(_map.points_desired()) / 10000.0, 0.25), 2)
		var width_factor := default_width_factor * 1.2 if (parent == 0 or parent == river_id) else default_width_factor
		var discharge := flux[mouth]
		var length := _approximate_length(points, valid_cells)
		var source_width := get_source_width(float(flux[source]))
		var width := get_offset(float(discharge), valid_cells.size(), width_factor, source_width)

		rivers.append({
			"i": river_id,
			"source": source,
			"mouth": mouth,
			"discharge": discharge,
			"length": length,
			"width": width,
			"widthFactor": width_factor,
			"sourceWidth": source_width,
			"parent": parent,
			"cells": valid_cells,
			"basin": get_basin(river_id),
			"name": get_name(mouth),
			"type": get_type(length, parent != 0),
		})

	_map.pack["rivers"] = rivers


static func _approximate_length(points: PackedVector2Array, cells: PackedInt32Array) -> float:
	var length := 0.0
	for i in range(1, cells.size()):
		var previous := cells[i - 1]
		var current := cells[i]
		if previous < 0 or current < 0:
			continue
		length += points[previous].distance_to(points[current])
	return FmgUtils.rn(length, 2)


static func get_source_width(flux_value: float) -> float:
	return FmgUtils.rn(minf(pow(flux_value, 0.9) / FLUX_FACTOR, MAX_FLUX_WIDTH), 2)


## River width at a given point of the course (FMG RiverModule.getOffset)
static func get_offset(flux_value: float, point_index: int, width_factor: float, starting_width: float) -> float:
	if point_index == 0:
		return starting_width
	var flux_width := minf(pow(flux_value, 0.7) / FLUX_FACTOR, MAX_FLUX_WIDTH)
	var last := float(LENGTH_PROGRESSION[LENGTH_PROGRESSION.size() - 1])
	var length_width := float(point_index) * LENGTH_STEP_WIDTH + (float(LENGTH_PROGRESSION[point_index]) if point_index < LENGTH_PROGRESSION.size() else last)
	return FmgUtils.rn(width_factor * (length_width + flux_width) + starting_width, 2)


func get_name(mouth: int) -> String:
	var cultures: PackedInt32Array = _map.pack["cells"].get("culture", PackedInt32Array())
	var culture := cultures[mouth] if mouth >= 0 and mouth < cultures.size() else 0
	return GenNames.get_culture_name(culture)


## Id of the river the given river flows into (FMG RiverModule.getBasin)
func get_basin(river_id: int) -> int:
	var current := river_id
	var guard := 0
	while river_parents.has(current) and guard < 100:
		var next_id: int = river_parents[current]
		if next_id == 0 or next_id == current:
			break
		current = next_id
		guard += 1
	return current


static func get_type(length: float, has_parent: bool) -> String:
	if length < 60.0:
		return "Creek"
	if length < 120.0:
		return "River"
	if length < 250.0:
		return "Bourne"
	if length < 500.0:
		return "Stream"
	if length < 1000.0:
		return "Tributary" if has_parent else "River"
	return "Main"


static func is_navigable(map: MapData, cell_id: int) -> bool:
	var rivers: PackedInt32Array = map.pack["cells"]["r"]
	var flux_values: PackedInt32Array = map.pack["cells"]["fl"]
	return cell_id < rivers.size() and rivers[cell_id] != 0 and cell_id < flux_values.size() and flux_values[cell_id] >= MIN_NAVIGABLE_FLUX
