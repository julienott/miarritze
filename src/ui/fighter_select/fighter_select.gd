extends Control
## Sélection des combattants (SPEC §10.5) : grille 6×2 de portraits,
## curseur J1 rouge / J2 vert, grand aperçu animé de chaque côté, nom,
## titre, archétype en 3 jauges, costume avec Haut/Bas (verrous visibles).
## Modes : "tower" (J1 + difficulté), "versus" (J1 + J2), "training" (J1),
## "quick" (combat rapide : mon combattant, puis l'adversaire piloté par
## l'ordi, puis le décor ; une case « Au hasard » termine la grille).

const CELL: int = 30
const COLS: int = 6
## Case « Au hasard » de la grille (combat rapide).
const RANDOM_ID: String = "?"
const QUICK_TITLES: PackedStringArray = ["Choisis ton combattant", "Choisis ton adversaire"]

var mode: String = "versus"
var ids: PackedStringArray = []
var _cursor: PackedInt32Array = PackedInt32Array([0, 1])
var _costume: PackedInt32Array = PackedInt32Array([0, 0])
var _done: Array[bool] = [false, false]
var _players: int = 1
var _previews: Array[FighterView] = [null, null]
var _info: Array[Label] = []
var _grid: Control
var _picking_difficulty: bool = false
var _font: Font
var _stage_bg: Sprite2D
var _names: Array[Label] = []
var _stats: Array = [[2, 2, 2], [2, 2, 2]]
var _locked: Array[bool] = [false, false]
var _overlay: Control
var _icons: Dictionary = {}
var _countdown: float = -1.0
var _count_label: Label
## Versus sur appareil tactile sans manette : J2 est l'ordinateur (SPEC §3.3 :
## pas de place pour deux manettes virtuelles sur iPhone).
var _vs_cpu: bool = false
## Combat rapide : une seule personne choisit J1 puis J2 (l'ordi), à la suite.
var _quick: bool = false
var _cols: int = COLS
var _head: Label
var _marks: Control


