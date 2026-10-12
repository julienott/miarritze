extends Control
## Choix de la map (versus) : liste des stages + « Aléatoire » (lauburu).

var _params: Dictionary = {}


func _ready() -> void:
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
	grid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	grid.position = Vector2(-186, 34)
	add_child(grid)
	var first: Button = null
	for id: String in Roster.STAGES:
		var b: Button = UiKit.button(str(Roster.STAGE_NAMES.get(id, id)), _pick.bind(id), 120)
		grid.add_child(b)
		if first == null:
			first = b
	var rnd: Button = UiKit.button("Aléatoire", _pick.bind(""), 120)
	grid.add_child(rnd)
	first.grab_focus.call_deferred()
	var rounds: Label = UiKit.label("Meilleur des 3 rounds", 8, UiKit.C_GOLD)
	rounds.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	rounds.position.y = -16
	add_child(rounds)


func _pick(id: String) -> void:
	if id == "":
		id = Roster.STAGES[randi() % (Roster.STAGES.size() - 1)]
	var params: Dictionary = _params.duplicate()
	params["stage"] = id
	params["ai"] = [0, 0]
	params["mode"] = "versus"
	params["on_end"] = VersusMode.on_fight_end
	VersusMode.last = params
	SceneRouter.goto(&"versus_splash", params)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		SceneRouter.goto(&"fighter_select", {"mode": "versus"})
