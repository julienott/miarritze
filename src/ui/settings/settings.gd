extends Control
## Réglages (SPEC §3, §7.2–7.4) : contrôles tactiles (manette virtuelle ou
## gestes, taille, opacité), clavier (réassignation touche par touche),
## sons, difficulté par défaut, combats express.

const KEY_ACTIONS: Array = [
	["p1_up", "J1 Haut"], ["p1_down", "J1 Bas"], ["p1_left", "J1 Gauche"], ["p1_right", "J1 Droite"],
	["p1_punch", "J1 Poing"], ["p1_kick", "J1 Pied"], ["p1_special", "J1 Spécial"], ["p1_guard", "J1 Garde"],
	["p2_up", "J2 Haut"], ["p2_down", "J2 Bas"], ["p2_left", "J2 Gauche"], ["p2_right", "J2 Droite"],
	["p2_punch", "J2 Poing"], ["p2_kick", "J2 Pied"], ["p2_special", "J2 Spécial"], ["p2_guard", "J2 Garde"],
]

var _list: VBoxContainer
var _waiting_action: String = ""
var _waiting_button: Button


func _ready() -> void:
	AudioManager.play_music(&"title")
	UiKit.backdrop(self, "bg_menu", 0.6)
	var head: Label = UiKit.title("RÉGLAGES")
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 4
	add_child(head)
	var back: Button = UiKit.button("Retour", func() -> void: SceneRouter.goto(&"main_menu"), 60)
	back.position = Vector2(4, 4)
	add_child(back)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 30
	scroll.offset_left = 40
	scroll.offset_right = -40
	scroll.offset_bottom = -4
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 3)
	scroll.add_child(_list)
	_build()


func _build() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	_section("CONTRÔLES TACTILES")
	_cycle("Mode", ["Manette virtuelle", "Gestes"], ["pad", "gestures"], "touch_mode")
	_cycle("Afficher la manette", ["Auto", "Toujours", "Jamais"], ["auto", "on", "off"], "pad_visible")
	_cycle("Taille des boutons", ["Petite", "Moyenne", "Grande"], [0, 1, 2], "pad_size")
	_cycle("Opacité", ["35 %", "55 %", "75 %", "95 %"], [0.35, 0.55, 0.75, 0.95], "pad_opacity")
	_section("SONS")
	_cycle("Musique", ["Coupée", "Faible", "Moyenne", "Forte"], [0.0, 0.4, 0.7, 1.0], "music_volume")
	_cycle("Effets", ["Coupés", "Faibles", "Moyens", "Forts"], [0.0, 0.4, 0.7, 1.0], "sfx_volume")
	_cycle("Voix", ["Coupées", "Faibles", "Moyennes", "Fortes"], [0.0, 0.4, 0.7, 1.0], "voice_volume")
	_section("JEU")
	_cycle("Difficulté par défaut", ["Facile", "Normal", "Expert"], [0, 1, 2], "default_difficulty")
	_cycle("Combats express (sans finish en ligne)", ["Non", "Oui"], [false, true], "express_fights")
	_section("ACCESSIBILITÉ")
	_cycle("Couleurs pour daltoniens", ["Non", "Oui"], [false, true], "colorblind")
	_cycle("Vibrations", ["Oui", "Non"], [true, false], "vibrations")
	_section("CLAVIER")
	for pair: Array in KEY_ACTIONS:
		_key_row(pair[0], pair[1])
	_list.add_child(UiKit.button("Réinitialiser les touches", func() -> void:
		Settings.reset_keys()
		_build(), 200))
	var first: Control = _list.get_child(1) as Control
	if first != null:
		first.grab_focus.call_deferred()


func _section(text: String) -> void:
	_list.add_child(UiKit.label(text, 8, UiKit.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT))


func _cycle(label_text: String, names: Array, values: Array, key: String) -> void:
	var current: Variant = Settings.get(key)
	var index: int = 0
	var best: float = INF
	for i: int in values.size():
		var d: float = absf(float(values[i]) - float(current)) if typeof(current) in [TYPE_FLOAT, TYPE_INT] \
			and typeof(values[i]) in [TYPE_FLOAT, TYPE_INT] else (0.0 if values[i] == current else INF)
		if d < best:
			best = d
			index = i
	var b: Button = UiKit.button("%s : %s" % [label_text, names[index]], func() -> void: pass, 260)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void:
		index = (index + 1) % values.size()
		Settings.set_value(key, values[index])
		b.text = "%s : %s" % [label_text, names[index]]
		if key == "music_volume" or key == "sfx_volume":
			AudioManager.apply_volumes())
	_list.add_child(b)


func _key_row(action: String, label_text: String) -> void:
	var b: Button = UiKit.button("%s : %s" % [label_text, _key_names(action)], func() -> void: pass, 260)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void:
		_waiting_action = action
		_waiting_button = b
		b.text = "%s : appuie sur une touche…" % label_text)
	b.set_meta(&"label", label_text)
	_list.add_child(b)


func _key_names(action: String) -> String:
	var names: PackedStringArray = []
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k: InputEventKey = ev
			var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			names.append(OS.get_keycode_string(code))
	return " / ".join(names)


func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not event is InputEventKey or not event.is_pressed():
		return
	var key: InputEventKey = event
	get_viewport().set_input_as_handled()
	if key.physical_keycode != KEY_ESCAPE:
		Settings.remap(_waiting_action, [int(key.physical_keycode)])
	_waiting_button.text = "%s : %s" % [str(_waiting_button.get_meta(&"label")), _key_names(_waiting_action)]
	_waiting_action = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		SceneRouter.goto(&"main_menu")