func _ready() -> void:
	AudioManager.play_music(&"select")
	mode = str(SceneRouter.params.get("mode", "versus"))
	_quick = mode == "quick"
	_players = 2 if mode == "versus" or _quick else 1
	_vs_cpu = mode == "versus" and Settings.touch_enabled() and Input.get_connected_joypads().is_empty()
	_font = load("res://assets/fonts/press_start_2p.ttf")
	ids = Roster.FIGHTERS.duplicate()
	if bool(Profiles.active().get("unlocks", {}).get("boss", false)) or OS.get_cmdline_user_args().has("--unlock-all"):
		ids.append(Roster.BOSS)
	if _quick:
		ids.append(RANDOM_ID)
	# Toujours deux rangées : la grille s'élargit plutôt que de déborder (boss, « ? »).
	_cols = maxi(COLS, ceili(ids.size() / 2.0))
	_stage_bg = Sprite2D.new()
	_stage_bg.centered = false
	_stage_bg.modulate = Color(0.55, 0.55, 0.65)
	add_child(_stage_bg)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.09, 0.06, 0.1, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_head = UiKit.title({"tower": "PYRAMIDE DU PHARE", "versus": "VERSUS",
		"training": "ENTRAÎNEMENT", "online": "EN LIGNE"}.get(mode, QUICK_TITLES[0]),
		UiKit.C_GOLD if _quick else UiKit.C_RED)
	_head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_head.position.y = 4
	add_child(_head)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 3
	_overlay.draw.connect(_draw_overlay)
	for icon: String in ["punch", "espadrille", "lauburu", "lock", "star"]:
		var ip: String = "res://assets/ui/icon_%s.png" % icon
		if ResourceLoader.exists(ip):
			_icons[icon] = load(ip)
	_grid = Control.new()
	_grid.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	add_child(_grid)
	_grid.draw.connect(_draw_grid)
	_build_cells()
	# Curseurs et étiquettes PAR-DESSUS les portraits (le dessin de la grille
	# elle-même passe sous ses cases).
	_marks = Control.new()
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_cursors)
	_grid.add_child(_marks)
	_grid.draw.connect(_marks.queue_redraw)
	add_child(_overlay)
	for p: int in 2:
		var info: Label = UiKit.label("", 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_LEFT if p == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
		info.size = Vector2(150, 30)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(info)
		_info.append(info)
	if mode == "versus" and not _vs_cpu:
		InputHub.set_versus()
	else:
		InputHub.set_solo()
	var back: Button = UiKit.button("Retour", _back, 60)
	back.position = Vector2(4, 4)
	back.focus_mode = Control.FOCUS_NONE
	add_child(back)
	var ok: Button = UiKit.button("OK", func() -> void: _confirm(0 if not _done[0] else (1 if _players == 2 else 0)), 48)
	ok.name = "OkButton"
	ok.focus_mode = Control.FOCUS_NONE
	add_child(ok)
	get_viewport().size_changed.connect(_layout)
	_layout()
	if _quick:
		_restore_quick()
	else:
		for p: int in _players:
			_refresh(p)
	if _vs_cpu:
		var sub: Label = UiKit.label("contre l'ordi", 8, UiKit.C_GOLD)
		sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
		sub.position.y = 24
		add_child(sub)
	if _players == 1:
		_refresh_cpu()
	_hint = UiKit.label("", 8, UiKit.C_LINEN)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	Prompts.bind(_hint, _hint_text)
	_layout()
	if mode == "online":
		# Favori du profil présélectionné ; 30 s pour choisir (§3.4).
		var fav: int = ids.find(str(Profiles.active().get("fighter", "louis")))
		if fav >= 0:
			_cursor[0] = fav
			_costume[0] = int(Profiles.active().get("costume", 0))
			_refresh(0)
		_countdown = float(OnlineMode.PICK_SECONDS)
		_count_label = UiKit.label("", 16, UiKit.C_GOLD)
		_count_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_count_label.position.y = 22
		add_child(_count_label)
		if not OnlineMode.qa.is_empty():
			_countdown = 1.5



func _process(delta: float) -> void:
	if _countdown < 0.0 or _done[0]:
		return
	_countdown -= delta
	_count_label.text = str(ceili(maxf(_countdown, 0.0)))
	if _countdown <= 0.0:
		if not _costume_ok(ids[_cursor[0]], _costume[0]):
			_costume[0] = 0
		_confirm(0)


func _layout() -> void:
	var w: float = get_viewport_rect().size.x
	_grid.position = Vector2(floorf((w - _cols * CELL) * 0.5), get_viewport_rect().size.y - 2 * CELL - 8)
	_grid.size = Vector2(_cols * CELL, 2 * CELL)
	for p: int in 2:
		if _previews[p] != null:
			_previews[p].position = Vector2(48 if p == 0 else w - 48, 204)
		_info[p].position = Vector2(4 if p == 0 else w - 154, 46)
	if _hint != null:
		_hint.position = Vector2(0, _grid.position.y - 12)
		_hint.size = Vector2(w, 10)
	var ok: Node = get_node_or_null("OkButton")
	if ok != null:
		(ok as Control).position = Vector2(w - 52, 4)


func _build_cells() -> void:
	for i: int in ids.size():
		var clip: Control = Control.new()
		clip.clip_contents = true
		clip.size = Vector2(CELL - 2, CELL - 2)
		clip.position = Vector2((i % _cols) * CELL + 1, (i / _cols) * CELL + 1)
		clip.mouse_filter = Control.MOUSE_FILTER_STOP
		clip.gui_input.connect(_on_cell_input.bind(i))
		var bg: ColorRect = ColorRect.new()
		bg.color = Color8(150, 104, 62) if i < 12 else Color8(44, 60, 110)
		bg.size = clip.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(bg)
		if ids[i] == RANDOM_ID:
			# Case « Au hasard » : gros point d'interrogation doré sur fond mer.
			bg.color = UiKit.C_SEA
			var q: Label = UiKit.label("?", 16, UiKit.C_GOLD)
			q.size = clip.size
			q.position.y = 2
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q.mouse_filter = Control.MOUSE_FILTER_IGNORE
			clip.add_child(q)
		else:
			clip.add_child(PortraitView.create(ids[i]))
		_grid.add_child(clip)


func _on_cell_input(event: InputEvent, index: int) -> void:
	var tapped: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	# Sur iPhone, Godot émule aussi un clic souris à partir du toucher : sans ce
	# filtre, un seul tap choisissait ET validait le perso.
	# Inversement, à la souris (web sur ordinateur), le projet émule un toucher
	# (emulate_touch_from_mouse) : un clic valait deux taps.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if not tapped or _picking_difficulty:
		return
	var p: int = 0 if not _done[0] else (1 if _players == 2 else 0)
	if _done[p]:
		return
	if _cursor[p] == index:
		_confirm(p)
	else:
		_cursor[p] = index
		_costume[p] = 0
		AudioManager.sfx(&"ui_move")
		_refresh(p)


func _is_random(p: int) -> bool:
	return ids[_cursor[p]] == RANDOM_ID


func _refresh(p: int) -> void:
	var id: String = ids[_cursor[p]]
	var random: bool = id == RANDOM_ID
	# Combat rapide en miroir : l'ordi prend d'office un autre costume.
	if _quick and p == 1 and id == ids[_cursor[0]] and _costume[1] == _costume[0]:
		_costume[1] = (_costume[0] + 1) % 4
	if _previews[p] != null:
		_previews[p].queue_free()
	# « Au hasard » : silhouette mystère (noire, contour doré).
	var shown: String = ids[p] if random else id
	_previews[p] = UiKit.fighter_preview(shown, 0 if random else _costume[p], "idle", 1 if p == 0 else -1)
	_previews[p].z_index = 2
	if random:
		_previews[p].set_silhouette(true)
	add_child(_previews[p])
	var data: Dictionary = {"name": "Au hasard"} if random else FighterDb.load_json(id)
	var stats: Dictionary = data.get("stats", {})
	_stats[p] = [int(stats.get("power", 2)), int(stats.get("speed", 2)), int(stats.get("reach", 2))]
	_locked[p] = not _costume_allowed(p)
	if random:
		_info[p].text = "Surprise !"
	else:
		# Le costume se change toujours en touchant l'aperçu ou haut/bas, sans libellé.
		_info[p].text = str(data.get("title", ""))
	_info[p].visible = true
	_overlay.queue_redraw()
	while _names.size() <= p:
		var nl: Label = UiKit.title("")
		nl.size = Vector2(150, 18)
		add_child(nl)
		_names.append(nl)
	_names[p].text = UiKit.euskal_text(str(data.get("name", id)))
	_names[p].visible = true
	_names[p].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if p == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	# Nom en lettrage basque, au-dessus de la tête du grand aperçu.
	_names[p].position = Vector2(4 if p == 0 else get_viewport_rect().size.x - 154, 28)
	if p == 0 and not random:
		_show_home_stage(id)
	_layout()
	_grid.queue_redraw()


## Combat rapide : efface le côté de l'adversaire (retour à la 1re étape).
func _hide_side(p: int) -> void:
	if _previews[p] != null:
		_previews[p].queue_free()
		_previews[p] = null
	if p < _names.size():
		_names[p].visible = false
	_info[p].visible = false
	_overlay.queue_redraw()
	_grid.queue_redraw()


## Combat rapide : étape 0 (mon combattant) ou 1 (l'adversaire).
func _quick_step(step: int) -> void:
	_head.text = UiKit.euskal_text(QUICK_TITLES[step])
	if step == 0:
		_hide_side(1)
	else:
		_refresh(1)


## Combat rapide : état initial (favori du profil) ou rétabli au retour du
## choix du décor (`sel1`/`sel2` = choix d'origine, « ? » compris).
func _restore_quick() -> void:
	var params: Dictionary = SceneRouter.params
	_cursor[0] = maxi(ids.find(str(params.get("sel1", Profiles.active().get("fighter", "louis")))), 0)
	_costume[0] = int(params.get("cc1", Profiles.active().get("costume", 0)))
	if _is_random(0) or not _costume_ok(ids[_cursor[0]], _costume[0]):
		_costume[0] = 0
	# L'adversaire démarre sur « Au hasard » : trois validations = l'ancien
	# combat rapide (mon perso, adversaire et décor au hasard).
	var opp: int = ids.find(str(params.get("sel2", RANDOM_ID)))
	_cursor[1] = opp if opp >= 0 else ids.size() - 1
	_costume[1] = int(params.get("cc2", 0))
	_refresh(0)
	if int(params.get("step", 0)) == 1:
		_done[0] = true
		_previews[0].play_preview("win", 1)
		_quick_step(1)
	else:
		_quick_step(0)


## Retour : annule l'étape en cours (combat rapide), sinon menu principal.
## Rappel des commandes au-dessus de la grille (rien au doigt : on touche).
## Versus au clavier : chacun ses touches, pas de place pour les deux.
func _hint_text() -> String:
	if mode == "versus" and _players == 2 and Prompts.kind() == Prompts.KEYBOARD:
		return ""
	return Prompts.pick({Prompts.GAMEPAD: "{ok} : choisir  {back} : retour",
		Prompts.KEYBOARD: "{punch} : choisir  {kick} : retour"})


var _hint: Label


func _back() -> void:
	if _picking_difficulty:
		return
	if mode == "online":
		OnlineMode.leave()
	elif _quick and _done[0]:
		_done[0] = false
		AudioManager.sfx(&"ui_move")
		_previews[0].play_preview("idle", 1)
		_quick_step(0)
	else:
		SceneRouter.goto(&"main_menu")


## Toucher le grand aperçu d'un joueur change son costume (pas de flèches au doigt).
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) or _picking_difficulty:
		return
	var pos: Vector2 = (event as InputEventScreenTouch).position
	var w: float = get_viewport_rect().size.x
	var h: float = get_viewport_rect().size.y
	if pos.y < h * 0.4:
		return
	var p: int = -1
	if pos.x < 110.0:
		p = 0
	elif pos.x > w - 110.0 and _players == 2:
		p = 1
	if p < 0 or _done[p] or (p == 1 and not _done[0]) or _is_random(p):
		return
	AudioManager.sfx(&"ui_move")
	_cycle_costume(p, 1)
	accept_event()


