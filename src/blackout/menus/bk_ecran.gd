class_name BkEcran
extends RefCounted
## Mise en page commune des écrans de menu de Blackout : fond de mer, marges de la zone sûre de
## l'iPhone (encoche, barre d'accueil), rappel des touches selon l'appareil (Prompts), bande du haut
## avec « Retour » et titre, musique des menus (Hegoak).

## Prépare un écran de menu : fond de mer, marges de la zone sûre (encoche de l'iPhone) et rappel
## des touches en bas. Renvoie le conteneur où poser le contenu (plein écran, marges comprises).
static func ecran(ecran_ctrl: Control, aide: bool = true) -> MarginContainer:
	BkEchelle.menus()
	ecran_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fond: BkUi.Fond = BkUi.Fond.new()
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ecran_ctrl.add_child(fond)
	var m: MarginContainer = MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ecran_ctrl.add_child(m)
	var marges: Callable = func() -> void:
		if not is_instance_valid(m) or not m.is_inside_tree():
			return
		var s: Vector4 = SafeArea.margins(m.get_viewport())
		m.add_theme_constant_override(&"margin_left", int(maxf(28.0, s.x + 12.0)))
		m.add_theme_constant_override(&"margin_top", int(maxf(18.0, s.y + 8.0)))
		m.add_theme_constant_override(&"margin_right", int(maxf(28.0, s.z + 12.0)))
		m.add_theme_constant_override(&"margin_bottom", int(maxf(40.0 if aide else 18.0, s.w + 8.0)))
	marges.call_deferred()
	m.resized.connect(marges)
	if aide:
		barre_aide(ecran_ctrl)
	return m


## Rappel des touches en bas de l'écran, selon l'appareil (rien au doigt).
static func barre_aide(parent: Control, variantes: Dictionary = {}) -> Label:
	if variantes.is_empty():
		variantes = {Prompts.KEYBOARD: "{ok} : valider    {back} : retour    FLÈCHES : choisir",
			Prompts.GAMEPAD: "{ok} : valider    {back} : retour    STICK : choisir"}
	var l: Label = BkUi.label("", 20, Color(1, 1, 1, 0.85))
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_top = -36
	l.offset_bottom = -6
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	Prompts.bind(l, func() -> String: return Prompts.pick(variantes))
	return l


## Bande du haut : bouton retour à gauche, titre au centre. Renvoie la bande.
static func entete(parent: Container, texte: String, retour: Callable) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	parent.add_child(h)
	if retour.is_valid():
		h.add_child(BkUi.bouton("‹ Retour", retour, Vector2(190, 68), BkUi.CREME, 26))
	var t: Label = BkUi.titre(texte)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	if retour.is_valid():
		var cale: Control = Control.new()
		cale.custom_minimum_size = Vector2(190, 0)
		h.add_child(cale)
	return h


