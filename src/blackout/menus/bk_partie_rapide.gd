extends Control
## Partie rapide (GDD-BLACKOUT.md) : toi contre des IA, hors ligne. « Jouer » lance tout de suite
## avec les défauts (6 joueurs, IA Normal, bac à sable, rounds = nombre de joueurs, options
## validées activées) ; « Réglages » déplie : joueurs (4 à 8), IA (Facile, Normal, Malin), carte,
## rounds (3 à 12 ; suivent le nombre de joueurs tant qu'on n'y a pas touché) et les options de
## gameplay du catalogue data/blackout/options_partie.json (on/off et curseurs bornés), posées sur
## rules.json au lancement (BkRules.appliquer_options). Les choix restent le temps de la session.
## « Debug » (temporaire, jalon actuel, GDD §7.2) déplie le menu debug : perso, rôle (chassé ou
## chasseur), boss (à venir), chrono, adversaires (IA ou personne : la visite), sur le bac à sable.

const NIVEAUX: PackedStringArray = ["facile", "normal", "malin"]
const NOMS_NIVEAUX: PackedStringArray = ["Facile", "Normal", "Malin"]
## Cartes jouables : [id, nom] (assets/maps/<id>/). Jalon actuel : le bac à sable seul (GDD §10.1) ;
## Port des Pêcheurs, plage et parc Mazon sont archivés (fichiers gardés, `--bk-map=<id>` en QA).
const CARTES: Array = [[BkGame.CARTE_DEFAUT, "Bac à sable"]]

## Réglages de la session : players, level, map, rounds, rounds_touche, options {clé: valeur}.
static var choix: Dictionary = {}
## Menu debug (session) : perso, role ("hider" ou "hunter"), boss ("" : aucun pour l'instant), chrono,
## seul (sans adversaires : la visite de la carte).
static var debug_choix: Dictionary = {}

var _resume: Label
var _carte: Label
var _jouer: Button
var _bouton_reglages: Button
var _panneau: Control
var _bouton_debug: Button
var _panneau_debug: Control
var _valeurs: Dictionary = {}         # nom de ligne → Label de valeur
var _lignes_option: Dictionary = {}   # id d'option → Array[Control] (curseurs à montrer si activée)


static func defauts() -> Dictionary:
	var opts: Dictionary = {}
	for o: Dictionary in BkRules.options_partie():
		for r: Dictionary in o.get("reglages", []):
			opts[str(r["cle"])] = float(r.get("defaut", 0.0))
	var n: int = int(BkRules.f("joueurs_defaut"))
	return {"players": n, "level": "normal", "map": str(CARTES[0][0]), "rounds": n, "rounds_touche": false,
		"options": opts}


static func reinitialiser() -> void:
	choix = defauts()


func _ready() -> void:
	if choix.is_empty():
		reinitialiser()
	var racine: MarginContainer = BkEcran.ecran(self)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override(&"separation", 12)
	racine.add_child(page)
	BkEcran.entete(page, "Partie rapide", func() -> void: BkNav.aller("accueil"))
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
	var av: BkAvatar = BkAvatar.cree(BkProfil.perso(), 200)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(av)
	_carte = BkUi.label("", 34, BkUi.JAUNE)
	col.add_child(_carte)
	_resume = BkUi.label("", 26)
	col.add_child(_resume)
	_jouer = BkUi.bouton("Jouer !", lancer, Vector2(400, 110), BkUi.JAUNE, 48)
	_jouer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_jouer)
	_bouton_reglages = BkUi.bouton("Réglages", _basculer, Vector2(300, 64), BkUi.CREME, 26)
	_bouton_reglages.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_bouton_reglages)
	_bouton_debug = BkUi.bouton("Debug", _basculer_debug, Vector2(300, 48), Color("3a3f4b"), 20)
	for k: StringName in [&"font_color", &"font_focus_color", &"font_hover_color"]:
		_bouton_debug.add_theme_color_override(k, BkUi.JAUNE)
	_bouton_debug.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_bouton_debug)
	_panneau = _construire_reglages()
	_panneau.visible = false
	corps.add_child(_panneau)
	if debug_choix.is_empty():
		debug_choix = {"perso": BkProfil.perso(), "role": "hunter", "boss": "", "chrono": true, "seul": false}
	_panneau_debug = _construire_debug()
	_panneau_debug.visible = false
	corps.add_child(_panneau_debug)
	_maj()
	_jouer.grab_focus.call_deferred()
	if BkRules.args().has("--bk-qa-reglages"):
		_basculer()          # QA : captures du panneau déplié
	if BkRules.args().has("--bk-qa-debug"):
		_basculer_debug()    # QA : captures du menu debug


