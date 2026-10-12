extends Control
## Pyramide (SPEC §10.5) : le phare de Biarritz en coupe, un étage par
## combat avec le portrait de l'adversaire, le curseur qui monte, le
## faisceau qui balaie. Appuie pour combattre.

const FLOOR_H: int = 19
const TOWER_W: int = 56

var _run: TowerMode
var _event: String = ""
var _beam: float = 0.0
var _cursor_y: float = 0.0
var _font: Font
var _ready_to_go: bool = false
var _canvas: Control


func _ready() -> void:
	_run = TowerMode.run
	if _run == null:
		SceneRouter.goto(&"main_menu")
		return
	_event = str(SceneRouter.params.get("event", "start"))
	_font = load("res://assets/fonts/press_start_2p.ttf")
	UiKit.backdrop(self, "bg_lighthouse", 0.35)
	# Le phare est dessiné par un enfant placé après le fond (le _draw du
	# parent passerait sous ses enfants).
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_tower)
	add_child(_canvas)
	var w: float = get_viewport_rect().size.x
	var tower_x: float = floorf(w * 0.5 - TOWER_W * 0.5)
	# Portraits des adversaires, un par étage (le 6e en a deux).
	for i: int in TowerMode.FLOORS:
		var fl: Dictionary = _run.floors[i]
		var opps: Array = fl["opponents"]
		for k: int in opps.size():
			var face: PortraitView = PortraitView.create(str(opps[k]), int(fl.get("costume", 0)))
			face.region_enabled = true
			face.region_rect = Rect2(5, 2, FLOOR_H - 2, FLOOR_H - 2)
			face.position = Vector2(tower_x + 3 + k * (FLOOR_H - 1), _floor_y(i) + 1)
			add_child(face)
	var player: FighterView = UiKit.fighter_preview(_run.fighter, _run.costume, "idle")
	player.position = Vector2(60, 190)
	add_child(player)
	var opp_id: String = _run.current_opponent()
	var opp: FighterView = UiKit.fighter_preview(opp_id, int(_run.current_floor().get("costume", 0)), "idle", -1)
	opp.position = Vector2(w - 60, 190)
	add_child(opp)
	var kind_names: Dictionary = {"normal": "", "double": "COMBAT EN DOUBLE", "reflet": "LE REFLET",
		"rival": "LE RIVAL", "boss": "LE GARDIEN DU PHARE"}
	var title_text: String = "ÉTAGE %d" % (_run.floor_index + 1)
	var kind: String = str(kind_names.get(_run.current_floor()["kind"], ""))
	var info: Label = UiKit.label("%s\n%s\n%s" % [title_text, kind, Roster.display_name(opp_id).to_upper()], 8,
		UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_RIGHT)
	info.position = Vector2(w - 154, 30)
	info.size = Vector2(150, 40)
	add_child(info)
	var msg: String = {"start": "Allez !", "won": "Bravo !",
		"lost": "Encore ! -20 %", "double_next": "Et de deux !"}.get(_event, "")
	if not _run.last_unlocks.is_empty():
		msg += "\n" + "\n".join(_run.last_unlocks)
		_run.last_unlocks.clear()
	var score: Label = UiKit.label("SCORE %d\n%s\n%s" % [_run.score, TowerMode.DIFFICULTY_NAMES[_run.difficulty], msg],
		8, UiKit.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	score.position = Vector2(4, 30)
	score.size = Vector2(150, 40)
	add_child(score)
	var go: Button = UiKit.button("Combattre !", _fight, 100)
	go.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	go.position = Vector2(w * 0.5 - 50, 216 - 28)
	add_child(go)
	go.grab_focus.call_deferred()
	var quit: Button = UiKit.button("Abandonner", func() -> void:
		TowerMode.run = null
		SceneRouter.goto(&"main_menu"), 80)
	quit.position = Vector2(4, 4)
	quit.focus_mode = Control.FOCUS_NONE
	add_child(quit)
	var from: int = maxi(_run.floor_index - (1 if _event == "won" else 0), 0)
	_cursor_y = _floor_y(from)
	create_tween().tween_property(self, "_cursor_y", _floor_y(_run.floor_index), 0.9) \
		.set_trans(Tween.TRANS_SINE).set_delay(0.3)
	get_tree().create_timer(0.6).timeout.connect(func() -> void: _ready_to_go = true)
	AudioManager.play_music(&"tower")


func _floor_y(i: int) -> float:
	return 196.0 - (i + 1) * FLOOR_H


func _process(delta: float) -> void:
	_beam += delta * 1.6
	_canvas.queue_redraw()


func _draw_tower() -> void:
	var w: float = size.x
	var x0: float = floorf(w * 0.5 - TOWER_W * 0.5)
	var top: float = _floor_y(TowerMode.FLOORS - 1)
	# Lanterne et faisceau
	var lamp: Vector2 = Vector2(w * 0.5, top - 14)
	var ang: float = sin(_beam) * 1.2
	var dir: Vector2 = Vector2(cos(ang), sin(ang) * 0.25)
	for s: int in [-1, 1]:
		var tip: Vector2 = lamp + Vector2(dir.x * s, dir.y) * 220.0
		_canvas.draw_colored_polygon(PackedVector2Array([lamp, tip + Vector2(0, -18), tip + Vector2(0, 18)]),
			Color(1.0, 0.95, 0.6, 0.18))
	_canvas.draw_rect(Rect2(x0 + 12, top - 22, TOWER_W - 24, 16), UiKit.C_OUTLINE)
	_canvas.draw_rect(Rect2(x0 + 14, top - 20, TOWER_W - 28, 12), Color8(255, 232, 110))
	_canvas.draw_rect(Rect2(x0 + 8, top - 6, TOWER_W - 16, 6), UiKit.C_OUTLINE)
	# Fût du phare, étage par étage
	for i: int in TowerMode.FLOORS:
		var y: float = _floor_y(i)
		var inset: float = floorf((TowerMode.FLOORS - 1 - i) * 0.0)
		var r: Rect2 = Rect2(x0 + inset, y, TOWER_W - inset * 2, FLOOR_H)
		var done: bool = i < _run.floor_index
		var fill: Color = Color8(236, 225, 204) if not done else Color8(176, 160, 140)
		if i == TowerMode.FLOORS - 1:
			fill = Color8(44, 60, 110)
		_canvas.draw_rect(r, UiKit.C_OUTLINE)
		_canvas.draw_rect(r.grow(-1), fill)
		_canvas.draw_string(_font, Vector2(r.end.x - 14, y + 13), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			UiKit.C_OUTLINE if i < TowerMode.FLOORS - 1 else UiKit.C_GOLD)
		if done:
			_canvas.draw_string(_font, Vector2(r.end.x - 26, y + 13), "v", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.C_GREEN)
		if i == _run.floor_index:
			_canvas.draw_rect(r.grow(1), UiKit.C_GOLD, false, 2.0)
	_canvas.draw_rect(Rect2(x0 - 6, 196, TOWER_W + 12, 8), UiKit.C_OUTLINE)
	# Curseur du joueur
	var cy: float = _cursor_y
	_canvas.draw_rect(Rect2(x0 - 10, cy + 4, 8, 12), UiKit.C_OUTLINE)
	_canvas.draw_rect(Rect2(x0 - 9, cy + 5, 6, 10), UiKit.C_RED)
	_canvas.draw_rect(Rect2(x0 + TOWER_W + 2, cy + 4, 8, 12), UiKit.C_OUTLINE)
	_canvas.draw_rect(Rect2(x0 + TOWER_W + 3, cy + 5, 6, 10), UiKit.C_RED)


func _fight() -> void:
	if not _ready_to_go:
		return
	var params: Dictionary = _run.fight_params()
	params["names"] = [Roster.display_name(_run.fighter), Roster.display_name(_run.current_opponent())]
	SceneRouter.goto(&"versus_splash", params)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"p1_punch") or event.is_action_pressed(&"ui_accept"):
		_fight()
