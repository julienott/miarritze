extends Node
## Profiles — profils locaux (jusqu'à 4 par appareil), lus et complétés par GkProfil.
## Hérité de l'ancien jeu, réduit au stockage : à remplacer par un équivalent Gordeka.
##
## Persistance : user://profiles.json (IndexedDB en web). Aucune donnée
## personnelle : pseudo seul (plus player_id + secret du serveur une fois en ligne).

signal profiles_changed

const SAVE_PATH: String = "user://profiles.json"
const MAX_PROFILES: int = 4

## Liste des profils (Dictionary) ; voir _new_profile() pour le format.
var profiles: Array[Dictionary] = []
## Index du profil actif (-1 = aucun).
var active_index: int = -1


func _ready() -> void:
	_load()
	# Outils QA (captures) : profil jetable.
	if profiles.is_empty() and OS.get_cmdline_user_args().has("--qa-profile"):
		create("Testeur")


func active() -> Dictionary:
	if active_index < 0 or active_index >= profiles.size():
		return {}
	return profiles[active_index]


func has_active() -> bool:
	return not active().is_empty()


## Crée un profil et le rend actif. Renvoie false si le maximum est atteint.
func create(pseudo: String) -> bool:
	if profiles.size() >= MAX_PROFILES:
		return false
	profiles.append(_new_profile(pseudo))
	active_index = profiles.size() - 1
	save()
	return true


func select(index: int) -> void:
	if index >= 0 and index < profiles.size():
		active_index = index
		save()


func remove(index: int) -> void:
	if index < 0 or index >= profiles.size():
		return
	profiles.remove_at(index)
	# L'actif garde son profil : décalé si on supprime un profil placé avant lui.
	if index < active_index:
		active_index -= 1
	elif index == active_index:
		active_index = 0 if not profiles.is_empty() else -1
	active_index = mini(active_index, profiles.size() - 1)
	save()


## Met à jour des champs du profil actif puis sauvegarde.
func update_active(fields: Dictionary) -> void:
	if not has_active():
		return
	profiles[active_index].merge(fields, true)
	save()


## Valide un pseudo (2 à 15 caractères, lettres/chiffres/espace/-/_).
## Le filtre anti-gros-mots complet est appliqué par le serveur (Profanity).
static func pseudo_ok(pseudo: String) -> bool:
	var p: String = pseudo.strip_edges()
	if p.length() < 2 or p.length() > 15:
		return false
	var re: RegEx = RegEx.create_from_string("^[\\p{L}0-9_-]+$")
	return re.search(p) != null


func _new_profile(pseudo: String) -> Dictionary:
	return {"pseudo": pseudo, "player_id": 0, "secret": ""}


func save() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Profiles: impossible d'écrire %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"active": active_index, "profiles": profiles}))
	profiles_changed.emit()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return
	var dict: Dictionary = data
	profiles.clear()
	for entry: Variant in dict.get("profiles", []):
		if entry is Dictionary:
			var merged: Dictionary = _new_profile(str((entry as Dictionary).get("pseudo", "")))
			merged.merge(entry as Dictionary, true)
			profiles.append(merged)
	active_index = clampi(int(dict.get("active", -1)), -1, profiles.size() - 1)
