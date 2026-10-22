extends Control
## Mon profil (GDD-BLACKOUT.md §7.1) : le perso (grille des 13, vignettes animées au focus ou au
## survol, son nom dessous) et le pseudo. Rien d'autre : ni couleur, ni emote, ni cosmétique.
## Chaque choix est enregistré tout de suite dans le profil.

var _grand: BkAvatar
var _nom: Label
var _vignettes: Dictionary = {}       # id du perso → BkAvatar
var _boutons_perso: Dictionary = {}   # id du perso → Button
var _nom_perso: Label
var _racine: MarginContainer
var _page: VBoxContainer
var _saisie: Control


func _ready() -> void:
	if not BkProfil.a_un_actif():
		BkNav.aller("qui_joue")
		return
	_racine = BkEcran.ecran(self)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override(&"separation", 10)
	_racine.add_child(_page)
	BkEcran.entete(_page, "Mon profil", func() -> void: BkNav.aller("accueil"))
	var corps: HBoxContainer = HBoxContainer.new()
	corps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corps.alignment = BoxContainer.ALIGNMENT_CENTER
	corps.add_theme_constant_override(&"separation", 34)
	_page.add_child(corps)
	# À gauche : le perso en grand, son pseudo (bouton pour le changer).
	var gauche: VBoxContainer = VBoxContainer.new()
	gauche.alignment = BoxContainer.ALIGNMENT_CENTER
	gauche.add_theme_constant_override(&"separation", 8)
	corps.add_child(gauche)
	_grand = BkAvatar.cree(BkProfil.perso(), 340)
	_grand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gauche.add_child(_grand)
	_nom = BkUi.label(BkProfil.pseudo(), 40)
	gauche.add_child(_nom)
	gauche.add_child(BkUi.bouton("Changer de pseudo", _changer_pseudo, Vector2(300, 60), BkUi.CREME, 24))
	gauche.add_child(BkUi.label("Pas ton vrai nom !", 22, Color(1, 1, 1, 0.8)))
	# À droite : les persos.
	var droite: VBoxContainer = VBoxContainer.new()
	droite.alignment = BoxContainer.ALIGNMENT_CENTER
	droite.add_theme_constant_override(&"separation", 12)
	corps.add_child(droite)
	var grille: GridContainer = GridContainer.new()
	grille.columns = 5
	grille.add_theme_constant_override(&"h_separation", 10)
	grille.add_theme_constant_override(&"v_separation", 10)
	droite.add_child(grille)
	for c: Variant in BkRules.data().get("characters", []):
		var id: String = str(c)
		var b: Button = BkUi.bouton("", _choisir_perso.bind(id), Vector2(118, 132), Color.WHITE)
		var av: BkAvatar = BkAvatar.cree(id, 112, false)
		av.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		av.offset_bottom = -6
		b.add_child(av)
		b.tooltip_text = _nom_perso_de(id)
		b.focus_entered.connect(func() -> void: av.anime = true)
		b.focus_exited.connect(func() -> void: av.anime = false)
		b.mouse_entered.connect(func() -> void: av.anime = true)
		b.mouse_exited.connect(func() -> void: av.anime = b.has_focus())
		grille.add_child(b)
		_vignettes[id] = av
		_boutons_perso[id] = b
	_nom_perso = BkUi.label("", 30, BkUi.JAUNE)
	droite.add_child(_nom_perso)
	_maj()
	(_boutons_perso.get(BkProfil.perso(), _boutons_perso.values()[0]) as Button).grab_focus.call_deferred()


func _nom_perso_de(id: String) -> String:
	var chars: Array = BkRules.data().get("characters", [])
	var noms: Array = BkRules.data().get("bot_names", [])
	var i: int = chars.find(id)
	return str(noms[i]) if i >= 0 and i < noms.size() else id.capitalize()


func _choisir_perso(id: String) -> void:
	BkProfil.regler(BkProfil.PERSO, id)
	_grand.regler(id)
	_maj()


## Perso choisi surligné (fond doré) et son nom sous la grille.
func _maj() -> void:
	for id: String in _boutons_perso:
		var b: Button = _boutons_perso[id]
		BkUi.teinter(b, BkUi.JAUNE if id == BkProfil.perso() else Color.WHITE)
	_nom_perso.text = _nom_perso_de(BkProfil.perso())


func _changer_pseudo() -> void:
	_page.visible = false
	_saisie = CenterContainer.new()
	_racine.add_child(_saisie)
	var s: BkSaisiePseudo = BkSaisiePseudo.new()
	s.texte_initial = BkProfil.pseudo()
	s.valider = func(texte: String) -> String:
		var err: String = BkProfil.erreur_pseudo(texte)
		var p: Node = BkProfil.profiles()
		for i: int in p.profiles.size():
			if i != p.active_index and str(p.profiles[i].get("pseudo", "")).to_lower() == texte.strip_edges().to_lower():
				err = "Ce pseudo est déjà sur cet appareil"
		if err == "":
			BkProfil.regler("pseudo", texte.strip_edges())
			_nom.text = BkProfil.pseudo()
			_fermer_saisie()
		return err
	s.annuler = _fermer_saisie
	_saisie.add_child(s)


func _fermer_saisie() -> void:
	if _saisie != null:
		_saisie.queue_free()
		_saisie = null
	_page.visible = true
	(_boutons_perso.get(BkProfil.perso()) as Button).grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _saisie != null:
			_fermer_saisie()
		else:
			BkNav.aller("accueil")

