extends Node
## Profiles — profils locaux (jusqu'à 4 par appareil), synchronisés au
## serveur quand le profil a rejoint un groupe (SPEC-BORROKA §3.1).
##
## Persistance : user://profiles.json (IndexedDB en web). Aucune donnée
## personnelle : pseudo seul + code de groupe.

signal profiles_changed

const SAVE_PATH: String = "user://profiles.json"
const MAX_PROFILES: int = 4

## Liste des profils (Dictionary) ; voir _new_profile() pour le format.
var profiles: Array[Dictionary] = []
## Index du profil actif (-1 = aucun).
var active_index: int = -1


func _ready() -> void:
	_load()
	# Outils QA (captures, pyramides automatiques) : profil jetable.
	if profiles.is_empty():
		for arg: String in OS.get_cmdline_user_args():
			if arg == "--qa-profile" or arg.begins_with("--autotower="):
				create("Testeur")
				break


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


## Titres débloquables (SPEC §3.1) : id -> [libellé, condition lisible].
const TITLES: Dictionary = {
	"": ["Sans titre", ""],
	"debutant": ["Petit·e baigneur·se", "Finir le tutoriel"],
	"txapeldun": ["Txapeldun", "Terminer la Pyramide du Phare"],
	"expert": ["Gardien·ne du Phare", "Terminer la Pyramide en Expert"],
	"cote_basques": ["Roi·Reine de la Côte des Basques", "Gagner 5 combats à la Côte des Basques"],
	"fronton": ["Invaincu·e du fronton", "Gagner 5 combats au Fronton"],
	"finisher": ["Maître du BUKATU", "Réussir 10 finishs"],
	"parfait": ["Parfait·e", "Gagner un round sans être touché·e"],
	"collection": ["Collectionneur·se", "Débloquer 10 costumes"],
}
const EMOTES: PackedStringArray = ["Agur !", "Prêt·e ?", "Bravo !", "Encore !"]
const BANNERS: int = 8
## Victoires avec un perso pour débloquer son costume 2 (§5.4).
const WINS_FOR_COSTUME_2: int = 5


## Valide un pseudo (2 à 15 caractères, lettres/chiffres/espace/-/_).
## Le filtre anti-gros-mots complet est appliqué par le serveur (Profanity).
static func pseudo_ok(pseudo: String) -> bool:
	var p: String = pseudo.strip_edges()
	if p.length() < 2 or p.length() > 15:
		return false
	var re: RegEx = RegEx.create_from_string("^[\\p{L}0-9_-]+$")
	return re.search(p) != null


func costume_unlocked(fighter: String, costume: int) -> bool:
	if costume == 0 or OS.get_cmdline_user_args().has("--unlock-all"):
		return true
	return (active().get("unlocks", {}).get(fighter, [0]) as Array).has(costume)


func title_unlocked(title_id: String) -> bool:
	return title_id == "" or (active().get("titles", []) as Array).has(title_id)


## Enregistre l'issue d'un combat pour le profil actif (stats, costumes, titres).
## Renvoie la liste des déblocages (textes) à annoncer.
func record_fight(fighter: String, won: bool, stage: String, finisher: bool, perfect: bool) -> Array[String]:
	var out: Array[String] = []
	if not has_active():
		return out
	var prof: Dictionary = profiles[active_index]
	var stats: Dictionary = prof.get("stats", {})
	stats["fights"] = int(stats.get("fights", 0)) + 1
	var per: Dictionary = stats.get("wins_by", {})
	var by_stage: Dictionary = stats.get("wins_stage", {})
	if won:
		stats["wins"] = int(stats.get("wins", 0)) + 1
		per[fighter] = int(per.get(fighter, 0)) + 1
		by_stage[stage] = int(by_stage.get(stage, 0)) + 1
	if finisher:
		stats["finishers"] = int(stats.get("finishers", 0)) + 1
	stats["wins_by"] = per
	stats["wins_stage"] = by_stage
	prof["stats"] = stats
	var unlocks: Dictionary = prof.get("unlocks", {})
	var costumes: Array = unlocks.get(fighter, [0])
	if int(per.get(fighter, 0)) >= WINS_FOR_COSTUME_2 and not costumes.has(1):
		costumes.append(1)
		out.append("Costume 2 de %s" % Roster.display_name(fighter))
	unlocks[fighter] = costumes
	prof["unlocks"] = unlocks
	if perfect:
		out.append_array(_grant_title(prof, "parfait"))
	if int(by_stage.get("cote_basques", 0)) + int(by_stage.get("cote_basques_crepuscule", 0)) >= 5:
		out.append_array(_grant_title(prof, "cote_basques"))
	if int(by_stage.get("fronton", 0)) >= 5:
		out.append_array(_grant_title(prof, "fronton"))
	if int(stats.get("finishers", 0)) >= 10:
		out.append_array(_grant_title(prof, "finisher"))
	var total_costumes: int = 0
	for f: Variant in unlocks:
		if unlocks[f] is Array:
			total_costumes += maxi((unlocks[f] as Array).size() - 1, 0)
	if total_costumes >= 10:
		out.append_array(_grant_title(prof, "collection"))
	save()
	return out


func grant_title(title_id: String) -> Array[String]:
	if not has_active():
		return []
	var out: Array[String] = _grant_title(profiles[active_index], title_id)
	save()
	return out


func _grant_title(prof: Dictionary, title_id: String) -> Array[String]:
	var titles: Array = prof.get("titles", [])
	if titles.has(title_id):
		return []
	titles.append(title_id)
	prof["titles"] = titles
	return ["Titre : %s" % str(TITLES[title_id][0])]


func _new_profile(pseudo: String) -> Dictionary:
	return {
		"pseudo": pseudo,
		"group_code": "",
		"player_id": 0,
		"secret": "",
		"fighter": "louis",
		"costume": 0,
		"banner": 0,
		"title": "",
		"emote": 0,
		"unlocks": {},
		"titles": [],
		"stats": {"fights": 0, "wins": 0, "towers": {}, "txapelas": {}, "best_tower": 0},
		"tutorial_done": false,
	}


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
