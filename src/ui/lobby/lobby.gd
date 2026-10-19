extends Control
## Salon en ligne (SPEC §3.4, §10.5) : une plage où chaque copain du groupe
## en ligne se promène (son combattant en miniature, sa carte au-dessus).
## Toucher un copain = le défier (20 s pour accepter). Match rapide.
## Aucun texte libre : seulement pseudos, titres et emotes prédéfinies.

const HEARTBEAT: float = 5.0
const QUICK_HEARTBEAT: float = 1.0

var _members: Array = []
var _walkers: Dictionary = {}       # player_id -> {view, x, dir, card}
var _status: String = "lobby"
var _hb_t: float = 99.0
var _info: Label
var _invite_box: Control
var _shown_invite: int = 0
var _font: Font
var _ground: Control


func _ready() -> void:
	AudioManager.play_music(&"select")
	_font = load("res://assets/fonts/press_start_2p.ttf")
	UiKit.backdrop(self, "bg_beach", 0.15)
	var head: Label = UiKit.title("SALON EN LIGNE")
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 4
	add_child(head)
	var back: Button = UiKit.button("Retour", _leave, 60)
	back.position = Vector2(4, 4)
	add_child(back)
	_info = UiKit.label("", 8, UiKit.C_LINEN)
	_info.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_info.position.y = 26
	add_child(_info)
	_ground = Control.new()
	_ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ground)
	var quick: Button = UiKit.button("Match rapide", _quick_match, 110)
	quick.position = Vector2(get_viewport_rect().size.x - 114, get_viewport_rect().size.y - 28)
	add_child(quick)
	var board: Button = UiKit.button("Classement", _show_board, 90)
	board.position = Vector2(4, get_viewport_rect().size.y - 28)
	add_child(board)
	# Clavier / manette : on ne peut pas « toucher » un copain → liste à choisir.
	var pick: Button = UiKit.button("Défier un copain", _show_pick, 130)
	pick.position = Vector2(roundf(get_viewport_rect().size.x * 0.5 - 65), get_viewport_rect().size.y - 28)
	add_child(pick)
	_pick_button = pick
	Prompts.on_change(pick, func() -> void: pick.visible = not InputHub.using_touch() and not pick.disabled)
	OnlineMode.reset_net()
	OnlineMode.current = {}
	if int(Profiles.active().get("player_id", 0)) <= 0:
		# Sans groupe, le serveur refuse : pas de recherche sans fin ni classement vide.
		quick.visible = false
		board.visible = false
		pick.disabled = true
		pick.visible = false
		set_process(false)
		_show_no_group()
		return
	Prompts.bind(_info, func() -> String:
		return "Groupe %s — %s" % [str(Profiles.active().get("group_code", "")),
			"touche un copain pour le défier" if InputHub.using_touch() else "choisis « Défier un copain »"])
	quick.grab_focus.call_deferred()


var _pick_button: Button
var _pick_box: Control
var _panel: Control      # écran « pas encore de groupe »


## Groupe tout juste créé : son code en grand, à donner aux copains.
func _show_new_code() -> void:
	_panel.queue_free()
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_info.text = "Groupe créé ! Donne ce code à tes copains :"
	var big: Label = UiKit.label(str(Profiles.active().get("group_code", "")), 24, UiKit.C_GOLD)
	big.set_anchors_preset(Control.PRESET_TOP_WIDE)
	big.position.y = 60
	_panel.add_child(big)
	var tip: Label = UiKit.label("Ils le tapent dans En ligne > J'ai un code.\nIl reste aussi affiché en haut du salon.", 8, UiKit.C_LINEN)
	tip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tip.position.y = 100
	_panel.add_child(tip)
	var go: Button = UiKit.button("C'est noté !", func() -> void: SceneRouter.goto(&"lobby"), 120)
	go.position = Vector2(roundf(get_viewport_rect().size.x * 0.5 - 60), 140)
	_panel.add_child(go)
	go.grab_focus.call_deferred()


