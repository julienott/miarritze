class_name BkActor
extends CharacterBody2D
## Un joueur (humain ou IA) du prototype : pastille de couleur avec une visière qui montre
## où il regarde (SPEC-GORDEKA §3). Les personnages se traversent (couche 4, on ne heurte
## que la carte) ; un fantôme traverse aussi les murs.

enum Role { HIDER, HUNTER, GHOST, OUT }

const LAYER_ACTOR: int = 4

var id: int = 0
var display_name: String = ""
## Personnage du roster (accessoire dessiné) : louis, maia, patxi…
var character: String = "louis"
var walk_phase: float = 0.0
var color: Color = Color.WHITE
var is_bot: bool = true
var role: Role = Role.HIDER
## Angle du regard (radians) : suit la marche, tourne à vitesse limitée.
var look: float = 0.0
var frozen: bool = false
var slow_left: float = 0.0
var power_cd: float = 0.0
var hidden_in: int = -1              # index de cachette, -1 = dehors
var hidden_t: float = 0.0
## Plongée dans la cachette : encore visible dehors tant que > 0 (s), même si `hidden_in` est posé.
var vanish_left: float = 0.0
## Sortie de cachette : le perso jaillit de `pop_from` vers sa position pendant `pop_left` (s).
var pop_from: Vector2 = Vector2.ZERO
var pop_left: float = 0.0
var search_left: float = 0.0
var gauge: float = 0.0               # repérage par le chasseur (0 → 1 = trouvé)
## Détection progressive : la jauge a passé le « ? » (detection_doute) ; « ouf ! » restant (s) quand
## elle est retombée à zéro sans capture (frôlement).
var doubted: bool = false
var ouf_t: float = 0.0
var extract_t: float = 0.0
var alive_t: float = 0.0             # temps de chasse passé non trouvé (points)
var score: int = 0
var round_points: int = 0
var won_round: bool = false
## Vu du joueur local : faut-il dessiner ce personnage ?
var shown: bool = true
## Dessin à plat (prototype) ; faux en 3D.
var draw_2d: bool = true
var radius: float = 20.0
## Perso dessiné (planches pixelforge) ; null tant que ce perso n'a pas ses planches.
var perso: BkPerso
## Chassé qui fuit le chasseur tout proche (allure affolée).
var scared: bool = false
## Multiplicateur de vitesse du chasseur IA selon son niveau (difficulté) ; 1 pour un humain.
var speed_mult: float = 1.0
## Idées de gameplay (rules.json, `idee_*`) : chatouille d'un fantôme (chasseur ralenti), sprint
## d'un gâteau basque (chassé), vent dans le dos du chasseur bredouille (multiplicateur), et
## délivrance (progression 0 → 1 du fantôme qu'un chassé délivre ; une seule fois par round).
var tickle_left: float = 0.0
var sprint_left: float = 0.0
## Poursuite (idee_poursuite) : secondes de vitesse de poursuite restantes (chasseur et chassé repéré).
var chase_left: float = 0.0
var chase_used: bool = false          # poursuite déjà lancée pour ce repérage (jusqu'à jauge vide)
var elan_mult: float = 1.0
var rescue_k: float = 0.0
var rescued: bool = false
## Pose de fin de round : "victory", "sad" ou "" pendant le jeu.
var end_pose: String = ""
## Emote en cours (index dans BkGame.EMOTES, -1 = aucune) et temps restant de sa bulle (s).
var emote: int = -1
var emote_t: float = 0.0


func setup(p_id: int, p_name: String, p_color: Color, bot: bool) -> void:
	id = p_id
	display_name = p_name
	color = p_color
	is_bot = bot
	radius = BkRules.px("body_radius")
	var cs: CollisionShape2D = CollisionShape2D.new()
	var c: CircleShape2D = CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	add_child(cs)
	collision_layer = LAYER_ACTOR
	collision_mask = BkMap.LAYER_MOVE
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	if BkPerso.available(character):
		perso = BkPerso.new()
		perso.setup(self)
		add_child(perso)


