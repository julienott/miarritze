class_name MoveList
extends PanelContainer
## Liste des coups d'un combattant (SPEC §3.5) : normaux communs, puis les
## 4 spéciaux, le super et le finish, avec l'entrée simple et la manip
## « à l'ancienne » (bonus +10 %). Utilisable en pause et à l'entraînement.

signal closed

## [nom, direction(s), bouton, précision] — l'entrée s'écrit avec les boutons
## de l'appareil utilisé (Prompts.move_input).
const NORMALS: Array = [
	["Direct (×3 = combo)", "", "punch", ""], ["Coup de pied", "", "kick", ""],
	["Pied haut", "Avant", "kick", ""], ["Petit coup accroupi", "Bas", "punch", ""],
	["Balayette (bas)", "Bas", "kick", ""], ["Txapel-cut (uppercut)", "Arrière-Bas", "punch", ""],
	["Projection", "Avant", "punch", "(contact)"], ["Garde", "", "guard", "(+ Bas : garde basse)"],
]
const SLOTS: Array = [["sp_neutral", ""], ["sp_forward", "Avant"], ["sp_down", "Bas"], ["sp_up", "Haut"]]

var _fighter_id: String = ""
var _col: VBoxContainer
var _scroll: ScrollContainer


static func create(fighter_id: String) -> MoveList:
	var m: MoveList = MoveList.new()
	m._build(fighter_id)
	return m


func _build(fighter_id: String) -> void:
	_fighter_id = fighter_id
	var data: Dictionary = FighterDb.load_json(fighter_id)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color8(24, 16, 28)
	box.border_color = UiKit.C_GOLD
	box.set_border_width_all(1)
	box.set_content_margin_all(6)
	add_theme_stylebox_override(&"panel", box)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 12
	offset_right = -12
	offset_top = 8
	offset_bottom = -8
	# Au-dessus du HUD (portraits) et de tout le reste de la couche UI.
	z_index = 100
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 4)
	add_child(outer)
	# En-tête fixe : « Fermer » toujours visible, sans avoir à faire défiler.
	var header: HBoxContainer = HBoxContainer.new()
	outer.add_child(header)
	var title: Label = UiKit.label("COUPS DE %s" % str(data.get("name", fighter_id)).to_upper(), 8, UiKit.C_GOLD,
		HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	var close: Button = UiKit.button("Fermer", func() -> void:
		closed.emit()
		queue_free(), 80)
	header.add_child(close)
	close.grab_focus.call_deferred()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_scroll = scroll
	_col = VBoxContainer.new()
	_col.add_theme_constant_override(&"separation", 3)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_col)
	var hint: Label = UiKit.label("", 8, Color8(196, 232, 230), HORIZONTAL_ALIGNMENT_LEFT)
	hint.add_theme_constant_override(&"outline_size", 0)
	outer.add_child(hint)
	Prompts.bind(hint, func() -> String:
		return Prompts.pick({Prompts.KEYBOARD: "↑↓ : défiler   {back} : fermer",
			Prompts.GAMEPAD: "↑↓ : défiler   {back} : fermer"}))
	_fill()
	# Clavier → manette → iPhone : la liste se réécrit avec les bons boutons.
	InputHub.device_changed.connect(func(_d: int) -> void: _fill())


## Contenu de la liste (boutons de l'appareil utilisé en dernier).
func _fill() -> void:
	for c: Node in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	var moves: Dictionary = FighterDb.load_json(_fighter_id).get("moves", {})
	var col: VBoxContainer = _col
	for n: Array in NORMALS:
		col.add_child(_row(n[0], Prompts.move_input(n[1], n[2], n[3]), ""))
	var sp_title: Label = UiKit.label("SPÉCIAUX", 8, UiKit.C_GOLD)
	sp_title.custom_minimum_size = Vector2(0, 14)
	sp_title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(sp_title)
	for slot: Array in SLOTS:
		var mv: Dictionary = moves.get(slot[0], {})
		col.add_child(_row(str(mv.get("name", slot[0])), Prompts.move_input(slot[1], "special"),
			Prompts.classic(str(mv.get("classic", "")))))
	var sup: Dictionary = moves.get("super", {})
	var gestures: bool = Prompts.kind() == Prompts.GESTURES
	var both: String = "%s + %s" % [Prompts.button("special"), Prompts.button("guard")]
	if Prompts.kind() == Prompts.TOUCH:
		both = "bouton MARÉE"
	col.add_child(_row("SUPER : %s" % str(sup.get("name", "Coup du Txapeldun")),
		("tape à deux doigts" if gestures else both) + " (Marée pleine)", ""))
	col.add_child(_row("Spécial renforcé", "(manette virtuelle seulement)" if gestures
		else "%s + %s + direction (1 Marée)" % [Prompts.button("special"), Prompts.button("guard")], ""))
	col.add_child(_row("Finish BUKATU !", ("pouce en bas ×2 + glisse vers le bas" if gestures
		else "Bas, Bas + %s" % Prompts.button("special")) + " (tout près)", ""))


func _row(name_text: String, input_text: String, classic: String) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 1)
	var a: Label = UiKit.label(name_text, 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_LEFT)
	a.add_theme_constant_override(&"outline_size", 0)
	row.add_child(a)
	var b: Label = UiKit.label("  " + input_text, 8, UiKit.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	b.add_theme_constant_override(&"outline_size", 0)
	# Les noms de boutons rallongent les lignes (« SPÉCIAL (ROND) ») : on passe
	# à la ligne plutôt que d'élargir le panneau hors de l'écran.
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(b)
	if classic != "":
		var c: Label = UiKit.label("  manip : " + classic + " (+10 %)", 8, Color8(196, 232, 230), HORIZONTAL_ALIGNMENT_LEFT)
		c.add_theme_constant_override(&"outline_size", 0)
		c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(c)
	return row


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()
	# Le focus reste sur « Fermer » : haut/bas font défiler la liste.
	elif event.is_action_pressed(&"ui_down", true) or event.is_action_pressed(&"ui_up", true):
		get_viewport().set_input_as_handled()
		_scroll.scroll_vertical += SCROLL_STEP if event.is_action_pressed(&"ui_down", true) else -SCROLL_STEP


const SCROLL_STEP: int = 24