## Pas encore de groupe : on le crée ou on le rejoint ici même (avant : Profil > Groupe).
func _show_no_group() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_info.text = "Pour jouer avec tes copains,\nil vous faut le même groupe."
	_info.position.y = 30
	var status: Label = UiKit.label("", 8, UiKit.C_GOLD)
	status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	status.position.y = 160
	_panel.add_child(status)
	var done: Callable = func(ok: bool, msg: String) -> void:
		if ok:
			SceneRouter.goto(&"lobby")
		elif is_instance_valid(status):
			status.text = msg
	var w: float = get_viewport_rect().size.x
	var create: Button = UiKit.button("Créer un groupe", func() -> void:
		status.text = "Création…"
		Api.create_group(func(ok: bool, msg: String) -> void:
			if ok:
				_show_new_code()
			elif is_instance_valid(status):
				status.text = msg), 150)
	create.position = Vector2(roundf(w * 0.5 - 75), 64)
	_panel.add_child(create)
	# Rejoindre : le code se tape au doigt / clavier, ou lettre par lettre à la manette.
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var edit: LineEdit = LineEdit.new()
	edit.max_length = 6
	edit.placeholder_text = "CODE"
	edit.custom_minimum_size = Vector2(70, 22)
	edit.add_theme_font_size_override(&"font_size", 8)
	row.add_child(edit)
	WebTextField.attach(edit)
	var join: Callable = func(t: String) -> void:
		status.text = "Connexion…"
		Api.join_group(t, done)
	row.add_child(UiKit.button("Rejoindre", func() -> void: join.call(edit.text), 80))
	row.position = Vector2(roundf(w * 0.5 - 77), 104)
	_panel.add_child(row)
	var hint: Label = UiKit.label("J'ai le code d'un copain :", 8, UiKit.C_LINEN)
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.position.y = 92
	_panel.add_child(hint)
	var pad_holder: Control = Control.new()
	pad_holder.position = Vector2(roundf(w * 0.5 - 100), 130)
	_panel.add_child(pad_holder)
	PadKeyboard.pad_button(pad_holder, edit, "Code du groupe (6 caractères)", false, join, 200,
		"Écrire le code à la manette", false)
	# Sans code : voir les salons où des joueurs sont connectés et demander à entrer.
	var rooms: Button = UiKit.button("Salons actifs", func() -> void: _show_rooms(status), 130)
	rooms.position = Vector2(roundf(w * 0.5 - 65), get_viewport_rect().size.y - 28)
	_panel.add_child(rooms)
	create.grab_focus.call_deferred()
	# Captures QA : --qa-lobby=rooms | request
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--qa-lobby=rooms":
			_show_rooms.call_deferred(status)
		elif arg == "--qa-lobby=request":
			_show_request.call_deferred({"request_id": 1, "pseudo": "Peio"})


## Salons actifs : un bouton par groupe (pseudos des connectés), toucher = demander à entrer.
func _show_rooms(status: Label) -> void:
	status.text = "Recherche des salons…"
	Api.call_api(HTTPClient.METHOD_GET, "/groups/active", {}, func(ok: bool, _c: int, data: Variant) -> void:
		if not is_instance_valid(status):
			return
		if not ok or not data is Array:
			status.text = "Serveur injoignable"
			return
		if (data as Array).is_empty():
			status.text = "Aucun salon ouvert pour l'instant"
			AudioManager.sfx(&"ui_no")
			return
		status.text = ""
		var buttons: Array = []
		for r: Variant in data:
			var rd: Dictionary = r
			var names: Array = rd.get("members", [])
			var label: String = ", ".join(PackedStringArray(names.slice(0, 2)))
			if names.size() > 2:
				label += " +%d" % (names.size() - 2)
			var gid: int = int(rd.get("group_id", 0))
			buttons.append(UiKit.button(label, func() -> void:
				_close_pick()
				_request_join(gid, label, status), 200))
		buttons.append(UiKit.button("Annuler", _close_pick, 200))
		_overlay_column(buttons.slice(0, 7), "Demander à entrer dans le salon de :"), false)


