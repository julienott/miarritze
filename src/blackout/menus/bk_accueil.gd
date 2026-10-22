extends Control
## Accueil (SPEC-GORDEKA §6.0) : quatre gros boutons Partie rapide, En ligne, Mon profil, Réglages,
## avec l'avatar animé du profil actif à côté (le toucher ouvre Mon profil). « Changer de joueur »
## revient à « Qui joue ? ». Les boutons « DEBUG · Visite » restent en bas (temporaires).


func _ready() -> void:
	if not GkProfil.a_un_actif():
		GkNav.aller("qui_joue")
		return
	var racine: MarginContainer = GkEcran.ecran(self)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	racine.add_child(col)
	var titre: Label = GkUi.titre("MIARRITZE GORDEKA")
	titre.add_theme_font_size_override(&"font_size", 64)
	col.add_child(titre)
	var sous: Label = GkUi.label("Cache-cache à Biarritz", 26, Color(1, 1, 1, 0.9))
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
	var av: GkAvatar = GkAvatar.cree(GkProfil.perso(), GkRules.color(GkProfil.couleur()), 330)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	joueur.add_child(av)
	joueur.add_child(GkUi.label(GkProfil.pseudo(), 40, Color.WHITE))
	joueur.add_child(GkUi.bouton("Changer de joueur", func() -> void: GkNav.aller("qui_joue"),
		Vector2(300, 56), GkUi.CREME, 22))
	# Les quatre gros boutons.
	var grille: GridContainer = GridContainer.new()
	grille.columns = 2
	grille.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grille.add_theme_constant_override(&"h_separation", 22)
	grille.add_theme_constant_override(&"v_separation", 22)
	milieu.add_child(grille)
	var taille: Vector2 = Vector2(330, 150)
	var jouer: Button = GkUi.bouton("Partie rapide", func() -> void: GkNav.aller("partie_rapide"), taille,
		GkUi.JAUNE, 36)
	grille.add_child(jouer)
	grille.add_child(GkUi.bouton("En ligne", func() -> void: GkNav.aller("en_ligne"), taille, GkUi.BLEU, 36))
	grille.add_child(GkUi.bouton("Mon profil", func() -> void: GkNav.aller("profil"), taille, GkUi.VERT, 36))
	grille.add_child(GkUi.bouton("Réglages", func() -> void: GkNav.aller("reglages"), taille, GkUi.GRIS, 36))
	# TEMPORAIRE, debug (Julien, 2026-10-20) : visite de la carte en chassé ou en chasseur (GkGame.visite).
	var dbg: HBoxContainer = HBoxContainer.new()
	dbg.alignment = BoxContainer.ALIGNMENT_CENTER
	dbg.add_theme_constant_override(&"separation", 12)
	col.add_child(dbg)
	for spec: Array in [["DEBUG · Visite : chassé", "chasse"], ["DEBUG · Visite : chasseur", "chasseur"]]:
		var mode: String = str(spec[1])
		var b: Button = GkUi.bouton(str(spec[0]), func() -> void: _visite(mode), Vector2(300, 48),
			Color("3a3f4b"), 20)
		b.add_theme_color_override(&"font_color", GkUi.JAUNE)
		b.add_theme_color_override(&"font_focus_color", GkUi.JAUNE)
		b.add_theme_color_override(&"font_hover_color", GkUi.JAUNE)
		dbg.add_child(b)
	jouer.grab_focus.call_deferred()


func _visite(mode: String) -> void:
	GkProfil.vers_partie()
	GkGame.config["visite"] = mode
	GkNav.aller("game")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		GkNav.aller("qui_joue")
		get_viewport().set_input_as_handled()
