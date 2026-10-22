class_name BkVersus
extends Control
## Écran Versus (GDD-BLACKOUT.md), entre le tirage et la cachette : à gauche le chasseur en grand
## (avatar animé, pseudo, icône de détection), à droite les chassés (avatar, pseudo, icône de
## piège), grand « VS » au centre qui arrive avec une secousse, compte à rebours
## 5 → 1 et son de tension généré ici (grondement qui monte, un coup de tambour par seconde).
## En attendant les icônes par perso (§4.2), une onde (détection) et une mâchoire (piège) génériques.

const ROUGE: Color = Color("e8392c")
## Largeur d'une case de chassé (px) : 4 colonnes tiennent dans la moitié droite.
const CASE_L: float = 130.0
const BLEU: Color = Color("2f7fd8")
## Son de tension : fréquence d'échantillonnage, grondement (Hz, de → à), coup de tambour.
const SON_HZ: int = 22050
const GRONDE_DE: float = 55.0
const GRONDE_A: float = 110.0
const TAMBOUR_HZ: float = 70.0
const TAMBOUR_S: float = 0.35

var game: BkGame
var duree: float = 5.0
var _t: float = 0.0
var _vs: Label
var _compte: Label
var _son: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h: BkActor = game.hunter
	# Le chasseur, à gauche.
	var gauche: VBoxContainer = VBoxContainer.new()
	gauche.alignment = BoxContainer.ALIGNMENT_CENTER
	gauche.add_theme_constant_override(&"separation", 2)
	gauche.anchor_left = 0.03
	gauche.anchor_right = 0.4
	gauche.anchor_top = 0.08
	gauche.anchor_bottom = 0.95
	add_child(gauche)
	gauche.add_child(_label("CHASSEUR", 44, Color.WHITE))
	var av: BkAvatar = BkAvatar.cree(h.character, 380)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gauche.add_child(av)
	var ligne: HBoxContainer = HBoxContainer.new()
	ligne.alignment = BoxContainer.ALIGNMENT_CENTER
	ligne.add_theme_constant_override(&"separation", 14)
	gauche.add_child(ligne)
	ligne.add_child(Icone.cree("detection", 58))
	ligne.add_child(_label(h.display_name, 44, Color.WHITE))
	# Les chassés, à droite (grille de 4 colonnes au plus).
	var droite: VBoxContainer = VBoxContainer.new()
	droite.alignment = BoxContainer.ALIGNMENT_CENTER
	droite.add_theme_constant_override(&"separation", 8)
	droite.anchor_left = 0.555
	droite.anchor_right = 0.99
	droite.anchor_top = 0.06
	droite.anchor_bottom = 0.95
	add_child(droite)
	droite.add_child(_label("CHASSÉS", 40, Color.WHITE))
	var chasses: Array[BkActor] = []
	for a: BkActor in game.actors:
		if a != h:
			chasses.append(a)
	var grille: GridContainer = GridContainer.new()
	grille.columns = clampi(int(ceil(chasses.size() / 2.0)), 1, 4)
	grille.add_theme_constant_override(&"h_separation", 10)
	grille.add_theme_constant_override(&"v_separation", 6)
	grille.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	droite.add_child(grille)
	var hauteur: float = 170.0 if chasses.size() <= 4 else 150.0
	for a: BkActor in chasses:
		# Case de taille fixe : l'avatar et son coup posé à ses pieds, le pseudo dessous (en jaune pour
		# le joueur local). Aucune couleur de joueur (GDD §7.1).
		var c: VBoxContainer = VBoxContainer.new()
		c.add_theme_constant_override(&"separation", 0)
		c.custom_minimum_size = Vector2(CASE_L, 0)
		var petit: BkAvatar = BkAvatar.cree(a.character, hauteur)
		petit.regard_gauche = true
		petit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		c.add_child(petit)
		var pied: Control = Control.new()
		pied.custom_minimum_size = Vector2(CASE_L, 0)
		c.add_child(pied)
		var piege: Icone = Icone.cree("piege", 34)
		piege.position = Vector2(CASE_L * 0.5 + 22.0, -40.0)
		piege.size = Vector2(34, 34)
		pied.add_child(piege)
		var nom: Label = _label(a.display_name.trim_suffix(" (IA)"), 22, BkUi.JAUNE if a == game.local else Color.WHITE)
		nom.clip_text = true
		nom.custom_minimum_size = Vector2(CASE_L, 30)
		c.add_child(nom)
		grille.add_child(c)
	# « VS » et le compte à rebours, au centre.
	_vs = _label("VS", 150, BkUi.JAUNE)
	_vs.add_theme_constant_override(&"outline_size", 28)
	_vs.set_anchors_preset(Control.PRESET_CENTER)
	_vs.size = Vector2(300, 200)
	_vs.pivot_offset = _vs.size * 0.5
	add_child(_vs)
	_compte = _label("", 70, Color.WHITE)
	_compte.size = Vector2(200, 100)
	add_child(_compte)
	var titre: Label = _label("Tu es le CHASSEUR !" if game.local == h else "Cache-toi bien !", 34, Color.WHITE)
	titre.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	titre.offset_top = 6
	titre.offset_bottom = 50
	add_child(titre)
	_son = AudioStreamPlayer.new()
	_son.bus = &"SFX"
	_son.stream = son_tension(duree)
	add_child(_son)
	if DisplayServer.get_name() != "headless":
		_son.play()