func _basculer() -> void:
	_panneau_debug.visible = false
	_panneau.visible = not _panneau.visible
	_bouton_reglages.text = "Moins de réglages" if _panneau.visible else "Réglages"
	if _panneau.visible:
		var premier: Control = _panneau.find_child("moins_joueurs", true, false) as Control
		if premier != null:
			premier.grab_focus.call_deferred()


func _basculer_debug() -> void:
	_panneau.visible = false
	_bouton_reglages.text = "Réglages"
	_panneau_debug.visible = not _panneau_debug.visible
	if _panneau_debug.visible:
		var premier: Control = _panneau_debug.find_child("moins_perso", true, false) as Control
		if premier != null:
			premier.grab_focus.call_deferred()


## Menu debug (GDD §7.2) : perso, rôle, boss (liste vide pour l'instant, désactivée), chrono,
## adversaires, et le bouton qui lance l'essai sur le bac à sable.
func _construire_debug() -> Control:
	var p: PanelContainer = BkUi.panneau(16)
	p.custom_minimum_size = Vector2(700, 0)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	p.add_child(col)
	var titre: Label = BkUi.label("Debug (bac à sable)", 26, BkUi.ROUGE, HORIZONTAL_ALIGNMENT_LEFT)
	titre.add_theme_constant_override(&"outline_size", 0)
	col.add_child(titre)
	_cycleur(col, "perso", "Perso", func(d: int) -> void:
		var persos: Array = BkRules.data().get("characters", [])
		var i: int = persos.find(str(debug_choix["perso"]))
		debug_choix["perso"] = str(persos[posmod(i + d, persos.size())])
		_maj())
	_cycleur(col, "role", "Rôle", func(_d: int) -> void:
		debug_choix["role"] = "hider" if str(debug_choix["role"]) == "hunter" else "hunter"
		_maj())
	var boss: HBoxContainer = _cycleur(col, "boss", "Boss", func(_d: int) -> void: pass)
	for b: Node in boss.get_children():
		if b is Button:
			(b as Button).disabled = true
	_cycleur(col, "chrono", "Chrono", func(_d: int) -> void:
		debug_choix["chrono"] = not bool(debug_choix["chrono"])
		_maj())
	_cycleur(col, "seul", "Adversaires", func(_d: int) -> void:
		debug_choix["seul"] = not bool(debug_choix["seul"])
		_maj())
	var go: Button = BkUi.bouton("Lancer le debug", lancer_debug, Vector2(360, 72), BkUi.JAUNE, 30)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(go)
	return p


## Panneau des réglages, défilant (doigt, molette ou focus qui suit).
func _construire_reglages() -> Control:
	var p: PanelContainer = BkUi.panneau(16)
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
	for o: Dictionary in BkRules.options_partie():
		if str(o.get("groupe", "")) != groupe:
			groupe = str(o.get("groupe", ""))
			var g: Label = BkUi.label(groupe, 26, BkUi.ROUGE, HORIZONTAL_ALIGNMENT_LEFT)
			g.add_theme_constant_override(&"outline_size", 0)
			col.add_child(g)
		_option(col, o)
	BkUi.touch_scroll(col)
	return p


