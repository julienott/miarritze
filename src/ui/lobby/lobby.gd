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
	var back: Button = UiKit.button("Retour", func() -> void:
		Api.call_api(HTTPClient.METHOD_POST, "/presence", {"status": "busy"}, func(_o: bool, _c: int, _d: Variant) -> void: pass)
		SceneRouter.goto(&"main_menu"), 60)
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
	quick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quick.position = Vector2(get_viewport_rect().size.x - 114, 216 - 28)
	add_child(quick)
	var board: Button = UiKit.button("Classement", _show_board, 90)
	board.position = Vector2(4, 216 - 28)
	add_child(board)
	OnlineMode.reset_net()
	OnlineMode.current = {}
	if int(Profiles.active().get("player_id", 0)) <= 0:
		_info.text = "Rejoins d'abord un groupe (Profil > Groupe)"
		var go: Button = UiKit.button("Aller au profil", func() -> void: SceneRouter.goto(&"profile_edit"), 140)
		go.set_anchors_preset(Control.PRESET_CENTER)
		go.position = Vector2(get_viewport_rect().size.x * 0.5 - 70, 100)
		add_child(go)
		set_process(false)
		return
	_info.text = "Groupe %s — touche un copain pour le défier" % str(Profiles.active().get("group_code", ""))


func _process(delta: float) -> void:
	_hb_t += delta
	var period: float = QUICK_HEARTBEAT if (_status == "queue" or not OnlineMode.qa.is_empty()) else HEARTBEAT
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
	if _invite_box != null:
		_invite_box.queue_free()
	var from: Dictionary = inv.get("from", {})
	if str(OnlineMode.qa.get("role", "")) == "accept":
		_respond(mid, true)
		return
	_invite_box = PanelContainer.new()
	_invite_box.set_anchors_preset(Control.PRESET_CENTER)
	_invite_box.position = Vector2(get_viewport_rect().size.x * 0.5 - 110, 70)
	_invite_box.custom_minimum_size = Vector2(220, 0)
	add_child(_invite_box)
	var col: VBoxContainer = VBoxContainer.new()
	_invite_box.add_child(col)
	col.add_child(UiKit.label("%s te défie ! %s" % [str(from.get("pseudo", "?")),
		Profiles.EMOTES[clampi(int(from.get("emote", 0)), 0, 3)]], 8, UiKit.C_GOLD))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(UiKit.button("Accepter", _respond.bind(mid, true), 100))
	row.add_child(UiKit.button("Refuser", _respond.bind(mid, false), 100))
	col.add_child(row)
	AudioManager.sfx(&"round")


func _respond(mid: int, accept: bool) -> void:
	if _invite_box != null:
		_invite_box.queue_free()
		_invite_box = null
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
