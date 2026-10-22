extends Control
## Mon profil (GDD-BLACKOUT.md) : le perso (grille des 12, vignettes animées au focus ou au
## survol), le pseudo, la couleur préférée (12 pastilles : tous les persos se recolorent) et l'emote
## favorite. Chaque choix est enregistré tout de suite dans le profil.

var _grand: BkAvatar
var _nom: Label
var _vignettes: Dictionary = {}       # id du perso → BkAvatar
var _boutons_perso: Dictionary = {}   # id du perso → Button
var _pastilles: Array[Button] = []
var _emotes: Array[Button] = []
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
	_grand = BkAvatar.cree(BkProfil.perso(), BkRules.color(BkProfil.couleur()), 340)
	_grand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gauche.add_child(_grand)
	_nom = BkUi.label(BkProfil.pseudo(), 40)
	gauche.add_child(_nom)
	gauche.add_child(BkUi.bouton("Changer de pseudo", _changer_pseudo, Vector2(300, 60), BkUi.CREME, 24))
	# À droite : persos, couleurs, emotes.
	var droite: VBoxContainer = VBoxContainer.new()
	droite.alignment = BoxContainer.ALIGNMENT_CENTER
	droite.add_theme_constant_override(&"separation", 12)
	corps.add_child(droite)
	var grille: GridContainer = GridContainer.new()
	grille.columns = 6
	grille.add_theme_constant_override(&"h_separation", 10)
	grille.add_theme_constant_override(&"v_separation", 10)
	droite.add_child(grille)
	for c: Variant in BkRules.data().get("characters", []):
		var id: String = str(c)
		var b: Button = BkUi.bouton("", _choisir_perso.bind(id), Vector2(118, 132), Color.WHITE)
		var av: BkAvatar = BkAvatar.cree(id, BkRules.color(BkProfil.couleur()), 124, false)
		av.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		av.offset_bottom = -6
		b.add_child(av)
		b.tooltip_text = _nom_perso(id)
		b.focus_entered.connect(func() -> void: av.anime = true)
		b.focus_exited.connect(func() -> void: av.anime = false)
		b.mouse_entered.connect(func() -> void: av.anime = true)
		b.mouse_exited.connect(func() -> void: av.anime = b.has_focus())
		grille.add_child(b)
		_vignettes[id] = av
		_boutons_perso[id] = b
	var titre_c: Label = BkUi.label("Ta couleur", 26, BkUi.JAUNE)
	droite.add_child(titre_c)
	var couleurs: HBoxContainer = HBoxContainer.new()
	couleurs.add_theme_constant_override(&"separation", 8)
	couleurs.alignment = BoxContainer.ALIGNMENT_CENTER
	droite.add_child(couleurs)
	var noms: Array = BkRules.data().get("color_names", [])
	for i: int in 12:
		var p: Button = BkUi.bouton("", _choisir_couleur.bind(i), Vector2(54, 52), BkRules.color(i))
		p.tooltip_text = str(noms[i]) if i < noms.size() else ""
		couleurs.add_child(p)
		_pastilles.append(p)
	droite.add_child(BkUi.label("Ton emote", 26, BkUi.JAUNE))
	var emotes: HBoxContainer = HBoxContainer.new()
	emotes.add_theme_constant_override(&"separation", 14)
	emotes.alignment = BoxContainer.ALIGNMENT_CENTER
	droite.add_child(emotes)
	for i: int in BkGame.EMOTES.size():
		var e: Button = BkUi.bouton("", _choisir_emote.bind(i), Vector2(72, 68), Color.WHITE)
		var icone: Icone = Icone.new()
		icone.emote = i
		icone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		e.add_child(icone)
		emotes.add_child(e)
		_emotes.append(e)
	_maj()
	(_boutons_perso.get(BkProfil.perso(), _boutons_perso.values()[0]) as Button).grab_focus.call_deferred()


func _nom_perso(id: String) -> String:
	var chars: Array = BkRules.data().get("characters", [])
	var noms: Array = BkRules.data().get("bot_names", [])
	var i: int = chars.find(id)
	return str(noms[i]) if i >= 0 and i < noms.size() else id.capitalize()


func _choisir_perso(id: String) -> void:
	BkProfil.regler(BkProfil.PERSO, id)
	_grand.regler(id, BkRules.color(BkProfil.couleur()))
	_maj()


func _choisir_couleur(i: int) -> void:
	BkProfil.regler(BkProfil.COULEUR, i)
	for id: String in _vignettes:
		(_vignettes[id] as BkAvatar).regler(id, BkRules.color(i))
	_grand.regler(BkProfil.perso(), BkRules.color(i))
	_maj()


func _choisir_emote(i: int) -> void:
	BkProfil.regler(BkProfil.EMOTE, i)
	_grand.emote(i)
	_maj()


## Choix en cours surlignés : bord épais doré sur le perso, la couleur et l'emote choisis.
func _maj() -> void:
	for id: String in _boutons_perso:
		var b: Button = _boutons_perso[id]
		BkUi.teinter(b, BkUi.JAUNE if id == BkProfil.perso() else Color.WHITE)
	# Couleur choisie : gros cadre blanc (pas de glyphe : la police du web n'a pas toutes les coches).
	for i: int in _pastilles.size():
		var sb: StyleBoxFlat = (_pastilles[i].get_theme_stylebox(&"normal") as StyleBoxFlat).duplicate()
		var choisie: bool = i == BkProfil.couleur()
		sb.border_color = Color.WHITE if choisie else BkUi.INK
		sb.set_border_width_all(7 if choisie else BkUi.BORD)
		sb.border_width_bottom = 7 if choisie else BkUi.BORD + 6
		_pastilles[i].add_theme_stylebox_override(&"normal", sb)
		_pastilles[i].add_theme_stylebox_override(&"hover", sb)
	for i: int in _emotes.size():
		BkUi.teinter(_emotes[i], BkUi.JAUNE if i == BkProfil.emote() else Color.WHITE)


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


## Icône d'une emote dans son bouton.
class Icone extends Control:
	var emote: int = 0

	func _draw() -> void:
		BkDraw.emote_icon(self, size * 0.5, minf(size.x, size.y) * 0.32, emote)
