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

const _IRIS_SHADER: String = """
shader_type canvas_item;
uniform float radius = 1.5;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= 16.0 / 9.0;
	// bord en escalier : l'iris est pixelisé comme le reste du jeu
	uv = floor(uv * 40.0) / 40.0;
	COLOR = length(uv) < radius ? vec4(0.0) : vec4(0.09, 0.06, 0.10, 1.0);
}
"""

var _iris: ColorRect
var _transitioning: bool = false
var _pending_path: String = ""



func _ready() -> void:
	# Jamais de gris : la couleur de fond par défaut = sable
	RenderingServer.set_default_clear_color(Color(0.933, 0.792, 0.502))
	# Iris de transition (fondu rond façon rétro), au-dessus de tout
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 95
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_iris = ColorRect.new()
	_iris.set_anchors_preset(Control.PRESET_FULL_RECT)
	_iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = Shader.new()
	shader.code = _IRIS_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("radius", 1.5)
	_iris.material = material
	layer.add_child(_iris)


func _iris_to(target_radius: float, duration: float) -> void:
	var material: ShaderMaterial = _iris.material as ShaderMaterial
	var tween: Tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_method(
		func(value: float) -> void: material.set_shader_parameter("radius", value),
		material.get_shader_parameter("radius") as float, target_radius, duration)
	await tween.finished


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
	if _transitioning:
		# une navigation arrivée pendant le fondu n'est jamais perdue :
		# elle remplace la destination en attente
		_pending_path = scene_path
		return
	_transitioning = true
	await _iris_to(0.0, 0.32)
	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("SceneRouter: échec du changement de scène vers %s (%s)" % [scene_path, error])
	await get_tree().process_frame
	await _iris_to(1.5, 0.38)
	_transitioning = false
	if _pending_path != "":
		var next_path: String = _pending_path
		_pending_path = ""
		_change_scene(next_path)
