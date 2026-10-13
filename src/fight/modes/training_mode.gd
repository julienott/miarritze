class_name TrainingMode
extends RefCounted
## Entraînement (SPEC §3.5) : mannequin Hondar (bonhomme de sable), vie
## rechargée, chrono figé, liste des coups, historique des entrées et
## dégâts du combo. Comportement du mannequin réglable.

const BEHAVIORS: PackedStringArray = ["Inerte", "Garde", "Saute", "Répète un coup", "Combat (Facile)"]
const BEHAVIOR_LEVELS: PackedInt32Array = [
	AiBrain.DUMMY_IDLE, AiBrain.DUMMY_GUARD, AiBrain.DUMMY_JUMP, AiBrain.DUMMY_REPEAT, AiBrain.SKILL_EASY]


## Comportement par défaut en entraînement : « Garde » plutôt qu'« Inerte »,
## pour que Louis voie que Hondar bouge et réagit (sinon l'écran a l'air figé).
const DEFAULT_BEHAVIOR: int = 1


static func fight_params(fighter: String, costume: int, behavior: int = DEFAULT_BEHAVIOR) -> Dictionary:
	return {
		"p1": fighter, "c1": costume, "p2": Roster.DUMMY, "c2": 0,
		"stage": "grande_plage", "rounds": 1, "ai": [0, BEHAVIOR_LEVELS[behavior]],
		"training": true, "behavior": behavior, "finishers": false,
		"mode": "training", "return_to": "main_menu",
	}


## Tutoriel : entraînement contre Hondar avec la surcouche guidée.
static func tutorial_params(fighter: String = "louis") -> Dictionary:
	var params: Dictionary = fight_params(fighter, 0, 0)
	params["tutorial"] = true
	return params
