class_name BkHud
extends Control
## Interface du round (SPEC-GORDEKA §2, §5) : rôle, chrono, messages, bouton d'action avec
## son temps de recharge, joystick tactile, flèche vers le chasseur hors champ, voile du
## chasseur qui compte, scores entre les rounds (« Round k/N », bouton « Terminer » en partie rapide).
## Versus et podium sont des écrans à part (BkVersus, BkPodium), sous ce calque : le HUD n'y montre
## que « Quitter » et l'éventail des emotes. Emotes : bulles d'icône au-dessus des têtes, petit bouton
## et éventail des 6 bulles quand elles sont permises.

var game: BkGame
var _quit: Button
## Partie rapide : arrêter la partie pendant les scores, podium tout de suite (SPEC-GORDEKA §2.2).
var _terminer: Button
## Vignettage du chassé local (idee_frisson) : bords sombres et rougeâtres, centre libre.
var _vignette: TextureRect


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
	# Visite de debug (temporaire) : boutons Formes et Perso, pour le tactile.
	_visite_buttons()
	_terminer = BkUi.bouton("Terminer la partie", func() -> void: game.quit_to_podium(), Vector2(340, 70),
		BkUi.CREME, 26)
	_terminer.visible = false
	# Jamais le focus : Espace (l'action du jeu) ne doit pas terminer la partie par erreur ; au clavier
	# et à la manette, c'est Échap / Start (rappelés sur le bouton).
	_terminer.focus_mode = Control.FOCUS_NONE
	add_child(_terminer)
	# Vignettage : un TextureRect plein écran (un draw_texture_rect modulé ne s'affiche pas ici).
	_vignette = TextureRect.new()
	_vignette.texture = vignette_texture()
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	add_child(_vignette)
	move_child(_vignette, 0)


## Vignettage : transparent au centre, rouge sombre vers les bords (ellipse étirée à l'écran).
## Image calculée une fois (un GradientTexture2D ne s'affiche pas en rendu Compatibility).
static func vignette_texture() -> ImageTexture:
	var w: int = 160
	var h: int = 90
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var u: Vector2 = Vector2((x + 0.5) / w - 0.5, (y + 0.5) / h - 0.5) * 2.0
			var k: float = clampf((u.length() - 0.45) / 0.55, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.22, 0.0, 0.03, 0.95 * k * k * (3.0 - 2.0 * k)))
	return ImageTexture.create_from_image(img)


## Ressenti du chassé (idee_frisson) : vignettage qui pulse avec le cœur, et « Il fouille à côté ! ».
func _draw_frisson(s: Vector2, font: Font) -> void:
	var f: BkFrisson = game.frisson
	if f == null:
		return
	if f.level > 0.01:
		# Le cœur bat : le voile fonce un instant à chaque battement.
		_vignette.modulate.a = clampf((0.3 + 0.7 * f.level) * (0.75 + 0.25 * f.beat), 0.0, 1.0)
	_vignette.visible = f.level > 0.01
	if f.search_near > 0.0:
		var k: float = clampf(f.search_near / 0.3, 0.0, 1.0)
		var wob: float = sin(Time.get_ticks_msec() * 0.03) * 3.0
		var at: Vector2 = Vector2(s.x * 0.5 + wob, s.y - 150.0)
		draw_rect(Rect2(at - Vector2(230, 34), Vector2(460, 48)), Color(0, 0, 0, 0.55 * k))
		_text(font, at, "Il fouille à côté !", 32, Color(Color("ffd34a"), k))


func _visite_buttons() -> void:
	if game == null or game.visite == "":
		return
	var specs: Array = [["Formes", game.visite_toggle_formes], ["Perso", game.visite_next_character]]
	for i: int in specs.size():
		var b: Button = Button.new()
		b.text = str(specs[i][0])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override(&"font_size", 20)
		b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		b.offset_left = -300 - i * 140
		b.offset_right = -170 - i * 140
		b.offset_top = 16
		b.offset_bottom = 64
		b.pressed.connect(specs[i][1])
		add_child(b)


