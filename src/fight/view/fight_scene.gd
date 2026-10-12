extends Node2D
## Scène de combat : fait tourner la sim à 60 Hz fixe et synchronise la vue.
## La vue lit l'état de la sim et consomme ses événements ; elle ne le
## modifie jamais (SPEC §8.4).
##
## Paramètres (SceneRouter.params) : p1, p2, c1, c2 (costumes), stage,
## rounds, ai [n1, n2], autoguard [0/1, 0/1], seed, finishers, health,
## names, on_end (Callable(result: Dictionary)), return_to (id d'écran).

signal match_finished(result: Dictionary)

const VIEW_H: float = 216.0

var sim: FightSim
var params: Dictionary = {}
var paused: bool = false

var _stage: StageView
var _views: Array[FighterView] = []
var _camera: FightCamera
var _hud: FightHud
var _announcer: Announcer
var _vfx: VfxPool
var _debug: DebugBoxes
var _dim: ColorRect
var _seen: Dictionary = {}
var _end_timer: float = -1.0
var _super_t: int = 0
var _ui: CanvasLayer
var _pause_box: Control
var _training: TrainingOverlay


func _ready() -> void:
	params = SceneRouter.params.duplicate()
	if params.is_empty():
		params = {"p1": "louis", "p2": "maia", "stage": "grande_plage"}
	var def1: FighterDef = FighterDb.get_def(str(params.get("p1", "louis")))
	var def2: FighterDef = FighterDb.get_def(str(params.get("p2", "maia")))
	var c1: int = int(params.get("c1", 0))
	var c2: int = int(params.get("c2", 0))
	if def1.id == def2.id and c1 == c2:
		c2 = (c1 + 1) % 4
	if QaCapture.autoplay:
		var ai: Array = (params.get("ai", [0, 0]) as Array).duplicate()
		ai[0] = 92
		params["ai"] = ai
	sim = FightSim.new()
	sim.setup(def1, def2, {
		"seed": int(params.get("seed", Time.get_ticks_usec() & 0x7FFFFFFF)),
		"rounds": int(params.get("rounds", 3)),
		"ai": params.get("ai", [0, 0]),
		"autoguard": params.get("autoguard", [0, 0]),
		"health": params.get("health", [0, 0]),
		"finishers": bool(params.get("finishers", true)),
		"training": bool(params.get("training", false)),
	})
	_build(def1, def2, c1, c2)
	var names: Array = params.get("names", [def1.display_name, def2.display_name])
	_hud.names = PackedStringArray([str(names[0]).to_upper(), str(names[1]).to_upper()])
	_hud.set_portraits([def1.id, def2.id], [c1, c2])
	_sync_views(true)


func _build(def1: FighterDef, def2: FighterDef, c1: int, c2: int) -> void:
	_stage = StageView.new()
	_stage.setup(str(params.get("stage", "grande_plage")))
	add_child(_stage)
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.04, 0.1, 0.0)
	_dim.size = Vector2(1200, 400)
	_dim.position = Vector2(-300, -100)
	_dim.z_index = 5
	add_child(_dim)
	for p: int in 2:
		var view: FighterView = FighterView.new()
		view.setup(def1 if p == 0 else def2, c1 if p == 0 else c2)
		view.z_index = 10 + p
		add_child(view)
		_views.append(view)
	_vfx = VfxPool.new()
	_vfx.sim = sim
	_vfx.defs = sim.defs
	_vfx.particles = str(_stage.data.get("impact_particles", "sand"))
	add_child(_vfx)
	_debug = DebugBoxes.new()
	_debug.sim = sim
	add_child(_debug)
	_camera = FightCamera.new()
	add_child(_camera)
	_camera.make_current()
	var ui: CanvasLayer = CanvasLayer.new()
	ui.layer = 10
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	_ui = ui
	_hud = FightHud.new()
	_hud.sim = sim
	ui.add_child(_hud)
	_announcer = Announcer.new()
	ui.add_child(_announcer)
	if bool(params.get("training", false)):
		_training = TrainingOverlay.new()
		_training.sim = sim
		_training.behavior = int(params.get("behavior", 0))
		_training.behavior_requested.connect(func(i: int) -> void:
			sim.ai_level[1] = TrainingMode.BEHAVIOR_LEVELS[i])
		_training.move_list_requested.connect(_show_move_list)
		ui.add_child(_training)
	if str(params.get("mode", "")) != "online":
		var pause_btn: Button = UiKit.button("II", _toggle_pause, 24)
		pause_btn.focus_mode = Control.FOCUS_NONE
		pause_btn.custom_minimum_size = Vector2(24, 24)
		pause_btn.position = Vector2(get_viewport_rect().size.x * 0.5 - 12, 30)
		ui.add_child(pause_btn)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_boxes") and OS.is_debug_build():
		_debug.visible = not _debug.visible
	elif event.is_action_pressed(&"ui_cancel") or (event is InputEventJoypadButton
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START and event.is_pressed()):
		if str(params.get("mode", "")) != "online":
			_toggle_pause()


