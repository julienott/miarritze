class_name BkHud
extends Control
## Interface du round (GDD-BLACKOUT.md), en 640×360 et police pixel (§9 : HUD minimal) : rôle,
## chrono, messages, bouton d'action (nom et icône du coup spécial du rôle, qui se remplit pendant la
## recharge, GDD §4.1), écran du joueur aveuglé (§4.5), joystick tactile, flèche vers le
## chasseur hors champ, voile du chasseur qui compte, scores entre les rounds (« Round k/N », bouton
## « Terminer » en partie rapide). Versus et podium sont des écrans à part (BkVersus, BkPodium, en
## 1280×720) : le HUD s'y efface.

## Tailles de texte (px de l'écran 640×360) : petit, normal, grand.
const PETIT: int = 8
const NORMAL: int = 16
const GRAND: int = 32
## Portraits (GDD §8.1) : celui du joueur local à côté de son rôle, ceux de la table des scores (px).
const PORTRAIT_ROLE: int = 32
const PORTRAIT_SCORES: int = 14

var game: BkGame
var _quit: Button
## Partie rapide : arrêter la partie pendant les scores, podium tout de suite (GDD-BLACKOUT.md).
var _terminer: Button
## Vignettage du chassé local (idee_frisson) : bords sombres et rougeâtres, centre libre.
var _vignette: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quit = Button.new()
	_quit.text = "Quitter"
	_quit.focus_mode = Control.FOCUS_NONE
	_quit.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quit.offset_left = -60
	_quit.offset_top = 6
	_quit.offset_right = -6
	_quit.offset_bottom = 24
	_quit.pressed.connect(func() -> void: game.quit_to_podium())
	add_child(_quit)
	# Debug et visite : boutons Formes, Lumière et Perso, pour le tactile (touches F, L, C).
	_debug_buttons()
	_terminer = Button.new()
	_terminer.text = "Terminer la partie"
	_terminer.pressed.connect(func() -> void: game.quit_to_podium())
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
	_vignette.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
func _draw_frisson(s: Vector2) -> void:
	var f: BkFrisson = game.frisson
	if f == null:
		return
	if f.level > 0.01:
		# Le cœur bat : le voile fonce un instant à chaque battement.
		_vignette.modulate.a = clampf((0.3 + 0.7 * f.level) * (0.75 + 0.25 * f.beat), 0.0, 1.0)
	_vignette.visible = f.level > 0.01
	if f.search_near > 0.0:
		var k: float = clampf(f.search_near / 0.3, 0.0, 1.0)
		var wob: float = roundf(sin(Time.get_ticks_msec() * 0.03) * 1.5)
		var at: Vector2 = Vector2(s.x * 0.5 + wob, s.y - 70.0)
		draw_rect(Rect2(at - Vector2(90, 14), Vector2(180, 20)), Color(0, 0, 0, 0.55 * k))
		_text(at, "Il fouille à côté !", NORMAL, Color(Color("ffd34a"), k))


func _debug_buttons() -> void:
	if game == null or (game.visite == "" and not game.debug):
		return
	var specs: Array = [["Formes", game.visite_toggle_formes], ["Lumière", game.debug_toggle_lumiere],
		["Perso", game.visite_next_character]]
	for i: int in specs.size():
		var b: Button = Button.new()
		b.text = str(specs[i][0])
		b.focus_mode = Control.FOCUS_NONE
		b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		b.offset_left = -120 - i * 56
		b.offset_right = -68 - i * 56
		b.offset_top = 6
		b.offset_bottom = 24
		b.pressed.connect(specs[i][1])
		add_child(b)


