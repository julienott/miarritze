extends Control
## Choix du décor (versus, combat rapide) : vignettes des décors + « Au hasard ».
## Le décor sélectionné s'affiche en grand derrière la grille, avec son nom.
## Clavier / manette : flèches + valider ; toucher : un tap sur la vignette.

## Vignette : image 84×44 dans un cadre de 3 px.
const THUMB: Vector2i = Vector2i(84, 44)
const FRAME: int = 3
const COLUMNS: int = 4
const GHOST_TAP_MS: int = 600

var _params: Dictionary = {}
var _quick: bool = false
var _bg: Sprite2D
var _name: Label
var _cards: Array[Button] = []
var _opened_ms: int = 0


func _ready() -> void:
	_opened_ms = Time.get_ticks_msec()
	AudioManager.play_music(&"select")
	_params = SceneRouter.params.duplicate()
	_quick = str(_params.get("mode", "")) == "quick"
	UiKit.backdrop(self, "bg_hub", 0.0)
	_bg = Sprite2D.new()
	_bg.centered = false
	add_child(_bg)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.09, 0.06, 0.1, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var head: Label = UiKit.title("Choisis le décor", UiKit.C_GOLD) if _quick else UiKit.title("Choix de la map")
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 4
	add_child(head)
	_name = UiKit.label("", 8, UiKit.C_GOLD)
	_name.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_name.position.y = 24
	add_child(_name)
	var grid: GridContainer = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	grid.position = Vector2(0, 36)
	add_child(grid)
	# Centrage sur la largeur réelle (iPhone 19,5:9 plus large que 384).
	var center: Callable = func() -> void:
		grid.reset_size()
		grid.position.x = roundf((get_viewport_rect().size.x - grid.get_combined_minimum_size().x) * 0.5)
	get_viewport().size_changed.connect(center)
	center.call_deferred()
	for id: String in Roster.STAGES:
		grid.add_child(_card(id))
	var rnd: Button = _card("")
	grid.add_child(rnd)
	# Combat rapide : « Au hasard » présélectionné (une validation = l'ancien
	# comportement) ; versus : premier décor.
	(rnd if _quick else _cards[0]).grab_focus.call_deferred()
	var back: Button = UiKit.button("Retour", _back, 60)
	back.position = Vector2(4, 4)
	back.focus_mode = Control.FOCUS_NONE
	add_child(back)
	if str(_params.get("mode", "")) == "online" and not OnlineMode.qa.is_empty():
		get_tree().create_timer(0.8).timeout.connect(_pick.bind("grande_plage"))
	var rounds: Label = UiKit.label("Meilleur des 3 rounds", 8, UiKit.C_LINEN)
	rounds.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	rounds.position.y = -14
	add_child(rounds)


## Image du décor (première frame du fond), ou ancien décor de repli.
func _stage_image(id: String) -> Image:
	var path: String = "res://assets/stages/%s/far_v_0.png" % id
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/%s_0.png" % str(StageView.FALLBACK_BG.get(id, "bg_beach"))
		if not ResourceLoader.exists(path):
			path = "res://assets/sprites/bg_beach_0.png"
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	return img


## Vignette cliquable d'un décor ("" = « Au hasard »).
func _card(id: String) -> Button:
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(THUMB.x + 2 * FRAME, THUMB.y + 2 * FRAME)
	b.focus_mode = Control.FOCUS_ALL
	for style: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		b.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	var inner: Rect2 = Rect2(FRAME, FRAME, THUMB.x, THUMB.y)
	if id == "":
		var sea: ColorRect = ColorRect.new()
		sea.color = UiKit.C_SEA
		sea.position = inner.position
		sea.size = inner.size
		sea.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sea)
		var q: Label = UiKit.label("?\nAu hasard", 8, UiKit.C_GOLD)
		q.position = inner.position
		q.size = inner.size
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(q)
	else:
		# Recadrage central au format de la vignette, puis réduction lissée.
		var img: Image = _stage_image(id)
		var crop_w: int = mini(img.get_width(), img.get_height() * THUMB.x / THUMB.y)
		img = img.get_region(Rect2i((img.get_width() - crop_w) / 2, 0, crop_w, img.get_height()))
		img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
		var thumb: TextureRect = TextureRect.new()
		thumb.texture = ImageTexture.create_from_image(img)
		thumb.position = inner.position
		thumb.size = inner.size
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(thumb)
	b.draw.connect(func() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, b.size)
		if b.has_focus():
			b.draw_rect(r, UiKit.C_GOLD)
		else:
			b.draw_rect(r.grow(-1), UiKit.C_OUTLINE))
	b.focus_entered.connect(func() -> void:
		AudioManager.sfx(&"ui_move")
		_show(id)
		b.queue_redraw())
	b.focus_exited.connect(b.queue_redraw)
	b.mouse_entered.connect(b.grab_focus)
	b.pressed.connect(func() -> void:
		AudioManager.sfx(&"ui_ok")
		_pick(id))
	_cards.append(b)
	return b


