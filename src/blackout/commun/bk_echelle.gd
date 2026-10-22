class_name BkEchelle
extends RefCounted
## Résolution de l'écran selon ce qu'on montre (GDD-BLACKOUT.md §9, §13) :
## - le jeu en pixel art : résolution logique 640×360 (project.godot), étirée en « viewport » ×2 dans
##   la fenêtre de 1280×720, filtre plus proche voisin, pixels calés ;
## - les menus (et les écrans versus et podium posés sur la partie) en 1280×720 « canvas_items » : le
##   kit BkUi y garde ses textes lisses et ses gros boutons, sans rien redessiner pour 640×360.

const MENUS: Vector2i = Vector2i(1280, 720)


## Taille logique du jeu (project.godot : display/window/size/viewport_*).
static func taille_jeu() -> Vector2i:
	return Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 640)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 360)))


static func jeu() -> void:
	_poser(Window.CONTENT_SCALE_MODE_VIEWPORT, taille_jeu())


static func menus() -> void:
	_poser(Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, MENUS)


static func _poser(mode: Window.ContentScaleMode, taille: Vector2i) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var w: Window = tree.root
	if w.content_scale_mode == mode and w.content_scale_size == taille:
		return
	w.content_scale_mode = mode
	w.content_scale_size = taille
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