func _draw() -> void:
	if game == null or game.local == null:
		return
	var s: Vector2 = size
	var me: BkActor = game.local
	# Versus et podium : écrans de menu par-dessus, le HUD s'efface.
	var ecran: bool = game.phase == BkGame.Phase.PODIUM or game.phase == BkGame.Phase.VERSUS
	_quit.visible = not ecran
	_maj_terminer()
	if ecran:
		_vignette.visible = false
		return
	# Voile du chasseur qui compte (il ne voit rien pendant la cachette).
	if game.phase == BkGame.Phase.HIDE and me == game.hunter:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.03, 0.07, 0.96))
		var n: int = clampi(int(BkRules.f("phase_hide") - game.phase_t) + 1, 1, BkGame.COUNT_WORDS.size())
		_text(s * Vector2(0.5, 0.45), BkGame.COUNT_WORDS[n - 1].capitalize() + "…", GRAND, Color.WHITE)
		_text(s * Vector2(0.5, 0.6), "Tu comptes, les autres se cachent", NORMAL, Color(1, 1, 1, 0.7))
	# Joueur aveuglé (effet commun) : écran noir ou bleu, sa silhouette seule (GDD §4.3, §4.5).
	BkEffetsRendu.ecran(self, game)
	_draw_frisson(s)
	# Bandeau du haut : rôle, phase, chrono.
	var role_text: String = {BkActor.Role.HIDER: "CHASSÉ", BkActor.Role.HUNTER: "CHASSEUR",
		BkActor.Role.GHOST: "FANTÔME", BkActor.Role.OUT: "ÉCHAPPÉ"}[me.role]
	var role_col: Color = {BkActor.Role.HIDER: Color("4aa3ff"), BkActor.Role.HUNTER: Color("ff3b30"),
		BkActor.Role.GHOST: Color("b8c0cc"), BkActor.Role.OUT: Color("6fe08a")}[me.role]
	draw_rect(Rect2(6, 6, 84 + PORTRAIT_ROLE + 4, PORTRAIT_ROLE + 4), Color(0, 0, 0, 0.55))
	draw_texture_rect(BkPerso.portrait_tex(me.character, PORTRAIT_ROLE), Rect2(8, 8, PORTRAIT_ROLE, PORTRAIT_ROLE), false)
	_text(Vector2(48 + PORTRAIT_ROLE + 4, 28), role_text, NORMAL, role_col)
	if game.debug and game.visite == "":
		_text(Vector2(48 + PORTRAIT_ROLE + 4, 52), "DEBUG · F · L", PETIT, Color("ffd34a"))
	if game.visite != "":
		# Visite de debug (temporaire) : pas de chrono, un bandeau discret.
		draw_rect(Rect2(s.x * 0.5 - 110, 6, 220, 14), Color(0, 0, 0, 0.45))
		_text(Vector2(s.x * 0.5, 16), "VISITE (debug) · F formes · L lumière · C perso · G fantôme", PETIT, Color("ffd34a"))
	else:
		var phase_text: String = {BkGame.Phase.DRAW: "Tirage…", BkGame.Phase.HIDE: "Cachez-vous !",
			BkGame.Phase.HUNT: "Chasse", BkGame.Phase.END: "Fin du round"}.get(game.phase, "")
		var no: String = "%d/%d" % [game.round_no, game.rounds_total] if game.rounds_total > 0 else str(game.round_no)
		var t: int = maxi(0, ceili(game.phase_t))
		draw_rect(Rect2(s.x * 0.5 - 60, 4, 120, 32), Color(0, 0, 0, 0.55))
		_text(Vector2(s.x * 0.5, 14), "%s · round %s" % [phase_text, no], PETIT, Color(1, 1, 1, 0.85))
		if game.sans_chrono and game.phase == BkGame.Phase.HUNT:
			_text(Vector2(s.x * 0.5, 32), "sans chrono", NORMAL, Color("ffd34a"))
		else:
			_text(Vector2(s.x * 0.5, 32), "%d:%02d" % [t / 60, t % 60], NORMAL,
				Color("ff6b5e") if game.phase == BkGame.Phase.HUNT and t <= 20 else Color.WHITE)
		var left: int = game.actors.filter(func(a: BkActor) -> bool: return a.role == BkActor.Role.HIDER).size()
		_text(Vector2(s.x * 0.5, 46), "%d chassé%s encore libre%s" % [left, "s" if left > 1 else "", "s" if left > 1 else ""],
			PETIT, Color(1, 1, 1, 0.8))
		if not game.open_exit_zones.is_empty() and (game.phase == BkGame.Phase.HIDE or game.phase == BkGame.Phase.HUNT):
			var where: String = " et ".join(game.open_exit_zones)
			if game.exits_open():
				_text(Vector2(s.x * 0.5, 57), "Sorties ouvertes : " + where, PETIT, Color("6fe08a"))
			else:
				_text(Vector2(s.x * 0.5, 57), "Sorties du round : " + where, PETIT, Color(1, 1, 1, 0.7))
		# Secteurs dans le noir (disjoncteur coupé), avec le temps avant le retour de la lumière.
		var noirs: PackedStringArray = []
		for k: Variant in game.pannes:
			var reste: float = float(game.pannes[k])
			noirs.append(game.map.secteur_nom(str(k)) + ("" if reste > 1.0e8 else " %d s" % ceili(reste)))
		if not noirs.is_empty() and game.phase == BkGame.Phase.HUNT:
			_text(Vector2(s.x * 0.5, 68), "Dans le noir : " + ", ".join(noirs), PETIT, Color("9fd8ef"))
	# Fantôme : ce qu'il peut encore faire (délivrance).
	if me.role == BkActor.Role.GHOST and game.phase == BkGame.Phase.HUNT and BkRules.on("idee_delivrance") \
			and not me.rescued and game._rescues < int(BkRules.f("delivrance_max")):
		draw_rect(Rect2(s.x * 0.5 - 100, s.y - 26, 200, 16), Color(0, 0, 0, 0.55))
		_text(Vector2(s.x * 0.5, s.y - 14), "Rejoins un chassé : il te délivre !", PETIT, Color("ffd34a"))
	# Messages.
	var y: float = roundf(s.y * 0.26)
	for m: Dictionary in game.messages:
		_text(Vector2(s.x * 0.5, y), str(m["text"]), NORMAL, m["color"])
		y += 20
	# Flèche vers le chasseur quand il est hors champ (chassés et fantômes).
	if me != game.hunter and game.hunter and game.hunter.visible and game.phase == BkGame.Phase.HUNT:
		var sp: Vector2 = game.screen_pos(game.hunter.position)
		var r: Rect2 = Rect2(Vector2.ZERO, s).grow(-16)
		if not r.has_point(sp):
			var c: Vector2 = s * 0.5
			var d: Vector2 = (sp - c).normalized()
			var k: float = minf(absf((r.size.x * 0.5) / maxf(absf(d.x), 0.001)), absf((r.size.y * 0.5) / maxf(absf(d.y), 0.001)))
			var p: Vector2 = (c + d * k).round()
			var pts: PackedVector2Array = [p + d * 10, p + d.orthogonal() * 6 - d * 4, p - d.orthogonal() * 6 - d * 4]
			draw_colored_polygon(pts, Color("ff3b30"))
	# Bouton d'action.
	var label: String = game.action_label(me)
	if label != "" and game.phase in [BkGame.Phase.HIDE, BkGame.Phase.HUNT] and not me.frozen:
		var c2: Vector2 = game.input.action_center()
		var cd: float = game.action_cooldown(me)
		var rr: float = BkInput.ACTION_RADIUS
		# Coup spécial : son icône et son nom ; gris s'il n'est pas encore codé (« bientôt ») ou hors de
		# la chasse ; pendant la recharge, la couleur remonte du bas et l'anneau blanc se referme.
		var coup: bool = game.action_est_coup(me)
		var cdata: Dictionary = game.coups.coup(me)
		var bientot: bool = coup and not BkCoups.code(cdata)
		var attente: bool = coup and game.phase != BkGame.Phase.HUNT
		var fond: Color = Color("ff3b30") if me == game.hunter else Color("4aa3ff")
		if bientot or attente:
			fond = Color("6a6f7c")
		draw_circle(c2, rr, Color(0, 0, 0, 0.45))
		if cd > 0.0:
			draw_circle(c2, rr - 3, fond.darkened(0.65))
			_segment(c2, rr - 3, c2.y + (rr - 3) * (2.0 * cd - 1.0), fond)
			draw_arc(c2, rr - 1.5, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - cd), 32, Color.WHITE, 2.0)
		else:
			draw_circle(c2, rr - 3, fond)
		if coup:
			BkEffetsRendu.icone(self, c2 + Vector2(0, -16), 9.0, str(cdata.get("famille", "")))
			_text(c2 + Vector2(0, 8), label, PETIT, Color.WHITE)
			if bientot or attente:
				_text(c2 + Vector2(0, 20), "bientôt" if bientot else "à la chasse", PETIT, Color("ffd34a"))
			elif cd > 0.0:
				_text(c2 + Vector2(0, 20), "%d s" % ceili(me.coup_cd), PETIT, Color(1, 1, 1, 0.85))
		else:
			_text(c2 + Vector2(0, 5), label, NORMAL, Color.WHITE)
		if me.search_left > 0.0:
			_text(c2 + Vector2(0, -rr - 6), "Fouille…", PETIT, Color.WHITE)
		elif me.use_left > 0.0:
			_text(c2 + Vector2(0, -rr - 6), "Actionne…", PETIT, Color.WHITE)
	# Joystick tactile.
	if game.input.touch_index >= 0:
		draw_circle(game.input.touch_origin, BkInput.STICK_RADIUS, Color(1, 1, 1, 0.15))
		draw_arc(game.input.touch_origin, BkInput.STICK_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.4), 1.0)
		var knob: Vector2 = game.input.touch_origin + (game.input.touch_pos - game.input.touch_origin).limit_length(BkInput.STICK_RADIUS)
		draw_circle(knob, BkInput.STICK_RADIUS * 0.42, Color(1, 1, 1, 0.5))
	# Scores du round.
	if game.phase == BkGame.Phase.END:
		_draw_scores(s)


