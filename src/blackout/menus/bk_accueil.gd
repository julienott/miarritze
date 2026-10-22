extends Control
## Accueil (GDD-BLACKOUT.md) : quatre gros boutons Partie rapide, En ligne, Mon profil, Réglages,
## avec l'avatar animé du profil actif à côté (le toucher ouvre Mon profil). « Changer de joueur »
## revient à « Qui joue ? ». Le debug (et la visite de la carte) est dans la partie rapide (GDD §7.2).


func _ready() -> void:
	if not BkProfil.a_un_actif():
		BkNav.aller("qui_joue")
		return
	var racine: MarginContainer = BkEcran.ecran(self)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	racine.add_child(col)
	var titre: Label = BkUi.titre("MIARRITZE BLACKOUT")
	titre.add_theme_font_size_override(&"font_size", 64)
	col.add_child(titre)
	var sous: Label = BkUi.label("Cache-cache à Biarritz", 26, Color(1, 1, 1, 0.9))
	col.add_child(sous)
	var milieu: HBoxContainer = HBoxContainer.new()
	milieu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	milieu.alignment = BoxContainer.ALIGNMENT_CENTER
	milieu.add_theme_constant_override(&"separation", 70)
	col.add_child(milieu)
	# Le joueur : avatar animé, pseudo.
	var joueur: VBoxContainer = VBoxContainer.new()
	joueur.alignment = BoxContainer.ALIGNMENT_CENTER
	joueur.add_theme_constant_override(&"separation", 4)
	milieu.add_child(joueur)
	var av: BkAvatar = BkAvatar.cree(BkProfil.perso(), 330)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	joueur.add_child(av)
	joueur.add_child(BkUi.label(BkProfil.pseudo(), 40, Color.WHITE))
	joueur.add_child(BkUi.bouton("Changer de joueur", func() -> void: BkNav.aller("qui_joue"),
		Vector2(300, 56), BkUi.CREME, 22))
	# Les quatre gros boutons.
	var grille: GridContainer = GridContainer.new()
	grille.columns = 2
	grille.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grille.add_theme_constant_override(&"h_separation", 22)
	grille.add_theme_constant_override(&"v_separation", 22)
	milieu.add_child(grille)
	var taille: Vector2 = Vector2(330, 150)
	var jouer: Button = BkUi.bouton("Partie rapide", func() -> void: BkNav.aller("partie_rapide"), taille,
		BkUi.JAUNE, 36)
	grille.add_child(jouer)
	grille.add_child(BkUi.bouton("En ligne", func() -> void: BkNav.aller("en_ligne"), taille, BkUi.BLEU, 36))
	grille.add_child(BkUi.bouton("Mon profil", func() -> void: BkNav.aller("profil"), taille, BkUi.VERT, 36))
	grille.add_child(BkUi.bouton("Réglages", func() -> void: BkNav.aller("reglages"), taille, BkUi.GRIS, 36))
	jouer.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		BkNav.aller("qui_joue")
		get_viewport().set_input_as_handled()
