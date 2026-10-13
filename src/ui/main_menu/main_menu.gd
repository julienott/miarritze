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
		UiKit.button("Combat rapide", _on_quick),
		UiKit.button("Versus", _on_versus),
	]
	var online: Button = UiKit.button("En ligne", _on_online)
	buttons.append(online)
	buttons.append(UiKit.button("Entraînement", _on_training))
	buttons.append(UiKit.button("Tutoriel", func() -> void:
		InputHub.set_solo()
		SceneRouter.goto(&"fight", TrainingMode.tutorial_params(str(Profiles.active().get("fighter", "louis"))))))
	if SceneRouter.has_screen(&"profile_edit"):
		buttons.append(UiKit.button("Profil", func() -> void: SceneRouter.goto(&"profile_edit")))
	if SceneRouter.has_screen(&"settings"):
		buttons.append(UiKit.button("Réglages", func() -> void: SceneRouter.goto(&"settings")))
	UiKit.menu_grid(self, buttons, 50)
	online.disabled = not SceneRouter.has_screen(&"lobby")
	# Web : une manette ne se signale qu'après un premier appui (§7.2).
	if OS.has_feature("web") and Input.get_connected_joypads().is_empty() and not Settings.touch_enabled():
		_pad_hint = UiKit.label("Manette ? Appuie sur un de ses boutons", 8, UiKit.C_LINEN)
		_pad_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_pad_hint.position.y = -12
		add_child(_pad_hint)
		Input.joy_connection_changed.connect(func(_d: int, connected: bool) -> void:
			if connected and is_instance_valid(_pad_hint):
				_pad_hint.text = "Manette détectée !")
	AudioManager.play_music(&"hegoak")


var _pad_hint: Label


func _on_tower() -> void:
	SceneRouter.goto(&"fighter_select", {"mode": "tower"})


func _on_versus() -> void:
	SceneRouter.goto(&"fighter_select", {"mode": "versus"})


func _on_training() -> void:
	SceneRouter.goto(&"fighter_select", {"mode": "training"})


## Combat rapide : perso du profil contre un adversaire aléatoire sur un
## stage aléatoire, 3 rounds, IA Normal. Un seul clic pour jouer.
func _on_quick() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var me: String = str(Profiles.active().get("fighter", "louis"))
	var others: Array[String] = []
	for id: String in Roster.FIGHTERS:
		if id != me:
			others.append(id)
	var opp: String = others[rng.randi() % others.size()]
	var stages: Array[String] = []
	for s: String in Roster.STAGES:
		if s != "phare_sommet":
			stages.append(s)
	var stage: String = stages[rng.randi() % stages.size()]
	InputHub.set_solo()
	SceneRouter.goto(&"fight", {"p1": me, "p2": opp, "c1": 0, "c2": 0,
		"stage": stage, "rounds": 3, "ai": [0, 2],
		"mode": "quick", "return_to": "main_menu"})


func _on_online() -> void:
	SceneRouter.goto(&"lobby")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		SceneRouter.goto(&"title")