func _draw() -> void:
	if game == null or game.local == null:
		return
	var s: Vector2 = size
	var font: Font = ThemeDB.fallback_font
	var me: BkActor = game.local
	_quit.visible = game.phase != BkGame.Phase.PODIUM
	_maj_terminer()
	if game.phase == BkGame.Phase.PODIUM:
		_draw_emote_wheel(font)
		return
	if game.phase == BkGame.Phase.VERSUS:
		return
	# Voile du chasseur qui compte (il ne voit rien pendant la cachette).
	if game.phase == BkGame.Phase.HIDE and me == game.hunter:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.03, 0.07, 0.96))
		var n: int = clampi(int(BkRules.f("phase_hide") - game.phase_t) + 1, 1, BkGame.COUNT_WORDS.size())
		_text(font, s * Vector2(0.5, 0.42), BkGame.COUNT_WORDS[n - 1].capitalize() + "…", 96, Color.WHITE)
		_text(font, s * Vector2(0.5, 0.58), "Tu comptes, les autres se cachent", 30, Color(1, 1, 1, 0.7))
	_draw_frisson(s, font)
	# Bandeau du haut : rôle, phase, chrono.
	var role_text: String = {BkActor.Role.HIDER: "CHASSÉ", BkActor.Role.HUNTER: "CHASSEUR",
		BkActor.Role.GHOST: "FANTÔME", BkActor.Role.OUT: "ÉCHAPPÉ"}[me.role]
	var role_col: Color = {BkActor.Role.HIDER: Color("4aa3ff"), BkActor.Role.HUNTER: Color("ff3b30"),
		BkActor.Role.GHOST: Color("b8c0cc"), BkActor.Role.OUT: Color("6fe08a")}[me.role]
	draw_rect(Rect2(16, 16, 230, 52), Color(0, 0, 0, 0.55))
	_text(font, Vector2(131, 52), role_text, 30, role_col)
	if game.visite != "":
		# Visite de debug (temporaire) : pas de chrono, un bandeau discret.
		draw_rect(Rect2(s.x * 0.5 - 170, 12, 340, 36), Color(0, 0, 0, 0.45))
		_text(font, Vector2(s.x * 0.5, 37), "VISITE (debug) · F formes · C perso · G fantôme", 17, Color("ffd34a"))
	else:
		var phase_text: String = {BkGame.Phase.DRAW: "Tirage…", BkGame.Phase.HIDE: "Cachez-vous !",
			BkGame.Phase.HUNT: "Chasse", BkGame.Phase.END: "Fin du round"}.get(game.phase, "")
		var no: String = "%d/%d" % [game.round_no, game.rounds_total] if game.rounds_total > 0 else str(game.round_no)
		var t: int = maxi(0, ceili(game.phase_t))
		draw_rect(Rect2(s.x * 0.5 - 150, 12, 300, 70), Color(0, 0, 0, 0.55))
		_text(font, Vector2(s.x * 0.5, 42), "%s · round %s" % [phase_text, no], 22, Color(1, 1, 1, 0.85))
		_text(font, Vector2(s.x * 0.5, 74), "%d:%02d" % [t / 60, t % 60], 32,
			Color("ff6b5e") if game.phase == BkGame.Phase.HUNT and t <= 20 else Color.WHITE)
		var left: int = game.actors.filter(func(a: BkActor) -> bool: return a.role == BkActor.Role.HIDER).size()
		_text(font, Vector2(s.x * 0.5, 104), "%d chassé%s encore libre%s" % [left, "s" if left > 1 else "", "s" if left > 1 else ""],
			20, Color(1, 1, 1, 0.8))
		if not game.open_exit_zones.is_empty() and (game.phase == BkGame.Phase.HIDE or game.phase == BkGame.Phase.HUNT):
			var where: String = " et ".join(game.open_exit_zones)
			if game.exits_open():
				_text(font, Vector2(s.x * 0.5, 128), "Sorties ouvertes : " + where, 20, Color("6fe08a"))
			else:
				_text(font, Vector2(s.x * 0.5, 128), "Sorties du round : " + where, 20, Color(1, 1, 1, 0.7))
	# Fantôme : ce qu'il peut encore faire (idées chatouille et délivrance).
	if me.role == BkActor.Role.GHOST and game.phase == BkGame.Phase.HUNT:
		var tips: PackedStringArray = []
		if BkRules.on("idee_chatouille"):
			tips.append("Touche le chasseur : il rit !")
		if BkRules.on("idee_delivrance") and not me.rescued and game._rescues < int(BkRules.f("delivrance_max")):
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
	if me != game.hunter and game.hunter and game.hunter.visible and game.phase == BkGame.Phase.HUNT:
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
		for a: BkActor in game.actors:
			if a.gauge > 0.0 and a.role == BkActor.Role.HIDER and a.shown and a.hidden_in < 0:
				var gp: Vector2 = game.screen_pos(a.position, 1.9)
				var w: float = 70.0
				var gr: Rect2 = Rect2(gp - Vector2(w * 0.5, 0), Vector2(w, 10))
				draw_rect(gr.grow(3), BkDraw.INK)
				draw_rect(Rect2(gr.position, Vector2(w * clampf(a.gauge, 0.0, 1.0), 10)), Color("ff3b30"))
	# Bulles d'emote au-dessus des têtes (seulement des persos que l'on voit).
	for a: BkActor in game.actors:
		if a.shown and a.hidden_in < 0:
			var tip: Vector2 = game.screen_pos(a.position, 2.3) if game.use_3d else \
				game.screen_pos(a.position + Vector2(0, a.name_y() - 24.0))
			_emote_bubble(a, tip, Vector2(0, -1))
	# Bouton d'action.
	var label: String = game.action_label(me)
	if label != "" and game.phase in [BkGame.Phase.HIDE, BkGame.Phase.HUNT] and not me.frozen:
		var c2: Vector2 = game.input.action_center()
		var cd: float = game.action_cooldown(me)
		draw_circle(c2, BkInput.ACTION_RADIUS, Color(0, 0, 0, 0.45))
		draw_circle(c2, BkInput.ACTION_RADIUS - 8, Color("ff3b30") if me == game.hunter else Color("4aa3ff"))
		if cd > 0.0:
			draw_circle(c2, BkInput.ACTION_RADIUS - 8, Color(0, 0, 0, 0.45))
			draw_arc(c2, BkInput.ACTION_RADIUS - 4, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - cd), 48, Color.WHITE, 6.0)
		_text(font, c2 + Vector2(0, 10), label, 28, Color.WHITE)
		if me.search_left > 0.0:
			_text(font, c2 + Vector2(0, -BkInput.ACTION_RADIUS - 14), "Fouille…", 24, Color.WHITE)
	# Joystick tactile.
	if game.input.touch_index >= 0:
		draw_circle(game.input.touch_origin, BkInput.STICK_RADIUS, Color(1, 1, 1, 0.15))
		draw_arc(game.input.touch_origin, BkInput.STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.4), 3.0)
		var knob: Vector2 = game.input.touch_origin + (game.input.touch_pos - game.input.touch_origin).limit_length(BkInput.STICK_RADIUS)
		draw_circle(knob, 38, Color(1, 1, 1, 0.5))
	# Scores du round.
	if game.phase == BkGame.Phase.END:
		_draw_scores(s, font)
	_draw_emote_wheel(font)


