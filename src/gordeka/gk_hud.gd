class_name GkHud
extends Control
## Interface du round (SPEC-GORDEKA §2, §5) : rôle, chrono, messages, bouton d'action avec
## son temps de recharge, joystick tactile, flèche vers le chasseur hors champ, voile du
## chasseur qui compte, scores entre les rounds et podium en quittant. Emotes : bulles d'icône
## au-dessus des têtes, petit bouton et éventail des 6 bulles quand elles sont permises.

var game: GkGame
var _quit: Button
var _menu: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quit = Button.new()
	_quit.text = "Quitter"
	_quit.focus_mode = Control.FOCUS_NONE
	_quit.add_theme_font_size_override(&"font_size", 24)
	_quit.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quit.offset_left = -150
	_quit.offset_top = 16
	_quit.offset_right = -20
	_quit.offset_bottom = 64
	_quit.pressed.connect(func() -> void: game.quit_to_podium())
	add_child(_quit)
	_menu = Button.new()
	_menu.text = "Retour au menu"
	_menu.add_theme_font_size_override(&"font_size", 30)
	_menu.visible = false
	_menu.pressed.connect(func() -> void: game.go_menu())
	add_child(_menu)


func _draw() -> void:
	if game == null or game.local == null:
		return
	var s: Vector2 = size
	var font: Font = ThemeDB.fallback_font
	var me: GkActor = game.local
	if game.phase == GkGame.Phase.PODIUM:
		_draw_podium(s, font)
		return
	_menu.visible = false
	_quit.visible = true
	# Voile du chasseur qui compte (il ne voit rien pendant la cachette).
	if game.phase == GkGame.Phase.HIDE and me == game.hunter:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.03, 0.07, 0.96))
		var n: int = clampi(int(GkRules.f("phase_hide") - game.phase_t) + 1, 1, GkGame.COUNT_WORDS.size())
		_text(font, s * Vector2(0.5, 0.42), GkGame.COUNT_WORDS[n - 1].capitalize() + "…", 96, Color.WHITE)
		_text(font, s * Vector2(0.5, 0.58), "Tu comptes, les autres se cachent", 30, Color(1, 1, 1, 0.7))
	# Bandeau du haut : rôle, phase, chrono.
	var role_text: String = {GkActor.Role.HIDER: "CHASSÉ", GkActor.Role.HUNTER: "CHASSEUR",
		GkActor.Role.GHOST: "FANTÔME", GkActor.Role.OUT: "ÉCHAPPÉ"}[me.role]
	var role_col: Color = {GkActor.Role.HIDER: Color("4aa3ff"), GkActor.Role.HUNTER: Color("ff3b30"),
		GkActor.Role.GHOST: Color("b8c0cc"), GkActor.Role.OUT: Color("6fe08a")}[me.role]
	draw_rect(Rect2(16, 16, 230, 52), Color(0, 0, 0, 0.55))
	_text(font, Vector2(131, 52), role_text, 30, role_col)
	var phase_text: String = {GkGame.Phase.DRAW: "Tirage…", GkGame.Phase.HIDE: "Cachez-vous !",
		GkGame.Phase.HUNT: "Chasse", GkGame.Phase.END: "Fin du round"}.get(game.phase, "")
	var t: int = maxi(0, ceili(game.phase_t))
	draw_rect(Rect2(s.x * 0.5 - 150, 12, 300, 70), Color(0, 0, 0, 0.55))
	_text(font, Vector2(s.x * 0.5, 42), "%s · round %d" % [phase_text, game.round_no], 22, Color(1, 1, 1, 0.85))
	_text(font, Vector2(s.x * 0.5, 74), "%d:%02d" % [t / 60, t % 60], 32,
		Color("ff6b5e") if game.phase == GkGame.Phase.HUNT and t <= 20 else Color.WHITE)
	var left: int = game.actors.filter(func(a: GkActor) -> bool: return a.role == GkActor.Role.HIDER).size()
	_text(font, Vector2(s.x * 0.5, 104), "%d chassé%s encore libre%s" % [left, "s" if left > 1 else "", "s" if left > 1 else ""],
		20, Color(1, 1, 1, 0.8))
	if not game.open_exit_zones.is_empty() and (game.phase == GkGame.Phase.HIDE or game.phase == GkGame.Phase.HUNT):
		var where: String = " et ".join(game.open_exit_zones)
		if game.exits_open():
			_text(font, Vector2(s.x * 0.5, 128), "Sorties ouvertes : " + where, 20, Color("6fe08a"))
		else:
			_text(font, Vector2(s.x * 0.5, 128), "Sorties du round : " + where, 20, Color(1, 1, 1, 0.7))
	# Fantôme : ce qu'il peut encore faire (idées chatouille et délivrance).
	if me.role == GkActor.Role.GHOST and game.phase == GkGame.Phase.HUNT:
		var tips: PackedStringArray = []
		if GkRules.on("idee_chatouille"):
			tips.append("Touche le chasseur : il rit !")
		if GkRules.on("idee_delivrance") and not me.rescued and game._rescues < int(GkRules.f("delivrance_max")):
			tips.append("Rejoins un chassé : il te délivre !")
		var ty: float = s.y - 30.0 - 38.0 * float(tips.size() - 1)
		for tip: String in tips:
			draw_rect(Rect2(s.x * 0.5 - 250, ty - 28, 500, 36), Color(0, 0, 0, 0.55))
			_text(font, Vector2(s.x * 0.5, ty), tip, 24, Color("ffd34a"))
			ty += 38.0
	# Messages.
	var y: float = s.y * 0.26
	for m: Dictionary in game.messages:
		_text(font, Vector2(s.x * 0.5 + 2, y + 2), str(m["text"]), 38, Color(0, 0, 0, 0.6))
		_text(font, Vector2(s.x * 0.5, y), str(m["text"]), 38, m["color"])
		y += 48
	# Flèche vers le chasseur quand il est hors champ (chassés et fantômes).
	if me != game.hunter and game.hunter and game.phase == GkGame.Phase.HUNT:
		var sp: Vector2 = game.screen_pos(game.hunter.position)
		var r: Rect2 = Rect2(Vector2.ZERO, s).grow(-40)
		if not r.has_point(sp):
			var c: Vector2 = s * 0.5
			var d: Vector2 = (sp - c).normalized()
			var k: float = minf(absf((r.size.x * 0.5) / maxf(absf(d.x), 0.001)), absf((r.size.y * 0.5) / maxf(absf(d.y), 0.001)))
			var p: Vector2 = c + d * k
			var pts: PackedVector2Array = [p + d * 26, p + d.orthogonal() * 16 - d * 10, p - d.orthogonal() * 16 - d * 10]
			draw_colored_polygon(pts, Color("ff3b30"))
	# En 3D, jauges de repérage au-dessus des chassés (dessinées ici, dans l'écran).
	if game.use_3d:
		for a: GkActor in game.actors:
			if a.gauge > 0.0 and a.role == GkActor.Role.HIDER and a.shown and a.hidden_in < 0:
				var gp: Vector2 = game.screen_pos(a.position, 1.9)
				var w: float = 70.0
				var gr: Rect2 = Rect2(gp - Vector2(w * 0.5, 0), Vector2(w, 10))
				draw_rect(gr.grow(3), GkDraw.INK)
				draw_rect(Rect2(gr.position, Vector2(w * clampf(a.gauge, 0.0, 1.0), 10)), Color("ff3b30"))
	# Bulles d'emote au-dessus des têtes (seulement des persos que l'on voit).
	for a: GkActor in game.actors:
		if a.shown and a.hidden_in < 0:
			var tip: Vector2 = game.screen_pos(a.position, 2.3) if game.use_3d else \
				game.screen_pos(a.position + Vector2(0, a.name_y() - 24.0))
			_emote_bubble(a, tip, Vector2(0, -1))
	# Bouton d'action.
	var label: String = game.action_label(me)
	if label != "" and game.phase in [GkGame.Phase.HIDE, GkGame.Phase.HUNT] and not me.frozen:
		var c2: Vector2 = game.input.action_center()
		var cd: float = game.action_cooldown(me)
		draw_circle(c2, GkInput.ACTION_RADIUS, Color(0, 0, 0, 0.45))
		draw_circle(c2, GkInput.ACTION_RADIUS - 8, Color("ff3b30") if me == game.hunter else Color("4aa3ff"))
		if cd > 0.0:
			draw_circle(c2, GkInput.ACTION_RADIUS - 8, Color(0, 0, 0, 0.45))
			draw_arc(c2, GkInput.ACTION_RADIUS - 4, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - cd), 48, Color.WHITE, 6.0)
		_text(font, c2 + Vector2(0, 10), label, 28, Color.WHITE)
		if me.search_left > 0.0:
			_text(font, c2 + Vector2(0, -GkInput.ACTION_RADIUS - 14), "Fouille…", 24, Color.WHITE)
	# Joystick tactile.
	if game.input.touch_index >= 0:
		draw_circle(game.input.touch_origin, GkInput.STICK_RADIUS, Color(1, 1, 1, 0.15))
		draw_arc(game.input.touch_origin, GkInput.STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.4), 3.0)
		var knob: Vector2 = game.input.touch_origin + (game.input.touch_pos - game.input.touch_origin).limit_length(GkInput.STICK_RADIUS)
		draw_circle(knob, 38, Color(1, 1, 1, 0.5))
	# Scores du round.
	if game.phase == GkGame.Phase.END:
		_draw_scores(s, font)
	_draw_emote_wheel(font)


