extends Control
## Menu principal (SPEC §3) : Pyramide, Versus local, En ligne,
## Entraînement, Profil, Réglages. Navigation clavier/manette + tactile.


func _ready() -> void:
	UiKit.backdrop(self, "bg_menu", 0.25)
	var head: Label = UiKit.title("MIARRITZE BORROKA")
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 6
	add_child(head)
	var profile: Dictionary = Profiles.active()
	if not profile.is_empty():
		var who: Label = UiKit.label("Salut %s !" % str(profile.get("pseudo", "")), 8, UiKit.C_GOLD)
		who.set_anchors_preset(Control.PRESET_TOP_WIDE)
		who.position.y = 26
		add_child(who)
	var buttons: Array = [
		UiKit.button("Pyramide du Phare", _on_tower),
		UiKit.button("Versus", _on_versus),
	]
	var online: Button = UiKit.button("En ligne", _on_online)
	buttons.append(online)
	buttons.append(UiKit.button("Entraînement", _on_training))
	if SceneRouter.has_screen(&"profile_edit"):
		buttons.append(UiKit.button("Profil", func() -> void: SceneRouter.goto(&"profile_edit")))
	if SceneRouter.has_screen(&"settings"):
		buttons.append(UiKit.button("Réglages", func() -> void: SceneRouter.goto(&"settings")))
	UiKit.menu_column(self, buttons, 42)
	online.disabled = not SceneRouter.has_screen(&"lobby")
	AudioManager.play_music(&"title")


func _on_tower() -> void:
	SceneRouter.goto(&"fighter_select", {"mode": "tower"})


func _on_versus() -> void:
	SceneRouter.goto(&"fighter_select", {"mode": "versus"})


func _on_training() -> void:
	SceneRouter.goto(&"fighter_select", {"mode": "training"})


func _on_online() -> void:
	SceneRouter.goto(&"lobby")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		SceneRouter.goto(&"title")
