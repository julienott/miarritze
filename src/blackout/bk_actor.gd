class_name BkActor
extends CharacterBody2D
## Un joueur (humain ou IA) : son perso en pixel art (BkPerso) et son pseudo au-dessus de la tête
## (GDD-BLACKOUT.md §7.1, aucune couleur de joueur). Les personnages se traversent (couche 4, on ne heurte
## que la carte) ; un fantôme traverse aussi les murs.

enum Role { HIDER, HUNTER, GHOST, OUT }

const LAYER_ACTOR: int = 4
## Taille du pseudo au-dessus de la tête (px de la résolution 640×360).
const NOM_TAILLE: int = 8

var id: int = 0
var display_name: String = ""
## Personnage du roster (accessoire dessiné) : louis, maia, patxi…
var character: String = "louis"
var walk_phase: float = 0.0
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
## Idées de gameplay (rules.json, `idee_*`) : sprint d'un gâteau basque (chassé), vent dans le dos du
## chasseur bredouille (multiplicateur), et délivrance (progression 0 → 1 du fantôme qu'un chassé
## délivre ; une seule fois par round).
var sprint_left: float = 0.0
## Poursuite (idee_poursuite) : secondes de vitesse de poursuite restantes (chasseur et chassé repéré).
var chase_left: float = 0.0
var chase_used: bool = false          # poursuite déjà lancée pour ce repérage (jusqu'à jauge vide)
var elan_mult: float = 1.0
var rescue_k: float = 0.0
var rescued: bool = false
## Pose de fin de round : "victory", "sad" ou "" pendant le jeu.
var end_pose: String = ""


func setup(p_id: int, p_name: String, bot: bool) -> void:
	id = p_id
	display_name = p_name
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
	perso = BkPerso.new()
	perso.setup(self)
	add_child(perso)


## Change de perso dessiné (visite de debug).
func set_character(c: String) -> void:
	character = c
	if perso != null:
		perso.queue_free()
		perso = null
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


## Ligne des pieds sous le centre de l'acteur (px, repère local) : l'ombre et les pieds du sprite.
func feet_dy() -> float:
	return roundf(radius * 0.4)


## Ligne de base du pseudo au-dessus de la tête (repère local).
func name_y() -> float:
	var lift: float = perso.hover_lift if perso != null else 0.0
	return feet_dy() - BkPerso.hauteur_px() - 2.0 - lift


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
	sprint_left = maxf(0.0, sprint_left - dt)
	chase_left = maxf(0.0, chase_left - dt)
	power_cd = maxf(0.0, power_cd - dt)
	queue_redraw()


func _draw() -> void:
	if not shown or inside() or not draw_2d:
		return
	var ghost: bool = role == Role.GHOST or role == Role.OUT
	var t: float = BkRules.f("tile_px")
	var fy: float = feet_dy()
	var face: float = 1.0 if cos(look) >= 0.0 else -1.0
	# Ombre au sol (plus petite sous un perso qui s'envole), et anneau rouge sous le chasseur (rôle).
	var lift: float = perso.hover_lift if perso != null else 0.0
	if not ghost:
		var k: float = clampf(1.0 - lift / t, 0.4, 1.0)
		BkDraw.ellipse(self, Vector2(0, fy), roundf(t * 0.22 * k), roundf(t * 0.08 * k) + 0.5, Color(0, 0, 0, 0.3))
	if role == Role.HUNTER:
		var ring: PackedVector2Array = BkDraw.ellipse_points(Vector2(0, fy), t * 0.32, t * 0.12, 20)
		ring.append(ring[0])
		draw_polyline(ring, Color("ff3b30"), 1.0)
	# Pseudo au-dessus de la tête : on reconnaît les joueurs à leur pseudo (GDD §7.1).
	var top: float = name_y()
	BkDraw.texte(self, Vector2(0, top), display_name, NOM_TAILLE, Color(1, 1, 1, 0.55 if ghost else 1.0), 2)
	if slow_left > 0.0:
		for k2: int in 3:
			var p: Vector2 = Vector2(0, top + 4) + Vector2.from_angle(float(k2) * TAU / 3.0 + slow_left * 4.0) * t * 0.22
			draw_rect(Rect2(p.round(), Vector2(2, 2)), Color("f2c12e"))
	# Vent dans le dos (chasseur bredouille), sprint du gâteau ou poursuite : traits de vitesse derrière.
	if (elan_mult > 1.0 and role == Role.HUNTER) or (sprint_left > 0.0 and role == Role.HIDER) \
			or (chase_left > 0.0 and (role == Role.HUNTER or role == Role.HIDER)):
		var back: float = -face
		var col: Color = Color("9fd8ef") if role == Role.HUNTER else Color("ffd34a")
		if chase_left > 0.0:
			col = Color("ff6b3d")                # poursuite : traits orange vif sur les deux
		for k3: int in 3:
			var y: float = roundf(fy - t * (0.7 - 0.2 * k3))
			var x0: float = roundf(back * (t * 0.3 + fmod(walk_phase * 3.0 + k3, 3.0)))
			draw_line(Vector2(x0, y), Vector2(x0 + back * t * 0.25, y), col, 1.0)
	# Délivrance en cours : anneau vert qui se remplit autour du fantôme.
	if rescue_k > 0.0 and role == Role.GHOST:
		draw_arc(Vector2(0, fy - t * 0.5), t * 0.6, -PI * 0.5, -PI * 0.5 + TAU * rescue_k, 24, Color("6fe08a"), 2.0)
	if gauge > 0.0 and role == Role.HIDER:
		var w: float = roundf(t * 0.75)
		var r: Rect2 = Rect2(Vector2(roundf(-w * 0.5), roundf(top - 13)), Vector2(w, 3))
		draw_rect(r.grow(1), BkDraw.INK)
		draw_rect(Rect2(r.position, Vector2(roundf(w * clampf(gauge, 0.0, 1.0)), r.size.y)), Color("ff3b30"))
