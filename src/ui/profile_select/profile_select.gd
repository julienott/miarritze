extends Control
## Choix du profil (SPEC §3.1) : jusqu'à 4 profils locaux sur l'appareil
## (frères, sœurs, copains). Créer, choisir, supprimer.

var _box: VBoxContainer
var _creating: bool = false


func _ready() -> void:
	AudioManager.play_music(&"title")
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
	if _box != null:
		_box.queue_free()
	_box = null


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
	_box = UiKit.menu_column(self, buttons, 40)
	_box.position.x -= 30


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
	_box = UiKit.menu_column(self, buttons, 40)
	_box.position.x -= 30


## Confirmation : un enfant ne doit pas effacer le profil de son frère par erreur.
func _confirm_delete(i: int) -> void:
	_clear()
	var pseudo: String = str(Profiles.profiles[i].get("pseudo", "?"))
	_box = UiKit.menu_column(self, [
		UiKit.button("Non, garder %s" % pseudo, _show_list, 220),
		UiKit.button("Oui, effacer %s pour toujours" % pseudo, func() -> void:
			Profiles.remove(i)
			if Profiles.profiles.is_empty():
				_show_create(true)
			else:
				_show_list(), 220),
	], 60)
	_box.position.x -= 40


func _show_create(first: bool) -> void:
	_clear()
	_box = VBoxContainer.new()
	_box.add_theme_constant_override(&"separation", 6)
	_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_box.position = Vector2(-100, 44)
	_box.custom_minimum_size = Vector2(200, 0)
	add_child(_box)
	_box.add_child(UiKit.label("Ton pseudo (pas ton vrai nom !)", 8, UiKit.C_GOLD))
	_box.add_child(UiKit.label("Lettres et chiffres, sans espace", 8, UiKit.C_LINEN))
	var edit: LineEdit = LineEdit.new()
	edit.max_length = 15
	edit.placeholder_text = "Pseudo"
	edit.custom_minimum_size = Vector2(200, 22)
	edit.add_theme_font_size_override(&"font_size", 8)
	_box.add_child(edit)
	var err: Label = UiKit.label("", 8, UiKit.C_RED)
	_box.add_child(err)
	var ok: Button = UiKit.button("C'est parti !", func() -> void: _create(edit.text, err), 200)
	_box.add_child(ok)
	edit.text_submitted.connect(func(t: String) -> void: _create(t, err))
	if not first:
		_box.add_child(UiKit.button("Annuler", _show_list, 200))
	edit.grab_focus.call_deferred()


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
