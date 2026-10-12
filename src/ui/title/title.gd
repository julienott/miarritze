extends Control
## Écran titre (provisoire Phase 0, DA finale en Phase 5) : baie de
## Biarritz, logo, « Appuie pour commencer ».

@onready var _press_label: Label = $PressLabel

var _blink: float = 0.0


func _process(delta: float) -> void:
	_blink += delta
	_press_label.visible = fmod(_blink, 1.0) < 0.7


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventKey and (event as InputEventKey).pressed) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
	if pressed:
		_on_start_pressed()


func _on_start_pressed() -> void:
	# Phase 0 : pas encore de menu ; les écrans arrivent aux phases suivantes.
	if SceneRouter.has_screen(&"main_menu"):
		SceneRouter.goto(&"main_menu")