func _draw_scores(s: Vector2) -> void:
	var rows: Array[BkActor] = game.actors.duplicate()
	rows.sort_custom(func(a: BkActor, b: BkActor) -> bool: return a.score > b.score)
	var h: float = 36.0 + 16.0 * rows.size()
	var box: Rect2 = Rect2(roundf(s.x * 0.5 - 150), roundf(s.y * 0.5 - h * 0.5), 300, h)
	draw_rect(box, Color(0.05, 0.06, 0.1, 0.88))
	var titre: String = "Round %d/%d terminé" % [game.round_no, game.rounds_total] if game.rounds_total > 0 \
		else "Round %d terminé" % game.round_no
	_text(Vector2(s.x * 0.5, box.position.y + 20), titre, NORMAL, Color.WHITE)
	if game.rounds_total > 0 and game.round_no >= game.rounds_total:
		_text(Vector2(s.x * 0.5, box.end.y + 16), "Dernier round : place au podium !", NORMAL, BkUi.JAUNE)
	var y: float = box.position.y + 42
	var f: Font = BkDraw.police()
	for a: BkActor in rows:
		var tag: String = "chasseur" if a == game.hunter else {BkActor.Role.OUT: "échappé", BkActor.Role.GHOST: "trouvé"}.get(a.role, "caché")
		draw_texture_rect(BkPerso.portrait_tex(a.character, PORTRAIT_SCORES), Rect2(box.position.x + 8, y - 11,
			PORTRAIT_SCORES, PORTRAIT_SCORES), false)
		draw_string(f, Vector2(box.position.x + 26, y), "%s — %s%s" % [a.display_name, tag, "  ★" if a.won_round else ""],
			HORIZONTAL_ALIGNMENT_LEFT, 184, PETIT, Color("ffd34a") if a.won_round else Color.WHITE)
		draw_string(f, Vector2(box.position.x + 210, y), "+%d   %d pts" % [a.round_points, a.score],
			HORIZONTAL_ALIGNMENT_RIGHT, 80, PETIT, Color.WHITE)
		y += 16


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
		_terminer.position = Vector2(roundf(size.x * 0.5 - _terminer.size.x * 0.5), size.y - 40.0)


## Partie d'un disque de centre `c` et de rayon `r` sous la ligne y = `niveau` (remplissage du bouton).
func _segment(c: Vector2, r: float, niveau: float, col: Color) -> void:
	if niveau >= c.y + r - 0.5:
		return
	# Arc sous la corde (y vers le bas) : de asin(h/r) à π − asin(h/r).
	var a0: float = asin(clampf((niveau - c.y) / r, -1.0, 1.0))
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 33:
		pts.append(c + Vector2.from_angle(lerpf(a0, PI - a0, float(i) / 32.0)) * r)
	draw_colored_polygon(pts, col)


func _text(at: Vector2, text: String, fsize: int, col: Color) -> void:
	BkDraw.texte(self, at, text, fsize, col, 2 if fsize < NORMAL else 3, 600.0)