## Fond sombre + colonne de boutons par-dessus tout (même place que la liste des copains).
func _overlay_column(buttons: Array, title: String) -> void:
	_close_pick()
	_pick_box = Control.new()
	_pick_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pick_box.z_index = 300
	add_child(_pick_box)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.1, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pick_box.add_child(shade)
	var head: Label = UiKit.label(title, 8, UiKit.C_GOLD)
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 30
	_pick_box.add_child(head)
	UiKit.menu_column(_pick_box, buttons, 46)


var _request: Dictionary = {}     # demande en cours : request_id, token
var _request_t: float = 0.0


## Demande envoyée : un membre connecté du salon doit accepter (on interroge toutes les 2 s).
func _request_join(gid: int, who: String, status: Label) -> void:
	status.text = "Demande en cours…"
	var pseudo: String = str(Profiles.active().get("pseudo", ""))
	Api.call_api(HTTPClient.METHOD_POST, "/group/request", {"group_id": gid, "pseudo": pseudo},
		func(ok: bool, _c: int, data: Variant) -> void:
			if not is_instance_valid(status):
				return
			if not ok or not data is Dictionary:
				var msg: String = str((data as Dictionary).get("error", "")) if data is Dictionary else ""
				status.text = msg if msg != "" else "Serveur injoignable"
				return
			_request = data
			_request_t = 0.0
			_overlay_column([UiKit.button("Annuler", func() -> void:
				_request = {}
				_close_pick(), 200)], "Demande envoyée à %s…\nUn joueur du salon doit accepter." % who)
			_request_status = status
			set_process(true), false)


var _request_status: Label


func _poll_request(delta: float) -> void:
	_request_t += delta
	if _request_t < 2.0:
		return
	_request_t = 0.0
	var rq: Dictionary = _request
	Api.call_api(HTTPClient.METHOD_GET, "/group/request", {"request_id": int(rq.get("request_id", 0)),
		"token": str(rq.get("token", ""))}, func(ok: bool, _c: int, data: Variant) -> void:
			if _request != rq or not ok or not data is Dictionary:
				return
			var d: Dictionary = data
			var state: String = str(d.get("state", ""))
			if state == "pending":
				return
			_request = {}
			_close_pick()
			if state == "accepted":
				Profiles.update_active({"group_code": str(d.get("code", "")), "player_id": int(d.get("player_id", 0)),
					"secret": str(d.get("secret", ""))})
				Api.sync_profile()
				SceneRouter.goto(&"lobby")
			elif is_instance_valid(_request_status):
				_request_status.text = "Ils ont dit non… essaie un autre salon" if state == "refused" \
					else "Personne n'a répondu, réessaie plus tard", false)


func _leave() -> void:
	Api.call_api(HTTPClient.METHOD_POST, "/presence", {"status": "busy"}, func(_o: bool, _c: int, _d: Variant) -> void: pass)
	SceneRouter.goto(&"main_menu")


## Liste des copains disponibles (clavier, manette, ou au doigt aussi).
func _show_pick() -> void:
	_close_pick()
	var buttons: Array = []
	for m: Variant in _members:
		var md: Dictionary = m
		if bool(md.get("me", false)) or str(md.get("status", "")) != "lobby":
			continue
		var pid: int = int(md.get("player_id", 0))
		buttons.append(UiKit.button("%s (%d pts)" % [str(md.get("pseudo", "?")), int(md.get("rating", 1000))],
			func() -> void:
				_close_pick()
				_challenge(pid), 180))
	if buttons.is_empty():
		_info.text = "Aucun copain disponible pour l'instant"
		AudioManager.sfx(&"ui_no")
		return
	buttons.append(UiKit.button("Annuler", _close_pick, 180))
	_pick_box = Control.new()
	_pick_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pick_box.z_index = 300
	add_child(_pick_box)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.1, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pick_box.add_child(shade)
	var col: VBoxContainer = UiKit.menu_column(_pick_box, buttons.slice(0, 7), 40)
	col.position.x -= 20


