extends Control
## En ligne (SPEC-GORDEKA §6.2) : écran d'attente « Salons en ligne : bientôt ». Les salons sont
## développés à part ; pour les brancher, remplacer cette scène (BkNav.ECRANS["en_ligne"]).


func _ready() -> void:
	var racine: MarginContainer = BkEcran.ecran(self)
	var page: VBoxContainer = VBoxContainer.new()
	racine.add_child(page)
	BkEcran.entete(page, "En ligne", func() -> void: BkNav.aller("accueil"))
	var centre: CenterContainer = CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(centre)
	var p: PanelContainer = BkUi.panneau(36)
	centre.add_child(p)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 20)
	p.add_child(col)
	var t: Label = BkUi.label("Salons en ligne : bientôt !", 44, BkUi.BLEU.darkened(0.2))
	t.add_theme_constant_override(&"outline_size", 0)
	col.add_child(t)
	var l: Label = BkUi.label("Tu pourras jouer avec les copains,\nchacun sur son appareil.", 28, BkUi.INK)
	l.add_theme_constant_override(&"outline_size", 0)
	col.add_child(l)
	var ok: Button = BkUi.bouton("Retour", func() -> void: BkNav.aller("accueil"), Vector2(280, 76), BkUi.JAUNE)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ok)
	ok.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		BkNav.aller("accueil")