func _draw_scores(s: Vector2, font: Font) -> void:
	var rows: Array[GkActor] = game.actors.duplicate()
	rows.sort_custom(func(a: GkActor, b: GkActor) -> bool: return a.score > b.score)
	var h: float = 90.0 + 48.0 * rows.size()
	var box: Rect2 = Rect2(s.x * 0.5 - 330, s.y * 0.5 - h * 0.5, 660, h)
	draw_rect(box, Color(0.05, 0.06, 0.1, 0.88))
	_text(font, Vector2(s.x * 0.5, box.position.y + 50), "Round %d terminé" % game.round_no, 34, Color.WHITE)
	var y: float = box.position.y + 100
	for a: GkActor in rows:
		draw_circle(Vector2(box.position.x + 40, y - 10), 14, a.color)
		var tag: String = "chasseur" if a == game.hunter else {GkActor.Role.OUT: "échappé", GkActor.Role.GHOST: "trouvé"}.get(a.role, "caché")
		draw_string(font, Vector2(box.position.x + 66, y), "%s — %s%s" % [a.display_name, tag, "  ★" if a.won_round else ""],
			HORIZONTAL_ALIGNMENT_LEFT, 420, 26, Color("ffd34a") if a.won_round else Color.WHITE)
		draw_string(font, Vector2(box.position.x + 480, y), "+%d   %d pts" % [a.round_points, a.score],
			HORIZONTAL_ALIGNMENT_RIGHT, 150, 26, Color.WHITE)
		y += 48


