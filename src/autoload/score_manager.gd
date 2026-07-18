extends Node
## ScoreManager — source de vérité LOCALE des scores.
##
## Meilleurs scores locaux par épreuve, calcul du cumul (somme des best des
## 5 épreuves cœur, cf. Challenges.CORE), persistance dans user://.
## Le post réseau est déclenché par ChallengeBase.end(), pas ici.

## Émis quand un nouveau meilleur score local est établi.
signal best_updated(challenge: StringName, score: int)

const _SAVE_PATH: String = "user://scores.json"

## Meilleur score local par épreuve (clé : StringName d'épreuve).
var _best_scores: Dictionary = {}


func _ready() -> void:
	_load()


## Soumet un score local. Retourne true si c'est un nouveau meilleur score
## (l'appelant déclenche alors le post réseau via LeaderboardClient).
func submit_local(challenge: StringName, score: int) -> bool:
	if score <= best(challenge):
		return false
	_best_scores[challenge] = score
	_save()
	best_updated.emit(challenge, score)
	return true


## Meilleur score local pour une épreuve (0 si jamais jouée).
func best(challenge: StringName) -> int:
	return int(_best_scores.get(challenge, 0))


## Score cumulé = somme des best des 5 épreuves cœur (débloque le Phare).
func cumulative() -> int:
	var total: int = 0
	for challenge: StringName in Challenges.CORE:
		total += best(challenge)
	return total


func _save() -> void:
	var file: FileAccess = FileAccess.open(_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("ScoreManager: impossible d'écrire %s" % _SAVE_PATH)
		return
	var data: Dictionary = {}
	for key: StringName in _best_scores:
		data[String(key)] = _best_scores[key]
	file.store_string(JSON.stringify(data))


func _load() -> void:
	if not FileAccess.file_exists(_SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		var dict: Dictionary = data
		for key: String in dict:
			_best_scores[StringName(key)] = int(dict[key])