func _toggle_pause() -> void:
	if _pause_box != null:
		_pause_box.queue_free()
		_pause_box = null
		paused = false
		return
	paused = true
	_pause_box = Control.new()
	_pause_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.1, 0.65)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_box.add_child(shade)
	_ui.add_child(_pause_box)
	var head: Label = UiKit.title("PAUSE")
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.position.y = 30
	_pause_box.add_child(head)
	UiKit.menu_column(_pause_box, [
		UiKit.button("Reprendre", _toggle_pause),
		UiKit.button("Liste des coups", _show_move_list),
		UiKit.button("Quitter", _leave),
	], 64)


func _show_move_list() -> void:
	var was_paused: bool = paused
	paused = true
	var list: MoveList = MoveList.create(sim.defs[0].id)
	list.closed.connect(func() -> void: paused = was_paused)
	_ui.add_child(list)


func _physics_process(_delta: float) -> void:
	if paused or get_tree().paused:
		return
	if not sim.is_over() or _end_timer > 0.0:
		sim.step(InputHub.sample(0), InputHub.sample(1))
		_consume_events()
	_sync_views(false)
	if _super_t > 0:
		_super_t -= 1
		if _super_t == 0:
			_dim.color.a = 0.0
			for v: FighterView in _views:
				v.set_silhouette(false)
			_camera.set_bias(0.0)
	if _end_timer > 0.0:
		_end_timer -= 1.0 / 60.0
		if _end_timer <= 0.0:
			_finish()


func _sync_views(snap: bool) -> void:
	for p: int in 2:
		_views[p].sync(sim.f[p])
	_camera.follow(sim.f[0].x / 256.0, sim.f[1].x / 256.0, snap)
	_stage.update_scroll(_camera.view_left())


func _consume_events() -> void:
	for ev: PackedInt32Array in sim.events:
		var key: int = (ev[0] << 12) | (ev[1] << 4) | (ev[2] + 1)
		if _seen.has(key):
			continue
		_seen[key] = true
		_on_event(ev)
	if _seen.size() > 2000:
		_seen.clear()