func _draw_podium(s: Vector2, font: Font) -> void:
	_quit.visible = false
	_menu.visible = true
	_menu.size = Vector2(320, 64)
	_menu.position = Vector2(s.x * 0.5 - 160, s.y - 110)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.05, 0.1, 0.92))
	_text(font, Vector2(s.x * 0.5, 90), "Podium", 56, Color("ffd34a"))
	var rows: Array[GkActor] = game.actors.duplicate()
	rows.sort_custom(func(a: GkActor, b: GkActor) -> bool: return a.score > b.score)
	var places: Array[Vector2] = [Vector2(0, 0), Vector2(-260, 70), Vector2(260, 110)]
	var heights: Array[float] = [220.0, 150.0, 110.0]
	var medal: Array[Color] = [Color("ffd34a"), Color("cfd6df"), Color("d08a4a")]
	for i: int in mini(3, rows.size()):
		var x: float = s.x * 0.5 + places[i].x
		var base: float = s.y - 150
		draw_rect(Rect2(x - 110, base - heights[i], 220, heights[i]), medal[i].darkened(0.35))
		draw_circle(Vector2(x, base - heights[i] - 50), 40, rows[i].color)
		_text(font, Vector2(x, base - heights[i] + 46), str(i + 1), 44, Color.WHITE)
		_text(font, Vector2(x, base - heights[i] - 110), rows[i].display_name, 28, Color.WHITE)
		_text(font, Vector2(x, base - heights[i] + 86), "%d pts" % rows[i].score, 24, Color.WHITE)
		# Emote à droite de la pastille.
		_emote_bubble(rows[i], Vector2(x + 40, base - heights[i] - 50), Vector2(1, -0.25))
	# Le joueur local hors du podium voit quand même son emote, près du bouton.
	if rows.find(game.local) >= 3 and game.local.emote_t > 0.0:
		var c: Vector2 = game.input.action_center() + Vector2(0, 40)
		draw_circle(c, 30, game.local.color)
		_emote_bubble(game.local, c + Vector2(0, -30), Vector2(0, -1))
	_draw_emote_wheel(font)


## Bulle de l'emote en cours d'un acteur, pointe en `tip`, posée dans la direction `dir` :
## elle apparaît en rebondissant et disparaît en se rétractant.
func _emote_bubble(a: GkActor, tip: Vector2, dir: Vector2) -> void:
	if a.emote < 0 or a.emote_t <= 0.0:
		return
	var age: float = GkRules.f("emote_duration") - a.emote_t
	var k: float = clampf(age / 0.18, 0.0, 1.0) * clampf(a.emote_t / 0.15, 0.0, 1.0)
	var r: float = 38.0 * (k + sin(k * PI) * 0.18)
	if r < 3.0:
		return
	GkDraw.emote_bubble(self, tip + dir.normalized() * (r + 14.0 * k), tip, a.emote, r)


## Petit bouton d'emote et, ouvert, l'éventail des 6 bulles (touches 1 à 6 rappelées au clavier).
func _draw_emote_wheel(font: Font) -> void:
	var inp: GkInput = game.input
	if not inp.emotes_enabled:
		return
	var c: Vector2 = inp.emote_center()
	draw_circle(c, GkInput.EMOTE_RADIUS + 6, Color(0, 0, 0, 0.45))
	GkDraw.emote_disc(self, c, GkInput.EMOTE_RADIUS, 1, Color("ffd34a") if inp.wheel_open else Color(0, 0, 0, 0))
	if not inp.wheel_open:
		return
	for i: int in GkGame.EMOTES.size():
		var b: Vector2 = inp.bubble_center(i)
		GkDraw.emote_disc(self, b, GkInput.BUBBLE_RADIUS, i, Color("ffd34a") if i == inp.wheel_sel else Color(0, 0, 0, 0))
		if not inp.touch_used:
			draw_circle(b + Vector2(28, 26), 13, GkDraw.INK)
			_text(font, b + Vector2(28, 33), str(i + 1), 20, Color.WHITE)


func _text(font: Font, at: Vector2, text: String, fsize: int, col: Color) -> void:
	draw_string(font, Vector2(at.x - 400, at.y), text, HORIZONTAL_ALIGNMENT_CENTER, 800, fsize, col)
