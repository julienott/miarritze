extends Control
## Écran versus (SPEC §10.5) : les deux combattants face à face, « VS »
## qui claque, nom du stage. 2 s, sans appui.

const DURATION: float = 2.0

var _params: Dictionary = {}


func _ready() -> void:
	_params = SceneRouter.params.duplicate()
	UiKit.backdrop(self, "bg_menu", 0.6)
	var w: float = get_viewport_rect().size.x
	for p: int in 2:
		var id: String = str(_params.get("p%d" % (p + 1), "louis"))
		var view: FighterView = UiKit.fighter_preview(id, int(_params.get("c%d" % (p + 1), 0)), "intro", 1 if p == 0 else -1)
		view.position = Vector2(w * (0.25 if p == 0 else 0.75), 176)
		add_child(view)
		var name_label: Label = UiKit.label(Roster.display_name(id).to_upper(), 16, UiKit.C_LINEN)
		name_label.position = Vector2(w * (0.25 if p == 0 else 0.75) - 80, 184)
		name_label.size = Vector2(160, 20)
		add_child(name_label)
	var vs: Label = UiKit.title("VS")
	vs.add_theme_font_size_override(&"font_size", 32)
	vs.set_anchors_preset(Control.PRESET_FULL_RECT)
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.pivot_offset = Vector2(w * 0.5, 108)
	vs.scale = Vector2(3, 3)
	add_child(vs)
	create_tween().tween_property(vs, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var stage: Label = UiKit.label(str(Roster.STAGE_NAMES.get(str(_params.get("stage", "")), "")), 8, UiKit.C_GOLD)
	stage.set_anchors_preset(Control.PRESET_TOP_WIDE)
	stage.position.y = 14
	add_child(stage)
	get_tree().create_timer(DURATION).timeout.connect(_go)


func _go() -> void:
	if str(_params.get("mode", "")) == "versus":
		InputHub.set_versus()
	SceneRouter.goto(&"fight", _params)
