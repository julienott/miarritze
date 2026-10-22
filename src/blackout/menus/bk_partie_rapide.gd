extends Control
## Partie rapide (SPEC-GORDEKA §6.1) : toi contre des IA, hors ligne. « Jouer » lance tout de suite
## avec les défauts (6 joueurs, IA Normal, Port des Pêcheurs, rounds = nombre de joueurs, options
## validées activées) ; « Réglages » déplie : joueurs (4 à 8), IA (Facile, Normal, Malin), carte,
## rounds (3 à 12 ; suivent le nombre de joueurs tant qu'on n'y a pas touché) et les options de
## gameplay du catalogue data/gordeka/options_partie.json (on/off et curseurs bornés), posées sur
## rules.json au lancement (GkRules.appliquer_options). Les choix restent le temps de la session.

const NIVEAUX: PackedStringArray = ["facile", "normal", "malin"]
const NOMS_NIVEAUX: PackedStringArray = ["Facile", "Normal", "Malin"]
## Cartes jouables : [id, nom] (assets/maps/<id>/).
const CARTES: Array = [["port_pecheurs", "Port des Pêcheurs"], ["parc_mazon", "Parc Mazon"],
	["plage", "Côte des Basques"]]

## Réglages de la session : players, level, map, rounds, rounds_touche, options {clé: valeur}.
static var choix: Dictionary = {}

var _resume: Label
var _carte: Label
var _jouer: Button
var _bouton_reglages: Button
var _panneau: Control
var _valeurs: Dictionary = {}         # nom de ligne → Label de valeur
var _lignes_option: Dictionary = {}   # id d'option → Array[Control] (curseurs à montrer si activée)


static func defauts() -> Dictionary:
	var opts: Dictionary = {}
	for o: Dictionary in GkRules.options_partie():
		for r: Dictionary in o.get("reglages", []):
			opts[str(r["cle"])] = float(r.get("defaut", 0.0))
	var n: int = int(GkRules.f("joueurs_defaut"))
	return {"players": n, "level": "normal", "map": str(CARTES[0][0]), "rounds": n, "rounds_touche": false,
		"options": opts}


static func reinitialiser() -> void:
	choix = defauts()


func _ready() -> void:
	if choix.is_empty():
		reinitialiser()
	var racine: MarginContainer = GkEcran.ecran(self)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 12)
	racine.add_child(page)
	GkEcran.entete(page, "Partie rapide", func() -> void: GkNav.aller("accueil"))
	var corps: HBoxContainer = HBoxContainer.new()
	corps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corps.alignment = BoxContainer.ALIGNMENT_CENTER
	corps.add_theme_constant_override(&"separation", 28)
	page.add_child(corps)
	# Colonne principale : la carte, le résumé, Jouer, Réglages.
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 16)
	corps.add_child(col)
	var av: GkAvatar = GkAvatar.cree(GkProfil.perso(), GkRules.color(GkProfil.couleur()), 200)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(av)
	_carte = GkUi.label("", 34, GkUi.JAUNE)
	col.add_child(_carte)
	_resume = GkUi.label("", 26)
	col.add_child(_resume)
	_jouer = GkUi.bouton("Jouer !", lancer, Vector2(400, 110), GkUi.JAUNE, 48)
	_jouer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_jouer)
	_bouton_reglages = GkUi.bouton("Réglages", _basculer, Vector2(300, 64), GkUi.CREME, 26)
	_bouton_reglages.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_bouton_reglages)
	_panneau = _construire_reglages()
	_panneau.visible = false
	corps.add_child(_panneau)
	_maj()
	_jouer.grab_focus.call_deferred()
	if GkRules.args().has("--gk-qa-reglages"):
		_basculer()          # QA : captures du panneau déplié


func _basculer() -> void:
	_panneau.visible = not _panneau.visible
	_bouton_reglages.text = "Moins de réglages" if _panneau.visible else "Réglages"
	if _panneau.visible:
		var premier: Control = _panneau.find_child("moins_joueurs", true, false) as Control
		if premier != null:
			premier.grab_focus.call_deferred()


