class_name GkUi
extends RefCounted
## Kit d'interface des menus de Gordeka en 1280×720 (1280×720) :
## style cartoon du jeu (aplats vifs, gros contour encre, coins ronds), gros boutons pour les doigts,
## focus doré bien visible au clavier et à la manette, fond de mer. Aucune référence
## aux autoloads (la partie et les tests headless s'en servent) ; la mise en page d'un écran de menu
## (zone sûre, rappel des touches) est dans GkEcran.

const INK: Color = GkDraw.INK
const CREME: Color = Color("fff4dc")
const JAUNE: Color = Color("ffd34a")
const BLEU: Color = Color("4aa3ff")
const ROUGE: Color = Color("ff5a4a")
const VERT: Color = Color("6fe08a")
const GRIS: Color = Color("c9cfd8")
const MER: Color = Color("1f6f9a")
const MER_FONCE: Color = Color("14405e")
const FOCUS: Color = Color("ffd34a")
const RAYON: int = 22
const BORD: int = 4
## Taille de texte des boutons et des libellés courants.
const TEXTE: int = 30

static var _theme: Theme


## Thème de tout le jeu (posé sur la racine par gk_boot) : boutons, cases, curseurs, champs.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.default_font_size = 26
	t.set_stylebox(&"normal", &"Button", _box(CREME))
	t.set_stylebox(&"hover", &"Button", _box(CREME.lerp(JAUNE, 0.35)))
	t.set_stylebox(&"pressed", &"Button", _box(JAUNE.darkened(0.1), 6))
	t.set_stylebox(&"hover_pressed", &"Button", _box(JAUNE.darkened(0.1), 6))
	t.set_stylebox(&"disabled", &"Button", _box(Color("d8d2c4"), 0, Color("8b8f99")))
	t.set_stylebox(&"focus", &"Button", _focus_box())
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
			&"font_hover_pressed_color"]:
		t.set_color(c, &"Button", INK)
	t.set_color(&"font_disabled_color", &"Button", Color("7d818a"))
	t.set_font_size(&"font_size", &"Button", TEXTE)
	t.set_constant(&"h_separation", &"Button", 12)
	# Cases à cocher (on/off) : même bouton, la coche à droite.
	t.set_stylebox(&"normal", &"CheckButton", _box(CREME))
	t.set_stylebox(&"hover", &"CheckButton", _box(CREME.lerp(JAUNE, 0.35)))
	t.set_stylebox(&"pressed", &"CheckButton", _box(CREME))
	t.set_stylebox(&"hover_pressed", &"CheckButton", _box(CREME.lerp(JAUNE, 0.35)))
	t.set_stylebox(&"focus", &"CheckButton", _focus_box())
	t.set_icon(&"checked", &"CheckButton", _interrupteur(true))
	t.set_icon(&"unchecked", &"CheckButton", _interrupteur(false))
	for c: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
			&"font_hover_pressed_color"]:
		t.set_color(c, &"CheckButton", INK)
	# Curseurs : rail épais, grosse poignée ronde.
	var rail: StyleBoxFlat = _box(Color("2a5d7c"), 0, INK, 10)
	rail.content_margin_top = 10
	rail.content_margin_bottom = 10
	t.set_stylebox(&"slider", &"HSlider", rail)
	var plein: StyleBoxFlat = _box(JAUNE, 0, INK, 10)
	plein.content_margin_top = 10
	plein.content_margin_bottom = 10
	t.set_stylebox(&"grabber_area", &"HSlider", plein)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", plein)
	t.set_icon(&"grabber", &"HSlider", _poignee(false))
	t.set_icon(&"grabber_highlight", &"HSlider", _poignee(true))
	t.set_stylebox(&"focus", &"HSlider", _focus_box())
	# Champ de texte (pseudo).
	var champ: StyleBoxFlat = _box(Color.WHITE)
	champ.content_margin_left = 18
	t.set_stylebox(&"normal", &"LineEdit", champ)
	var champ_f: StyleBoxFlat = champ.duplicate()
	champ_f.border_color = FOCUS.darkened(0.15)
	champ_f.set_border_width_all(6)
	t.set_stylebox(&"focus", &"LineEdit", champ_f)
	t.set_color(&"font_color", &"LineEdit", INK)
	t.set_color(&"caret_color", &"LineEdit", INK)
	t.set_color(&"font_placeholder_color", &"LineEdit", Color(INK, 0.4))
	t.set_font_size(&"font_size", &"LineEdit", 36)
	# Libellés : contour encre pour rester lisibles sur la mer.
	t.set_color(&"font_outline_color", &"Label", INK)
	t.set_constant(&"outline_size", &"Label", 8)
	_theme = t
	return t


