extends Control
## Sélection des combattants (SPEC §10.5) : grille 6×2 de portraits,
## curseur J1 rouge / J2 vert, grand aperçu animé de chaque côté, nom,
## titre, archétype en 3 jauges, costume avec Haut/Bas (verrous visibles).
## Modes : "tower" (J1 + difficulté), "versus" (J1 + J2), "training" (J1).

const CELL: int = 30
const COLS: int = 6

var mode: String = "versus"
var ids: PackedStringArray = []
var _cursor: PackedInt32Array = PackedInt32Array([0, 1])
var _costume: PackedInt32Array = PackedInt32Array([0, 0])
var _done: Array[bool] = [false, false]
var _players: int = 1
var _previews: Array[FighterView] = [null, null]
var _info: Array[Label] = []
var _grid: Control
var _picking_difficulty: bool = false
var _font: Font


func _ready() -> void:
	AudioManager.play_music(&"select")
	mode = str(SceneRouter.params.get("mode", "versus"))
	_players = 2 if mode == "versus" else 1
	_font = load("res://assets/fonts/press_start_2p.ttf")
	ids = Roster.FIGHTERS.duplicate()
	if bool(Profiles.active().get("unlocks", {}).get("boss", false)) or OS.get_cmdline_user_args().has("--unlock-all"):
		ids.append(Roster.BOSS)
	UiKit.backdrop(self, "bg_hub", 0.45)
	var head: Label = UiKit.title({"tower": "PYRAMIDE DU PHARE", "versus": "VERSUS",
		"training": "ENTRAÎNEMENT"}.get(mode, "CHOIX"))
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 10
	head.add_theme_font_size_override(&"font_size", 8)
	add_child(head)
	_grid = Control.new()
	_grid.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	add_child(_grid)
	_grid.draw.connect(_draw_grid)
	_build_cells()
	for p: int in 2:
		var info: Label = UiKit.label("", 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_LEFT if p == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
		info.size = Vector2(130, 40)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(info)
		_info.append(info)
	if mode == "versus":
		InputHub.set_versus()
	else:
		InputHub.set_solo()
	var back: Button = UiKit.button("Retour", func() -> void: SceneRouter.goto(&"main_menu"), 60)
	back.position = Vector2(4, 4)
	back.focus_mode = Control.FOCUS_NONE
	add_child(back)
	var ok: Button = UiKit.button("OK", func() -> void: _confirm(0), 48)
	ok.name = "OkButton"
	ok.focus_mode = Control.FOCUS_NONE
	add_child(ok)
	get_viewport().size_changed.connect(_layout)
	_layout()
	for p: int in _players:
		_refresh(p)
	if _players == 1:
		_refresh_cpu()



func _layout() -> void:
	var w: float = get_viewport_rect().size.x
	_grid.position = Vector2(floorf((w - COLS * CELL) * 0.5), 216 - 2 * CELL - 8)
	_grid.size = Vector2(COLS * CELL, 2 * CELL)
	for p: int in 2:
		if _previews[p] != null:
			_previews[p].position = Vector2(48 if p == 0 else w - 48, 204)
		_info[p].position = Vector2(4 if p == 0 else w - 134, 30)
	var ok: Node = get_node_or_null("OkButton")
	if ok != null:
		(ok as Control).position = Vector2(w - 52, 4)


func _build_cells() -> void:
	for i: int in ids.size():
		var clip: Control = Control.new()
		clip.clip_contents = true
		clip.size = Vector2(CELL - 2, CELL - 2)
		clip.position = Vector2((i % COLS) * CELL + 1, (i / COLS) * CELL + 1)
		clip.mouse_filter = Control.MOUSE_FILTER_STOP
		clip.gui_input.connect(_on_cell_input.bind(i))
		var bg: ColorRect = ColorRect.new()
		bg.color = Color8(150, 104, 62) if i < 12 else Color8(44, 60, 110)
		bg.size = clip.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(bg)
		var face: PortraitView = PortraitView.create(ids[i])
		clip.add_child(face)
		_grid.add_child(clip)


func _on_cell_input(event: InputEvent, index: int) -> void:
	var tapped: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if not tapped or _picking_difficulty:
		return
	var p: int = 0 if not _done[0] else (1 if _players == 2 else 0)
	if _cursor[p] == index:
		_confirm(p)
	else:
		_cursor[p] = index
		_costume[p] = 0
		_refresh(p)


func _refresh(p: int) -> void:
	var id: String = ids[_cursor[p]]
	if _previews[p] != null:
		_previews[p].queue_free()
	_previews[p] = UiKit.fighter_preview(id, _costume[p], "idle", 1 if p == 0 else -1)
	_previews[p].z_index = 2
	add_child(_previews[p])
	var data: Dictionary = FighterDb.load_json(id)
	var stats: Dictionary = data.get("stats", {})
	var bars: String = "Puissance %s\nVitesse   %s\nPortée    %s" % [
		_bar(int(stats.get("power", 2))), _bar(int(stats.get("speed", 2))), _bar(int(stats.get("reach", 2)))]
	var lock: String = "" if _costume_ok(id, _costume[p]) else "  (verrouillé)"
	_info[p].text = "%s\n%s\nCostume %d%s\n%s" % [str(data.get("name", id)).to_upper(),
		str(data.get("title", "")), _costume[p] + 1, lock, bars]
	_layout()
	_grid.queue_redraw()


func _refresh_cpu() -> void:
	if mode != "versus":
		_info[1].text = "" if mode == "tower" else "HONDAR\nBonhomme de sable"
		if mode == "training" and _previews[1] == null:
			_previews[1] = UiKit.fighter_preview(Roster.DUMMY, 0, "idle", -1)
			add_child(_previews[1])
			_layout()


func _bar(n: int) -> String:
	return "#".repeat(n) + ".".repeat(3 - n)


func _costume_ok(id: String, c: int) -> bool:
	if c == 0 or OS.get_cmdline_user_args().has("--unlock-all"):
		return true
	var unlocks: Dictionary = Profiles.active().get("unlocks", {})
	return (unlocks.get(id, [0]) as Array).has(c)


func _draw_grid() -> void:
	for i: int in ids.size():
		var r: Rect2 = Rect2((i % COLS) * CELL, (i / COLS) * CELL, CELL, CELL)
		_grid.draw_rect(r, UiKit.C_OUTLINE, false, 1.0)
	var colors: Array[Color] = [UiKit.C_RED, UiKit.C_GREEN]
	for p: int in _players:
		var i2: int = _cursor[p]
		var r2: Rect2 = Rect2((i2 % COLS) * CELL, (i2 / COLS) * CELL, CELL, CELL).grow(-p)
		_grid.draw_rect(r2, colors[p], false, 2.0)
		if _done[p]:
			_grid.draw_rect(r2.grow(-3), Color(colors[p], 0.35))
		_grid.draw_string(_font, r2.position + Vector2(2, 9), "J%d" % (p + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, colors[p])


func _unhandled_input(event: InputEvent) -> void:
	if _picking_difficulty:
		return
	for p: int in _players:
		var prefixes: Array[String] = []
		if _players == 1:
			prefixes.append_array(["p1", "p2", "ui"])
		else:
			prefixes.append("p1" if p == 0 else "p2")
		if _done[p]:
			if _pressed(event, prefixes, ["_kick", "_cancel"]):
				_done[p] = false
				_grid.queue_redraw()
			continue
		var moved: bool = false
		if _pressed(event, prefixes, ["_left"]):
			_cursor[p] = (_cursor[p] + ids.size() - 1) % ids.size()
			moved = true
		elif _pressed(event, prefixes, ["_right"]):
			_cursor[p] = (_cursor[p] + 1) % ids.size()
			moved = true
		elif _pressed(event, prefixes, ["_up"]):
			_costume[p] = (_costume[p] + 3) % 4
			_refresh(p)
		elif _pressed(event, prefixes, ["_down"]):
			_costume[p] = (_costume[p] + 1) % 4
			_refresh(p)
		elif _pressed(event, prefixes, ["_punch", "_accept"]):
			_confirm(p)
		elif _pressed(event, prefixes, ["_kick", "_cancel"]):
			SceneRouter.goto(&"main_menu")
		if moved:
			_costume[p] = 0
			AudioManager.sfx(&"ui_move")
			_refresh(p)


func _pressed(event: InputEvent, prefixes: Array[String], suffixes: Array) -> bool:
	for prefix: String in prefixes:
		for suffix: String in suffixes:
			if InputMap.has_action(prefix + suffix) and event.is_action_pressed(prefix + suffix):
				return true
	return false


func _confirm(p: int) -> void:
	var id: String = ids[_cursor[p]]
	if not _costume_ok(id, _costume[p]):
		AudioManager.sfx(&"ui_no")
		return
	_done[p] = true
	AudioManager.sfx(&"ui_ok")
	_grid.queue_redraw()
	if _previews[p] != null:
		_previews[p].play_preview("win", 1 if p == 0 else -1)
	for q: int in _players:
		if not _done[q]:
			return
	_proceed()


func _proceed() -> void:
	var p1: String = ids[_cursor[0]]
	match mode:
		"tower":
			_ask_difficulty()
		"training":
			InputHub.set_solo()
			SceneRouter.goto(&"fight", TrainingMode.fight_params(p1, _costume[0]))
		_:
			var p2: String = ids[_cursor[1]]
			var c2: int = _costume[1]
			if p2 == p1 and c2 == _costume[0]:
				c2 = (c2 + 1) % 4
			SceneRouter.goto(&"stage_select", {"p1": p1, "c1": _costume[0], "p2": p2, "c2": c2})


func _ask_difficulty() -> void:
	_picking_difficulty = true
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.1, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var label: Label = UiKit.label("Difficulté ?", 16, UiKit.C_GOLD)
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.position.y = 40
	add_child(label)
	var buttons: Array = []
	for d: int in 3:
		buttons.append(UiKit.button(TowerMode.DIFFICULTY_NAMES[d], _start_tower.bind(d)))
	UiKit.menu_column(self, buttons, 70)


func _start_tower(difficulty: int) -> void:
	TowerMode.start(ids[_cursor[0]], _costume[0], difficulty)
	InputHub.set_solo()
	SceneRouter.goto(&"tower", {"event": "start"})