func _label(texte: String, taille: int, couleur: Color) -> Label:
	var l: Label = BkUi.label(texte, taille, couleur)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(dt: float) -> void:
	_t += dt
	var s: Vector2 = size
	# « VS » : arrive en grand puis se pose, secoué ; chaque seconde, une petite secousse de plus.
	var entree: float = clampf(_t / 0.35, 0.0, 1.0)
	var sec: float = fmod(_t, 1.0)
	var choc: float = (1.0 - entree) * 18.0 + maxf(0.0, 1.0 - sec / 0.25) * 6.0
	_vs.scale = Vector2.ONE * (2.2 - 1.2 * (1.0 - pow(1.0 - entree, 3.0))) * (1.0 + maxf(0.0, 0.08 - sec * 0.3))
	_vs.position = s * Vector2(0.47, 0.45) - _vs.size * 0.5 \
		+ Vector2(sin(_t * 71.0), cos(_t * 53.0)) * choc
	var n: int = clampi(ceili(duree - _t), 1, 5)
	_compte.text = str(n)
	_compte.position = s * Vector2(0.47, 0.66) - _compte.size * 0.5
	_compte.add_theme_color_override(&"font_color", Color.WHITE.lerp(BkUi.ROUGE, 1.0 - float(n) / 5.0))
	queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.06, 0.12, 0.94))
	# Deux moitiés en biais : rouge du chasseur, bleu des chassés.
	var k: float = clampf(_t / 0.3, 0.0, 1.0)
	var mx: float = s.x * 0.48
	if k > 0.02:
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2((mx + 60.0) * k, 0),
			Vector2((mx - 60.0) * k, s.y), Vector2(0, s.y)]), Color(ROUGE, 0.85))
		draw_colored_polygon(PackedVector2Array([Vector2(s.x - (s.x - mx - 60.0) * k, 0), Vector2(s.x, 0),
			Vector2(s.x, s.y), Vector2(s.x - (s.x - mx + 60.0) * k, s.y)]), Color(BLEU, 0.85))
	# Rayons qui tournent derrière le VS.
	var c: Vector2 = s * Vector2(0.48, 0.45)
	for i: int in 12:
		var a: float = _t * 0.6 + TAU * float(i) / 12.0
		draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - 0.08) * 900.0,
			c + Vector2.from_angle(a + 0.08) * 900.0]), Color(1, 1, 1, 0.05))
	draw_line(Vector2(mx + 60, 0), Vector2(mx - 60, s.y), BkUi.INK, 10.0, true)


## Son de tension : grondement grave qui monte et grossit, avec un coup de tambour à chaque seconde.
static func son_tension(secondes: float) -> AudioStreamWAV:
	var n: int = int(SON_HZ * secondes)
	var data: PackedByteArray = PackedByteArray()
	data.resize(n * 2)
	var phase: float = 0.0
	var phase_t: float = 0.0
	for i: int in n:
		var t: float = float(i) / SON_HZ
		var k: float = t / secondes
		phase += TAU * lerpf(GRONDE_DE, GRONDE_A, k * k) / SON_HZ
		var gronde: float = (sin(phase) + 0.45 * sin(phase * 2.0) + 0.2 * sin(phase * 3.01)) * lerpf(0.12, 0.32, k)
		var tt: float = fmod(t, 1.0)
		var tambour: float = 0.0
		if tt < TAMBOUR_S:
			phase_t += TAU * TAMBOUR_HZ * (1.0 + 1.5 * (1.0 - tt / TAMBOUR_S)) / SON_HZ
			tambour = sin(phase_t) * pow(1.0 - tt / TAMBOUR_S, 2.5) * 0.6
		else:
			phase_t = 0.0
		var fin: float = clampf((secondes - t) / 0.15, 0.0, 1.0)
		var v: int = int(clampf((gronde + tambour) * fin, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SON_HZ
	s.data = data
	return s


## Petites icônes rondes dessinées : « detection » (onde), « piege » (mâchoire), en attendant les
## icônes des coups spéciaux (§4).
class Icone extends Control:
	var genre: String = "piege"

	static func cree(p_genre: String, taille: float) -> Icone:
		var i: Icone = Icone.new()
		i.genre = p_genre
		i.custom_minimum_size = Vector2(taille, taille)
		i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		i.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return i

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 2.0
		BkDraw.ellipse(self, c, r, r, Color.WHITE, 3.0)
		if genre == "detection":
			# Onde : point central et deux arcs.
			BkDraw.ellipse(self, c, r * 0.18, r * 0.18, BkVersus.ROUGE)
			for k: float in [0.45, 0.72]:
				draw_arc(c, r * k, -PI * 0.3, PI * 0.3, 12, BkVersus.ROUGE, r * 0.12, true)
				draw_arc(c, r * k, PI * 0.7, PI * 1.3, 12, BkVersus.ROUGE, r * 0.12, true)
		else:
			# Piège : mâchoire à dents.
			var col: Color = Color("4a5263")
			draw_arc(c, r * 0.55, PI * 0.1, PI * 0.9, 12, col, r * 0.16, true)
			draw_arc(c, r * 0.55, PI * 1.1, PI * 1.9, 12, col, r * 0.16, true)
			for i: int in 4:
				var x: float = c.x - r * 0.42 + r * 0.28 * i
				draw_colored_polygon(PackedVector2Array([Vector2(x - r * 0.1, c.y - r * 0.05),
					Vector2(x + r * 0.1, c.y - r * 0.05), Vector2(x, c.y + r * 0.22)]), BkDraw.INK)
