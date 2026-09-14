## The smaller pipeline stages: ice, markers, zones, goods and state forms.
## Ports of parts of `src/generators/ice-generator.ts`, `markers-generator.ts`,
## `zones-generator.ts`, `goods-generator.ts` and `states-generator.ts` (Azgaar, MIT).
## These stages are lighter than the web app versions: they cover the map data the renderer and
## the gameplay layers need, not the full editor functionality.
class_name GenExtras
extends RefCounted

const ICEBERG_MAX_TEMP := 0
const GLACIER_MAX_TEMP := -8


## Glaciers and icebergs (a reduced port of Ice.generate)
static func generate_ice(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var grid_reference: PackedInt32Array = cells["g"]
	var grid_temp: PackedInt32Array = map.grid["cells"]["temp"]
	var neighbours: Array = cells["c"]

	var glaciers := PackedInt32Array()
	var icebergs := PackedInt32Array()

	for cell_id in heights.size():
		if cell_id >= grid_reference.size():
			continue
		var temperature := float(grid_temp[grid_reference[cell_id]])
		if heights[cell_id] >= MapData.SEA_LEVEL:
			if temperature <= GLACIER_MAX_TEMP and _has_land_neighbour(heights, neighbours, cell_id):
				glaciers.append(cell_id)
		elif temperature <= ICEBERG_MAX_TEMP and _has_water_neighbour(heights, neighbours, cell_id):
			icebergs.append(cell_id)

	map.pack["ice"] = {"glaciers": glaciers, "icebergs": icebergs}


static func _has_land_neighbour(heights: PackedInt32Array, neighbours: Array, cell_id: int) -> bool:
	for neighbour in neighbours[cell_id]:
		if heights[neighbour] >= MapData.SEA_LEVEL:
			return true
	return false


static func _has_water_neighbour(heights: PackedInt32Array, neighbours: Array, cell_id: int) -> bool:
	for neighbour in neighbours[cell_id]:
		if heights[neighbour] < MapData.SEA_LEVEL:
			return true
	return false


## Natural and cultural markers (a reduced port of Markers.generate)
static func generate_markers(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var grid_reference: PackedInt32Array = cells["g"]
	var grid_temp: PackedInt32Array = map.grid["cells"]["temp"]
	var biomes: PackedInt32Array = cells["biome"]
	var neighbours: Array = cells["c"]
	var markers: Array = []

	for cell_id in heights.size():
		if heights[cell_id] < MapData.SEA_LEVEL:
			continue
		var temperature := float(grid_temp[grid_reference[cell_id]])
		var biome: int = biomes[cell_id]
		if heights[cell_id] >= 60 and temperature < 0.0 and FmgRandom.p(0.3):
			markers.append({"i": markers.size() + 1, "type": "mountain", "cell": cell_id, "name": "Peak"})
		elif biome == 1 and FmgRandom.p(0.05):
			markers.append({"i": markers.size() + 1, "type": "dune", "cell": cell_id})
		elif biome == 11 and FmgRandom.p(0.1):
			markers.append({"i": markers.size() + 1, "type": "glacier", "cell": cell_id})
		elif heights[cell_id] < 25 and FmgRandom.p(0.02):
			markers.append({"i": markers.size() + 1, "type": "volcano", "cell": cell_id})
	map.pack["markers"] = markers


## Climate zones: belts of latitude used by other systems (a reduced port of Zones.generate)
static func generate_zones(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var grid_reference: PackedInt32Array = cells["g"]
	var grid_temp: PackedInt32Array = map.grid["cells"]["temp"]
	var zones: Array = []
	var zone_ids := {}
	for cell_id in cells["h"].size():
		var temperature := float(grid_temp[grid_reference[cell_id]])
		var name := "polar"
		var color := "#a7c1d3"
		if temperature >= 25.0:
			name = "tropical"
			color = "#c2e699"
		elif temperature >= 18.0:
			name = "tropical seasonal"
			color = "#d9f0a3"
		elif temperature >= 10.0:
			name = "subtropical"
			color = "#f7f5b2"
		elif temperature >= 0.0:
			name = "temperate"
			color = "#fdd0a2"
		var key := "%s|%s" % [name, color]
		if not zone_ids.has(key):
			zone_ids[key] = {"i": zones.size() + 1, "name": name, "color": color, "cells": PackedInt32Array()}
			zones.append(zone_ids[key])
		zone_ids[key]["cells"].append(cell_id)
	map.pack["zones"] = zones


## Natural resources of every cell (a reduced port of Goods.generate)
static func generate_goods(map: MapData) -> void:
	var cells: Dictionary = map.pack["cells"]
	var heights: PackedInt32Array = cells["h"]
	var biomes: PackedInt32Array = cells["biome"]
	var grid_reference: PackedInt32Array = cells["g"]
	var grid_temp: PackedInt32Array = map.grid["cells"]["temp"]
	var biome_goods := [
		[1, "Dates"],
		[2, "Kelp"],
		[3, "Teff"],
		[4, "Wheat"],
		[5, "Bananas"],
		[6, "Apples"],
		[7, "Cocoa"],
		[8, "Rice"],
		[9, "Furs"],
		[10, "Reindeer"],
		[11, "Fish"],
		[12, "Reeds"],
	]
	var good_of := PackedInt32Array()
	good_of.resize(heights.size())
	var goods: Array = [{"i": 0, "name": "None", "value": 0}]
	var by_name := {}
	for cell_id in heights.size():
		if heights[cell_id] < MapData.SEA_LEVEL:
			continue
		var biome: int = biomes[cell_id]
		var name := "None"
		for entry in biome_goods:
			if int(entry[0]) == biome:
				name = str(entry[1])
				break
		var temperature := float(grid_temp[grid_reference[cell_id]])
		if name == "None":
			name = "Wool" if temperature < 10.0 else "Fruit"
		if not by_name.has(name):
			by_name[name] = goods.size()
			goods.append({"i": goods.size(), "name": name, "value": 5 + goods.size() % 10})
		good_of[cell_id] = by_name[name]
	cells["good"] = good_of
	map.pack["goods"] = goods


## Forms of government: they depend on the state's culture and expansionism (FMG defineStateForms)
static func define_state_forms(map: MapData) -> void:
	var forms: PackedStringArray = ["Monarchy", "Republic", "Theocracy", "Union", "Federation", "Khanate", "Tribe"]
	for state: Dictionary in map.pack.get("states", []):
		var state_id := int(state.get("i", 0))
		if state_id == 0:
			continue
		var type := str(state.get("type", "Generic"))
		var form: String = forms[FmgRandom.rand_i(0, forms.size() - 1)]
		if type == "Nomadic":
			form = "Tribe"
		elif type == "Naval":
			form = "Republic"
		state["form"] = form
		state["fullName"] = "%s %s" % [form, str(state.get("name", ""))]
		state["color"] = str(state.get("color", "#66c2a5"))
		state["capitalName"] = str(map.pack["burgs"][int(state.get("capital", 0))].get("name", "")) if int(state.get("capital", 0)) < map.pack["burgs"].size() else ""