## Change de perso dessiné (visite de debug).
func set_character(c: String) -> void:
	character = c
	if perso != null:
		perso.queue_free()
		perso = null
	if BkPerso.available(character):
		perso = BkPerso.new()
		perso.setup(self)
		add_child(perso)
	queue_redraw()


## Geste ponctuel du perso dessiné (piège, détection, trouvé, cachette, sortie).
func play_once(anim: String) -> void:
	if perso != null:
		perso.play_once(anim)


## Durée d'un geste ponctuel du perso dessiné (s), 0 sans perso ou sans cette animation.
func once_length(anim: String) -> float:
	return perso.length(anim) if perso != null else 0.0


## Vrai si l'acteur est dans sa cachette et n'est plus visible (plongée terminée).
func inside() -> bool:
	return hidden_in >= 0 and vanish_left <= 0.0


## Coupe l'emote en cours (la partie reprend : on ne gêne pas la cachette).
func stop_emote() -> void:
	emote_t = 0.0
	if perso != null:
		perso.stop_emote()


## Ligne du pseudo au-dessus de la tête (repère local) ; la bulle d'emote se pose au-dessus.
func name_y() -> float:
	if perso != null:
		return radius * 0.6 - BkPerso.HEIGHT_PX - 4.0
	return (-34.0 if character == "ramuntxo" else -27.0) * radius / 10.0


func set_role(r: Role) -> void:
	role = r
	collision_mask = 0 if r == Role.GHOST or r == Role.OUT else BkMap.LAYER_MOVE
	queue_redraw()


func is_hider() -> bool:
	return role == Role.HIDER


func speed() -> float:
	var key: String = {Role.HIDER: "speed_hider", Role.HUNTER: "speed_hunter"}.get(role, "speed_ghost")
	var s: float = BkRules.px(key)
	if slow_left > 0.0:
		s *= BkRules.f("trap_slow")
	if tickle_left > 0.0:
		s *= BkRules.f("chatouille_lent")
	if sprint_left > 0.0 and role == Role.HIDER:
		s *= BkRules.f("gateau_sprint")
	if chase_left > 0.0:
		s *= BkGame.chase_mult(role == Role.HUNTER)
	if role == Role.HUNTER:
		s *= speed_mult * elan_mult
	return s


## Avance d'un pas : `move` de longueur ≤ 1, `look_dir` optionnel pour regarder sans bouger.
func step(move: Vector2, look_dir: Vector2, dt: float) -> void:
	if frozen or hidden_in >= 0 or search_left > 0.0:
		velocity = Vector2.ZERO
	else:
		velocity = move.limit_length(1.0) * speed()
		move_and_slide()
		walk_phase = fmod(walk_phase + velocity.length() * dt * 0.06, TAU) if velocity.length() > 5.0 else 0.0
	var want: Vector2 = move if move.length() > 0.2 else look_dir
	if want.length() > 0.1 and hidden_in < 0:
		var turn: float = deg_to_rad(BkRules.f("turn_speed_deg")) * dt
		look = rotate_toward(look, want.angle(), turn)
	slow_left = maxf(0.0, slow_left - dt)
	tickle_left = maxf(0.0, tickle_left - dt)
	sprint_left = maxf(0.0, sprint_left - dt)
	chase_left = maxf(0.0, chase_left - dt)
	power_cd = maxf(0.0, power_cd - dt)
	queue_redraw()


