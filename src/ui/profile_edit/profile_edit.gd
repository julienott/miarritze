extends Control
## Profil (SPEC §3.1) : carte de joueur (favori, costume, bannière, titre,
## emote), groupe (code de 6 caractères), statistiques et txapelas.

var _card: PlayerCard
var _list: VBoxContainer
var _status: Label
## Costume affiché sur la carte : on peut voir les costumes verrouillés (et
## comment les gagner) ; seul un costume débloqué est enregistré.
var _shown_costume: int = -1

const COSTUME_HOW: PackedStringArray = ["", "5 victoires avec lui", "finir la Pyramide", "Pyramide difficile"]


func _ready() -> void:
	AudioManager.play_music(&"hegoak")
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
	scroll.follow_focus = true
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 3)
	scroll.add_child(_list)
	UiKit.touch_scroll(_list)
	_build()


func _build() -> void:
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var prof: Dictionary = Profiles.active()
	var ids: PackedStringArray = Roster.FIGHTERS.duplicate()
	if bool(prof.get("unlocks", {}).get("boss", false)):
		ids.append(Roster.BOSS)
	_cycler("Favori", func() -> String: return Roster.display_name(str(Profiles.active().get("fighter", "louis"))),
		func(d: int) -> void:
			var i: int = (ids.find(str(Profiles.active().get("fighter", "louis"))) + d + ids.size()) % ids.size()
			_shown_costume = -1
			Profiles.update_active({"fighter": ids[i], "costume": 0}))
	_cycler("Costume", func() -> String:
			var c: int = _costume_shown()
			if Profiles.costume_unlocked(str(Profiles.active().get("fighter")), c):
				return "%d / 4" % (c + 1)
			return "%d / 4 à gagner\n%s" % [c + 1, COSTUME_HOW[c]],
		func(d: int) -> void:
			# Les 4 costumes défilent ; un costume verrouillé se montre sans s'enregistrer.
			var c2: int = (_costume_shown() + d + 4) % 4
			_shown_costume = c2
			if Profiles.costume_unlocked(str(Profiles.active().get("fighter")), c2):
				Profiles.update_active({"costume": c2}))
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
	# Message de Créer / Rejoindre juste au-dessus de la ligne du code (visible
	# sans défiler), sur plusieurs lignes si besoin.
	_status = UiKit.label("", 8, UiKit.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(get_viewport_rect().size.x - 136, 0)
	_list.add_child(_status)
	var row: HBoxContainer = HBoxContainer.new()
	var edit: LineEdit = LineEdit.new()
	edit.max_length = 6
	edit.placeholder_text = "CODE"
	edit.custom_minimum_size = Vector2(70, 22)
	edit.add_theme_font_size_override(&"font_size", 8)
	row.add_child(edit)
	WebTextField.attach(edit)
	row.add_child(UiKit.button("Rejoindre", func() -> void: _join(edit.text.strip_edges().to_upper()), 80))
	row.add_child(UiKit.button("Créer", _create_group, 60))
	_list.add_child(row)
	# Manette : le code se compose lettre par lettre ; à la validation, on rejoint.
	PadKeyboard.pad_button(_list, edit, "Code du groupe (6 caractères)", false,
		func(t: String) -> void: _join(t.strip_edges().to_upper()), 200, "Écrire le code à la manette", false)
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		SceneRouter.goto(&"main_menu")


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
	# Manette / clavier : focus visible dès l'arrivée (premier « > »).
	if _list.get_child_count() == 0 and get_viewport().gui_get_focus_owner() == null:
		next.grab_focus.call_deferred()
	row.add_child(prev)
	row.add_child(next)
	row.add_child(name_label)
	_list.add_child(row)


func _costume_shown() -> int:
	return _shown_costume if _shown_costume >= 0 else int(Profiles.active().get("costume", 0))


func _refresh_card() -> void:
	_card.data = Profiles.active().duplicate()
	_card.data["costume"] = _costume_shown()
	_card.locked = not Profiles.costume_unlocked(str(_card.data.get("fighter")), _costume_shown())
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