func _draw_scores(s: Vector2, font: Font) -> void:
	var rows: Array[BkActor] = game.actors.duplicate()
	rows.sort_custom(func(a: BkActor, b: BkActor) -> bool: return a.score > b.score)
	var h: float = 90.0 + 48.0 * rows.size()
	var box: Rect2 = Rect2(s.x * 0.5 - 330, s.y * 0.5 - h * 0.5, 660, h)
	draw_rect(box, Color(0.05, 0.06, 0.1, 0.88))
	var titre: String = "Round %d/%d terminé" % [game.round_no, game.rounds_total] if game.rounds_total > 0 \
		else "Round %d terminé" % game.round_no
	_text(font, Vector2(s.x * 0.5, box.position.y + 50), titre, 34, Color.WHITE)
	if game.rounds_total > 0 and game.round_no >= game.rounds_total:
		_text(font, Vector2(s.x * 0.5, box.position.y + h + 40), "Dernier round : place au podium !", 28, BkUi.JAUNE)
	var y: float = box.position.y + 100
	for a: BkActor in rows:
		draw_circle(Vector2(box.position.x + 40, y - 10), 14, a.color)
		var tag: String = "chasseur" if a == game.hunter else {BkActor.Role.OUT: "échappé", BkActor.Role.GHOST: "trouvé"}.get(a.role, "caché")
		draw_string(font, Vector2(box.position.x + 66, y), "%s — %s%s" % [a.display_name, tag, "  ★" if a.won_round else ""],
			HORIZONTAL_ALIGNMENT_LEFT, 420, 26, Color("ffd34a") if a.won_round else Color.WHITE)
		draw_string(font, Vector2(box.position.x + 480, y), "+%d   %d pts" % [a.round_points, a.score],
			HORIZONTAL_ALIGNMENT_RIGHT, 150, 26, Color.WHITE)
		y += 48


