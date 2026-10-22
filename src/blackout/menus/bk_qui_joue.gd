extends Control
## « Qui joue ? » au lancement (SPEC-GORDEKA §6.0) : jusqu'à 4 profils sur l'appareil (frères et
## sœurs). Une carte par profil (avatar animé, pseudo) : la toucher choisit le profil. « Nouveau »
## crée un profil (pseudo, rappel « pas ton vrai nom ! »), « Supprimer » passe en mode effacement,
## toujours avec une confirmation.

var _racine: MarginContainer
var _corps: VBoxContainer
var _suppression: bool = false


func _ready() -> void:
	_racine = BkEcran.ecran(self)
	if BkProfil.profiles().profiles.is_empty():
		_creation(true)
	elif BkRules.args().has("--bk-qa-effacer"):
		_confirmer(0)        # QA : capture de la confirmation
	else:
		_liste()


func _vider() -> void:
	if _corps != null:
		_corps.queue_free()
	_corps = VBoxContainer.new()
	_corps.add_theme_constant_override(&"separation", 22)
	_racine.add_child(_corps)


func _liste() -> void:
	_vider()
	_corps.add_child(BkUi.titre("Qui joue ?" if not _suppression else "Quel profil effacer ?"))
	var centre: CenterContainer = CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_corps.add_child(centre)
	var rang: HBoxContainer = HBoxContainer.new()
	rang.add_theme_constant_override(&"separation", 26)
	centre.add_child(rang)
	var p: Node = BkProfil.profiles()
	var premier: Button = null
	for i: int in p.profiles.size():
		var prof: Dictionary = p.profiles[i]
		var carte: Button = _carte(str(prof.get("pseudo", "?")), str(prof.get(BkProfil.PERSO, "louis")),
			BkRules.color(int(prof.get(BkProfil.COULEUR, 0))), _choisi.bind(i))
		if _suppression:
			BkUi.teinter(carte, Color("ffb3a8"))
		rang.add_child(carte)
		if i == p.active_index or premier == null:
			premier = carte
	if p.profiles.size() < p.MAX_PROFILES and not _suppression:
		var neuf: Button = BkUi.bouton("+\nNouveau", func() -> void: _creation(false), Vector2(230, 330),
			Color("d7f3df"), 34)
		rang.add_child(neuf)
	var bas: HBoxContainer = HBoxContainer.new()
	bas.alignment = BoxContainer.ALIGNMENT_CENTER
	bas.add_theme_constant_override(&"separation", 20)
	_corps.add_child(bas)
	if _suppression:
		bas.add_child(BkUi.bouton("Annuler", func() -> void:
			_suppression = false
			_liste(), Vector2(300, 72)))
	else:
		bas.add_child(BkUi.bouton("Effacer un profil", func() -> void:
			_suppression = true
			_liste(), Vector2(300, 64), BkUi.CREME, 24))
	if premier != null:
		premier.grab_focus.call_deferred()


## Carte d'un profil : avatar figé qui s'anime au focus ou au survol, pseudo dessous.
func _carte(pseudo: String, perso: String, couleur: Color, action: Callable) -> Button:
	var b: Button = BkUi.bouton("", action, Vector2(230, 330))
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 14
	col.offset_bottom = -14
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var av: BkAvatar = BkAvatar.cree(perso, couleur, 230, false)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(av)
	var nom: Label = BkUi.label(pseudo, 30, BkUi.INK)
	nom.add_theme_constant_override(&"outline_size", 0)
	nom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(nom)
	b.focus_entered.connect(func() -> void: av.anime = true)
	b.focus_exited.connect(func() -> void: av.anime = false)
	b.mouse_entered.connect(func() -> void: av.anime = true)
	b.mouse_exited.connect(func() -> void: av.anime = b.has_focus())
	return b


func _choisi(i: int) -> void:
	if _suppression:
		_confirmer(i)
		return
	BkProfil.profiles().select(i)
	BkNav.aller("accueil")


## Confirmation : un enfant ne doit pas effacer le profil de son frère par erreur.
func _confirmer(i: int) -> void:
	_vider()
	var p: Node = BkProfil.profiles()
	var prof: Dictionary = p.profiles[i]
	var pseudo: String = str(prof.get("pseudo", "?"))
	_corps.add_child(BkUi.titre("Effacer %s ?" % pseudo))
	var centre: CenterContainer = CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_corps.add_child(centre)
	var rang: HBoxContainer = HBoxContainer.new()
	rang.add_theme_constant_override(&"separation", 40)
	centre.add_child(rang)
	var av: BkAvatar = BkAvatar.cree(str(prof.get(BkProfil.PERSO, "louis")),
		BkRules.color(int(prof.get(BkProfil.COULEUR, 0))), 300)
	av.pose("sad")
	rang.add_child(av)
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 22)
	rang.add_child(col)
	col.add_child(BkUi.label("Son perso et ses réglages\nseront perdus pour toujours.", 30))
	var non: Button = BkUi.bouton("Non, garder %s" % pseudo, func() -> void:
		_suppression = false
		_liste(), Vector2(460, 84), BkUi.VERT)
	col.add_child(non)
	col.add_child(BkUi.bouton("Oui, effacer %s" % pseudo, func() -> void:
		p.remove(i)
		_suppression = false
		if p.profiles.is_empty():
			_creation(true)
		else:
			_liste(), Vector2(460, 72), Color("ffb3a8"), 26))
	non.grab_focus.call_deferred()


## Création d'un profil : pseudo seulement (le perso et la couleur se choisissent dans Mon profil).
func _creation(premier: bool) -> void:
	_vider()
	_corps.add_child(BkUi.titre("Nouveau joueur"))
	var centre: CenterContainer = CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_corps.add_child(centre)
	var saisie: BkSaisiePseudo = BkSaisiePseudo.new()
	saisie.valider = func(texte: String) -> String:
		var err: String = BkProfil.creer(texte)
		if err == "":
			BkNav.aller("profil")
		return err
	if not premier:
		saisie.annuler = _liste
	centre.add_child(saisie)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _suppression:
		_suppression = false
		_liste()
		get_viewport().set_input_as_handled()