func _refresh_cpu() -> void:
	if mode != "versus":
		_info[1].text = "" if mode == "tower" else "HONDAR\nBonhomme de sable"
		if mode == "training" and _previews[1] == null:
			_previews[1] = UiKit.fighter_preview(Roster.DUMMY, 0, "idle", -1)
			add_child(_previews[1])
			_layout()


## Stage maison du perso en fond (assombri), sinon un ancien décor.
func _show_home_stage(id: String) -> void:
	var stage: String = Roster.home_stage(id).replace("_soir", "").replace("_crepuscule", "")
	var path: String = "res://assets/stages/%s/far_v_0.png" % stage
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/%s_0.png" % str(StageView.FALLBACK_BG.get(stage, "bg_beach"))
		if not ResourceLoader.exists(path):
			path = "res://assets/sprites/bg_beach_0.png"
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var small: Vector2i = Vector2i(maxi(img.get_width() / 4, 1), maxi(img.get_height() / 4, 1))
	img.resize(small.x, small.y, Image.INTERPOLATE_BILINEAR)
	img.resize(small.x * 4, small.y * 4, Image.INTERPOLATE_BILINEAR)
	_stage_bg.texture = ImageTexture.create_from_image(img)
	var w: float = get_viewport_rect().size.x
	var f: float = maxf(w / _stage_bg.texture.get_width(), 216.0 / _stage_bg.texture.get_height())
	_stage_bg.scale = Vector2(f, f)
	_stage_bg.position = Vector2((w - _stage_bg.texture.get_width() * f) * 0.5, 0)