func _draw() -> void:
	if not shown or inside() or not draw_2d:
		return
	var ghost: bool = role == Role.GHOST or role == Role.OUT
	var u: float = radius / 10.0
	var face: float = 1.0 if cos(look) >= 0.0 else -1.0
	# Ombre au sol, et anneau rouge sous le chasseur.
	if not ghost:
		BkDraw.ellipse(self, Vector2(0, 5.5 * u), 10.5 * u, 3.6 * u, Color(0, 0, 0, 0.22))
	elif perso != null and perso.hover_lift > 0.0:
		# Fantôme en vol (TEMPORAIRE, BkPerso) : l'ombre reste au sol, plus petite et plus pâle en haut.
		var k: float = clampf(1.0 - perso.hover_lift / 40.0, 0.4, 1.0)
		BkDraw.ellipse(self, Vector2(0, 5.5 * u), 9.0 * u * k, 3.0 * u * k, Color(0, 0, 0, 0.16 * k))
	if role == Role.HUNTER:
		var ring: PackedVector2Array = BkDraw.ellipse_points(Vector2(0, 5.5 * u), 13.0 * u, 5.0 * u, 32)
		ring.append(ring[0])
		draw_polyline(ring, Color("ff3b30"), 4.0, true)
	if perso == null:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(face * u, u))
		_draw_body(ghost)
		draw_set_transform(Vector2.ZERO)
	var font: Font = ThemeDB.fallback_font
	var top: float = name_y()
	draw_string(font, Vector2(-120, top), display_name, HORIZONTAL_ALIGNMENT_CENTER, 240, 20,
		Color(1, 1, 1, 0.5 if ghost else 1.0))
	if slow_left > 0.0:
		for k: int in 3:
			var p: Vector2 = Vector2(0, -8 * u) + Vector2.from_angle(float(k) * TAU / 3.0 + slow_left * 4.0) * 14 * u
			draw_circle(p, 4.0, Color("f2c12e"))
	# Chatouillé par un fantôme : il rit (« hi hi ») en se tortillant.
	if tickle_left > 0.0:
		var wob: float = sin(tickle_left * 30.0) * 4.0
		draw_string(font, Vector2(-120 + wob, top - 40), "hi hi !", HORIZONTAL_ALIGNMENT_CENTER, 240, 24, Color("ffd34a"))
	# Vent dans le dos (chasseur bredouille) ou sprint du gâteau : traits de vitesse derrière lui.
	if (elan_mult > 1.0 and role == Role.HUNTER) or (sprint_left > 0.0 and role == Role.HIDER) \
			or (chase_left > 0.0 and (role == Role.HUNTER or role == Role.HIDER)):
		var back: float = -face
		var col: Color = Color("9fd8ef") if role == Role.HUNTER else Color("ffd34a")
		if chase_left > 0.0:
			col = Color("ff6b3d")                # poursuite : traits orange vif sur les deux
		for k: int in 3:
			var y: float = (-14.0 + k * 7.0) * u
			var x0: float = back * (12.0 + fmod(walk_phase * 3.0 + k, 3.0)) * u
			draw_line(Vector2(x0, y), Vector2(x0 + back * 10.0 * u, y), col, 3.0, true)
	# Délivrance en cours : anneau vert qui se remplit autour du fantôme.
	if rescue_k > 0.0 and role == Role.GHOST:
		draw_arc(Vector2(0, -8 * u), radius + 16, -PI * 0.5, -PI * 0.5 + TAU * rescue_k, 32, Color("6fe08a"), 6.0)
	if gauge > 0.0 and role == Role.HIDER:
		var w: float = radius * 2.4
		var r: Rect2 = Rect2(Vector2(-w * 0.5, top - 30), Vector2(w, 9))
		draw_rect(r.grow(2), BkDraw.INK)
		draw_rect(Rect2(r.position, Vector2(w * clampf(gauge, 0.0, 1.0), r.size.y)), Color("ff3b30"))


## Le petit bonhomme façon Among Us, de profil vers la droite, en unités (1 u = rayon / 10) ;
## les pieds touchent y = 6.
func _draw_body(ghost: bool) -> void:
	var a: float = 0.45 if ghost else 1.0
	var main: Color = Color(color, a)
	var dark: Color = Color(color.darkened(0.35), a)
	var ink: Color = Color(BkDraw.INK, a)
	var step_y: float = sin(walk_phase) * 1.6
	if not ghost:
		BkDraw.rbox(self, Rect2(-6.5, -1 - maxf(step_y, 0.0), 5.5, 7), dark, 2.5, 0.35, ink)
	_back_item(a)
	if ghost:
		# Fantôme : pas de jambes, une petite queue ondulante.
		BkDraw.poly(self, PackedVector2Array([Vector2(-8, -2), Vector2(8, -2), Vector2(5, 4), Vector2(1, 1),
			Vector2(-3, 5), Vector2(-6, 1)]), main, 0.35, ink)
	# Corps : contour sombre, puis l'aplat, puis l'ombre douce côté dos.
	BkDraw.rbox(self, Rect2(-8.6, -19.6, 17.2, 22.2), ink, 8.0, 0.0, ink)
	BkDraw.rbox(self, Rect2(-8, -19, 16, 21), main, 7.0, 0.0, ink)
	BkDraw.rbox(self, Rect2(-8, -13, 4, 14), dark, 2.0, 0.0, ink)
	if not ghost:
		BkDraw.rbox(self, Rect2(1, -1 - maxf(-step_y, 0.0), 5.5, 7), main, 2.5, 0.35, ink)
	# Visière.
	BkDraw.rbox(self, Rect2(1, -15.5, 9.5, 7.5), Color(Color("8fd3ee"), a), 3.6, 0.4, ink)
	BkDraw.rbox(self, Rect2(4.5, -14.2, 4.5, 2.2), Color(1, 1, 1, 0.85 * a), 1.0, 0.0, ink)
	_head_item(a)


