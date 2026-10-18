class_name PadKeyboard
extends Control
## Clavier à l'écran pour la manette (pseudo, code de groupe) : une grille de
## lettres et de chiffres qu'on parcourt au stick/à la croix, A = ajouter la
## lettre, B = effacer la dernière (ou fermer si c'est vide), START = valider.
## Écrit dans un LineEdit existant (qui reste la source de l'écran) : aucun
## texte libre en plus, seulement les caractères autorisés.

signal submitted(text: String)
signal closed

## Pseudo : lettres, chiffres, - et _ (Profiles.pseudo_ok) ; code de groupe :
## A-Z et 2-9 (backend Validation::isValidGroupCode).
const ROWS_PSEUDO: PackedStringArray = ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ-_", "0123456789"]
const ROWS_CODE: PackedStringArray = ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ", "23456789"]
const CELL_W: float = 24.0
const CELL_H: float = 20.0

var _edit: LineEdit
var _allow_lower: bool = true
var _lower: bool = false
var _display: Label
var _letters: Array[Button] = []
var _first: Button


## Ouvre le clavier par-dessus `parent` pour remplir `edit`.
## `allow_lower` : minuscules possibles (pseudo) ; sinon tout en majuscules (code).
static func open(parent: Control, edit: LineEdit, title_text: String, allow_lower: bool = true) -> PadKeyboard:
	var kb: PadKeyboard = PadKeyboard.new()
	kb._edit = edit
	kb._allow_lower = allow_lower
	kb._build(title_text)
	parent.add_child(kb)
	return kb


## Bouton « Écrire à la manette » à poser près d'un champ : visible seulement
## quand on joue à la manette (il prend alors le focus) ; ouvre le clavier et
## appelle `on_submit(texte)` à la validation.
static func pad_button(parent: Control, edit: LineEdit, title_text: String, allow_lower: bool,
		on_submit: Callable, width: float = 200.0, label_text: String = "Écrire à la manette",
		grab: bool = true) -> Button:
	var b: Button = UiKit.button(label_text, func() -> void: pass, width)
	var screen: Control = parent
	b.pressed.connect(func() -> void:
		var kb: PadKeyboard = PadKeyboard.open(screen.get_tree().current_scene as Control, edit, title_text, allow_lower)
		kb.submitted.connect(on_submit)
		kb.closed.connect(func() -> void:
			if is_instance_valid(b) and b.is_visible_in_tree():
				b.grab_focus.call_deferred()))
	parent.add_child(b)
	Prompts.on_change(b, func() -> void:
		var was: bool = b.visible
		b.visible = InputHub.using_gamepad()
		if b.visible and not was and grab:
			b.grab_focus.call_deferred())
	if InputHub.using_gamepad() and grab:
		b.grab_focus.call_deferred()
	return b


func _build(title_text: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.1, 0.88)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 3)
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.position = Vector2(-130, 8)
	col.custom_minimum_size = Vector2(260, 0)
	add_child(col)
	col.add_child(UiKit.label(title_text, 8, UiKit.C_GOLD))
	_display = UiKit.label("", 16, UiKit.C_LINEN)
	_display.custom_minimum_size = Vector2(260, 22)
	_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(_display)
	var rows: Array = []   # rangées de boutons, pour une navigation qui boucle
	var letter_rows: PackedStringArray = ROWS_PSEUDO if _allow_lower else ROWS_CODE
	for row_text: String in letter_rows:
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 2)
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(line)
		var row: Array[Button] = []
		for i: int in row_text.length():
			var ch: String = row_text[i]
			var b: Button = UiKit.button(ch, _type.bind(ch), CELL_W)
			b.custom_minimum_size = Vector2(CELL_W, CELL_H)
			b.set_meta(&"char", ch)
			line.add_child(b)
			_letters.append(b)
			row.append(b)
		rows.append(row)
	_first = (rows[0] as Array)[0]
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 4)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(actions)
	var action_row: Array[Button] = []
	if _allow_lower:
		action_row.append(UiKit.button("abc / ABC", _toggle_case, 80))
	action_row.append(UiKit.button("Effacer", _erase, 70))
	action_row.append(UiKit.button("OK", _submit, 60))
	for b: Button in action_row:
		actions.add_child(b)
	rows.append(action_row)
	_wire(rows)
	var hint: Label = UiKit.label("", 8, UiKit.C_LINEN)
	Prompts.bind(hint, func() -> String:
		return Prompts.pick({Prompts.GAMEPAD: "{ok} : lettre   {back} : effacer   {pause} : OK",
			Prompts.KEYBOARD: "ENTRÉE : lettre   ÉCHAP : effacer"}))
	col.add_child(hint)
	_refresh()
	_first.grab_focus.call_deferred()


## Voisins de focus explicites qui bouclent dans le clavier : le stick ne
## s'échappe jamais vers les boutons de l'écran caché dessous.
func _wire(rows: Array) -> void:
	for r: int in rows.size():
		var row: Array = rows[r]
		for c: int in row.size():
			var b: Button = row[c]
			var up_row: Array = rows[(r + rows.size() - 1) % rows.size()]
			var down_row: Array = rows[(r + 1) % rows.size()]
			b.focus_neighbor_left = b.get_path_to(row[(c + row.size() - 1) % row.size()])
			b.focus_neighbor_right = b.get_path_to(row[(c + 1) % row.size()])
			b.focus_neighbor_top = b.get_path_to(up_row[_near(c, row.size(), up_row.size())])
			b.focus_neighbor_bottom = b.get_path_to(down_row[_near(c, row.size(), down_row.size())])
			b.focus_next = b.focus_neighbor_right
			b.focus_previous = b.focus_neighbor_left


## Colonne correspondante dans une rangée d'une autre longueur.
static func _near(c: int, from_size: int, to_size: int) -> int:
	return clampi(int(roundf(float(c) * float(to_size - 1) / maxf(float(from_size - 1), 1.0))), 0, to_size - 1)


func _refresh() -> void:
	_display.text = (_edit.text if _edit.text != "" else "_") if is_instance_valid(_edit) else ""
	for b: Button in _letters:
		var ch: String = str(b.get_meta(&"char"))
		b.text = ch.to_lower() if _lower else ch


func _type(ch: String) -> void:
	if not is_instance_valid(_edit):
		return
	if _edit.max_length > 0 and _edit.text.length() >= _edit.max_length:
		AudioManager.sfx(&"ui_no")
		return
	_set_text(_edit.text + (ch.to_lower() if _lower else ch))


func _erase() -> void:
	if is_instance_valid(_edit) and _edit.text != "":
		_set_text(_edit.text.left(-1))


func _set_text(t: String) -> void:
	_edit.text = t
	_edit.text_changed.emit(t)
	_refresh()


func _toggle_case() -> void:
	_lower = not _lower
	_refresh()


func _submit() -> void:
	var t: String = _edit.text if is_instance_valid(_edit) else ""
	_close()
	submitted.emit(t)


func _close() -> void:
	closed.emit()
	queue_free()


## B : efface une lettre, puis ferme quand il n'y a plus rien.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_edit) and _edit.text != "":
			_erase()
		else:
			_close()


## START est aussi dans ui_accept : intercepté avant que la lettre sous le
## curseur ne soit ajoutée.
func _input(event: InputEvent) -> void:
	if InputDevice.is_start(event):
		get_viewport().set_input_as_handled()
		_submit()
