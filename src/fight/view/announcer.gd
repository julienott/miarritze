class_name Announcer
extends Control
## Annonces plein écran : « ROUND 1 », « BORROKA ! », « PLOUF ! »,
## « BUKATU ! », « PARFAIT ! »… Grandes lettres qui arrivent en rebond.

const C_RED: Color = Color8(206, 52, 52)
const C_GOLD: Color = Color8(244, 198, 62)
const C_OUTLINE: Color = Color8(58, 38, 52)

var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Au-dessus des têtes : tiers haut de l'écran.
	_label.offset_bottom = -110
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 24)
	_label.add_theme_color_override(&"font_color", C_RED)
	_label.add_theme_color_override(&"font_outline_color", C_GOLD)
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.add_theme_color_override(&"font_shadow_color", C_OUTLINE)
	_label.add_theme_constant_override(&"shadow_offset_x", 2)
	_label.add_theme_constant_override(&"shadow_offset_y", 2)
	_label.visible = false
	add_child(_label)


func say(text: String, duration: float = 1.0, color: Color = C_RED, size_px: int = 24) -> void:
	_label.text = text
	_label.add_theme_color_override(&"font_color", color)
	_label.add_theme_font_size_override(&"font_size", size_px)
	_label.visible = true
	_label.pivot_offset = size * 0.5
	_label.scale = Vector2(2.2, 2.2)
	_label.rotation = -0.12
	var tween: Tween = create_tween()
	tween.tween_property(_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_label, "rotation", 0.0, 0.18)
	tween.tween_interval(duration)
	tween.tween_callback(func() -> void: _label.visible = false)


## Un Control sous un CanvasLayer n'a pas de parent dimensionné : on
## recopie la taille visible du viewport (largeur variable en paysage).
func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
