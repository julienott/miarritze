class_name TutorialOverlay
extends Control
## Tutoriel intégré (SPEC §7.5) : combat d'apprentissage contre Hondar en
## 7 étapes guidées (bouger, frapper, garder, uppercut, spécial, super, K.O.).
## Chaque étape attend que le geste soit réussi. Passable (bouton).

signal finished

const STEPS: Array = [
	{"title": "BOUGER", "pad": "Glisse le pouce à gauche de l'écran", "keys": "Q / D (ou ← →)", "goal": "move"},
	{"title": "FRAPPER", "pad": "Touche le bouton rouge (poing)", "keys": "J (POING) — 3 fois = combo !", "goal": "hit"},
	{"title": "GARDER", "pad": "Garde le doigt sur le bouton bleu (bouclier)", "keys": "Espace (GARDE)", "goal": "block"},
	{"title": "TXAPEL-CUT !", "pad": "Pouce en bas, vers l'arrière, + bouton rouge", "keys": "S + Q + J (bas-arrière + POING)", "goal": "uppercut"},
	{"title": "SPÉCIAL", "pad": "Touche le bouton jaune (lauburu)", "keys": "L (SPÉCIAL)", "goal": "special"},
	{"title": "SUPER !", "pad": "Touche le bouton MARÉE", "keys": "L + Espace (SPÉCIAL + GARDE)", "goal": "super"},
	{"title": "K.O. !", "pad": "Vide la barre de vie de Hondar !", "keys": "Vide la barre de vie de Hondar !", "goal": "ko"},
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
	_enter(0)


func _enter(i: int) -> void:
	step = i
	if step >= STEPS.size():
		_label.text = "BRAVO ! Tu es prêt·e pour la Pyramide !"
		get_tree().create_timer(2.5).timeout.connect(func() -> void: finished.emit())
		return
	var st: Dictionary = STEPS[step]
	var how: String = st["pad"] if Settings.touch_enabled() else st["keys"]
	_label.text = "%d/%d  %s\n%s" % [step + 1, STEPS.size(), st["title"], how]
	_start_x = sim.f[0].x
	sim.ai_level[1] = AiBrain.DUMMY_ATTACK if st["goal"] == "block" else AiBrain.DUMMY_IDLE
	if st["goal"] == "super":
		sim.f[0].meter = SimConst.METER_MAX
	if st["goal"] == "ko":
		sim.training_ko = true
		sim.f[1].health = mini(sim.f[1].health, sim.f[1].max_health * KO_START_PCT / 100)


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
