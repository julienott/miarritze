class_name GkSaisiePseudo
extends PanelContainer
## Saisie du pseudo (SPEC-GORDEKA §6.0) : champ de texte (vrai champ HTML sur le web, pour le clavier
## de l'iPhone : WebTextField), rappel « pas ton vrai nom ! », message d'erreur, et à la manette une
## grille de lettres (seuls les caractères permis). `valider(texte) -> String` renvoie l'erreur, ou ""
## si le pseudo est accepté ; `annuler` (facultatif) ajoute un bouton Annuler.

const LETTRES: PackedStringArray = ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ-_", "0123456789"]

var valider: Callable
var annuler: Callable
var texte_initial: String = ""
var edit: LineEdit
var _err: Label
var _grille: VBoxContainer
var _ok: Button
var _min: bool = false


func _ready() -> void:
	var sb: StyleBoxFlat = GkUi._box(Color(GkUi.CREME, 0.97))
	sb.set_content_margin_all(28)
	add_theme_stylebox_override(&"panel", sb)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 14)
	add_child(col)
	var titre: Label = GkUi.label("Ton pseudo — pas ton vrai nom !", 32, GkUi.INK)
	titre.add_theme_constant_override(&"outline_size", 0)
	col.add_child(titre)
	var aide: Label = GkUi.label("2 à 15 lettres ou chiffres, sans espace", 22, Color(GkUi.INK, 0.7))
	aide.add_theme_constant_override(&"outline_size", 0)
	col.add_child(aide)
	edit = LineEdit.new()
	edit.max_length = 15
	edit.placeholder_text = "Pseudo"
	edit.text = texte_initial
	edit.custom_minimum_size = Vector2(560, 76)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(edit)
	WebTextField.attach(edit)
	edit.text_submitted.connect(func(_t: String) -> void: _envoyer())
	_err = GkUi.label("", 24, Color("c8321f"))
	_err.add_theme_constant_override(&"outline_size", 0)
	col.add_child(_err)
	_grille = VBoxContainer.new()
	_grille.add_theme_constant_override(&"separation", 6)
	col.add_child(_grille)
	_construire_grille()
	var bas: HBoxContainer = HBoxContainer.new()
	bas.alignment = BoxContainer.ALIGNMENT_CENTER
	bas.add_theme_constant_override(&"separation", 18)
	col.add_child(bas)
	if annuler.is_valid():
		bas.add_child(GkUi.bouton("Annuler", annuler, Vector2(220, 76)))
	_ok = GkUi.bouton("C'est parti !", _envoyer, Vector2(300, 76), GkUi.VERT)
	bas.add_child(_ok)
	Prompts.on_change(self, _maj_appareil)
	_maj_appareil()


func _maj_appareil() -> void:
	var manette: bool = InputHub.using_gamepad()
	_grille.visible = manette
	if manette:
		var b: Control = _grille.get_child(0).get_child(0) as Control
		b.grab_focus.call_deferred()
	elif edit.focus_mode != Control.FOCUS_NONE:
		edit.grab_focus.call_deferred()
	else:
		_ok.grab_focus.call_deferred()      # web : le champ HTML a le clavier


## Lettres (manette) : A ajoute la lettre, « Effacer », « abc », puis OK.
func _construire_grille() -> void:
	for c: Node in _grille.get_children():
		c.queue_free()
	for rang: String in LETTRES:
		var h: HBoxContainer = HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override(&"separation", 6)
		_grille.add_child(h)
		for i: int in rang.length():
			var ch: String = rang[i].to_lower() if _min else rang[i]
			var b: Button = GkUi.bouton(ch, _taper.bind(ch), Vector2(54, 50), Color.WHITE, 24)
			h.add_child(b)
	var act: HBoxContainer = HBoxContainer.new()
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	act.add_theme_constant_override(&"separation", 10)
	_grille.add_child(act)
	act.add_child(GkUi.bouton("abc / ABC", func() -> void:
		_min = not _min
		_construire_grille()
		_maj_appareil(), Vector2(170, 50), Color.WHITE, 22))
	act.add_child(GkUi.bouton("Effacer", func() -> void:
		edit.text = edit.text.left(-1)
		edit.text_changed.emit(edit.text), Vector2(150, 50), Color.WHITE, 22))


func _taper(ch: String) -> void:
	if edit.text.length() < edit.max_length:
		edit.text += ch
		edit.text_changed.emit(edit.text)


func _envoyer() -> void:
	if not valider.is_valid():
		return
	var err: String = str(valider.call(edit.text))
	_err.text = err
