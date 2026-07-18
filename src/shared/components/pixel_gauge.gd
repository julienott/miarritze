class_name PixelGauge
extends Node2D
## Jauge pixel art du thème : fond sombre, bordure crème 3 px, graduations,
## remplissage coloré cranté sur la grille de 4 px. Horizontale ou verticale.

const PX: float = 4.0
const BORDER_COLOR: Color = Color(0.97, 0.945, 0.89)
const BG_COLOR: Color = Color(0.145, 0.095, 0.13, 0.92)

@export var size: Vector2 = Vector2(600.0, 40.0)
@export var vertical: bool = false
@export var fill_color: Color = Color(0.3, 0.85, 0.3)
## 0..1
@export var value: float = 0.0
## Position d'un trait-objectif (0..1, -1 = aucun)
@export var target_mark: float = -1.0
@export var label_text: String = ""

var _label: Label = null


func _ready() -> void:
	if label_text != "":
		_label = Label.new()
		_label.text = label_text
		_label.add_theme_font_size_override(&"font_size", 14)
		_label.add_theme_color_override(&"font_color", BORDER_COLOR)
		_label.position = Vector2(0.0, -26.0) if not vertical else Vector2(-8.0, size.y + 8.0)
		add_child(_label)


func _process(_delta: float) -> void:
	queue_redraw()


func _q(v: float) -> float:
	return floorf(v / PX) * PX


func _draw() -> void:
	# fond + bordure double (crème puis sombre)
	draw_rect(Rect2(-PX, -PX, size.x + PX * 2.0, size.y + PX * 2.0), BORDER_COLOR)
	draw_rect(Rect2(0.0, 0.0, size.x, size.y), BG_COLOR)
	# remplissage cranté
	var v: float = clampf(value, 0.0, 1.0)
	if v > 0.0:
		if vertical:
			var h: float = _q(size.y * v)
			draw_rect(Rect2(PX, size.y - h + PX * 0.0, size.x - PX * 2.0, maxf(h - PX, PX)), fill_color)
		else:
			draw_rect(Rect2(PX, PX, maxf(_q(size.x * v) - PX * 2.0, PX), size.y - PX * 2.0), fill_color)
	# graduations tous les 25 %
	for i: int in [1, 2, 3]:
		var t: float = i / 4.0
		if vertical:
			draw_rect(Rect2(0.0, _q(size.y * t), PX * 1.5, PX), BORDER_COLOR)
		else:
			draw_rect(Rect2(_q(size.x * t), size.y - PX * 1.5, PX, PX * 1.5), BORDER_COLOR)
	# trait-objectif (jaune)
	if target_mark >= 0.0:
		var gold: Color = Color(0.95, 0.78, 0.24)
		if vertical:
			draw_rect(Rect2(-PX, _q(size.y * (1.0 - target_mark)), size.x + PX * 2.0, PX), gold)
		else:
			draw_rect(Rect2(_q(size.x * target_mark), -PX, PX, size.y + PX * 2.0), gold)
