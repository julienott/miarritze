class_name TutorialOverlay
extends Control
## Tutoriel intégré (SPEC §7.5) : combat d'apprentissage contre Hondar en
## 6 étapes guidées (bouger, frapper, garder, uppercut, spécial, super).
## Chaque étape attend que le geste soit réussi. Passable (bouton).

signal finished

const STEPS: Array = [
	{"title": "BOUGER", "pad": "Glisse le pouce à gauche de l'écran", "keys": "A / D (ou ← →)", "goal": "move"},
	{"title": "FRAPPER", "pad": "Touche le bouton rouge P", "keys": "J (POING) — 3 fois = combo !", "goal": "hit"},
	{"title": "GARDER", "pad": "Maintiens le bouton bleu G", "keys": "Espace (GARDE)", "goal": "block"},
	{"title": "TXAPEL-CUT !", "pad": "Pouce en bas-arrière + P", "keys": "S + A + J (bas-arrière + POING)", "goal": "uppercut"},
	{"title": "SPÉCIAL", "pad": "Touche le bouton or S", "keys": "L (SPÉCIAL)", "goal": "special"},
	{"title": "SUPER !", "pad": "Touche MARÉE (jauge pleine)", "keys": "L + Espace (SPÉCIAL + GARDE)", "goal": "super"},
]

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
	_label = UiKit.label("", 8, UiKit.C_LINEN)
	_label.position = Vector2(0, 60)
	_label.size = Vector2(size.x, 30)
	add_child(_label)
	var skip: Button = UiKit.button("Passer", func() -> void: finished.emit(), 60)
	skip.focus_mode = Control.FOCUS_NONE
	skip.position = Vector2(size.x - 64, 38)
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
	_label.text = "%d/6  %s\n%s" % [step + 1, st["title"], how]
	_start_x = sim.f[0].x
	sim.ai_level[1] = AiBrain.DUMMY_ATTACK if st["goal"] == "block" else AiBrain.DUMMY_IDLE
	if st["goal"] == "super":
		sim.f[0].meter = SimConst.METER_MAX


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
		_done_t = 0.8


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
	return false
