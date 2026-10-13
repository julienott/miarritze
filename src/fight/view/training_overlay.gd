class_name TrainingOverlay
extends Control
## Surcouche d'entraînement : historique des entrées de J1, dégâts du
## dernier combo, comportement du mannequin, liste des coups.

signal behavior_requested(index: int)
signal move_list_requested

var sim: FightSim
var behavior: int = 0
var _history: Array[String] = []
var _counts: Array[int] = []
var _last_mask: int = -1
var _combo_peak: int = 0
var _combo_hits: int = 0
var _font: Font
var _behavior_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/press_start_2p.ttf")
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	_behavior_button = UiKit.button("Mannequin : " + TrainingMode.BEHAVIORS[behavior], _cycle, 150)
	_behavior_button.focus_mode = Control.FOCUS_NONE
	add_child(_behavior_button)
	_place_behavior()
	var moves: Button = UiKit.button("Coups", func() -> void: move_list_requested.emit(), 60)
	moves.focus_mode = Control.FOCUS_NONE
	moves.position = Vector2(size.x - 64, 70)
	add_child(moves)
	_build_keys_help()


## Petit panneau clavier : rappel des touches par défaut, affiché en bas à
## gauche pendant 6 s puis masqué (bouton « Touches » pour le rouvrir).
var _keys_panel: PanelContainer
var _keys_toggle: Button


func _build_keys_help() -> void:
	_keys_panel = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color8(24, 16, 28, 220)
	sb.border_color = UiKit.C_GOLD
	sb.set_border_width_all(1)
	sb.set_content_margin_all(5)
	_keys_panel.add_theme_stylebox_override(&"panel", sb)
	_keys_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 1)
	_keys_panel.add_child(v)
	for line: String in [
		"TOUCHES  J1",
		"ZQSD : bouger / sauter / s'accroupir",
		"J : POING    K : PIED",
		"L : SPÉCIAL    I : GARDE",
		"Échap : pause",
	]:
		var l: Label = UiKit.label(line, 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_LEFT)
		v.add_child(l)
	add_child(_keys_panel)
	_keys_panel.position = Vector2(6, size.y - 72)
	_keys_toggle = UiKit.button("Touches", _toggle_keys, 60)
	_keys_toggle.focus_mode = Control.FOCUS_NONE
	_keys_toggle.position = Vector2(size.x - 128, 70)
	add_child(_keys_toggle)
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(_keys_panel):
			_keys_panel.visible = false)


func _toggle_keys() -> void:
	if is_instance_valid(_keys_panel):
		_keys_panel.visible = not _keys_panel.visible


func _cycle() -> void:
	behavior = (behavior + 1) % TrainingMode.BEHAVIORS.size()
	_behavior_button.text = "Mannequin : " + TrainingMode.BEHAVIORS[behavior]
	_place_behavior()
	behavior_requested.emit(behavior)


## Calé à droite selon la largeur réelle du libellé (il varie avec le comportement).
func _place_behavior() -> void:
	_behavior_button.reset_size()
	var bw: float = _behavior_button.get_combined_minimum_size().x
	_behavior_button.position = Vector2(size.x - bw - 4, 44)


func _process(_delta: float) -> void:
	if sim == null:
		return
	var mask: int = sim.buffers[0].current()
	if mask != _last_mask:
		_last_mask = mask
		if mask != 0:
			_history.push_front(_describe(mask, sim.f[0].facing))
			_counts.push_front(1)
			if _history.size() > 12:
				_history.pop_back()
				_counts.pop_back()
	var dummy: FighterState = sim.f[1]
	if dummy.combo_damage > 0:
		_combo_peak = dummy.combo_damage
		_combo_hits = dummy.combo_hits
	queue_redraw()


func _describe(mask: int, facing: int) -> String:
	var dir: int = InputBuffer.numpad(mask, facing)
	var dirs: Dictionary = {1: "BAr", 2: "B", 3: "BAv", 4: "Ar", 5: "", 6: "Av", 7: "HAr", 8: "H", 9: "HAv"}
	var out: String = str(dirs.get(dir, ""))
	for pair: Array in [[SimConst.PUNCH, "P"], [SimConst.KICK, "K"], [SimConst.SPECIAL, "S"], [SimConst.GUARD, "G"]]:
		if mask & int(pair[0]):
			out += ("+" if out != "" else "") + str(pair[1])
	return out


func _draw() -> void:
	for i: int in _history.size():
		var alpha: float = 1.0 - i * 0.07
		draw_string(_font, Vector2(6, 84 + i * 9), _history[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(UiKit.C_LINEN, alpha))
	if _combo_peak > 0:
		draw_string(_font, Vector2(size.x * 0.5 - 100, 66), "COMBO %d coups : %d dégâts" % [_combo_hits, _combo_peak],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.C_GOLD)
	if sim.f[0].state == SimConst.ST_MOVE and sim.f[0].move >= 0:
		var mv: MoveDef = sim.defs[0].moves[sim.f[0].move]
		draw_string(_font, Vector2(size.x * 0.5 - 100, 76), "%s (%d+%d+%d)" % [mv.name, mv.startup, mv.active, mv.recovery],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.C_LINEN)
