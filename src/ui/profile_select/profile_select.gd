extends Control
## Choix du profil (SPEC §3.1) : jusqu'à 4 profils locaux sur l'appareil
## (frères, sœurs, copains). Créer, choisir, supprimer.

## Contenu centré sous le titre, quelle que soit la taille de l'écran
## (Steam Deck 16:10 = 384×240, iPhone plus large que 384).
var _wrap: CenterContainer
var _box: VBoxContainer
var _creating: bool = false

const TOP: float = 28.0


func _ready() -> void:
	AudioManager.play_music(&"hegoak")
	UiKit.backdrop(self, "bg_menu", 0.45)
	var head: Label = UiKit.title("QUI JOUE ?")
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 8
	add_child(head)
	if Profiles.profiles.is_empty():
		_show_create(true)
	else:
		_show_list()


func _clear() -> void:
	if _wrap != null:
		_wrap.queue_free()
	_wrap = null
	_box = null


func _column(buttons: Array, separation: int = 4) -> VBoxContainer:
	_wrap = CenterContainer.new()
	_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wrap.offset_top = TOP
	add_child(_wrap)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override(&"separation", separation)
	_wrap.add_child(box)
	for b: Variant in buttons:
		box.add_child(b as Control)
	if not buttons.is_empty():
		(buttons[0] as Control).grab_focus.call_deferred()
	return box


func _show_list() -> void:
	_clear()
	var buttons: Array = []
	for i: int in Profiles.profiles.size():
		var prof: Dictionary = Profiles.profiles[i]
		var title_id: String = str(prof.get("title", ""))
		var title_text: String = str(Profiles.TITLES.get(title_id, ["", ""])[0]) if title_id != "" else ""
		var label: String = str(prof.get("pseudo", "?")) + ("  — " + title_text if title_text != "" else "")
		buttons.append(UiKit.button(label, _choose.bind(i), 200))
	if Profiles.profiles.size() < Profiles.MAX_PROFILES:
		buttons.append(UiKit.button("+ Nouveau profil", func() -> void: _show_create(false), 200))
	buttons.append(UiKit.button("Supprimer un profil", _show_delete, 200))
	_box = _column(buttons)


func _choose(i: int) -> void:
	Profiles.select(i)
	SceneRouter.goto(&"main_menu")


func _show_delete() -> void:
	_clear()
	var buttons: Array = []
	for i: int in Profiles.profiles.size():
		buttons.append(UiKit.button("Supprimer %s" % str(Profiles.profiles[i].get("pseudo", "?")),
			_confirm_delete.bind(i), 200))
	buttons.append(UiKit.button("Annuler", _show_list, 200))
	_box = _column(buttons)


## Confirmation : un enfant ne doit pas effacer le profil de son frère par erreur.
func _confirm_delete(i: int) -> void:
	_clear()
	var pseudo: String = str(Profiles.profiles[i].get("pseudo", "?"))
	_box = _column([
		UiKit.button("Non, garder %s" % pseudo, _show_list, 220),
		UiKit.button("Oui, effacer %s pour toujours" % pseudo, func() -> void:
			Profiles.remove(i)
			if Profiles.profiles.is_empty():
				_show_create(true)
			else:
				_show_list(), 220),
	])


func _show_create(first: bool) -> void:
	_clear()
	_box = _column([], 6)
	_box.custom_minimum_size = Vector2(200, 0)
	_box.add_child(UiKit.label("Ton pseudo (pas ton vrai nom !)", 8, UiKit.C_GOLD))
	_box.add_child(UiKit.label("Lettres et chiffres, sans espace", 8, UiKit.C_LINEN))
	var edit: LineEdit = LineEdit.new()
	edit.max_length = 15
	edit.placeholder_text = "Pseudo"
	edit.custom_minimum_size = Vector2(200, 28)
	edit.add_theme_font_size_override(&"font_size", 12)
	# Cadre doré visible au focus : sur Mac le LineEdit par défaut est
	# quasi invisible à cette taille, Louis ne voyait pas où il tapait.
	var sb_normal: StyleBoxFlat = StyleBoxFlat.new()
	sb_normal.bg_color = Color8(247, 241, 227)
	sb_normal.border_color = Color8(58, 38, 52)
	sb_normal.set_border_width_all(1)
	sb_normal.set_content_margin_all(4)
	var sb_focus: StyleBoxFlat = sb_normal.duplicate()
	sb_focus.border_color = UiKit.C_GOLD
	sb_focus.set_border_width_all(2)
	edit.add_theme_stylebox_override(&"normal", sb_normal)
	edit.add_theme_stylebox_override(&"focus", sb_focus)
	edit.add_theme_color_override(&"font_color", Color8(58, 38, 52))
	edit.add_theme_color_override(&"caret_color", Color8(58, 38, 52))
	_box.add_child(edit)
	WebTextField.attach(edit)
	var err: Label = UiKit.label("", 8, UiKit.C_RED)
	_box.add_child(err)
	# Manette : choisir les lettres une à une (clavier à l'écran).
	var pad_btn: Button = PadKeyboard.pad_button(_box, edit, "Ton pseudo (pas ton vrai nom !)", true,
		func(t: String) -> void: _create(t, err))
	var ok: Button = UiKit.button("C'est parti !", func() -> void: _create(edit.text, err), 200)
	_box.add_child(ok)
	edit.text_submitted.connect(func(t: String) -> void: _create(t, err))
	if not first:
		_box.add_child(UiKit.button("Annuler", _show_list, 200))
	if InputHub.using_gamepad():
		pad_btn.grab_focus.call_deferred()
	elif edit.focus_mode != Control.FOCUS_NONE:
		edit.grab_focus.call_deferred()
	else:
		# Web : le champ HTML a le clavier ; le bouton garde un focus visible.
		ok.grab_focus.call_deferred()


func _create(pseudo: String, err: Label) -> void:
	if not Profiles.pseudo_ok(pseudo):
		err.text = "2 à 15 lettres ou chiffres"
		AudioManager.sfx(&"ui_no")
		return
	Profiles.create(pseudo.strip_edges())
	# Premier lancement : tutoriel guidé contre Hondar (§7.5).
	InputHub.set_solo()
	SceneRouter.goto(&"fight", TrainingMode.tutorial_params())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not Profiles.profiles.is_empty():
		SceneRouter.goto(&"title")
