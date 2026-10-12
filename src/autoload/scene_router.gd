extends Node
## SceneRouter — transitions de scène, chargement/déchargement propre.
##
## Point unique de navigation : personne d'autre n'appelle change_scene.
## Responsable anti-fuite WASM : change_scene_to_file libère la scène
## sortante ; les écrans ne gardent aucune référence croisée.

## Table des écrans : identifiant -> scène. Les écrans se passent leurs
## paramètres via `params` (lu par la scène d'arrivée dans _ready).
var _SCENES: Dictionary = {
	&"boot": "res://src/ui/boot/boot.tscn",
	&"title": "res://src/ui/title/title.tscn",
	&"fight": "res://src/fight/view/fight_scene.tscn",
	&"main_menu": "res://src/ui/main_menu/main_menu.tscn",
	&"fighter_select": "res://src/ui/fighter_select/fighter_select.tscn",
	&"stage_select": "res://src/ui/stage_select/stage_select.tscn",
	&"versus_splash": "res://src/ui/versus_splash/versus_splash.tscn",
	&"tower": "res://src/ui/tower/tower.tscn",
	&"ending": "res://src/ui/ending/ending.tscn",
	&"results": "res://src/ui/results/results.tscn",
	&"settings": "res://src/ui/settings/settings.tscn",
	&"profile_select": "res://src/ui/profile_select/profile_select.tscn",
	&"profile_edit": "res://src/ui/profile_edit/profile_edit.tscn",
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
	# Jamais de gris : fond par défaut = bleu nuit du Phare
	RenderingServer.set_default_clear_color(Color(0.11, 0.13, 0.26))
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


## Paramètres du dernier `goto` (lus par la scène d'arrivée).
var params: Dictionary = {}


## Enregistre (ou remplace) une scène dans la table (utile aux modes).
func register(id: StringName, path: String) -> void:
	_SCENES[id] = path


## Vrai si l'écran est dans la table.
func has_screen(id: StringName) -> bool:
	return _SCENES.has(id)


## Navigue vers un écran de la table, avec des paramètres optionnels.
func goto(id: StringName, p_params: Dictionary = {}) -> void:
	if not _SCENES.has(id):
		push_error("SceneRouter: écran inconnu %s" % id)
		return
	params = p_params
	_goto(_SCENES[id])


## Navigue vers une scène par chemin (QA, outils).
func goto_path(path: String, p_params: Dictionary = {}) -> void:
	params = p_params
	_goto(path)


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
