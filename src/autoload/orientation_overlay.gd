extends CanvasLayer
## Overlay global « Tourne ton appareil » : plein écran dès que le viewport
## passe en portrait, met le jeu en pause, disparaît au retour en paysage.

var _dim: ColorRect
var _message: Label


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.10, 0.16, 0.96)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)
	_message = Label.new()
	_message.text = "Tourne ton appareil\n\n(le jeu est en pause)"
	_message.add_theme_font_size_override(&"font_size", 30)
	_message.add_theme_color_override(&"font_color", Color(0.97, 0.95, 0.89))
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message.visible = false
	add_child(_message)
	get_viewport().size_changed.connect(_update)
	_update()


func _update() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var portrait: bool = size.y > size.x
	_dim.visible = portrait
	_message.visible = portrait
	get_tree().paused = portrait
