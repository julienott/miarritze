class_name UiKit
extends RefCounted
## Petits constructeurs d'interface communs à tous les écrans (384×216).
## Cibles tactiles généreuses : boutons d'au moins 24 px logiques de haut
## (≈ 44 pt sur iPhone en paysage).

const C_OUTLINE: Color = Color8(58, 38, 52)
const C_LINEN: Color = Color8(247, 241, 227)
const C_RED: Color = Color8(206, 52, 52)
const C_GOLD: Color = Color8(244, 198, 62)
const C_GREEN: Color = Color8(52, 128, 72)
const C_NAVY: Color = Color8(34, 44, 82)
const C_WOOD: Color = Color8(150, 104, 62)
const C_SEA: Color = Color8(32, 120, 154)
const MIN_BUTTON_H: float = 24.0


static func button(text: String, on_pressed: Callable, min_w: float = 120.0) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, MIN_BUTTON_H)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void:
		AudioManager.sfx(&"ui_ok")
		on_pressed.call())
	b.focus_entered.connect(func() -> void: AudioManager.sfx(&"ui_move"))
	return b


static func label(text: String, size: int = 8, color: Color = C_LINEN,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", C_OUTLINE)
	l.add_theme_constant_override(&"outline_size", 3 if size <= 8 else 5)
	return l


const EUSKAL: String = "res://assets/fonts/euskal_outline.fnt"


## Titre de page : lettrage basque (euskal letra, police bitmap 16 px).
static func title(text: String, color: Color = C_RED) -> Label:
	var l: Label = Label.new()
	l.text = text.to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ResourceLoader.exists(EUSKAL):
		l.add_theme_font_override(&"font", load(EUSKAL))
		l.add_theme_font_size_override(&"font_size", 16)
		l.add_theme_color_override(&"font_color", color.lightened(0.15))
		l.add_theme_constant_override(&"shadow_offset_x", 0)
		l.add_theme_constant_override(&"shadow_offset_y", 1)
	else:
		l.add_theme_font_size_override(&"font_size", 16)
		l.add_theme_color_override(&"font_color", color)
	return l


## Fond animé d'un écran (décor i2i existant, plein écran « cover »).
static func backdrop(parent: Node, bg_name: String = "bg_menu", dim: float = 0.35) -> void:
	var bg: PixelBg = PixelBg.new()
	bg.bg_name = bg_name
	parent.add_child(bg)
	if dim > 0.0:
		var shade: ColorRect = ColorRect.new()
		shade.color = Color(0.09, 0.06, 0.1, dim)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(shade)


## Colonne de boutons centrée ; le premier reçoit le focus (clavier/manette).
static func menu_column(parent: Control, buttons: Array, top: float = 60.0) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-70, top)
	box.custom_minimum_size = Vector2(140, 0)
	parent.add_child(box)
	for b: Variant in buttons:
		box.add_child(b as Control)
	if not buttons.is_empty():
		(buttons[0] as Control).grab_focus.call_deferred()
	return box


## Combattant animé pour les menus (anim en boucle), costume appliqué.
static func fighter_preview(id: String, costume: int = 0, anim: String = "idle", facing: int = 1) -> FighterView:
	var view: FighterView = FighterView.new()
	view.setup(FighterDb.get_def(id), costume)
	view.play_preview(anim, facing)
	return view


## Grille de boutons sur deux colonnes (menus longs, écran de 216 px).
static func menu_grid(parent: Control, buttons: Array, top: float = 60.0) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 5)
	grid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	grid.position = Vector2(-146, top)
	parent.add_child(grid)
	for b: Variant in buttons:
		(b as Control).custom_minimum_size.x = 140
		grid.add_child(b as Control)
	if not buttons.is_empty():
		(buttons[0] as Control).grab_focus.call_deferred()
	return grid