func _close_pick() -> void:
	if _pick_box != null:
		_pick_box.queue_free()
		_pick_box = null
		if is_instance_valid(_pick_button) and _pick_button.visible:
			_pick_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _pick_box != null:
		_request = {}
		_close_pick()
	elif _invite_box != null and _box_request > 0:
		_decide(_box_request, false)
	elif _invite_box != null:
		_respond(_shown_invite, false)
	else:
		_leave()


func _process(delta: float) -> void:
	if not _request.is_empty():
		_poll_request(delta)
		return
	if _panel != null:
		return
	_hb_t += delta
	# Défi envoyé : on guette l'acceptation de près.
	var waiting: bool = _status == "queue" or not OnlineMode.current.is_empty() or not OnlineMode.qa.is_empty()
	var period: float = QUICK_HEARTBEAT if waiting else HEARTBEAT
	if _hb_t >= period:
		_hb_t = 0.0
		_heartbeat()
	_animate_walkers(delta)


func _heartbeat() -> void:
	Api.call_api(HTTPClient.METHOD_POST, "/presence", {"status": _status}, func(ok: bool, _c: int, data: Variant) -> void:
		if not ok or not data is Dictionary:
			_info.text = "Serveur injoignable… on réessaie"
			return
		var d: Dictionary = data
		_members = d.get("members", [])
		_sync_walkers()
		if d.get("match") is Dictionary:
			_on_match(d["match"])
		var invites: Array = d.get("invites", [])
		if not invites.is_empty():
			_show_invite(invites[0])
		elif _invite_box == null:
			var requests: Array = d.get("requests", [])
			if not requests.is_empty():
				_show_request(requests[0])
		_qa_actions())


## Rôles de test automatisés (Playwright à deux pages) : inviter / accepter.
func _qa_actions() -> void:
	if OnlineMode.qa.is_empty() or not OnlineMode.current.is_empty():
		return
	if str(OnlineMode.qa.get("role", "")) == "invite":
		for m: Variant in _members:
			var md: Dictionary = m
			if not bool(md.get("me", false)) and str(md.get("status", "")) == "lobby":
				_challenge(int(md.get("player_id", 0)))
				return


func _sync_walkers() -> void:
	var seen: Dictionary = {}
	var w: float = get_viewport_rect().size.x
	for m: Variant in _members:
		var md: Dictionary = m
		var pid: int = int(md.get("player_id", 0))
		seen[pid] = true
		if _walkers.has(pid):
			continue
		var view: FighterView = UiKit.fighter_preview(str(md.get("fighter", "louis")), int(md.get("costume", 0)), "walk")
		view.scale = Vector2(0.5, 0.5)
		_ground.add_child(view)
		_walkers[pid] = {"view": view, "x": randf_range(40.0, w - 40.0), "dir": 1.0 if randf() < 0.5 else -1.0,
			"y": randf_range(150.0, 185.0), "data": md}
	for pid: Variant in _walkers.keys():
		if not seen.has(pid):
			(_walkers[pid]["view"] as Node).queue_free()
			_walkers.erase(pid)
	_ground.queue_redraw()


func _animate_walkers(delta: float) -> void:
	var w: float = get_viewport_rect().size.x
	for pid: Variant in _walkers:
		var wk: Dictionary = _walkers[pid]
		wk["x"] = float(wk["x"]) + float(wk["dir"]) * 14.0 * delta
		if float(wk["x"]) < 30.0 or float(wk["x"]) > w - 30.0:
			wk["dir"] = -float(wk["dir"])
		var view: FighterView = wk["view"]
		view.position = Vector2(roundf(float(wk["x"])), roundf(float(wk["y"])))
		view.preview.facing = 1 if float(wk["dir"]) > 0 else -1
		view.z_index = int(float(wk["y"]))
	_ground.queue_redraw()
	if not _ground.draw.is_connected(_draw_cards):
		_ground.draw.connect(_draw_cards)