static func _box(fill: Color, enfonce: int = 0, ink: Color = INK, rayon: int = RAYON) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = ink
	sb.set_border_width_all(BORD)
	# Relief : bord du bas plus épais, qui s'écrase quand on appuie.
	sb.border_width_bottom = BORD + 6 - enfonce
	sb.content_margin_top = 10 + enfonce
	sb.content_margin_bottom = 10
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.set_corner_radius_all(rayon)
	sb.anti_aliasing = true
	sb.corner_detail = 10
	return sb


static func _focus_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = FOCUS
	sb.set_border_width_all(7)
	sb.set_expand_margin_all(7)
	sb.set_corner_radius_all(RAYON + 7)
	sb.anti_aliasing = true
	sb.shadow_color = Color(INK, 0.6)
	sb.shadow_size = 4
	return sb


## Interrupteur dessiné (64×36) : vert à droite = activé.
static func _interrupteur(on: bool) -> ImageTexture:
	var w: int = 72
	var h: int = 40
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fond: Color = VERT.darkened(0.1) if on else Color("9aa1ad")
	var c_rond: Vector2 = Vector2(w - h * 0.5, h * 0.5) if on else Vector2(h * 0.5, h * 0.5)
	for y: int in h:
		for x: int in w:
			var p: Vector2 = Vector2(x + 0.5, y + 0.5)
			# Pilule : distance au segment central.
			var q: Vector2 = Vector2(clampf(p.x, h * 0.5, w - h * 0.5), h * 0.5)
			var d: float = p.distance_to(q)
			var col: Color = Color(0, 0, 0, 0)
			if d <= h * 0.5:
				col = INK
			if d <= h * 0.5 - 3.5:
				col = fond
			var dr: float = p.distance_to(c_rond)
			if dr <= h * 0.5 - 5.0:
				col = INK
			if dr <= h * 0.5 - 8.0:
				col = Color.WHITE
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _poignee(fort: bool) -> ImageTexture:
	var s: int = 44
	var img: Image = Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c: Vector2 = Vector2(s, s) * 0.5
	for y: int in s:
		for x: int in s:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			var col: Color = Color(0, 0, 0, 0)
			if d <= s * 0.5 - 1.0:
				col = INK
			if d <= s * 0.5 - 5.0:
				col = JAUNE if fort else Color.WHITE
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- briques

## Gros bouton avec sons ; `couleur` teinte le fond (sinon crème).
static func bouton(texte: String, action: Callable, taille: Vector2 = Vector2(320, 84),
		couleur: Color = CREME, police: int = TEXTE) -> Button:
	var b: Button = Button.new()
	b.text = texte
	b.custom_minimum_size = taille
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override(&"font_size", police)
	if couleur != CREME:
		teinter(b, couleur)
	b.pressed.connect(action)
	return b


