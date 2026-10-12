class_name BotSource
extends InputSource
## Entrées pseudo-aléatoires « humaines » (QA en ligne, tests de charge) :
## avance vers l'adversaire, frappe, saute, garde, de temps en temps.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _hold: int = 0
var _left: int = 0


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func sample() -> int:
	if _left > 0:
		_left -= 1
		return _hold if _left > 2 else _hold & DIRS_ONLY
	var r: int = _rng.randi_range(0, 99)
	var dir: int = RIGHT if _rng.randi_range(0, 3) > 0 else LEFT
	if r < 30:
		_hold = dir
	elif r < 55:
		_hold = PUNCH
	elif r < 68:
		_hold = KICK | (DOWN if _rng.randi_range(0, 2) == 0 else 0)
	elif r < 78:
		_hold = SPECIAL | (dir if _rng.randi_range(0, 1) == 0 else 0)
	elif r < 86:
		_hold = UP | dir
	elif r < 94:
		_hold = GUARD
	else:
		_hold = DOWN | LEFT | PUNCH
	_left = _rng.randi_range(4, 14)
	return _hold


const DIRS_ONLY: int = 15


func label() -> String:
	return "Bot"