func _draw_cards() -> void:
	for pid: Variant in _walkers:
		var wk: Dictionary = _walkers[pid]
		var md: Dictionary = wk["data"]
		var x: float = roundf(float(wk["x"]))
		var top: float = roundf(float(wk["y"])) - 62.0
		var name: String = str(md.get("pseudo", "?"))
		var me: bool = bool(md.get("me", false))
		var line2: String = "%d pts" % int(md.get("rating", 1000))
		var tw: float = maxf(_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x,
			_font.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x) + 8.0
		var r: Rect2 = Rect2(x - tw * 0.5, top - 20.0, tw, 20.0)
		_ground.draw_rect(r, UiKit.C_OUTLINE)
		_ground.draw_rect(r.grow(-1), Color8(150, 104, 62) if not me else Color8(52, 128, 72))
		_ground.draw_string(_font, Vector2(r.position.x + 4, r.position.y + 9), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.C_LINEN)
		_ground.draw_string(_font, Vector2(r.position.x + 4, r.position.y + 18), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.C_GOLD)
		if str(md.get("status", "")) == "busy" and not me:
			_ground.draw_string(_font, Vector2(r.position.x, r.position.y - 2), "en combat", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiKit.C_RED)


func _gui_input(event: InputEvent) -> void:
	var pos: Vector2 = Vector2.ZERO
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		pos = (event as InputEventMouseButton).position
	else:
		return
	for pid: Variant in _walkers:
		var wk: Dictionary = _walkers[pid]
		var md: Dictionary = wk["data"]
		if bool(md.get("me", false)):
			continue
		var hit: Rect2 = Rect2(float(wk["x"]) - 26.0, float(wk["y"]) - 86.0, 52.0, 86.0)
		if hit.has_point(pos):
			_challenge(int(pid))
			return


func _challenge(pid: int) -> void:
	_info.text = "Défi envoyé… (20 s)"
	Api.call_api(HTTPClient.METHOD_POST, "/match/invite", {"to": pid}, func(ok: bool, _c: int, data: Variant) -> void:
		if not ok:
			_info.text = "Impossible de défier ce copain"
			return
		OnlineMode.current = {"match_id": int((data as Dictionary).get("match_id", 0)), "host": true, "state": "invited"})


func _quick_match() -> void:
	_status = "queue"
	_info.text = "Recherche d'un copain disponible…"
	Api.call_api(HTTPClient.METHOD_POST, "/match/queue", {}, func(ok: bool, _c: int, data: Variant) -> void:
		if ok and data is Dictionary and (data as Dictionary).get("match") is Dictionary:
			_on_match((data as Dictionary)["match"]))


func _show_invite(inv: Dictionary) -> void:
	var mid: int = int(inv.get("match_id", 0))
	if mid == _shown_invite:
		return
	_shown_invite = mid
	_box_request = 0
	if _invite_box != null:
		_invite_box.queue_free()
	var from: Dictionary = inv.get("from", {})
	if str(OnlineMode.qa.get("role", "")) == "accept":
		_respond(mid, true)
		return
	_invite_box = PanelContainer.new()
	_invite_box.position = Vector2(roundf(get_viewport_rect().size.x * 0.5 - 110), 70)
	_invite_box.custom_minimum_size = Vector2(220, 0)
	_invite_box.z_index = 300      # au-dessus des copains qui se promènent (z = leur y)
	add_child(_invite_box)
	var col: VBoxContainer = VBoxContainer.new()
	_invite_box.add_child(col)
	col.add_child(UiKit.label("%s te défie ! %s" % [str(from.get("pseudo", "?")),
		Profiles.EMOTES[clampi(int(from.get("emote", 0)), 0, 3)]], 8, UiKit.C_GOLD))
	var row: HBoxContainer = HBoxContainer.new()
	var accept: Button = UiKit.button("Accepter", _respond.bind(mid, true), 100)
	row.add_child(accept)
	row.add_child(UiKit.button("Refuser", _respond.bind(mid, false), 100))
	col.add_child(row)
	accept.grab_focus.call_deferred()
	AudioManager.sfx(&"round")


