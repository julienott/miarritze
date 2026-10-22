class_name BkPodium
extends Control
## Podium de fin de partie (GDD-BLACKOUT.md) : cumul des points, or, argent et bronze sur leurs
## marches avec les avatars animés (pose de victoire), les autres en dessous, puis « Retour à
## l'accueil ». Les emotes restent permises (bulles des avatars) ; le joueur local fait son emote
## favorite en arrivant.

const OR: Color = Color("ffd34a")
const ARGENT: Color = Color("cfd6df")
const BRONZE: Color = Color("d08a4a")

var game: BkGame
var _avatars: Dictionary = {}     # id d'acteur → BkAvatar
var _bouton: Button
var _t: float = 0.0
var _rangs: Array[BkActor] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rangs = classement(game.actors)
	var titre: Label = BkUi.titre("Podium")
	titre.add_theme_font_size_override(&"font_size", 64)
	titre.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	titre.offset_top = 16
	titre.offset_bottom = 96
	add_child(titre)
	for i: int in mini(3, _rangs.size()):
		var a: BkActor = _rangs[i]
		var av: BkAvatar = BkAvatar.cree(a.character, a.color, 250.0 if i == 0 else 210.0)
		av.pose("victory")
		add_child(av)
		_avatars[a.id] = av
	_bouton = BkUi.bouton("Retour à l'accueil", func() -> void: game.go_menu(), Vector2(380, 80), BkUi.JAUNE)
	add_child(_bouton)
	_bouton.grab_focus.call_deferred()


## Classement : points décroissants ; à égalité, l'ordre des joueurs.
static func classement(actors: Array[BkActor]) -> Array[BkActor]:
	var rows: Array[BkActor] = actors.duplicate()
	rows.sort_custom(func(a: BkActor, b: BkActor) -> bool:
		return a.score > b.score or (a.score == b.score and a.id < b.id))
	return rows


## Marche de la place `i` (0 = or) : rectangle à l'écran.
func marche(i: int) -> Rect2:
	var s: Vector2 = size
	var xs: Array[float] = [0.5, 0.27, 0.73]
	var hs: Array[float] = [215.0, 165.0, 128.0]
	var w: float = 250.0
	var base: float = s.y - 118.0
	return Rect2(s.x * xs[i] - w * 0.5, base - hs[i], w, hs[i])


func _process(dt: float) -> void:
	_t += dt
	for i: int in mini(3, _rangs.size()):
		var a: BkActor = _rangs[i]
		var av: BkAvatar = _avatars[a.id]
		var r: Rect2 = marche(i)
		# Arrivée en sautant sur la marche, l'une après l'autre (bronze, argent, or).
		var k: float = clampf((_t - 0.25 * float(2 - i)) / 0.4, 0.0, 1.0)
		var saut: float = sin(k * PI) * 60.0 + (1.0 - k) * 300.0
		av.size = av.custom_minimum_size
		av.position = Vector2(r.position.x + r.size.x * 0.5 - av.size.x * 0.5, r.position.y - av.size.y + 6.0 - saut)
		av.modulate.a = k
		# L'emote des persos du podium (joueur local ou IA) passe par son avatar.
		if a.emote_t > 0.0 and av.actor != null and av.actor.emote_t <= 0.0 and a.emote >= 0:
			av.emote(a.emote)
	_bouton.position = Vector2(size.x * 0.5 - _bouton.size.x * 0.5, size.y - 98.0)
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.06, 0.13, 0.93))
	# Confettis.
	for i: int in 60:
		var x: float = fmod(float(i) * 97.3 + _t * (20.0 + i % 7 * 6.0), s.x)
		var y: float = fmod(float(i) * 53.1 + _t * (60.0 + i % 5 * 15.0), s.y)
		draw_rect(Rect2(x, y, 10, 6).abs(), BkRules.color(i % 12))
	var font: Font = ThemeDB.fallback_font
	var medailles: Array[Color] = [OR, ARGENT, BRONZE]
	for i: int in mini(3, _rangs.size()):
		var r: Rect2 = marche(i)
		BkDraw.rbox(self, r, medailles[i].darkened(0.15), 14.0, 5.0)
		BkDraw.ellipse(self, r.position + Vector2(r.size.x * 0.5, 36), 27, 27, medailles[i], 4.0)
		_texte(font, r.position + Vector2(r.size.x * 0.5, 50), str(i + 1), 36, BkUi.INK)
		var a: BkActor = _rangs[i]
		_texte(font, r.position + Vector2(r.size.x * 0.5, 92), a.display_name, 26, Color.WHITE, true)
		_texte(font, r.position + Vector2(r.size.x * 0.5, 117), "%d pts" % a.score, 20,
			Color.WHITE, true)
	# Les suivants, en colonne à droite.
	for i: int in range(3, _rangs.size()):
		var y: float = 190.0 + 40.0 * float(i - 3)
		draw_circle(Vector2(s.x - 228.0, y - 8.0), 10.0, _rangs[i].color)
		draw_string_outline(font, Vector2(s.x - 210.0, y), "%d. %s  %d" % [i + 1, _rangs[i].display_name, _rangs[i].score],
			HORIZONTAL_ALIGNMENT_LEFT, 200, 20, 6, BkUi.INK)
		draw_string(font, Vector2(s.x - 210.0, y), "%d. %s  %d" % [i + 1, _rangs[i].display_name, _rangs[i].score],
			HORIZONTAL_ALIGNMENT_LEFT, 200, 20, Color.WHITE)


func _texte(font: Font, at: Vector2, texte: String, taille: int, col: Color, contour: bool = false) -> void:
	var p: Vector2 = Vector2(at.x - 600, at.y)
	if contour:
		draw_string_outline(font, p, texte, HORIZONTAL_ALIGNMENT_CENTER, 1200, taille, 8, BkUi.INK)
	draw_string(font, p, texte, HORIZONTAL_ALIGNMENT_CENTER, 1200, taille, col)
