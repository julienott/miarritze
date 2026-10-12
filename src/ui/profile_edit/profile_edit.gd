extends Control
## Profil (SPEC §3.1) : carte de joueur (favori, costume, bannière, titre,
## emote), groupe (code de 6 caractères), statistiques et txapelas.

var _card: PlayerCard
var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	AudioManager.play_music(&"title")
	UiKit.backdrop(self, "bg_hub", 0.55)
	var head: Label = UiKit.title("MON PROFIL")
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 4
	add_child(head)
	var back: Button = UiKit.button("Retour", func() -> void: SceneRouter.goto(&"main_menu"), 60)
	back.position = Vector2(4, 4)
	back.focus_mode = Control.FOCUS_NONE
	add_child(back)
	_card = PlayerCard.create(Profiles.active())
	_card.position = Vector2(12, 34)
	add_child(_card)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(120, 30)
	scroll.size = Vector2(get_viewport_rect().size.x - 126, 182)
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 3)
	scroll.add_child(_list)
	_build()


func _build() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var prof: Dictionary = Profiles.active()
	var ids: PackedStringArray = Roster.FIGHTERS.duplicate()
	if bool(prof.get("unlocks", {}).get("boss", false)):
		ids.append(Roster.BOSS)
	_cycler("Favori", func() -> String: return Roster.display_name(str(Profiles.active().get("fighter", "louis"))),
		func(d: int) -> void:
			var i: int = (ids.find(str(Profiles.active().get("fighter", "louis"))) + d + ids.size()) % ids.size()
			Profiles.update_active({"fighter": ids[i], "costume": 0}))
	_cycler("Costume", func() -> String:
			var p2: Dictionary = Profiles.active()
			var c: int = int(p2.get("costume", 0))
			return "%d%s" % [c + 1, "" if Profiles.costume_unlocked(str(p2.get("fighter")), c) else " (verrouillé)"],
		func(d: int) -> void:
			var p3: Dictionary = Profiles.active()
			for step: int in range(1, 5):
				var c2: int = (int(p3.get("costume", 0)) + d * step + 8) % 4
				if Profiles.costume_unlocked(str(p3.get("fighter")), c2):
					Profiles.update_active({"costume": c2})
					return)
	_cycler("Bannière", func() -> String: return "%d" % (int(Profiles.active().get("banner", 0)) + 1),
		func(d: int) -> void: Profiles.update_active({"banner": (int(Profiles.active().get("banner", 0)) + d + Profiles.BANNERS) % Profiles.BANNERS}))
	_cycler("Titre", func() -> String: return str(Profiles.TITLES.get(str(Profiles.active().get("title", "")), ["Sans titre"])[0]),
		func(d: int) -> void:
			var owned: Array = [""]
			owned.append_array(Profiles.active().get("titles", []))
			var i2: int = (owned.find(str(Profiles.active().get("title", ""))) + d + owned.size()) % owned.size()
			Profiles.update_active({"title": owned[i2]}))
	_cycler("Emote", func() -> String: return Profiles.EMOTES[int(Profiles.active().get("emote", 0))],
		func(d: int) -> void: Profiles.update_active({"emote": (int(Profiles.active().get("emote", 0)) + d + 4) % 4}))
	_list.add_child(UiKit.label("GROUPE", 8, UiKit.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	var code: String = str(prof.get("group_code", ""))
	_list.add_child(UiKit.label("Code : %s" % (code if code != "" else "aucun"), 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_LEFT))
	var row: HBoxContainer = HBoxContainer.new()
	var edit: LineEdit = LineEdit.new()
	edit.max_length = 6
	edit.placeholder_text = "CODE"
	edit.custom_minimum_size = Vector2(70, 22)
	edit.add_theme_font_size_override(&"font_size", 8)
	row.add_child(edit)
	row.add_child(UiKit.button("Rejoindre", func() -> void: _join(edit.text.strip_edges().to_upper()), 80))
	row.add_child(UiKit.button("Créer", _create_group, 60))
	_list.add_child(row)
	_status = UiKit.label("", 8, UiKit.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_list.add_child(_status)
	_list.add_child(UiKit.label("STATISTIQUES", 8, UiKit.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	var stats: Dictionary = prof.get("stats", {})
	var tx: Dictionary = stats.get("txapelas", {})
	var lines: PackedStringArray = [
		"Combats : %d   Victoires : %d" % [int(stats.get("fights", 0)), int(stats.get("wins", 0))],
		"Pyramides : %d   Txapelas : %d" % [_sum(stats.get("towers", {})), tx.size()],
		"Meilleur score : %d" % int(stats.get("best_tower", 0)),
		"Finishs réussis : %d" % int(stats.get("finishers", 0)),
	]
	for line: String in lines:
		_list.add_child(UiKit.label(line, 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_LEFT))
	var rank: Label = UiKit.label("Rang du groupe : —", 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_LEFT)
	_list.add_child(rank)
	if code != "":
		Api.call_api(HTTPClient.METHOD_GET, "/leaderboard", {"code": code, "type": "rating"},
			func(ok: bool, _c: int, data: Variant) -> void:
				if ok and data is Array and is_instance_valid(rank):
					var pseudo: String = str(Profiles.active().get("pseudo", ""))
					for i: int in (data as Array).size():
						if str((data as Array)[i].get("pseudo", "")) == pseudo:
							rank.text = "Rang du groupe : %d / %d (%d pts)" % [i + 1, (data as Array).size(),
								int((data as Array)[i].get("rating", 1000))], false)


func _sum(d: Dictionary) -> int:
	var t: int = 0
	for k: Variant in d:
		t += int(d[k])
	return t


func _cycler(label_text: String, value: Callable, change: Callable) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	var name_label: Label = UiKit.label("%s : %s" % [label_text, value.call()], 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.custom_minimum_size = Vector2(170, 24)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var prev: Button = UiKit.button("<", func() -> void:
		change.call(-1)
		name_label.text = "%s : %s" % [label_text, value.call()]
		_refresh_card(), 24)
	var next: Button = UiKit.button(">", func() -> void:
		change.call(1)
		name_label.text = "%s : %s" % [label_text, value.call()]
		_refresh_card(), 24)
	row.add_child(prev)
	row.add_child(next)
	row.add_child(name_label)
	_list.add_child(row)


func _refresh_card() -> void:
	_card.data = Profiles.active()
	_card.refresh()
	Api.sync_profile()


func _create_group() -> void:
	_status.text = "Création…"
	Api.call_api(HTTPClient.METHOD_POST, "/group", {}, func(ok: bool, _c: int, data: Variant) -> void:
		if ok and data is Dictionary:
			_join(str((data as Dictionary).get("code", "")))
		else:
			_status.text = "Serveur injoignable", false)


func _join(code: String) -> void:
	if code.length() != 6:
		_status.text = "Le code fait 6 caractères"
		return
	_status.text = "Connexion…"
	var pseudo: String = str(Profiles.active().get("pseudo", ""))
	Api.call_api(HTTPClient.METHOD_POST, "/group/join", {"code": code, "pseudo": pseudo},
		func(ok: bool, _c: int, data: Variant) -> void:
			if ok and data is Dictionary:
				var d: Dictionary = data
				Profiles.update_active({"group_code": code, "player_id": int(d.get("player_id", 0)),
					"secret": str(d.get("secret", ""))})
				Api.sync_profile()
				_build()
				_status.text = "Bienvenue dans le groupe %s !" % code
			else:
				var msg: String = str((data as Dictionary).get("error", "")) if data is Dictionary else ""
				_status.text = "Impossible : %s" % (msg if msg != "" else "serveur injoignable"), false)
