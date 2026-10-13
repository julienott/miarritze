extends Control
## Écran titre (provisoire Phase 0, DA finale en Phase 5) : baie de
## Biarritz, logo, « Appuie pour commencer ».

@onready var _press_label: Label = $PressLabel

var _blink: float = 0.0
var _started: bool = false


func _ready() -> void:
	# Le Control racine ne doit pas capter les touchers : sinon la GUI les
	# consomme et « Appuie pour commencer » ne réagit pas sur iPhone.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$TitleLabel.visible = false
	$SubLabel.visible = false
	var logo: LogoView = LogoView.new()
	logo.position = Vector2(get_viewport_rect().size.x * 0.5, 62)
	add_child(logo)
	get_viewport().size_changed.connect(func() -> void:
		logo.position.x = get_viewport_rect().size.x * 0.5)
	AudioManager.play_music(&"title")


func _process(delta: float) -> void:
	_blink += delta
	_press_label.visible = fmod(_blink, 1.0) < 0.7


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventKey and (event as InputEventKey).pressed) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
	if pressed and not _started:
		_started = true
		_on_start_pressed()


func _on_start_pressed() -> void:
	if SceneRouter.has_screen(&"profile_select"):
		SceneRouter.goto(&"profile_select")
		return
	# Phase 1 : versus local direct au clavier (J1 WASD+JKL, J2 flèches+Num).
	InputHub.set_versus()
	SceneRouter.goto(&"fight", {"p1": "louis", "p2": "maia", "stage": "grande_plage"})