## Objet porté dans le dos (à la place du sac à dos d'Among Us).
func _back_item(a: float) -> void:
	var ink: Color = Color(BkDraw.INK, a)
	match character:
		"maia":                     # planche de surf
			BkDraw.ellipse(self, Vector2(-11, -9), 2.8, 12, Color(Color("f7efdc"), a), 0.4, ink)
			draw_line(Vector2(-11, -20), Vector2(-11, 2), Color(Color("2fb24a"), a), 1.0)
		"mattin":                   # la pierre qu'il soulève
			BkDraw.poly(self, PackedVector2Array([Vector2(-15, -12), Vector2(-11, -17), Vector2(-6, -15),
				Vector2(-5, -4), Vector2(-9, -1), Vector2(-15, -4)]), Color(Color("8d939e"), a), 0.4, ink)
		"xabi":                     # chistera
			BkDraw.ellipse(self, Vector2(-12, -8), 3.2, 9, Color(Color("c9a46a"), a), 0.4, ink)
			for k: int in 3:
				draw_line(Vector2(-14, -13 + k * 4), Vector2(-10, -12 + k * 4), Color(Color("8a6a3a"), a), 0.4)
		"amaia":                    # makila en travers du dos
			draw_line(Vector2(-13, 0), Vector2(-5, -22), Color(Color("7a4a24"), a), 1.6)
			BkDraw.ellipse(self, Vector2(-5, -22), 1.4, 1.4, Color(Color("d8dde3"), a), 0.3, ink)
		"karramarro":               # pinces de crabe devant
			BkDraw.ellipse(self, Vector2(-11, -8), 3, 6, Color(color.darkened(0.35), a), 0.4, ink)
		_:
			BkDraw.rbox(self, Rect2(-11.5, -14, 5, 12), Color(color.darkened(0.35), a), 2.2, 0.4, ink)


