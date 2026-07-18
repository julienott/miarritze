extends Node
## SceneRouter — transitions de scène, chargement/déchargement propre.
##
## Point unique de navigation : personne d'autre n'appelle change_scene.
## Responsable anti-fuite WASM : la scène quittée doit être libérée
## (cf. CLAUDE.md §8, budget mémoire web).
## STUB Phase 0 : navigation minimale, pas encore de transitions animées.

const _HUB_SCENE: String = "res://src/hub/hub.tscn"
const _ORIENTATION_GATE_SCENE: String = "res://src/ui/orientation_gate/orientation_gate.tscn"
const _LEADERBOARD_SCENE: String = "res://src/ui/leaderboard/leaderboard.tscn"


## Va au hub (carte de Biarritz). STUB : hub.tscn n'existe pas encore (Phase 1).
func goto_hub() -> void:
	_goto(_HUB_SCENE)


## Lance une épreuve par identifiant (cf. Challenges). STUB Phase 1.
func goto_challenge(_id: StringName) -> void:
	pass


## Va aux tableaux de classement. STUB Phase 1.
func goto_leaderboard() -> void:
	_goto(_LEADERBOARD_SCENE)


## Va à l'écran "tourne ton appareil" (appelé par boot en Phase 0).
func goto_orientation_gate() -> void:
	_goto(_ORIENTATION_GATE_SCENE)


## Changement de scène centralisé. Godot libère la scène sortante ;
## les épreuves devront en plus libérer leurs ressources lourdes ici.
func _goto(scene_path: String) -> void:
	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("SceneRouter: échec du changement de scène vers %s (%s)" % [scene_path, error])