## Panneau des réglages, défilant (doigt, molette ou focus qui suit).
func _construire_reglages() -> Control:
	var p: PanelContainer = GkUi.panneau(16)
	p.custom_minimum_size = Vector2(700, 0)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	p.add_child(scroll)
	# Marge intérieure : le cadre doré du focus ne doit pas être rogné par le défilement.
	var marge: MarginContainer = MarginContainer.new()
	marge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		marge.add_theme_constant_override(c, 12)
	scroll.add_child(marge)
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 10)
	marge.add_child(col)
	_cycleur(col, "joueurs", "Joueurs", func(d: int) -> void: regler_joueurs(int(choix["players"]) + d))
	_cycleur(col, "niveau", "IA", func(d: int) -> void:
		var i: int = NIVEAUX.find(str(choix["level"]))
		choix["level"] = NIVEAUX[clampi(i + d, 0, NIVEAUX.size() - 1)]
		_maj())
	_cycleur(col, "carte", "Carte", func(d: int) -> void:
		var ids: Array = CARTES.map(func(c: Array) -> String: return str(c[0]))
		var i: int = ids.find(str(choix["map"]))
		choix["map"] = str(ids[posmod(i + d, ids.size())])
		_maj())
	_cycleur(col, "rounds", "Rounds", func(d: int) -> void: regler_rounds(int(choix["rounds"]) + d))
	var groupe: String = ""
	for o: Dictionary in GkRules.options_partie():
		if str(o.get("groupe", "")) != groupe:
			groupe = str(o.get("groupe", ""))
			var g: Label = GkUi.label(groupe, 26, GkUi.ROUGE, HORIZONTAL_ALIGNMENT_LEFT)
			g.add_theme_constant_override(&"outline_size", 0)
			col.add_child(g)
		_option(col, o)
	GkUi.touch_scroll(col)
	return p


