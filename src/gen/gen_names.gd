## Name generator: Markov chains over the name bases from `data/name_bases.json`.
## Port of Fantasy Map Generator's `src/generators/names-generator.ts` (Azgaar, MIT).
class_name GenNames
extends RefCounted

static var _chains: Array = [] # cached Markov chains, one per name base
static var _bases: Array = [] # cached name bases


## Name bases shipped with the project (extracted from the web app)
static func get_name_bases() -> Array:
	if _bases.is_empty():
		_bases = FmgUtils.load_json_array("res://data/name_bases.json")
	return _bases


static func clear_chains() -> void:
	_chains = []


## Markov chain of pseudo-syllables for one name base (FMG calculateChain)
static func calculate_chain(names_list: String) -> Dictionary:
	var chain := {}
	for raw_name in names_list.split(","):
		var name := raw_name.strip_edges().to_lower()
		var basic := true # English-like rules apply to printable ASCII names
		for i in name.length():
			if name.unicode_at(i) < 32 or name.unicode_at(i) > 126:
				basic = false
				break

		var i := -1
		while i < name.length():
			var syllable := ""
			var prev := name[i] if i >= 0 and i < name.length() else ""
			var vowel_seen := false
			var c := i + 1
			while c < name.length() and syllable.length() < 5:
				var that := name[c]
				var next := name[c + 1] if c + 1 < name.length() else ""
				syllable += that
				if syllable == " " or syllable == "-":
					break
				if next == "" or next == " " or next == "-":
					break
				if FmgUtils.is_vowel(that):
					vowel_seen = true
				if that == "y" and next == "e":
					c += 1
					continue # keep 'ye' together
				if basic:
					if that == "o" and next == "o":
						c += 1
						continue
					if that == "e" and next == "e":
						c += 1
						continue
					if that == "a" and next == "e":
						c += 1
						continue
					if that == "c" and next == "h":
						c += 1
						continue
				if FmgUtils.is_vowel(that) == FmgUtils.is_vowel(next):
					break # two vowels or two consonants in a row
				if vowel_seen and c + 2 < name.length() and FmgUtils.is_vowel(name[c + 2]):
					break
				c += 1

			if not chain.has(prev):
				chain[prev] = PackedStringArray()
			var list: PackedStringArray = chain[prev]
			list.append(syllable)
			chain[prev] = list

			var step := syllable.length()
			i += step if step > 0 else 1
	return chain


static func _update_chain(index: int) -> void:
	var bases := get_name_bases()
	if index >= 0 and index < bases.size() and String(bases[index].get("b", "")) != "":
		_chains[index] = calculate_chain(str(bases[index]["b"]))
	else:
		_chains[index] = null


## Generate a name with the Markov chain of `base` (FMG Names.getBase)
static func get_base(base: int, min_length := 0, max_length := 0, duplicate := "") -> String:
	var bases := get_name_bases()
	if bases.is_empty():
		return "ERROR"
	if base < 0 or base >= bases.size():
		base = 0
	if _chains.size() < bases.size():
		_chains.resize(bases.size())
	if _chains[base] == null:
		_update_chain(base)

	var chain: Variant = _chains[base]
	if chain == null or not (chain as Dictionary).has(""):
		push_warning("GenNames: name base %d is incorrect" % base)
		return "ERROR"
	var data: Dictionary = chain

	if min_length == 0:
		min_length = int(bases[base].get("min", 5))
	if max_length == 0:
		max_length = int(bases[base].get("max", 10))
	if duplicate != "":
		duplicate = str(bases[base].get("d", ""))

	var values: PackedStringArray = data[""]
	var current: String = values[FmgRandom.rand_i(0, values.size() - 1)] if values.size() > 0 else ""
	var word := ""
	var last_letter := ""
	for _i in 20:
		if current == "":
			if word.length() < min_length:
				current = ""
				word = ""
				values = data[""]
				last_letter = ""
			else:
				break
		else:
			if word.length() + current.length() > max_length:
				if word.length() < min_length:
					word += current
				break
			var key := ""
			if current.length() > 0:
				key = current[current.length() - 1]
			var next_values: Variant = data.get(key, data[""])
			values = next_values if next_values is PackedStringArray else data[""]
			last_letter = key
		word += current
		if values.size() == 0:
			break
		current = values[FmgRandom.rand_i(0, values.size() - 1)]

	# quirks of the original: trim duplicates, capitalise, fix 'ae'
	var result := _check_duplicates(word, duplicate)
	return FmgUtils.capitalize(result)


static func _check_duplicates(word: String, duplicate: String) -> String:
	if duplicate == "" or word == "":
		return word
	var filtered := ""
	for i in word.length():
		var letter := word[i]
		if duplicate.contains(letter) and filtered.ends_with(letter):
			continue
		filtered += letter
	return filtered


static func get_name(base: int) -> String:
	return get_base(base)


## Random name of a culture (FMG Names.getCulture)
static func get_culture_name(culture_id: int, min_length := 0, max_length := 0) -> String:
	var bases := get_name_bases()
	if bases.is_empty():
		return "ERROR"
	var base: int = culture_id % max(1, bases.size())
	if min_length == 0:
		min_length = int(bases[base].get("min", 5))
	if max_length == 0:
		max_length = int(bases[base].get("max", 10))
	return _get_culture(base, min_length, max_length)


static func _get_culture(base: int, min_length: int, max_length: int) -> String:
	var name := get_base(base, min_length, max_length)
	for _attempt in 20:
		if not name.ends_with("'") and not name.ends_with("-") and not name.contains("  "):
			break
		name = get_base(base, min_length, max_length)
	return name


## Name of a state: two words, or a single longer word (FMG Names.getState)
static func get_state_name(base: int = -1, culture: int = 0) -> String:
	var bases := get_name_bases()
	if bases.is_empty():
		return "ERROR"
	if base == -1:
		base = culture % max(1, bases.size())
	var two_words_chance := 0.5
	if FmgRandom.p(two_words_chance):
		var first := get_base(base, 4, 8)
		var second := get_base(base, 4, 8)
		return "%s %s" % [first, second]
	return get_base(base, 5, 12)


## Short name for a burg or a river
static func get_short_name(base: int = -1, culture: int = 0) -> String:
	var bases := get_name_bases()
	if bases.is_empty():
		return "ERROR"
	if base == -1:
		base = culture % max(1, bases.size())
	return get_base(base, 3, 7)


## Name a feature (island, lake) with the culture of its first cell
static func get_feature_name(base: int = -1, culture: int = 0) -> String:
	return get_culture_name(culture if base == -1 else base)