## Ce qui rend chaque perso reconnaissable : chapeau, lunettes, bec, pinces…
func _head_item(a: float) -> void:
	var ink: Color = Color(BkDraw.INK, a)
	match character:
		"louis":                    # txapela rouge
			BkDraw.ellipse(self, Vector2(0.5, -19), 9.5, 2.6, Color(Color("c62828"), a), 0.4, ink)
			BkDraw.ellipse(self, Vector2(0, -21), 7, 3, Color(Color("d83a34"), a), 0.4, ink)
			draw_line(Vector2(0, -24), Vector2(0.5, -26), ink, 0.8)
		"maia":                     # bandeau jaune
			BkDraw.rbox(self, Rect2(-8.3, -18, 16.6, 2.4), Color(Color("f2c12e"), a), 1.0, 0.35, ink)
		"patxi":                    # bonnet de marin et barbe
			BkDraw.rbox(self, Rect2(-8, -24, 16, 9), Color(Color("2b4c8c"), a), 6.0, 0.4, ink)
			BkDraw.rbox(self, Rect2(-8.6, -17.5, 17.2, 3.4), Color(Color("1f3a70"), a), 1.5, 0.4, ink)
			BkDraw.ellipse(self, Vector2(7, -6), 3.6, 2.8, Color(Color("6b4226"), a), 0.35, ink)
		"xabi":                     # bandeau de pelotari
			BkDraw.rbox(self, Rect2(-8.3, -17.5, 16.6, 2.6), Color(Color("ffffff"), a), 1.0, 0.35, ink)
			draw_line(Vector2(-8, -16.2), Vector2(8, -16.2), Color(Color("c62828"), a), 0.6)
		"mattin":                   # béret noir
			BkDraw.ellipse(self, Vector2(0, -19.5), 8.5, 2.6, Color(Color("2a2a30"), a), 0.4, ink)
		"amaia":                    # fleur rouge de dantzari
			for k: int in 5:
				BkDraw.ellipse(self, Vector2(-3, -19) + Vector2.from_angle(TAU * k / 5.0) * 1.6, 1.3, 1.3, Color(Color("e53935"), a))
			BkDraw.ellipse(self, Vector2(-3, -19), 0.9, 0.9, Color(Color("ffd34a"), a))
		"txomin":                   # lunettes noires et sifflet
			BkDraw.rbox(self, Rect2(1.5, -14.5, 9.5, 4.2), Color(Color("111111"), a), 1.6, 0.3, ink)
			draw_line(Vector2(-6, -15), Vector2(1.5, -13), ink, 0.6)
			BkDraw.ellipse(self, Vector2(6, -4), 1.4, 1.1, Color(Color("f2c12e"), a), 0.3, ink)
		"kaio":                     # bec de goéland et houppette
			BkDraw.poly(self, PackedVector2Array([Vector2(9.5, -13.5), Vector2(16, -11.5), Vector2(9.5, -9.5)]),
				Color(Color("f6a91e"), a), 0.4, ink)
			BkDraw.ellipse(self, Vector2(15.2, -11.5), 0.7, 0.7, Color(Color("e53935"), a))
			for k: int in 3:
				BkDraw.ellipse(self, Vector2(-2 + k * 2.2, -19.5 - (1 if k == 1 else 0)), 1.6, 2.4, Color(Color("eef1f4"), a), 0.3, ink)
		"karramarro":               # yeux sur pédoncules et pince
			for x: float in [1.0, 5.0]:
				draw_line(Vector2(x, -18), Vector2(x + 0.5, -24), ink, 0.8)
				BkDraw.ellipse(self, Vector2(x + 0.5, -24.5), 1.8, 1.8, Color(1, 1, 1, a), 0.3, ink)
				BkDraw.ellipse(self, Vector2(x + 1.0, -24.5), 0.7, 0.7, ink)
			BkDraw.poly(self, PackedVector2Array([Vector2(8, -5), Vector2(14, -8), Vector2(16, -5), Vector2(13, -4),
				Vector2(16, -2), Vector2(13, 0), Vector2(8, -1)]), Color(color.darkened(0.1), a), 0.4, ink)
		"ramuntxo":                 # toque de chef
			BkDraw.rbox(self, Rect2(-5.5, -27, 11, 9), Color(1, 1, 1, a), 2.5, 0.4, ink)
			for x: float in [-4.0, 0.0, 4.0]:
				BkDraw.ellipse(self, Vector2(x, -28), 3.4, 3.0, Color(1, 1, 1, a), 0.4, ink)
			BkDraw.rbox(self, Rect2(-6, -20.5, 12, 2.5), Color(Color("e8e8e8"), a), 1.0, 0.35, ink)
		"itsaso":                   # couronne d'écume
			for k: int in 4:
				BkDraw.ellipse(self, Vector2(-6 + k * 4, -19 - (k % 2) * 1.2), 2.4, 2.2,
					Color(Color("e8fbff") if k % 2 == 0 else Color("7fd6f0"), a), 0.3, ink)
		"peio":                     # casque de rugby rayé
			BkDraw.rbox(self, Rect2(-8.6, -22, 17.2, 10), Color(Color("c62828"), a), 6.5, 0.4, ink)
			for x: float in [-4.0, 0.0, 4.0]:
				draw_line(Vector2(x, -21.5), Vector2(x, -13), Color(1, 1, 1, a), 0.8)
