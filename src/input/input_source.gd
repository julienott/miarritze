class_name InputSource
extends RefCounted
## Source d'entrée abstraite : produit un InputFrame (8 bits) par tick.
## Seules les sources lisent l'état brut des périphériques (SPEC §7.1).

const UP: int = 1
const DOWN: int = 2
const LEFT: int = 4
const RIGHT: int = 8
const PUNCH: int = 16
const KICK: int = 32
const SPECIAL: int = 64
const GUARD: int = 128


## Renvoie le masque de l'instant (directions absolues gauche/droite).
func sample() -> int:
	return 0


## Nom court affichable (« Clavier J1 », « Manette 1 »…).
func label() -> String:
	return "?"
