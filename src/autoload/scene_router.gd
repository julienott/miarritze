extends Node
## SceneRouter — transitions de scène, chargement/déchargement propre.
##
## Point unique de navigation : personne d'autre n'appelle change_scene.
## Responsable anti-fuite WASM : change_scene_to_file libère la scène
## sortante ; les épreuves ne gardent aucune référence croisée.

const _SCENES: Dictionary = {
	&"boot": "res://src/ui/boot/boot.tscn",
	&"orientation_gate": "res://src/ui/orientation_gate/orientation_gate.tscn",
	&"pseudo_entry": "res://src/ui/pseudo_entry/pseudo_entry.tscn",
	&"hub": "res://src/hub/hub.tscn",
	&"results": "res://src/ui/results/results.tscn",
	&"leaderboard": "res://src/ui/leaderboard/leaderboard.tscn",
}

func _ready() -> void:
	# Jamais de gris : la couleur de fond par défaut = sable
	RenderingServer.set_default_clear_color(Color(0.933, 0.792, 0.502))


## Payload de navigation vers l'écran results (posé par goto_results).
var last_challenge: StringName = &""
var last_score: int = 0
var last_was_best: bool = false

## Épreuve affichée par défaut à l'ouverture du leaderboard (&"" = cumul).
var leaderboard_focus: StringName = &""


func goto_orientation_gate() -> void:
	_goto(_SCENES[&"orientation_gate"])


func goto_pseudo_entry() -> void:
	_goto(_SCENES[&"pseudo_entry"])


## Va au hub (carte de Biarritz).
func goto_hub() -> void:
	_goto(_SCENES[&"hub"])


## Lance une épreuve par identifiant (cf. Challenges.IDS).
func goto_challenge(id: StringName) -> void:
	var path: String = "res://src/challenges/%s/%s.tscn" % [id, id]
	if not ResourceLoader.exists(path):
		push_warning("SceneRouter: épreuve absente (%s), pas encore construite" % id)
		return
	_goto(path)


## Fin d'épreuve → écran de score (appelé par ChallengeBase).
func goto_results(challenge: StringName, score: int, was_best: bool) -> void:
	last_challenge = challenge
	last_score = score
	last_was_best = was_best
	_goto(_SCENES[&"results"])


## Va aux tableaux de classement. `focus` = épreuve pré-sélectionnée.
func goto_leaderboard(focus: StringName = &"") -> void:
	leaderboard_focus = focus
	_goto(_SCENES[&"leaderboard"])


func _goto(scene_path: String) -> void:
	# Différé : un changement de scène pendant un callback de signal
	# (fin d'épreuve, timer) est unsafe.
	_change_scene.call_deferred(scene_path)


func _change_scene(scene_path: String) -> void:
	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("SceneRouter: échec du changement de scène vers %s (%s)" % [scene_path, error])