## Fond d'un bouton à une autre couleur (et son survol, son appui).
static func teinter(b: Control, couleur: Color) -> void:
	b.add_theme_stylebox_override(&"normal", _box(couleur))
	b.add_theme_stylebox_override(&"hover", _box(couleur.lightened(0.18)))
	b.add_theme_stylebox_override(&"pressed", _box(couleur.darkened(0.12), 6))
	b.add_theme_stylebox_override(&"hover_pressed", _box(couleur.darkened(0.12), 6))


## Un curseur n'a pas de cadre de focus : son libellé passe en rouge, précédé d'une flèche, tant
## qu'il a le focus (clavier, manette).
static func focus_libelle(ctrl: Control, l: Label) -> void:
	var texte: String = l.text
	var couleur: Color = l.get_theme_color(&"font_color")
	ctrl.focus_entered.connect(func() -> void:
		l.text = "> " + texte
		l.add_theme_color_override(&"font_color", ROUGE.darkened(0.15)))
	ctrl.focus_exited.connect(func() -> void:
		l.text = texte
		l.add_theme_color_override(&"font_color", couleur))


static func label(texte: String, taille: int = TEXTE, couleur: Color = Color.WHITE,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l: Label = Label.new()
	l.text = texte
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", taille)
	l.add_theme_color_override(&"font_color", couleur)
	l.add_theme_color_override(&"font_outline_color", INK)
	l.add_theme_constant_override(&"outline_size", maxi(4, taille / 4))
	return l


## Titre d'écran : grandes lettres jaunes à gros contour.
static func titre(texte: String) -> Label:
	var l: Label = label(texte, 52, JAUNE)
	l.add_theme_constant_override(&"outline_size", 16)
	return l


## Panneau crème arrondi (contenu en colonne).
static func panneau(marge: int = 24) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = _box(Color(CREME, 0.96))
	sb.set_content_margin_all(marge)
	p.add_theme_stylebox_override(&"panel", sb)
	return p


## Liste dans un ScrollContainer : les boutons laissent passer le glissé du doigt
## (MOUSE_FILTER_PASS), sinon on ne peut défiler qu'en partant d'un titre.
static func touch_scroll(list: Control) -> void:
	_pass_buttons(list)
	list.child_entered_tree.connect(_pass_buttons)


static func _pass_buttons(n: Node) -> void:
	if n is BaseButton or n is LineEdit:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	for c: Node in n.get_children():
		_pass_buttons(c)


## Fond des menus : mer en dégradé, vagues qui ondulent doucement, sable en bas.
class Fond extends Control:
	var _t: float = 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		var s: Vector2 = size
		var n: int = 12
		for i: int in n:
			var k: float = float(i) / float(n)
			draw_rect(Rect2(0, s.y * k, s.x, s.y / n + 1.0), GkUi.MER.lerp(GkUi.MER_FONCE, k))
		# Vagues : petits arcs blancs qui dérivent.
		for row: int in 7:
			var y: float = s.y * (0.1 + row * 0.12)
			var off: float = fmod(_t * (14.0 + row * 3.0) + row * 77.0, 160.0)
			var x: float = -160.0 + off
			while x < s.x + 40.0:
				var c: Vector2 = Vector2(x + (row % 2) * 80.0, y + sin(_t * 1.2 + x * 0.01) * 4.0)
				draw_arc(c, 22.0, PI * 1.15, PI * 1.85, 10, Color(1, 1, 1, 0.13), 4.0, true)
				x += 160.0
		# Sable.
		var pts: PackedVector2Array = PackedVector2Array()
		var base: float = s.y - 46.0
		for i: int in 33:
			var x2: float = s.x * float(i) / 32.0
			pts.append(Vector2(x2, base + sin(x2 * 0.012 + _t * 0.6) * 6.0))
		pts.append(Vector2(s.x, s.y))
		pts.append(Vector2(0, s.y))
		draw_colored_polygon(pts, Color("f2d49b"))
		var ecume: PackedVector2Array = pts.slice(0, 33)
		draw_polyline(ecume, Color(1, 1, 1, 0.7), 5.0, true)