## Quelqu'un des salons actifs demande à entrer dans le groupe.
func _show_request(rq: Dictionary) -> void:
	var rid: int = int(rq.get("request_id", 0))
	if _seen_requests.has(rid):
		return
	_seen_requests.append(rid)
	_box_request = rid
	_invite_box = PanelContainer.new()
	_invite_box.position = Vector2(roundf(get_viewport_rect().size.x * 0.5 - 110), 70)
	_invite_box.custom_minimum_size = Vector2(220, 0)
	_invite_box.z_index = 300
	add_child(_invite_box)
	var col: VBoxContainer = VBoxContainer.new()
	_invite_box.add_child(col)
	col.add_child(UiKit.label("%s veut entrer\ndans ton groupe" % str(rq.get("pseudo", "?")), 8, UiKit.C_GOLD))
	var row: HBoxContainer = HBoxContainer.new()
	var yes: Button = UiKit.button("Accepter", _decide.bind(rid, true), 100)
	row.add_child(yes)
	row.add_child(UiKit.button("Refuser", _decide.bind(rid, false), 100))
	col.add_child(row)
	yes.grab_focus.call_deferred()
	AudioManager.sfx(&"round")


var _seen_requests: Array[int] = []
var _box_request: int = 0         # demande affichée dans _invite_box (0 = c'est un défi)


func _decide(rid: int, accept: bool) -> void:
	_box_request = 0
	if _invite_box != null:
		_invite_box.queue_free()
		_invite_box = null
		if is_instance_valid(_pick_button) and _pick_button.visible:
			_pick_button.grab_focus.call_deferred()
	Api.call_api(HTTPClient.METHOD_POST, "/group/decide", {"request_id": rid, "accept": accept},
		func(ok: bool, _c: int, data: Variant) -> void:
			if not ok and accept:
				_info.text = str((data as Dictionary).get("error", "Demande expirée")) if data is Dictionary else "Demande expirée")


func _respond(mid: int, accept: bool) -> void:
	if _invite_box != null:
		_invite_box.queue_free()
		_invite_box = null
		if is_instance_valid(_pick_button) and _pick_button.visible:
			_pick_button.grab_focus.call_deferred()
	Api.call_api(HTTPClient.METHOD_POST, "/match/respond", {"match_id": mid, "accept": accept},
		func(ok: bool, _c: int, data: Variant) -> void:
			if ok and accept and data is Dictionary and (data as Dictionary).get("match") is Dictionary:
				_on_match((data as Dictionary)["match"])
			elif accept:
				_info.text = "Invitation expirée")


func _on_match(m: Dictionary) -> void:
	var state: String = str(m.get("state", ""))
	if state == "invited":
		OnlineMode.current = m
		return
	if state in ["accepted", "signaling"]:
		OnlineMode.current = m
		_status = "busy"
		set_process(false)
		SceneRouter.goto(&"fighter_select", {"mode": "online"})


func _show_board() -> void:
	var code: String = str(Profiles.active().get("group_code", ""))
	Api.call_api(HTTPClient.METHOD_GET, "/leaderboard", {"code": code, "type": "rating"}, func(ok: bool, _c: int, data: Variant) -> void:
		if not ok or not data is Array:
			return
		var lines: PackedStringArray = ["CLASSEMENT DU GROUPE"]
		var i: int = 1
		for row: Variant in data:
			var rd: Dictionary = row
			lines.append("%d. %s  %d pts  (%d V / %d D)" % [i, str(rd.get("pseudo", "")), int(rd.get("rating", 1000)),
				int(rd.get("wins", 0)), int(rd.get("losses", 0))])
			i += 1
			if i > 8:
				break
		_info.text = "\n".join(lines), false)
