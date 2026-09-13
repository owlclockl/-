## Seeded randomness for the whole generation pipeline.
##
## Fantasy Map Generator swaps `Math.random` for a seeded Alea instance, and several generators
## re-seed the global PRNG in the middle of the pipeline to keep sub-steps reproducible on their own.
## The same behaviour is mirrored here: one static, globally seeded stream plus the distribution
## helpers from `src/utils/probabilityUtils.ts`.
class_name FmgRandom
extends RefCounted

static var _rng: FmgAlea = FmgAlea.new(["0"])
static var _gauss_spare: float = NAN


static func seed_with(value: String) -> void:
	_rng = FmgAlea.new([value])
	_gauss_spare = NAN


static func export_state() -> Array:
	return _rng.export_state()


static func import_state(state: Array) -> void:
	_rng.import_state(state)


static func next() -> float:
	return _rng.next()


## random integer between min_value and max_value (inclusive)
static func rand_i(min_value: int, max_value: int) -> int:
	if max_value < min_value:
		var tmp := max_value
		max_value = min_value
		min_value = tmp
	return int(floor(next() * float(max_value - min_value + 1))) + min_value


## random integer between 0 and max_value (inclusive)
static func rand_to(max_value: int) -> int:
	return rand_i(0, max_value)


static func rand_float_between(min_value: float, max_value: float) -> float:
	return min_value + next() * (max_value - min_value)


static func p(probability: float) -> bool:
	if probability >= 1.0:
		return true
	if probability <= 0.0:
		return false
	return next() < probability


## true every `interval` indices, the FMG `each(n)` helper
static func each(index: int, interval: int) -> bool:
	return index % interval == 0


## random element of an array (FMG `ra`)
static func ra(array: Array) -> Variant:
	if array.is_empty():
		return null
	return array[int(floor(next() * float(array.size())))]


static func ra_int(array: PackedInt32Array) -> int:
	if array.is_empty():
		return 0
	return array[int(floor(next() * float(array.size())))]


## random key of a weights dictionary (FMG `rw`)
static func rw(weights: Dictionary) -> String:
	var pool: Array = []
	for key in weights.keys():
		var weight := int(weights[key])
		for i in weight:
			pool.append(key)
	if pool.is_empty():
		return ""
	return str(pool[int(floor(next() * float(pool.size())))])


## biased random integer towards min_value (`ex` controls the bias)
static func biased(min_value: int, max_value: int, ex: float) -> int:
	return int(round(float(min_value) + float(max_value - min_value) * pow(next(), ex)))


## Marsaglia polar method, mirroring d3.randomNormal with the current stream
static func gauss(expected := 100.0, deviation := 30.0, min_value := 0.0, max_value := 300.0, decimals := 0) -> float:
	var y := 0.0
	if not is_nan(_gauss_spare):
		y = _gauss_spare
		_gauss_spare = NAN
	else:
		var x := 0.0
		var r := 0.0
		var guard := 0
		while guard < 1000:
			x = next() * 2.0 - 1.0
			y = next() * 2.0 - 1.0
			r = x * x + y * y
			guard += 1
			if r > 0.0 and r <= 1.0:
				break
		y = y * sqrt(-2.0 * log(max(r, 1e-12)) / max(r, 1e-12))
		_gauss_spare = x
	return FmgUtils.rn(FmgUtils.minmax(expected + deviation * y, min_value, max_value), decimals)
