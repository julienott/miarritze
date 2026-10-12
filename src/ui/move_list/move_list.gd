class_name MoveList
extends PanelContainer
## Liste des coups d'un combattant (SPEC §3.5) : normaux communs, puis les
## 4 spéciaux, le super et le finish, avec l'entrée simple et la manip
## « à l'ancienne » (bonus +10 %). Utilisable en pause et à l'entraînement.

signal closed

const NORMALS: Array = [
	["Direct (×3 = combo)", "POING"], ["Coup de pied", "PIED"], ["Pied haut", "Avant + PIED"],
	["Petit coup accroupi", "Bas + POING"], ["Balayette (bas)", "Bas + PIED"],
	["Txapel-cut (uppercut)", "Arrière-Bas + POING"], ["Projection", "Avant + POING (contact)"],
	["Garde", "GARDE (Bas + GARDE : garde basse)"],
]
const SLOTS: Array = [["sp_neutral", "SPÉCIAL"], ["sp_forward", "Avant + SPÉCIAL"],
	["sp_down", "Bas + SPÉCIAL"], ["sp_up", "Haut + SPÉCIAL"]]


static func create(fighter_id: String) -> MoveList:
	var m: MoveList = MoveList.new()
	m._build(fighter_id)
	return m


func _build(fighter_id: String) -> void:
	var data: Dictionary = FighterDb.load_json(fighter_id)
	var moves: Dictionary = data.get("moves", {})
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.09, 0.06, 0.1, 0.94)
	box.border_color = UiKit.C_GOLD
	box.set_border_width_all(1)
	box.set_content_margin_all(6)
	add_theme_stylebox_override(&"panel", box)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 12
	offset_right = -12
	offset_top = 8
	offset_bottom = -8
	var scroll: ScrollContainer = ScrollContainer.new()
	add_child(scroll)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(UiKit.label("COUPS DE %s" % str(data.get("name", fighter_id)).to_upper(), 8, UiKit.C_GOLD))
	for n: Array in NORMALS:
		col.add_child(_row(n[0], n[1], ""))
	col.add_child(UiKit.label("SPÉCIAUX", 8, UiKit.C_GOLD))
	for slot: Array in SLOTS:
		var mv: Dictionary = moves.get(slot[0], {})
		col.add_child(_row(str(mv.get("name", slot[0])), slot[1], _classic(str(mv.get("classic", "")))))
	var sup: Dictionary = moves.get("super", {})
	col.add_child(_row("SUPER : %s" % str(sup.get("name", "Coup du Txapeldun")), "SPÉCIAL + GARDE (Marée pleine)", ""))
	col.add_child(_row("Spécial renforcé", "SPÉCIAL + GARDE + direction (1 Marée)", ""))
	col.add_child(_row("Finish BUKATU !", "Bas, Bas + SPÉCIAL (tout près)", ""))
	var close: Button = UiKit.button("Fermer", func() -> void:
		closed.emit()
		queue_free(), 80)
	col.add_child(close)
	close.grab_focus.call_deferred()


func _row(name_text: String, input_text: String, classic: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var a: Label = UiKit.label(name_text, 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_LEFT)
	a.custom_minimum_size = Vector2(150, 0)
	a.add_theme_constant_override(&"outline_size", 0)
	row.add_child(a)
	var b: Label = UiKit.label(input_text + (("  [" + classic + "]") if classic != "" else ""), 8,
		UiKit.C_GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	b.add_theme_constant_override(&"outline_size", 0)
	row.add_child(b)
	return row


## « D,DF,F+P » → « Bas, Bas-Av, Av + P ».
func _classic(code: String) -> String:
	if code == "":
		return ""
	var names: Dictionary = {"D": "Bas", "DF": "Bas-Av", "F": "Av", "B": "Arr", "DB": "Bas-Arr",
		"U": "Haut", "UF": "Haut-Av", "UB": "Haut-Arr"}
	var parts: PackedStringArray = code.split("+")
	var dirs: PackedStringArray = []
	for d: String in parts[0].split(","):
		dirs.append(str(names.get(d, d)))
	return ", ".join(dirs) + " + " + (parts[1] if parts.size() > 1 else "P")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()
