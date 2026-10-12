extends Control
## Fin de pyramide (SPEC §3.2, §10.5) : cinématique « TXAPELDUN ! » (la
## txapela descend sur la tête du champion), puis la fin illustrée du
## personnage en 3 cadrages d'une même image, texte en cadre parchemin.
## Tant que l'illustration RD n'existe pas : décor maison + pose de victoire.

const PANEL_TIME: float = 3.6

var _params: Dictionary = {}
var _stage: Node2D
var _texts: Array = []
var _text_label: Label
var _panel: int = -1
var _beret: Polygon2D
var _hero: FighterView
var _done: bool = false
var _skip_ready: bool = false
var _tween: Tween
var _has_art: bool = false
var _art_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_params = SceneRouter.params.duplicate()
	var fighter: String = str(_params.get("fighter", "louis"))
	var data: Dictionary = FighterDb.load_json(fighter)
	_texts = data.get("ending_text", ["", "", ""])
	var bg: ColorRect = ColorRect.new()
	bg.color = Color8(24, 16, 28)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_stage = Node2D.new()
	add_child(_stage)
	var art_path: String = "res://assets/fighters/%s/ending.png" % fighter
	if ResourceLoader.exists(art_path):
		var art: Sprite2D = Sprite2D.new()
		art.texture = load(art_path)
		art.centered = false
		_art_offset = Vector2(floorf((get_viewport_rect().size.x - 320.0) * 0.5), 0)
		art.position = _art_offset
		_stage.add_child(art)
		_has_art = true
	else:
		var pbg: PixelBg = PixelBg.new()
		pbg.bg_name = _bg_for(Roster.home_stage(fighter))
		_stage.add_child(pbg)
		_hero = UiKit.fighter_preview(fighter, int(_params.get("costume", 0)), "win")
		_hero.position = Vector2(get_viewport_rect().size.x * 0.5, 196)
		_stage.add_child(_hero)
	_beret = Polygon2D.new()
	_beret.polygon = PackedVector2Array([Vector2(-12, 0), Vector2(12, 0), Vector2(10, -6), Vector2(0, -9), Vector2(-10, -6)])
	_beret.color = UiKit.C_RED
	_beret.position = Vector2(get_viewport_rect().size.x * 0.5, -20)
	_stage.add_child(_beret)
	var frame: PanelContainer = PanelContainer.new()
	var parchment: StyleBoxFlat = StyleBoxFlat.new()
	parchment.bg_color = Color8(236, 225, 204)
	parchment.border_color = Color8(108, 72, 46)
	parchment.set_border_width_all(2)
	parchment.set_content_margin_all(6)
	frame.add_theme_stylebox_override(&"panel", parchment)
	frame.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	frame.offset_top = -40
	frame.offset_left = 20
	frame.offset_right = -20
	frame.offset_bottom = -6
	add_child(frame)
	_text_label = UiKit.label("", 8, UiKit.C_OUTLINE)
	_text_label.remove_theme_constant_override(&"outline_size")
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame.add_child(_text_label)
	AudioManager.play_music(&"txapeldun")
	AudioManager.voice(&"txapeldun")
	get_tree().create_timer(9.0).timeout.connect(func() -> void: AudioManager.play_music(&"ending"))
	_txapeldun()
	get_tree().create_timer(1.0).timeout.connect(func() -> void: _skip_ready = true)


func _bg_for(stage: String) -> String:
	var map: Dictionary = {"grande_plage": "bg_beach", "grande_plage_soir": "bg_beach",
		"cote_basques": "bg_surf", "cote_basques_crepuscule": "bg_surf", "port_pecheurs": "bg_fishing",
		"rocher_vierge": "bg_rock", "port_vieux": "bg_espadrille", "phare_sommet": "bg_menu"}
	return str(map.get(stage, "bg_menu"))


func _txapeldun() -> void:
	_text_label.text = ""
	var big: Label = UiKit.title("TXAPELDUN !")
	big.add_theme_font_size_override(&"font_size", 24)
	big.set_anchors_preset(Control.PRESET_TOP_WIDE)
	big.position.y = 20
	big.name = "Big"
	add_child(big)
	# La txapela vise le haut de la silhouette du champion.
	var head_y: float = 196.0 - _hero_height() - 2.0 if _hero != null else 80.0
	if _has_art:
		_beret.visible = false   # la txapela est déjà dans l'illustration
	if _tween != null:
		_tween.kill()
	var tween: Tween = create_tween()
	_tween = tween
	tween.tween_property(_beret, "position:y", head_y, 1.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.4)
	tween.tween_callback(func() -> void:
		big.queue_free()
		_next_panel())


func _hero_height() -> float:
	var data: Dictionary = FighterDb.load_json(str(_params.get("fighter", "louis")))
	var cell: float = float(data.get("cell", 128))
	return 104.0 if cell <= 128.0 else 130.0


func _next_panel() -> void:
	_panel += 1
	if _panel >= 3:
		_show_summary()
		return
	_text_label.text = str(_texts[_panel]) if _panel < _texts.size() else ""
	var w: float = get_viewport_rect().size.x
	# Cadrages : plan large, puis 2 zooms ×2 avec un lent panoramique.
	var zoom: float = 1.0 if _panel == 0 else 2.0
	var focus: Vector2 = Vector2(w * 0.5, 150) if _panel == 1 else Vector2(w * 0.5 + 40, 120)
	if _has_art:
		# Cadrages sur l'illustration : le champion, puis le décor.
		focus = _art_offset + (Vector2(160, 70) if _panel == 1 else Vector2(230, 100))
	var start: Vector2 = Vector2.ZERO if _panel == 0 else (Vector2(w * 0.5, 108) - focus * zoom)
	_stage.scale = Vector2(zoom, zoom)
	_stage.position = start.round()
	if _tween != null:
		_tween.kill()
	var tween: Tween = create_tween()
	_tween = tween
	if _panel > 0:
		tween.tween_property(_stage, "position", (start + Vector2(-30, 0)).round(), PANEL_TIME)
	else:
		tween.tween_interval(PANEL_TIME)
	tween.tween_callback(_next_panel)


func _show_summary() -> void:
	_done = true
	_stage.scale = Vector2.ONE
	_stage.position = Vector2.ZERO
	var unlocked: Array = _params.get("unlocked", [])
	var lines: PackedStringArray = ["SCORE FINAL : %d" % int(_params.get("score", 0))]
	for u: Variant in unlocked:
		lines.append("Débloqué : %s" % str(u))
	_text_label.text = "\n".join(lines)
	var ok: Button = UiKit.button("Menu", func() -> void:
		TowerMode.run = null
		SceneRouter.goto(&"main_menu"), 80)
	ok.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ok.position = Vector2(-40, 10)
	add_child(ok)
	ok.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _done or not _skip_ready:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"p1_punch"):
		_skip_ready = false
		get_tree().create_timer(0.3).timeout.connect(func() -> void: _skip_ready = true)
		for child: Node in get_children():
			if child.name == "Big":
				child.queue_free()
		_next_panel()
