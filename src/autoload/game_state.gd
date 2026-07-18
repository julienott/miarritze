extends Node
## GameState — session courante du joueur.
##
## Détient l'identité (pseudo + code de groupe), les jetons renvoyés par
## l'API (player_id / player_secret) et l'état de déblocage du Phare.
## Persiste la session dans user:// (IndexedDB en web) pour ne pas
## redemander le pseudo à chaque visite.

const _SAVE_PATH: String = "user://session.json"

## Pseudo choisi par le joueur (jamais de nom réel — cf. CLAUDE.md §0.6).
var pseudo: String = ""

## Code de groupe partageable (leaderboard privé).
var group_code: String = ""

## Identifiant joueur renvoyé par POST /api/group/join (0 = pas encore joint).
var player_id: int = 0

## Jeton secret par joueur, requis pour poster un score.
var player_secret: String = ""


func _ready() -> void:
	_load()


## Enregistre l'identité de session (appelé depuis pseudo_entry).
func set_identity(p_pseudo: String, p_code: String) -> void:
	pseudo = p_pseudo
	group_code = p_code
	_save()


## Enregistre les jetons renvoyés par l'API au join.
func set_credentials(p_player_id: int, p_secret: String) -> void:
	player_id = p_player_id
	player_secret = p_secret
	_save()


## Session complète = identité + jetons (on peut aller au hub directement).
func has_session() -> bool:
	return pseudo != "" and group_code != "" and player_id > 0 and player_secret != ""


## Efface la session (bouton "changer de joueur").
func clear_session() -> void:
	pseudo = ""
	group_code = ""
	player_id = 0
	player_secret = ""
	_save()


## Le Phare est débloqué quand le cumul franchit le seuil de balance.gd.
func is_lighthouse_unlocked() -> bool:
	return ScoreManager.cumulative() >= Balance.LIGHTHOUSE_UNLOCK_THRESHOLD


func _save() -> void:
	var file: FileAccess = FileAccess.open(_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameState: impossible d'écrire %s" % _SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"pseudo": pseudo,
		"group_code": group_code,
		"player_id": player_id,
		"player_secret": player_secret,
	}))


func _load() -> void:
	if not FileAccess.file_exists(_SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		var dict: Dictionary = data
		pseudo = str(dict.get("pseudo", ""))
		group_code = str(dict.get("group_code", ""))
		player_id = int(dict.get("player_id", 0))
		player_secret = str(dict.get("player_secret", ""))
