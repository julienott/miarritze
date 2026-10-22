extends Control
## Réglages (GDD-BLACKOUT.md §7.1) : vibration (réglage de l'appareil, autoload Settings) et aide
## (les règles en quelques lignes). Pas de round guidé (retiré le 22/10). Le jeu n'a plus de son (Julien 2026-10-22) : les curseurs Musique et Sons sont
## masqués (AVEC_SONS), les volumes restent dans Settings.

const AVEC_SONS: bool = false

const AIDE: String = """Un joueur est le CHASSEUR, les autres se cachent.
Le chasseur voit seulement dans son cône rouge : s'il te voit, tu es trouvé !
Cache-toi derrière les bateaux, les caisses, les maisons, ou entre dans un casier.
Ton bouton d'action : un piège quand tu te caches, une détection quand tu chasses.
Après 1 min 30, les sorties s'ouvrent : reste 4 s dessus sans être vu pour t'échapper.
Trouvé ? Tu deviens un petit fantôme : rejoins un chassé, il peut te délivrer.
Bouger : flèches, ZQSD, stick ou pouce gauche. Action : Espace, A ou pouce droit."""

var _racine: MarginContainer
var _page: VBoxContainer
var _aide: Control


func _ready() -> void:
	_racine = BkEcran.ecran(self)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override(&"separation", 18)
	_racine.add_child(_page)
	BkEcran.entete(_page, "Réglages", _retour)
	var centre: CenterContainer = CenterContainer.new()
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(centre)
	var panneau: PanelContainer = BkUi.panneau(30)
	centre.add_child(panneau)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 18)
	panneau.add_child(col)
	if AVEC_SONS:
		_curseur(col, "Musique", Settings.music_volume, func(v: float) -> void:
			Settings.set_value("music_volume", v))
		_curseur(col, "Sons", Settings.sfx_volume, func(v: float) -> void:
			Settings.set_value("sfx_volume", v))
	var vib: CheckButton = CheckButton.new()
	vib.text = "Vibration"
	vib.button_pressed = Settings.vibrations
	vib.custom_minimum_size = Vector2(640, 72)
	vib.toggled.connect(func(on: bool) -> void:
		Settings.set_value("vibrations", on))
	col.add_child(vib)
	var bas: HBoxContainer = HBoxContainer.new()
	bas.add_theme_constant_override(&"separation", 18)
	col.add_child(bas)
	bas.add_child(BkUi.bouton("Aide", _montrer_aide, Vector2(250, 76), BkUi.BLEU))
	(col.get_child(0) as Control).grab_focus.call_deferred()


func _curseur(parent: Container, texte: String, valeur: float, change: Callable) -> HSlider:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 20)
	parent.add_child(h)
	var l: Label = BkUi.label(texte, 30, BkUi.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.add_theme_constant_override(&"outline_size", 0)
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	var s: HSlider = HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.1
	s.value = valeur
	s.custom_minimum_size = Vector2(450, 56)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(change)
	h.add_child(s)
	BkUi.focus_libelle(s, l)
	return s


func _montrer_aide() -> void:
	_page.visible = false
	_aide = CenterContainer.new()
	_racine.add_child(_aide)
	var p: PanelContainer = BkUi.panneau(30)
	_aide.add_child(p)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 16)
	p.add_child(col)
	var t: Label = BkUi.label("Comment on joue ?", 40, BkUi.ROUGE)
	t.add_theme_constant_override(&"outline_size", 0)
	col.add_child(t)
	var l: Label = BkUi.label(AIDE, 24, BkUi.INK, HORIZONTAL_ALIGNMENT_LEFT)
	l.add_theme_constant_override(&"outline_size", 0)
	l.add_theme_constant_override(&"line_spacing", 6)
	col.add_child(l)
	var ok: Button = BkUi.bouton("J'ai compris !", _fermer_aide, Vector2(300, 76), BkUi.VERT)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ok)
	ok.grab_focus.call_deferred()


func _fermer_aide() -> void:
	if _aide != null:
		_aide.queue_free()
		_aide = null
	_page.visible = true


func _retour() -> void:
	BkNav.aller("accueil")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _aide != null:
			_fermer_aide()
		else:
			_retour()
