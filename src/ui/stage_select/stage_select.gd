extends Control
## Choix de la map (versus) : liste des stages + « Aléatoire » (lauburu).

var _params: Dictionary = {}


func _ready() -> void:
	AudioManager.play_music(&"select")
	_params = SceneRouter.params.duplicate()
	UiKit.backdrop(self, "bg_hub", 0.5)
	var head: Label = UiKit.title("CHOIX DE LA MAP")
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 6
	add_child(head)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	grid.position = Vector2(0, 34)
	add_child(grid)
	# Centrage sur la largeur réelle (iPhone 19,5:9 plus large que 384).
	var center: Callable = func() -> void:
		# Écran étroit (iPhone SE, 16:9) : 3 colonnes ne tiennent pas → 2.
		grid.columns = 3
		grid.reset_size()
		if grid.get_combined_minimum_size().x > get_viewport_rect().size.x - 8:
			grid.columns = 2
		grid.reset_size()
		grid.position.x = roundf((get_viewport_rect().size.x - grid.get_combined_minimum_size().x) * 0.5)
	get_viewport().size_changed.connect(center)
	center.call_deferred()
	var first: Button = null
	for id: String in Roster.STAGES:
		var b: Button = UiKit.button(str(Roster.STAGE_NAMES.get(id, id)), _pick.bind(id), 120)
		grid.add_child(b)
		if first == null:
			first = b
	var rnd: Button = UiKit.button("Aléatoire", _pick.bind(""), 120)
	grid.add_child(rnd)
	first.grab_focus.call_deferred()
	if str(_params.get("mode", "")) == "online" and not OnlineMode.qa.is_empty():
		get_tree().create_timer(0.8).timeout.connect(_pick.bind("grande_plage"))
	var rounds: Label = UiKit.label("Meilleur des 3 rounds", 8, UiKit.C_GOLD)
	rounds.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	rounds.position.y = -16
	add_child(rounds)


func _pick(id: String) -> void:
	if id == "":
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
	params["mode"] = "versus"
	params["return_to"] = "main_menu"
	params["on_end"] = VersusMode.on_fight_end
	VersusMode.last = params
	SceneRouter.goto(&"versus_splash", params)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if str(_params.get("mode", "")) == "online":
			OnlineMode.leave()
		else:
			SceneRouter.goto(&"fighter_select", {"mode": "versus"})
