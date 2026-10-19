class_name GkActor
extends CharacterBody2D
## Un joueur (humain ou IA) du prototype : pastille de couleur avec une visière qui montre
## où il regarde (SPEC-GORDEKA §3). Les personnages se traversent (couche 4, on ne heurte
## que la carte) ; un fantôme traverse aussi les murs.

enum Role { HIDER, HUNTER, GHOST, OUT }

const LAYER_ACTOR: int = 4

var id: int = 0
var display_name: String = ""
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
var search_left: float = 0.0
var gauge: float = 0.0               # repérage par le chasseur (0 → 1 = trouvé)
var extract_t: float = 0.0
var alive_t: float = 0.0             # temps de chasse passé non trouvé (points)
var score: int = 0
var round_points: int = 0
var won_round: bool = false
## Vu du joueur local : faut-il dessiner ce personnage ?
var shown: bool = true
var radius: float = 20.0


func setup(p_id: int, p_name: String, p_color: Color, bot: bool) -> void:
	id = p_id
	display_name = p_name
	color = p_color
	is_bot = bot
	radius = GkRules.px("body_radius")
	var cs: CollisionShape2D = CollisionShape2D.new()
	var c: CircleShape2D = CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	add_child(cs)
	collision_layer = LAYER_ACTOR
	collision_mask = GkMap.LAYER_MOVE
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func set_role(r: Role) -> void:
	role = r
	collision_mask = 0 if r == Role.GHOST or r == Role.OUT else GkMap.LAYER_MOVE
	queue_redraw()


func is_hider() -> bool:
	return role == Role.HIDER


func speed() -> float:
	var key: String = {Role.HIDER: "speed_hider", Role.HUNTER: "speed_hunter"}.get(role, "speed_ghost")
	var s: float = GkRules.px(key)
	if slow_left > 0.0:
		s *= GkRules.f("trap_slow")
	return s


## Avance d'un pas : `move` de longueur ≤ 1, `look_dir` optionnel pour regarder sans bouger.
func step(move: Vector2, look_dir: Vector2, dt: float) -> void:
	if frozen or hidden_in >= 0 or search_left > 0.0:
		velocity = Vector2.ZERO
	else:
		velocity = move.limit_length(1.0) * speed()
		move_and_slide()
	var want: Vector2 = move if move.length() > 0.2 else look_dir
	if want.length() > 0.1 and hidden_in < 0:
		var turn: float = deg_to_rad(GkRules.f("turn_speed_deg")) * dt
		look = rotate_toward(look, want.angle(), turn)
	slow_left = maxf(0.0, slow_left - dt)
	power_cd = maxf(0.0, power_cd - dt)
	queue_redraw()


func _draw() -> void:
	if not shown or hidden_in >= 0:
		return
	var ghost: bool = role == Role.GHOST or role == Role.OUT
	var a: float = 0.4 if ghost else 1.0
	var dir: Vector2 = Vector2.from_angle(look)
	var dark: Color = color.darkened(0.45)
	# Ombre, sac à dos, corps, visière (façon Among Us vue de dessus).
	if not ghost:
		draw_circle(Vector2(0, radius * 0.55), radius * 1.05, Color(0, 0, 0, 0.18))
	draw_circle(-dir * radius * 0.75, radius * 0.55, Color(dark, a))
	draw_circle(Vector2.ZERO, radius + 3, Color(Color("1d2230"), a))
	draw_circle(Vector2.ZERO, radius, Color(color, a))
	var vis: Vector2 = dir * radius * 0.45
	draw_set_transform(vis, look, Vector2(0.55, 1.0))
	draw_circle(Vector2.ZERO, radius * 0.62, Color(Color("1d2230"), a))
	draw_circle(Vector2.ZERO, radius * 0.5, Color(Color("9fd8ef"), a))
	draw_set_transform(Vector2.ZERO)
	if role == Role.HUNTER:
		draw_arc(Vector2.ZERO, radius + 9, 0, TAU, 32, Color("ff3b30"), 5.0)
	if slow_left > 0.0:
		for i: int in 3:
			var p: Vector2 = Vector2.from_angle(float(i) * TAU / 3.0 + slow_left * 4.0) * (radius + 6)
			draw_circle(p, 5, Color("f2c12e"))
	var font: Font = ThemeDB.fallback_font
	var label: String = display_name
	draw_string(font, Vector2(-120, -radius - 14), label, HORIZONTAL_ALIGNMENT_CENTER, 240, 20,
		Color(1, 1, 1, a))
	if gauge > 0.0 and role == Role.HIDER:
		var w: float = radius * 2.4
		var r: Rect2 = Rect2(Vector2(-w * 0.5, -radius - 44), Vector2(w, 9))
		draw_rect(r.grow(2), Color("1d2230"))
		draw_rect(Rect2(r.position, Vector2(w * clampf(gauge, 0.0, 1.0), r.size.y)), Color("ff3b30"))
