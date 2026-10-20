extends Control
## En ligne (SPEC-GORDEKA §6.2) : écran d'attente « Salons en ligne : bientôt ». Les salons sont
## développés à part ; pour les brancher, remplacer cette scène (GkNav.ECRANS["en_ligne"]).


func _ready() -> void:
	var racine: MarginContainer = GkEcran.ecran(self)
	var page: VBoxContainer = VBoxContainer.new()
	racine.add_child(page)
	GkEcran.entete(page, "En ligne", func() -> void: GkNav.aller("accueil"))
	var centre: CenterContainer = CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(centre)
	var p: PanelContainer = GkUi.panneau(36)
	centre.add_child(p)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 20)
	p.add_child(col)
	var t: Label = GkUi.label("Salons en ligne : bientôt !", 44, GkUi.BLEU.darkened(0.2))
	t.add_theme_constant_override(&"outline_size", 0)
	col.add_child(t)
	var l: Label = GkUi.label("Tu pourras jouer avec les copains,\nchacun sur son appareil.", 28, GkUi.INK)
	l.add_theme_constant_override(&"outline_size", 0)
	col.add_child(l)
	var ok: Button = GkUi.bouton("Retour", func() -> void: GkNav.aller("accueil"), Vector2(280, 76), GkUi.JAUNE)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ok)
	ok.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		GkNav.aller("accueil")
