class_name GkNav
extends RefCounted
## Navigation entre les écrans de Gordeka (SPEC-GORDEKA §6.0). Chaque écran a un identifiant ;
## `--scene=gk_<id>` (web : `#scene=gk_<id>`) ouvre directement l'écran (QA, captures).
## « En ligne » ouvre ECRANS["en_ligne"] : une seule ligne à changer pour brancher les salons.

const ECRANS: Dictionary = {
	"qui_joue": "res://src/gordeka/menus/gk_qui_joue.tscn",
	"accueil": "res://src/gordeka/menus/gk_accueil.tscn",
	"profil": "res://src/gordeka/menus/gk_profil_ecran.tscn",
	"reglages": "res://src/gordeka/menus/gk_reglages.tscn",
	"partie_rapide": "res://src/gordeka/menus/gk_partie_rapide.tscn",
	"en_ligne": "res://src/gordeka/gk_online.tscn",
	"game": "res://src/gordeka/gk_game.tscn",
}
## Anciens noms (QA) : gk_menu = l'accueil.
const ALIAS: Dictionary = {"menu": "accueil", "partie": "game"}


static func chemin(id: String) -> String:
	id = str(ALIAS.get(id, id))
	return str(ECRANS.get(id, ECRANS["accueil"]))


static func aller(id: String) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var am: Node = tree.root.get_node_or_null("/root/AudioManager")
	if id == "game" and am != null:
		am.stop_music()
	tree.change_scene_to_file.call_deferred(chemin(id))


## Écran de départ : « Qui joue ? », sauf `--scene=gk_<id>`.
static func depart(args: PackedStringArray) -> String:
	for arg: String in args:
		if arg.begins_with("--scene=gk_"):
			var id: String = arg.trim_prefix("--scene=gk_")
			id = str(ALIAS.get(id, id))
			if ECRANS.has(id):
				return id
	return "qui_joue"