## Archétype en 3 jauges d'étoiles + verrou de costume (dessin par-dessus).
func _draw_overlay() -> void:
	var w: float = get_viewport_rect().size.x
	var labels: PackedStringArray = ["Puissance", "Vitesse", "Portée"]
	var shown: int = _players if mode == "versus" else (2 if _quick and _done[0] else 1)
	for p: int in shown:
		if _is_random(p):
			continue
		var right: bool = p == 1
		for row: int in 3:
			var y: float = 84.0 + row * 9.0
			var lx: float = 4.0 if not right else w - 4.0 - 108.0
			_overlay.draw_string(_font, Vector2(lx + 1, y + 8), labels[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.C_OUTLINE)
			_overlay.draw_string(_font, Vector2(lx, y + 7), labels[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.C_LINEN)
			for k: int in 3:
				var on: bool = k < int(_stats[p][row])
				if _icons.has("star"):
					_overlay.draw_texture_rect(_icons["star"], Rect2(lx + 80.0 + k * 9.0, y, 8, 8), false,
						Color(1, 1, 1, 1) if on else Color(0.2, 0.18, 0.22, 0.9))
		if _locked[p] and _icons.has("lock"):
			var kx: float = 76.0 if not right else w - 76.0 - 16.0
			_overlay.draw_texture(_icons["lock"], Vector2(kx, 60))


func _bar(n: int) -> String:
	return "#".repeat(n) + ".".repeat(3 - n)


func _costume_ok(id: String, c: int) -> bool:
	if c == 0 or OS.get_cmdline_user_args().has("--unlock-all"):
		return true
	var unlocks: Dictionary = Profiles.active().get("unlocks", {})
	return (unlocks.get(id, [0]) as Array).has(c)


## Costume jouable ? « Au hasard » toujours ; l'ordi du combat rapide peut
## porter n'importe quel costume (les verrous récompensent le joueur).
func _costume_allowed(p: int) -> bool:
	if _is_random(p) or (_quick and p == 1):
		return true
	return _costume_ok(ids[_cursor[p]], _costume[p])


func _draw_grid() -> void:
	for i: int in ids.size():
		var r: Rect2 = Rect2((i % _cols) * CELL, (i / _cols) * CELL, CELL, CELL)
		_grid.draw_rect(r, UiKit.C_OUTLINE, false, 1.0)


func _draw_cursors() -> void:
	var colors: Array[Color] = [UiKit.C_RED, UiKit.C_GREEN]
	var tags: PackedStringArray = ["TOI", "IA"] if _quick else ["J1", "J2"]
	var cursors: int = (2 if _done[0] else 1) if _quick else _players
	for p: int in cursors:
		var i2: int = _cursor[p]
		var r2: Rect2 = Rect2((i2 % _cols) * CELL, (i2 / _cols) * CELL, CELL, CELL).grow(-p * 2)
		if _done[p]:
			_marks.draw_rect(r2.grow(-2), Color(colors[p], 0.35))
		_marks.draw_rect(r2.grow(-1), colors[p], false, 2.0)
		# Étiquette en bas de case (J2 / IA), en haut pour J1 / TOI : lisibles
		# même quand les deux curseurs sont sur le même perso.
		var at: Vector2 = r2.position + (Vector2(3, 11) if p == 0 else Vector2(3, r2.size.y - 3))
		_marks.draw_string_outline(_font, at, tags[p], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, UiKit.C_OUTLINE)
		_marks.draw_string(_font, at, tags[p], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, colors[p].lightened(0.25))


func _unhandled_input(event: InputEvent) -> void:
	if _picking_difficulty:
		if event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			_cancel_difficulty()
		return
	if _quick:
		# Une seule personne choisit : toutes les touches pilotent l'étape en cours.
		var active: int = 1 if _done[0] else 0
		if not _done[active]:
			_handle_cursor(event, active, ["p1", "p2", "ui"])
		return
	for p: int in _players:
		var prefixes: Array[String] = []
		if _players == 1:
			prefixes.append_array(["p1", "p2", "ui"])
		else:
			prefixes.append("p1" if p == 0 else "p2")
		if _done[p]:
			if _pressed(event, prefixes, ["_kick", "_cancel"]):
				_done[p] = false
				_grid.queue_redraw()
			continue
		_handle_cursor(event, p, prefixes)


## Curseur d'un joueur : gauche/droite = perso, haut/bas = costume,
## coup de poing / Entrée = valider, coup de pied / Échap = retour.
func _handle_cursor(event: InputEvent, p: int, prefixes: Array[String]) -> void:
	var moved: bool = false
	if _pressed(event, prefixes, ["_left"]):
		_cursor[p] = (_cursor[p] + ids.size() - 1) % ids.size()
		moved = true
	elif _pressed(event, prefixes, ["_right"]):
		_cursor[p] = (_cursor[p] + 1) % ids.size()
		moved = true
	elif _pressed(event, prefixes, ["_up"]) and not _is_random(p):
		_cycle_costume(p, 3)
	elif _pressed(event, prefixes, ["_down"]) and not _is_random(p):
		_cycle_costume(p, 1)
	elif _pressed(event, prefixes, ["_punch", "_accept"]):
		_confirm(p)
	elif _pressed(event, prefixes, ["_kick", "_cancel"]):
		_back()
	if moved:
		_costume[p] = 0
		AudioManager.sfx(&"ui_move")
		_refresh(p)


## Costume suivant (step 1) ou précédent (step 3) ; en miroir (combat rapide),
## on saute le costume déjà porté par mon combattant.
func _cycle_costume(p: int, step: int) -> void:
	_costume[p] = (_costume[p] + step) % 4
	if _quick and p == 1 and ids[_cursor[1]] == ids[_cursor[0]] and _costume[1] == _costume[0]:
		_costume[p] = (_costume[p] + step) % 4
	_refresh(p)


## Manette : actions de menu (stick/croix, A = valider, B = retour). En
## versus, la 1re manette pilote J1 et la 2e J2 (comme InputHub.set_versus).
const PAD_ACTIONS: Dictionary = {"_left": &"ui_left", "_right": &"ui_right", "_up": &"ui_up",
	"_down": &"ui_down", "_punch": &"ui_accept", "_accept": &"ui_accept", "_kick": &"ui_cancel",
	"_cancel": &"ui_cancel"}


func _pressed(event: InputEvent, prefixes: Array[String], suffixes: Array) -> bool:
	if InputDevice.is_pad(event):
		var slot: int = InputDevice.pad_slot(event)
		var shared: bool = prefixes.has("ui") or (prefixes.has("p1") and prefixes.has("p2"))
		if not shared and not ((prefixes.has("p1") and slot == 0) or (prefixes.has("p2") and slot == 1)):
			return false
		for suffix: String in suffixes:
			if PAD_ACTIONS.has(suffix) and event.is_action_pressed(PAD_ACTIONS[suffix]):
				return true
		return false
	for prefix: String in prefixes:
		for suffix: String in suffixes:
			if InputMap.has_action(prefix + suffix) and event.is_action_pressed(prefix + suffix):
				return true
	return false


func _confirm(p: int) -> void:
	if _done[p] or _picking_difficulty:
		return
	if not _costume_allowed(p):
		AudioManager.sfx(&"ui_no")
		return
	_done[p] = true
	AudioManager.sfx(&"ui_ok")
	_grid.queue_redraw()
	if _previews[p] != null:
		_previews[p].play_preview("win", 1 if p == 0 else -1)
	if _quick and p == 0:
		_quick_step(1)
		return
	for q: int in _players:
		if not _done[q]:
			return
	_proceed()


func _proceed() -> void:
	var p1: String = ids[_cursor[0]]
	match mode:
		"tower":
			_ask_difficulty()
		"training":
			InputHub.set_solo()
			SceneRouter.goto(&"fight", TrainingMode.fight_params(p1, _costume[0]))
		"online":
			OnlineMode.my_pick = {"fighter": p1, "costume": _costume[0],
				"pseudo": str(Profiles.active().get("pseudo", "?")), "express": Settings.express_fights}
			# Celui qui a défié choisit la map ; l'autre attend directement la connexion.
			if OnlineMode.is_host():
				SceneRouter.goto(&"stage_select", {"mode": "online"})
			else:
				SceneRouter.goto(&"online_connect")
		"quick":
			_start_quick()
		_:
			if _vs_cpu:
				_ask_difficulty()
				return
			var p2: String = ids[_cursor[1]]
			var c2: int = _costume[1]
			if p2 == p1 and c2 == _costume[0]:
				c2 = (c2 + 1) % 4
			SceneRouter.goto(&"stage_select", {"p1": p1, "c1": _costume[0], "p2": p2, "c2": c2})


## Combat rapide : tire les « Au hasard », puis passe au choix du décor.
## L'ordi joue au niveau de la difficulté par défaut des réglages.
func _start_quick() -> void:
	var p1: String = ids[_cursor[0]]
	var c1: int = _costume[0]
	if p1 == RANDOM_ID:
		p1 = Roster.FIGHTERS[randi() % Roster.FIGHTERS.size()]
		c1 = 0
	var p2: String = ids[_cursor[1]]
	var c2: int = _costume[1]
	if p2 == RANDOM_ID:
		var others: Array[String] = []
		for id: String in Roster.FIGHTERS:
			if id != p1:
				others.append(id)
		p2 = others[randi() % others.size()]
		c2 = 0
	# Miroir : costume différent pour qu'on se reconnaisse.
	if p2 == p1 and c2 == c1:
		c2 = (c2 + 1) % 4
	var r: Array = TowerMode.SKILL_RANGE[clampi(Settings.default_difficulty, 0, TowerMode.SKILL_RANGE.size() - 1)]
	InputHub.set_solo()
	SceneRouter.goto(&"stage_select", {"mode": "quick", "p1": p1, "c1": c1, "p2": p2, "c2": c2,
		"ai_level": (int(r[0]) + int(r[1])) / 2,
		"sel1": ids[_cursor[0]], "cc1": _costume[0], "sel2": ids[_cursor[1]], "cc2": _costume[1]})


func _ask_difficulty() -> void:
	_picking_difficulty = true
	_difficulty_box = Control.new()
	_difficulty_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_difficulty_box.z_index = 10
	add_child(_difficulty_box)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.1, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_difficulty_box.add_child(shade)
	var label: Label = UiKit.label("Difficulté ?", 16, UiKit.C_GOLD)
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.position.y = 40
	_difficulty_box.add_child(label)
	var buttons: Array = []
	for d: int in 3:
		buttons.append(UiKit.button(TowerMode.DIFFICULTY_NAMES[d],
			(_start_vs_cpu if _vs_cpu else _start_tower).bind(d)))
	buttons.append(UiKit.button("Retour", _cancel_difficulty))
	UiKit.menu_column(_difficulty_box, buttons, 66)
	UiKit.prompt_bar(_difficulty_box)


var _difficulty_box: Control


## Retour depuis le choix de difficulté : on rechoisit son combattant.
func _cancel_difficulty() -> void:
	if _difficulty_box != null:
		_difficulty_box.queue_free()
		_difficulty_box = null
	_picking_difficulty = false
	for p: int in 2:
		if _done[p]:
			_done[p] = false
			if _previews[p] != null:
				_previews[p].play_preview("idle", 1 if p == 0 else -1)
	_grid.queue_redraw()


func _start_vs_cpu(difficulty: int) -> void:
	var p1: String = ids[_cursor[0]]
	var p2: String = ids[_cursor[1]]
	var c2: int = _costume[1]
	if p2 == p1 and c2 == _costume[0]:
		c2 = (c2 + 1) % 4
	var r: Array = TowerMode.SKILL_RANGE[difficulty]
	SceneRouter.goto(&"stage_select", {"p1": p1, "c1": _costume[0], "p2": p2, "c2": c2,
		"ai_level": (int(r[0]) + int(r[1])) / 2})


func _start_tower(difficulty: int) -> void:
	TowerMode.start(ids[_cursor[0]], _costume[0], difficulty)
	InputHub.set_solo()
	SceneRouter.goto(&"tower", {"event": "start"})