## Bouton « Terminer » : pendant les scores d'une partie rapide (pas au dernier round), avec la
## touche qui fait la même chose selon l'appareil.
func _maj_terminer() -> void:
	var montrer: bool = game.peut_terminer() and not (game.rounds_total > 0 and game.round_no >= game.rounds_total)
	_terminer.visible = montrer
	if montrer:
		# Appareil courant lu sur InputHub par son chemin : pas de dépendance aux autoloads (tests headless).
		var hub: Node = get_node_or_null("/root/InputHub")
		var dev: int = int(hub.get("device")) if hub != null else InputDevice.KEYBOARD
		_terminer.text = {InputDevice.TOUCH: "Terminer la partie",
			InputDevice.GAMEPAD: "Terminer la partie (START)"}.get(dev, "Terminer la partie (ÉCHAP)")
		_terminer.reset_size()
		_terminer.position = Vector2(size.x * 0.5 - _terminer.size.x * 0.5, size.y - 96.0)


## Bulle de l'emote en cours d'un acteur, pointe en `tip`, posée dans la direction `dir` :
## elle apparaît en rebondissant et disparaît en se rétractant.
func _emote_bubble(a: BkActor, tip: Vector2, dir: Vector2) -> void:
	if a.emote < 0 or a.emote_t <= 0.0:
		return
	var age: float = BkRules.f("emote_duration") - a.emote_t
	var k: float = clampf(age / 0.18, 0.0, 1.0) * clampf(a.emote_t / 0.15, 0.0, 1.0)
	var r: float = 38.0 * (k + sin(k * PI) * 0.18)
	if r < 3.0:
		return
	BkDraw.emote_bubble(self, tip + dir.normalized() * (r + 14.0 * k), tip, a.emote, r)


## Petit bouton d'emote et, ouvert, l'éventail des 6 bulles (touches 1 à 6 rappelées au clavier).
func _draw_emote_wheel(font: Font) -> void:
	var inp: BkInput = game.input
	if not inp.emotes_enabled:
		return
	var c: Vector2 = inp.emote_center()
	draw_circle(c, BkInput.EMOTE_RADIUS + 6, Color(0, 0, 0, 0.45))
	BkDraw.emote_disc(self, c, BkInput.EMOTE_RADIUS, 1, Color("ffd34a") if inp.wheel_open else Color(0, 0, 0, 0))
	if not inp.wheel_open:
		return
	for i: int in BkGame.EMOTES.size():
		var b: Vector2 = inp.bubble_center(i)
		BkDraw.emote_disc(self, b, BkInput.BUBBLE_RADIUS, i, Color("ffd34a") if i == inp.wheel_sel else Color(0, 0, 0, 0))
		if not inp.touch_used:
			draw_circle(b + Vector2(28, 26), 13, BkDraw.INK)
			_text(font, b + Vector2(28, 33), str(i + 1), 20, Color.WHITE)


func _text(font: Font, at: Vector2, text: String, fsize: int, col: Color) -> void:
	draw_string(font, Vector2(at.x - 400, at.y), text, HORIZONTAL_ALIGNMENT_CENTER, 800, fsize, col)
