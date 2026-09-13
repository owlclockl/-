## Alea PRNG — direct port of the generator Fantasy Map Generator uses
## (https://github.com/jcubic/alea, Johannes Baagøe's Mash/Alea, public domain).
##
## FMG makes generation deterministic by replacing Math.random with a seeded Alea instance,
## so the same algorithm is used here: same seed + same options => same map.
##
## Note: seeds are hashed per character. JS hashes UTF-16 code units, Godot hashes code points,
## so non-ASCII seeds (e.g. Cyrillic) hash differently from the web app. Numeric/ASCII seeds match.
class_name FmgAlea
extends RefCounted

const FRAC_32 := 2.3283064365386963e-10 # 2^-32
const UINT32 := 4294967296.0 # 2^32

var s0 := 0.0
var s1 := 0.0
var s2 := 0.0
var c := 1.0
var args: Array = []


func _init(seed_args: Array = []) -> void:
	args = seed_args.duplicate()
	if args.is_empty():
		args = [float(Time.get_unix_time_from_system())]
	_seed(args)


## JavaScript's ToUint32: truncate towards zero, then wrap into [0, 2^32)
static func to_uint32(value: float) -> float:
	var truncated := floor(value) if value >= 0.0 else ceil(value)
	var wrapped: float = fmod(truncated, UINT32)
	if wrapped < 0.0:
		wrapped += UINT32
	return wrapped


## Stateful string hasher (Baagøe's Mash). The state keeps the full float, while the returned
## hash is the wrapped 32 bit value — exactly like the original implementation.
class Mash:
	extends RefCounted

	var n := 0.0

	func _init() -> void:
		n = float(0xefc8249d)

	func hash_text(data: String) -> float:
		for i in data.length():
			n += float(data.unicode_at(i))
			var h := 0.02519603282416938 * n
			n = FmgAlea.to_uint32(h)
			h -= n
			h *= n
			n = FmgAlea.to_uint32(h)
			h -= n
			n += h * FmgAlea.UINT32
		return FmgAlea.to_uint32(n) * FmgAlea.FRAC_32


func _seed(seed_args: Array) -> void:
	var mash := Mash.new()
	s0 = mash.hash_text(" ")
	s1 = mash.hash_text(" ")
	s2 = mash.hash_text(" ")
	for arg in seed_args:
		var text := str(arg)
		var v0 := mash.hash_text(text)
		s0 -= v0
		if s0 < 0.0:
			s0 += 1.0
		var v1 := mash.hash_text(text)
		s1 -= v1
		if s1 < 0.0:
			s1 += 1.0
		var v2 := mash.hash_text(text)
		s2 -= v2
		if s2 < 0.0:
			s2 += 1.0


## next random float in [0, 1)
func next() -> float:
	var t := 2091639.0 * s0 + c * FRAC_32
	s0 = s1
	s1 = s2
	c = float(int(t)) # JS `t | 0` truncates towards zero
	s2 = t - c
	return s2


func uint32() -> float:
	return next() * UINT32


func export_state() -> Array:
	return [s0, s1, s2, c]


func import_state(state: Array) -> void:
	s0 = float(state[0]) if state.size() > 0 else 0.0
	s1 = float(state[1]) if state.size() > 1 else 0.0
	s2 = float(state[2]) if state.size() > 2 else 0.0
	c = float(state[3]) if state.size() > 3 else 0.0
