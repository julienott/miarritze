class_name TutorialOverlay
extends Control
## Tutoriel intégré (SPEC §7.5) : combat d'apprentissage contre Hondar en
## 7 étapes guidées (bouger, frapper, garder, uppercut, spécial, super, K.O.).
## Chaque étape attend que le geste soit réussi. Passable (bouton).

signal finished

## Consigne de chaque étape selon l'appareil (Prompts.pick) : clavier et
## manette avec les vrais boutons ({punch}…), manette tactile, gestes.
const STEPS: Array = [
	{"title": "BOUGER", "goal": "move", "how": {
		"keyboard": "{left} / {right} (ou ← →)",
		"gamepad": "Pousse le stick (ou la croix) ← →",
		"touch": "Glisse le pouce à gauche de l'écran",
		"gestures": "Pose le pouce à gauche de l'écran et glisse"}},
	{"title": "FRAPPER", "goal": "hit", "how": {
		"keyboard": "{punch} (POING) — 3 fois = combo !",
		"gamepad": "{punch} (POING) — 3 fois = combo !",
		"touch": "Touche le bouton rouge (poing)",
		"gestures": "Tape à droite de l'écran — 3 fois = combo !"}},
	{"title": "GARDER", "goal": "block", "how": {
		"keyboard": "{guard} (GARDE)",
		"gamepad": "Garde {guard} enfoncé (GARDE)",
		"touch": "Garde le doigt sur le bouton bleu (bouclier)",
		"gestures": "Garde le doigt appuyé à droite de l'écran"}},
	{"title": "TXAPEL-CUT !", "goal": "uppercut", "how": {
		"keyboard": "{down} + {left} + {punch} (bas-arrière + POING)",
		"gamepad": "Stick en bas vers l'arrière + {punch} (POING)",
		"touch": "Pouce en bas, vers l'arrière, + bouton rouge",
		"gestures": "Pouce gauche en bas vers l'arrière + tape à droite"}},
	{"title": "SPÉCIAL", "goal": "special", "how": {
		"keyboard": "{special} (SPÉCIAL)",
		"gamepad": "{special} (SPÉCIAL)",
		"touch": "Touche le bouton jaune (lauburu)",
		"gestures": "Glisse le doigt vers le haut, à droite de l'écran"}},
	{"title": "SUPER !", "goal": "super", "how": {
		"keyboard": "{special} + {guard} (SPÉCIAL + GARDE)",
		"gamepad": "{special} + {guard} ensemble (SPÉCIAL + GARDE)",
		"touch": "Touche le bouton MARÉE",
		"gestures": "Tape avec deux doigts en même temps"}},
	{"title": "K.O. !", "goal": "ko", "how": {
		"keyboard": "Vide la barre de vie de Hondar !",
		"touch": "Vide la barre de vie de Hondar !"}},
]

## Vie de départ du mannequin à l'étape K.O. (en %), pour un K.O. rapide.
const KO_START_PCT: int = 40

var sim: FightSim
var step: int = 0
var _start_x: int = 0
var _label: Label
var _done_t: float = 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	# Consigne centrée dans une bannière sombre, bien séparée du bouton PAUSE
	# (haut-centre) et des portraits du HUD (haut-gauche/droite). Sur fond de
	# combat les lettres se perdaient : on ajoute un panneau.
	var panel: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color8(24, 16, 28, 215)
	sb.border_color = UiKit.C_GOLD
	sb.set_border_width_all(1)
	sb.set_content_margin_all(5)
	panel.add_theme_stylebox_override(&"panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_top = 56
	add_child(panel)
	_label = UiKit.label("", 8, UiKit.C_LINEN, HORIZONTAL_ALIGNMENT_CENTER)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_label)
	var skip: Button = UiKit.button("Passer", func() -> void: finished.emit(), 60)
	skip.focus_mode = Control.FOCUS_NONE
	# Bas-droit : loin du bouton PAUSE (haut-centre) et des portraits du HUD.
	skip.position = Vector2(size.x - 68, size.y - 28)
	add_child(skip)
	InputHub.device_changed.connect(_render)
	_enter(0)


func _enter(i: int) -> void:
	step = i
	if step >= STEPS.size():
		_label.text = "BRAVO ! Tu es prêt·e pour la Pyramide !"
		get_tree().create_timer(2.5).timeout.connect(func() -> void: finished.emit())
		return
	var st: Dictionary = STEPS[step]
	_render()
	_start_x = sim.f[0].x
	sim.ai_level[1] = AiBrain.DUMMY_ATTACK if st["goal"] == "block" else AiBrain.DUMMY_IDLE
	if st["goal"] == "super":
		sim.f[0].meter = SimConst.METER_MAX
	if st["goal"] == "ko":
		sim.training_ko = true
		sim.f[1].health = mini(sim.f[1].health, sim.f[1].max_health * KO_START_PCT / 100)


## Consigne de l'étape en cours pour l'appareil utilisé (rappelé quand on
## change d'appareil : manette prise en main, iPhone…).
func _render(_device: int = 0) -> void:
	if step >= STEPS.size() or _done_t > 0.0:
		return
	var st: Dictionary = STEPS[step]
	_label.text = "%d/%d  %s\n%s" % [step + 1, STEPS.size(), st["title"], Prompts.pick(st["how"])]


func _physics_process(_delta: float) -> void:
	if sim == null or step >= STEPS.size():
		return
	if _done_t > 0.0:
		_done_t -= 1.0 / 60.0
		if _done_t <= 0.0:
			_enter(step + 1)
		return
	if _achieved(str(STEPS[step]["goal"])):
		AudioManager.sfx(&"ui_ok")
		_label.text = "Super !"
		_done_t = 1.6 if str(STEPS[step]["goal"]) == "ko" else 0.8


func _achieved(goal: String) -> bool:
	var me: FighterState = sim.f[0]
	var dummy: FighterState = sim.f[1]
	var mv: String = sim.defs[0].moves[me.move].name if me.state == SimConst.ST_MOVE and me.move >= 0 else ""
	match goal:
		"move":
			return absi(me.x - _start_x) > 40 * SimConst.SUB
		"hit":
			return dummy.combo_hits >= 2 or (dummy.state == SimConst.ST_HITSTUN and dummy.combo_hits >= 1 and mv == "punch_3")
		"block":
			return me.state == SimConst.ST_BLOCKSTUN
		"uppercut":
			return mv == "uppercut"
		"special":
			return mv.begins_with("sp_")
		"super":
			return mv == "super"
		"ko":
			return dummy.health <= 0
	return false