## Grand aperçu du décor sélectionné derrière la grille + son nom.
func _show(id: String) -> void:
	_name.text = "Au hasard !" if id == "" else str(Roster.STAGE_NAMES.get(id, id))
	_bg.visible = id != ""
	if id == "":
		return
	_bg.texture = ImageTexture.create_from_image(_stage_image(id))
	var view: Vector2 = get_viewport_rect().size
	var f: float = maxf(view.x / _bg.texture.get_width(), view.y / _bg.texture.get_height())
	_bg.scale = Vector2(f, f)
	_bg.position = Vector2(roundf((view.x - _bg.texture.get_width() * f) * 0.5), 0)


func _pick(id: String) -> void:
	# Garde anti « tap fantôme » : le 2e tap qui validait l'adversaire ne
	# doit pas choisir aussi le décor sous le doigt.
	if Time.get_ticks_msec() - _opened_ms < GHOST_TAP_MS:
		return
	if id == "":
		# Au hasard : jamais le Sommet du Phare (dernier, réservé au boss).
		id = Roster.STAGES[randi() % (Roster.STAGES.size() - 1)]
	if str(_params.get("mode", "")) == "online":
		# Chacun propose ; le serveur tire entre les deux propositions (§3.4).
		Api.call_api(HTTPClient.METHOD_POST, "/match/stage",
			{"match_id": int(OnlineMode.current.get("match_id", 0)), "stage": id},
			func(_ok: bool, _c: int, _d: Variant) -> void: SceneRouter.goto(&"online_connect"))
		return
	var params: Dictionary = _params.duplicate()
	params["stage"] = id
	params["ai"] = [0, int(_params.get("ai_level", 0))]
	params["mode"] = "quick" if _quick else "versus"
	params["return_to"] = "main_menu"
	params["on_end"] = VersusMode.on_fight_end
	if _quick:
		params["rounds"] = 3
		InputHub.set_solo()
	VersusMode.last = params
	SceneRouter.goto(&"versus_splash", params)


## Retour à l'étape précédente : combat rapide → choix de l'adversaire
## (sélections conservées), versus → sélection, en ligne → quitter.
func _back() -> void:
	if str(_params.get("mode", "")) == "online":
		OnlineMode.leave()
	elif _quick:
		SceneRouter.goto(&"fighter_select", {"mode": "quick", "step": 1, "sel1": _params.get("sel1", ""),
			"cc1": _params.get("cc1", 0), "sel2": _params.get("sel2", "?"), "cc2": _params.get("cc2", 0)})
	else:
		SceneRouter.goto(&"fighter_select", {"mode": "versus"})


## Flèches / manette / Entrée / Échap : focus natif des boutons (actions ui_*).
## Les touches de combat de J1 (ZQSD/WASD, poing, pied) marchent aussi, comme
## dans la sélection des combattants.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"p1_kick"):
		get_viewport().set_input_as_handled()
		_back()
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus == null:
		return
	if event.is_action_pressed(&"p1_punch") and focus is Button:
		get_viewport().set_input_as_handled()
		(focus as Button).pressed.emit()
		return
	var sides: Dictionary = {&"p1_left": SIDE_LEFT, &"p1_right": SIDE_RIGHT, &"p1_up": SIDE_TOP, &"p1_down": SIDE_BOTTOM}
	for action: StringName in sides:
		if event.is_action_pressed(action):
			var next: Control = focus.find_valid_focus_neighbor(sides[action])
			if next != null:
				get_viewport().set_input_as_handled()
				next.grab_focus()
			return