func _on_event(ev: PackedInt32Array) -> void:
	var type: int = ev[1]
	var actor: int = ev[2]
	var pos: Vector2 = Vector2(ev[3], ev[4])
	match type:
		FxEvents.ROUND_START:
			_announcer.say("ROUND %d" % ev[5], 0.9)
		FxEvents.FIGHT:
			_announcer.say("BORROKA !", 0.7)
			AudioManager.sfx(&"fight")
		FxEvents.HIT:
			var hit_pos: Vector2 = pos + Vector2(0, -56)
			if actor >= 0:
				hit_pos.x -= sim.f[actor].facing * -6
			_vfx.spark(hit_pos, ev[5])
			AudioManager.sfx([&"hit_light", &"hit_heavy", &"hit_uppercut", &"hit_super"][clampi(ev[5], 0, 3)])
			if OS.has_feature("mobile") or OS.has_feature("web_android"):
				Input.vibrate_handheld(20)
		FxEvents.BLOCK:
			_vfx.block(pos + Vector2(0, -56))
			AudioManager.sfx(&"block")
		FxEvents.SHAKE:
			_camera.shake(ev[5])
		FxEvents.COMBO:
			_hud.show_combo(actor, ev[5])
		FxEvents.KO:
			_announcer.say("PLOUF !", 1.4)
			_vfx.dust(pos, true)
			AudioManager.sfx(&"plouf")
		FxEvents.TIME_OVER:
			_announcer.say("TEMPS !", 1.0)
		FxEvents.PERFECT:
			_announcer.say("PARFAIT !", 1.2, Color8(244, 198, 62))
		FxEvents.WAVE_RETURN:
			_vfx.word(pos + Vector2(0, -100), "LA MARÉE MONTE !", Color8(196, 232, 230))
			AudioManager.sfx(&"wave")
		FxEvents.SUPER_START:
			_super_t = 34
			_dim.color.a = 0.55
			_views[actor].set_silhouette(true)
			_camera.set_bias(sim.f[actor].facing * 24.0)
			AudioManager.sfx(&"super")
		FxEvents.LAND, FxEvents.KNOCKDOWN, FxEvents.JUMP:
			_vfx.dust(pos, type == FxEvents.KNOCKDOWN)
		FxEvents.THROW:
			_vfx.word(pos + Vector2(0, -90), "HOP !")
		FxEvents.TECH:
			_vfx.word(pos + Vector2(0, -90), "ESQUIVE !", Color8(84, 112, 168))
		FxEvents.BUKATU:
			_announcer.say("BUKATU !", 2.0)
		FxEvents.FINISHER:
			_announcer.say("ZORIONAK !", 1.6, Color8(244, 198, 62))
			var fin: Dictionary = FighterDb.load_json(sim.defs[actor].id).get("finisher", {})
			var fx: FinisherFx = FinisherFx.new()
			add_child(fx)
			fx.start(str(fin.get("fx", "bucket")), str(fin.get("text", "PLOUF !")), _views[actor], _views[1 - actor], _vfx)
		FxEvents.MATCH_END:
			_on_match_end(actor)
		FxEvents.PROJ_HIT:
			if sim.defs[actor].projectiles[ev[5]].damage > 0:
				_vfx.spark(pos, 0)
		FxEvents.PROJ_CLASH:
			_vfx.spark(pos, 1)


func _on_match_end(w: int) -> void:
	if w >= 0:
		_announcer.say("%s GAGNE !" % _hud.names[w], 2.4, Color8(244, 198, 62), 16)
	else:
		_announcer.say("ÉGALITÉ !", 2.4)
	_end_timer = 2.8


func result() -> Dictionary:
	return {
		"winner": sim.winner,
		"rounds": [sim.f[0].rounds, sim.f[1].rounds],
		"health": [sim.f[0].health, sim.f[1].health],
		"timer": sim.timer,
		"finisher": sim.f[0].finisher_done if sim.winner == 0 else (sim.f[1].finisher_done if sim.winner == 1 else 0),
		"perfect": sim.winner >= 0 and sim.f[sim.winner].damage_taken_round == 0,
		"checksum": sim.checksum(),
		"frames": sim.frame,
	}


func _finish() -> void:
	var res: Dictionary = result()
	match_finished.emit(res)
	var on_end: Variant = params.get("on_end")
	if on_end is Callable and (on_end as Callable).is_valid():
		(on_end as Callable).call(res)
	else:
		_leave()


func _leave() -> void:
	SceneRouter.goto(StringName(str(params.get("return_to", "title"))))
