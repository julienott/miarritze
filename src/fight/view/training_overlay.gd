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
	_behavior_button.position = Vector2(size.x - 154, 44)
	add_child(_behavior_button)
	var moves: Button = UiKit.button("Coups", func() -> void: move_list_requested.emit(), 60)
	moves.focus_mode = Control.FOCUS_NONE
	moves.position = Vector2(size.x - 64, 70)
	add_child(moves)


func _cycle() -> void:
	behavior = (behavior + 1) % TrainingMode.BEHAVIORS.size()
	_behavior_button.text = "Mannequin : " + TrainingMode.BEHAVIORS[behavior]
	behavior_requested.emit(behavior)


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
