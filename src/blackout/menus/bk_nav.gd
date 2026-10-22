class_name BkNav
extends RefCounted
## Navigation entre les écrans de Blackout (SPEC-GORDEKA §6.0). Chaque écran a un identifiant ;
## `--scene=bk_<id>` (web : `#scene=bk_<id>`) ouvre directement l'écran (QA, captures).
## « En ligne » ouvre ECRANS["en_ligne"] : une seule ligne à changer pour brancher les salons.

const ECRANS: Dictionary = {
	"qui_joue": "res://src/blackout/menus/bk_qui_joue.tscn",
	"accueil": "res://src/blackout/menus/bk_accueil.tscn",
	"profil": "res://src/blackout/menus/bk_profil_ecran.tscn",
	"reglages": "res://src/blackout/menus/bk_reglages.tscn",
	"partie_rapide": "res://src/blackout/menus/bk_partie_rapide.tscn",
	"en_ligne": "res://src/blackout/bk_online.tscn",
	"game": "res://src/blackout/bk_game.tscn",
}
## Anciens noms (QA) : bk_menu = l'accueil.
const ALIAS: Dictionary = {"menu": "accueil", "partie": "game"}


static func chemin(id: String) -> String:
	id = str(ALIAS.get(id, id))
	return str(ECRANS.get(id, ECRANS["accueil"]))


static func aller(id: String) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.change_scene_to_file.call_deferred(chemin(id))


## Écran de départ : « Qui joue ? », sauf `--scene=bk_<id>`.
static func depart(args: PackedStringArray) -> String:
	for arg: String in args:
		if arg.begins_with("--scene=bk_"):
			var id: String = arg.trim_prefix("--scene=bk_")
			id = str(ALIAS.get(id, id))
			if ECRANS.has(id):
				return id
	return "qui_joue"
