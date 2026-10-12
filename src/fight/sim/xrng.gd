class_name XRng
extends RefCounted
## Générateur xorshift32 maison, 100 % déterministe (SPEC §8.2).
## Jamais de RNG Godot dans la sim.

const MASK: int = 0xFFFFFFFF

var state: int = 0x9E3779B9


func _init(seed_value: int = 0x9E3779B9) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	state = seed_value & MASK
	if state == 0:
		state = 0x9E3779B9


func next_u32() -> int:
	var x: int = state
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	state = x & MASK
	return state


## Entier dans [0, n).
func below(n: int) -> int:
	if n <= 1:
		return 0
	return next_u32() % n


## Vrai avec une probabilité de `permille` / 1000.
func chance(permille: int) -> bool:
	return below(1000) < permille