## Ligne « libellé  ‹ valeur › ».
func _cycleur(parent: Container, nom: String, libelle: String, change: Callable) -> void:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	parent.add_child(h)
	var l: Label = GkUi.label(libelle, 28, GkUi.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.add_theme_constant_override(&"outline_size", 0)
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	var moins: Button = GkUi.bouton("‹", func() -> void: change.call(-1), Vector2(72, 64), Color.WHITE, 34)
	moins.name = "moins_" + nom
	h.add_child(moins)
	var v: Label = GkUi.label("", 28, GkUi.INK)
	v.add_theme_constant_override(&"outline_size", 0)
	v.custom_minimum_size = Vector2(300, 0)
	h.add_child(v)
	h.add_child(GkUi.bouton("›", func() -> void: change.call(1), Vector2(72, 64), Color.WHITE, 34))
	_valeurs[nom] = v


## Une option du catalogue : l'interrupteur (premier réglage on/off) puis ses curseurs.
func _option(parent: Container, o: Dictionary) -> void:
	var curseurs: Array[Control] = []
	var interrupteur: CheckButton = null
	for r: Dictionary in o.get("reglages", []):
		var cle: String = str(r["cle"])
		if str(r.get("type", "")) == "on_off":
			interrupteur = CheckButton.new()
			interrupteur.text = str(o.get("libelle", cle))
			interrupteur.tooltip_text = str(o.get("aide", ""))
			interrupteur.custom_minimum_size = Vector2(620, 64)
			interrupteur.button_pressed = float(choix["options"].get(cle, r.get("defaut", 1))) > 0.5
			interrupteur.toggled.connect(func(on: bool) -> void:
				regler_option(cle, 1.0 if on else 0.0))
			parent.add_child(interrupteur)
			var aide: Label = GkUi.label(str(o.get("aide", "")), 20, Color(GkUi.INK, 0.75), HORIZONTAL_ALIGNMENT_LEFT)
			aide.add_theme_constant_override(&"outline_size", 0)
			aide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			aide.custom_minimum_size = Vector2(620, 0)
			parent.add_child(aide)
		else:
			var h: HBoxContainer = HBoxContainer.new()
			h.add_theme_constant_override(&"separation", 12)
			parent.add_child(h)
			var l: Label = GkUi.label(str(r.get("libelle", cle)), 22, GkUi.INK, HORIZONTAL_ALIGNMENT_LEFT)
			l.add_theme_constant_override(&"outline_size", 0)
			l.custom_minimum_size = Vector2(300, 0)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			h.add_child(l)
			var s: HSlider = HSlider.new()
			s.min_value = float(r.get("min", 0))
			s.max_value = float(r.get("max", 1))
			s.step = float(r.get("pas", 1))
			s.value = float(choix["options"].get(cle, r.get("defaut", 0)))
			s.custom_minimum_size = Vector2(250, 52)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(s)
			GkUi.focus_libelle(s, l)
			var v: Label = GkUi.label(_nombre(s.value), 24, GkUi.INK)
			v.add_theme_constant_override(&"outline_size", 0)
			v.custom_minimum_size = Vector2(60, 0)
			h.add_child(v)
			s.value_changed.connect(func(x: float) -> void:
				regler_option(cle, x)
				v.text = _nombre(x))
			curseurs.append(h)
	_lignes_option[str(o.get("id", ""))] = curseurs
	if interrupteur != null:
		var maj: Callable = func(on: bool) -> void:
			for c: Control in curseurs:
				c.visible = on
		interrupteur.toggled.connect(maj)
		maj.call(interrupteur.button_pressed)


static func _nombre(x: float) -> String:
	return ("%.2f" % x).rstrip("0").rstrip(".").replace(".", ",")


# ---------------------------------------------------------------- réglages (testés)

func regler_joueurs(n: int) -> void:
	choix["players"] = clampi(n, int(GkRules.f("joueurs_min")), int(GkRules.f("joueurs_max")))
	# Les rounds suivent le nombre de joueurs (chacun est chasseur une fois) tant qu'on n'y a pas touché.
	if not bool(choix.get("rounds_touche", false)):
		choix["rounds"] = clampi(int(choix["players"]), int(GkRules.f("rounds_min")), int(GkRules.f("rounds_max")))
	_maj()


func regler_rounds(n: int) -> void:
	choix["rounds"] = clampi(n, int(GkRules.f("rounds_min")), int(GkRules.f("rounds_max")))
	choix["rounds_touche"] = true
	_maj()


func regler_option(cle: String, v: float) -> void:
	(choix["options"] as Dictionary)[cle] = v


## Pose les réglages sur la partie (config et rules.json), sans la lancer.
func preparer() -> void:
	GkRules.appliquer_options(choix["options"])
	var cfg: Dictionary = GkGame.config
	cfg["players"] = int(choix["players"])
	cfg["level"] = str(choix["level"])
	cfg["map"] = str(choix["map"])
	cfg["rounds"] = int(choix["rounds"])
	cfg["visite"] = ""
	GkProfil.vers_partie()


func lancer() -> void:
	preparer()
	GkNav.aller("game")


func _maj() -> void:
	if _resume == null:
		return
	var niveau: String = NOMS_NIVEAUX[maxi(0, NIVEAUX.find(str(choix["level"])))]
	var nom_carte: String = str(CARTES[0][1])
	for c: Array in CARTES:
		if str(c[0]) == str(choix["map"]):
			nom_carte = str(c[1])
	_carte.text = nom_carte
	_resume.text = "%d joueurs · IA %s · %d rounds" % [int(choix["players"]), niveau, int(choix["rounds"])]
	if _valeurs.is_empty():
		return
	(_valeurs["joueurs"] as Label).text = "%d (toi + %d IA)" % [int(choix["players"]), int(choix["players"]) - 1]
	(_valeurs["niveau"] as Label).text = niveau
	(_valeurs["carte"] as Label).text = nom_carte
	(_valeurs["rounds"] as Label).text = str(int(choix["rounds"]))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _panneau.visible:
			_basculer()
			_bouton_reglages.grab_focus.call_deferred()
		else:
			GkNav.aller("accueil")
