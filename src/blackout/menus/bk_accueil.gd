extends Control
## Accueil (SPEC-GORDEKA §6.0) : quatre gros boutons Partie rapide, En ligne, Mon profil, Réglages,
## avec l'avatar animé du profil actif à côté (le toucher ouvre Mon profil). « Changer de joueur »
## revient à « Qui joue ? ». Les boutons « DEBUG · Visite » restent en bas (temporaires).


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
	var av: BkAvatar = BkAvatar.cree(BkProfil.perso(), BkRules.color(BkProfil.couleur()), 330)
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
	# TEMPORAIRE, debug (Julien, 2026-10-20) : visite de la carte en chassé ou en chasseur (BkGame.visite).
	var dbg: HBoxContainer = HBoxContainer.new()
	dbg.alignment = BoxContainer.ALIGNMENT_CENTER
	dbg.add_theme_constant_override(&"separation", 12)
	col.add_child(dbg)
	for spec: Array in [["DEBUG · Visite : chassé", "chasse"], ["DEBUG · Visite : chasseur", "chasseur"]]:
		var mode: String = str(spec[1])
		var b: Button = BkUi.bouton(str(spec[0]), func() -> void: _visite(mode), Vector2(300, 48),
			Color("3a3f4b"), 20)
		b.add_theme_color_override(&"font_color", BkUi.JAUNE)
		b.add_theme_color_override(&"font_focus_color", BkUi.JAUNE)
		b.add_theme_color_override(&"font_hover_color", BkUi.JAUNE)
		dbg.add_child(b)
	jouer.grab_focus.call_deferred()


func _visite(mode: String) -> void:
	BkProfil.vers_partie()
	BkGame.config["visite"] = mode
	BkNav.aller("game")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		BkNav.aller("qui_joue")
		get_viewport().set_input_as_handled()