## Ligne « libellé  ‹ valeur › ».
func _cycleur(parent: Container, nom: String, libelle: String, change: Callable) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	parent.add_child(h)
	var l: Label = BkUi.label(libelle, 28, BkUi.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.add_theme_constant_override(&"outline_size", 0)
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	var moins: Button = BkUi.bouton("‹", func() -> void: change.call(-1), Vector2(72, 64), Color.WHITE, 34)
	moins.name = "moins_" + nom
	h.add_child(moins)
	var v: Label = BkUi.label("", 28, BkUi.INK)
	v.add_theme_constant_override(&"outline_size", 0)
	v.custom_minimum_size = Vector2(300, 0)
	h.add_child(v)
	h.add_child(BkUi.bouton("›", func() -> void: change.call(1), Vector2(72, 64), Color.WHITE, 34))
	_valeurs[nom] = v
	return h


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
			var aide: Label = BkUi.label(str(o.get("aide", "")), 20, Color(BkUi.INK, 0.75), HORIZONTAL_ALIGNMENT_LEFT)
			aide.add_theme_constant_override(&"outline_size", 0)
			aide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			aide.custom_minimum_size = Vector2(620, 0)
			parent.add_child(aide)
		else:
			var h: HBoxContainer = HBoxContainer.new()
			h.add_theme_constant_override(&"separation", 12)
			parent.add_child(h)
			var l: Label = BkUi.label(str(r.get("libelle", cle)), 22, BkUi.INK, HORIZONTAL_ALIGNMENT_LEFT)
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
			BkUi.focus_libelle(s, l)
			var v: Label = BkUi.label(_nombre(s.value), 24, BkUi.INK)
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
	choix["players"] = clampi(n, int(BkRules.f("joueurs_min")), int(BkRules.f("joueurs_max")))
	# Les rounds suivent le nombre de joueurs (chacun est chasseur une fois) tant qu'on n'y a pas touché.
	if not bool(choix.get("rounds_touche", false)):
		choix["rounds"] = clampi(int(choix["players"]), int(BkRules.f("rounds_min")), int(BkRules.f("rounds_max")))
	_maj()


func regler_rounds(n: int) -> void:
	choix["rounds"] = clampi(n, int(BkRules.f("rounds_min")), int(BkRules.f("rounds_max")))
	choix["rounds_touche"] = true
	_maj()


func regler_option(cle: String, v: float) -> void:
	(choix["options"] as Dictionary)[cle] = v


## Pose les réglages sur la partie (config et rules.json), sans la lancer.
func preparer() -> void:
	BkRules.appliquer_options(choix["options"])
	var cfg: Dictionary = BkGame.config
	cfg["players"] = int(choix["players"])
	cfg["level"] = str(choix["level"])
	cfg["map"] = str(choix["map"])
	cfg["rounds"] = int(choix["rounds"])
	cfg["visite"] = ""
	cfg["debug"] = false
	cfg["debug_role"] = ""
	cfg["debug_boss"] = ""
	cfg["sans_chrono"] = false
	BkProfil.vers_partie()


func lancer() -> void:
	preparer()
	BkNav.aller("game")


## Pose le menu debug sur la partie (après les réglages de la partie rapide) : bac à sable, perso et
## rôle imposés, boss, chrono ; « personne » en face : la visite de la carte.
func preparer_debug() -> void:
	preparer()
	var cfg: Dictionary = BkGame.config
	cfg["debug"] = true
	cfg["map"] = BkGame.CARTE_DEFAUT
	cfg["character"] = str(debug_choix["perso"])
	cfg["debug_role"] = str(debug_choix["role"])
	cfg["debug_boss"] = str(debug_choix["boss"])
	cfg["sans_chrono"] = not bool(debug_choix["chrono"])
	if bool(debug_choix["seul"]):
		cfg["visite"] = "chasseur" if str(debug_choix["role"]) == "hunter" else "chasse"


func lancer_debug() -> void:
	preparer_debug()
	BkNav.aller("game")


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
	if _valeurs.has("perso"):
		(_valeurs["perso"] as Label).text = str(debug_choix["perso"]).capitalize()
		(_valeurs["role"] as Label).text = "Chasseur" if str(debug_choix["role"]) == "hunter" else "Chassé"
		(_valeurs["boss"] as Label).text = "aucun (à venir)" if str(debug_choix["boss"]) == "" else str(debug_choix["boss"])
		(_valeurs["chrono"] as Label).text = "avec chrono" if bool(debug_choix["chrono"]) else "sans chrono"
		(_valeurs["seul"] as Label).text = "personne (visite)" if bool(debug_choix["seul"]) else "IA (%d)" % (int(choix["players"]) - 1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _panneau.visible:
			_basculer()
			_bouton_reglages.grab_focus.call_deferred()
		elif _panneau_debug.visible:
			_basculer_debug()
			_bouton_debug.grab_focus.call_deferred()
		else:
			BkNav.aller("accueil")
