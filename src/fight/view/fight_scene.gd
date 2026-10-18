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
var _touch: TouchControls
var _tutorial: TutorialOverlay
## En ligne : session rollback + lien P2P (SPEC §8.6).
var session: RollbackSession
var _online: bool = false
var _local_slot: int = 0
var _net_icon: Label
var _away_t: float = -1.0
var _forfeit: int = -2
var _recorded: bool = false
var _stall_t: float = 0.0
var _was_hidden: bool = false


## Web : l'onglet passé en arrière-plan (visibilitychange) prévient l'adversaire.
func _check_visibility(link: P2PLink) -> void:
	if not OS.has_feature("web"):
		return
	var hidden: bool = bool(JavaScriptBridge.eval("document.hidden", true))
	if hidden != _was_hidden:
		_was_hidden = hidden
		link.send_ctrl({"t": "away" if hidden else "back"})


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
	if str(params.get("mode", "")) == "online" and OnlineMode.link != null:
		_setup_online()
	var names: Array = params.get("names", [def1.display_name, def2.display_name])
	_hud.names = PackedStringArray([str(names[0]).to_upper(), str(names[1]).to_upper()])
	_hud.set_portraits([def1.id, def2.id], [c1, c2])
	_sync_views(true)
	_play_stage_music()


func _setup_online() -> void:
	_online = true
	_local_slot = int(params.get("local_slot", 0))
	session = RollbackSession.new()
	session.setup(sim, _local_slot, int(params.get("delay", 2)), int(params.get("seed", 0)))
	OnlineMode.link.ctrl_received.connect(_on_ctrl)
	OnlineMode.link.failed.connect(func(_r: String) -> void:
		if not sim.is_over():
			_forfeit = _local_slot
			_announcer.say("CONNEXION PERDUE", 2.0)
			_end_timer = 2.5)
	_net_icon = UiKit.label("~", 16, Color8(196, 232, 230))
	_net_icon.position = Vector2(4, 48)
	_net_icon.visible = false
	_ui.add_child(_net_icon)


func _on_ctrl(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"away":
			_away_t = 10.0
		"back":
			_away_t = -1.0


func _notification(what: int) -> void:
	if not _online:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		OnlineMode.link.send_ctrl({"t": "away"})
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		OnlineMode.link.send_ctrl({"t": "back"})


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
	for b: bool in [true, false]:
		var mfx: MoveFx = MoveFx.new()
		mfx.sim = sim
		mfx.defs = sim.defs
		mfx.back = b
		add_child(mfx)
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
		_training.behavior = int(params.get("behavior", TrainingMode.DEFAULT_BEHAVIOR))
		_training.behavior_requested.connect(func(i: int) -> void:
			sim.ai_level[1] = TrainingMode.BEHAVIOR_LEVELS[i])
		_training.move_list_requested.connect(_show_move_list)
		ui.add_child(_training)
	if bool(params.get("tutorial", false)):
		var tuto: TutorialOverlay = TutorialOverlay.new()
		_tutorial = tuto
		tuto.sim = sim
		tuto.finished.connect(func() -> void:
			Profiles.update_active({"tutorial_done": true})
			Profiles.grant_title("debutant")
			_leave())
		ui.add_child(tuto)
		if _training != null:
			_training.visible = false
	var ai_pair: Array = params.get("ai", [0, 0])
	# Versus contre l'ordi (J2 piloté par l'IA) : la manette tactile reste dispo.
	if Settings.touch_enabled() and (str(params.get("mode", "")) != "versus" or int(ai_pair[1]) > 0) \
			and int(ai_pair[0]) == 0:
		_touch = TouchControls.new()
		var me_slot: int = int(params.get("local_slot", 0))
		_touch.facing_getter = func() -> int: return sim.f[me_slot].facing
		_touch.meter_full_getter = func() -> bool: return sim.f[me_slot].meter >= SimConst.METER_MAX
		_touch.fighter_rects_getter = func() -> Array:
			var out: Array = []
			var xf: Transform2D = get_viewport().get_canvas_transform()
			for p: int in 2:
				var feet: Vector2 = xf * Vector2(sim.f[p].x / 256.0, sim.f[p].y / 256.0)
				out.append(Rect2(feet.x - 22.0, feet.y - 96.0, 44.0, 96.0))
			return out
		ui.add_child(_touch)
		InputHub.add_source(0, VirtualPadSource.new(_touch))
	if str(params.get("mode", "")) != "online":
		var pause_btn: Button = UiKit.button("PAUSE", _toggle_pause, 50)
		pause_btn.focus_mode = Control.FOCUS_NONE
		pause_btn.custom_minimum_size = Vector2(50, 20)
		pause_btn.position = Vector2(get_viewport_rect().size.x * 0.5 - 25, 30)
		ui.add_child(pause_btn)
	# Les annonces passent au-dessus du bouton pause et de la manette.
	ui.move_child(_announcer, -1)


const SPECIAL_SFX: Dictionary = {"txomin": &"whistle", "karramarro": &"pinch", "ramuntxo": &"fire",
	"xabi": &"pelota", "kaio": &"gull", "maia": &"wave", "itsaso": &"splash"}


func _play_stage_music() -> void:
	var track: String = str(_stage.data.get("music", ""))
	if track == "":
		track = str(params.get("stage", "grande_plage")).replace("_soir", "").replace("_crepuscule", "")
	if sim.defs[1].id == Roster.BOSS:
		track = "phare_sommet"
	AudioManager.play_music(StringName(track))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_boxes") and OS.is_debug_build():
		_debug.visible = not _debug.visible
	elif event.is_action_pressed(&"ui_cancel") or InputDevice.is_start(event):
		if str(params.get("mode", "")) != "online":
			get_viewport().set_input_as_handled()
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
	var buttons: Array = [
		UiKit.button("Reprendre", _toggle_pause),
		UiKit.button("Liste des coups", _show_move_list),
	]
	# Entraînement : le mannequin se règle aussi à la manette / au clavier
	# (ses boutons à l'écran ne se pilotent qu'au doigt ou à la souris).
	if _training != null and _training.visible:
		var dummy: Button = UiKit.button("Mannequin : " + TrainingMode.BEHAVIORS[_training.behavior],
			func() -> void: pass, 160)
		dummy.pressed.connect(func() -> void:
			_training.cycle_behavior()
			dummy.text = "Mannequin : " + TrainingMode.BEHAVIORS[_training.behavior])
		buttons.append(dummy)
	if _tutorial != null:
		buttons.append(UiKit.button("Passer le tutoriel", func() -> void:
			_toggle_pause()
			_tutorial.finished.emit()))
	buttons.append(UiKit.button("Quitter", _leave))
	for b: Variant in buttons:
		(b as Control).custom_minimum_size.x = 160
	UiKit.menu_column(_pause_box, buttons, 58).position.x -= 10
	UiKit.prompt_bar(_pause_box, {"keyboard": "{ok} : valider   {back} : reprendre",
		"gamepad": "{ok} : valider   {back} : reprendre"})


func _show_move_list() -> void:
	var was_paused: bool = paused
	paused = true
	var list: MoveList = MoveList.create(sim.defs[0].id)
	list.closed.connect(func() -> void:
		paused = was_paused
		# Retour au menu pause : le focus revient sur « Liste des coups ».
		if _pause_box != null and is_instance_valid(_pause_box):
			for b: Node in _pause_box.find_children("*", "Button", true, false):
				if (b as Button).text == "Liste des coups":
					(b as Button).grab_focus.call_deferred())
	_ui.add_child(list)


func _physics_process(_delta: float) -> void:
	if paused or get_tree().paused:
		return
	if _online:
		_online_tick()
	elif not sim.is_over() or _end_timer > 0.0:
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
		# En ligne, on attend le checksum final confirmé (sauf forfait/désync).
		if _end_timer <= 0.0 and _online and session.final_checksum < 0 and _forfeit < 0 and not session.desync:
			_end_timer = 1.0 / 60.0
		elif _end_timer <= 0.0:
			_finish()


func _online_tick() -> void:
	var link: P2PLink = OnlineMode.link
	if link == null or not is_instance_valid(link):
		return
	_check_visibility(link)
	# Adversaire figé trop longtemps (onglet suspendu, réseau coupé) : forfait.
	if session.stalled:
		_stall_t += 1.0 / 60.0
		if _stall_t > 12.0 and _end_timer < 0.0:
			_forfeit = 1 - _local_slot
			_announcer.say("FORFAIT", 2.0)
			_end_timer = 2.5
	else:
		_stall_t = 0.0
	for packet: PackedByteArray in link.poll_inputs():
		session.receive(packet)
	if not sim.is_over() or session.final_checksum < 0 or _end_timer > 0.0:
		link.send_input(session.tick(InputHub.sample(0)))
	else:
		# Canal non fiable : on continue de renvoyer la dernière fenêtre
		# d'entrées pour que l'adversaire confirme lui aussi la fin du match.
		link.send_input(session._input_packet())
	for c: PackedByteArray in session.take_check_packets():
		link.send_input(c)
	for ev: PackedInt32Array in session.take_events():
		var key: int = (ev[0] << 12) | (ev[1] << 4) | (ev[2] + 1)
		if not _seen.has(key):
			_seen[key] = true
			_on_event(ev)
	_net_icon.visible = session.stalled
	if session.desync and _end_timer < 0.0:
		_announcer.say("MATCH NUL TECHNIQUE", 2.0)
		_end_timer = 2.5
	if _away_t > 0.0:
		_away_t -= 1.0 / 60.0
		_announcer.say("%s : %d" % [_hud.names[1 - _local_slot], ceili(_away_t)], 0.2, Color8(244, 198, 62), 8)
		if _away_t <= 0.0 and _end_timer < 0.0:
			_forfeit = 1 - _local_slot
			_announcer.say("FORFAIT", 2.0)
			_end_timer = 2.5


func _sync_views(snap: bool) -> void:
	for p: int in 2:
		_views[p].sync(sim.f[p])
		# L'attaquant est dessiné devant : on voit qui frappe qui.
		_views[p].z_index = 11 if sim.f[p].state == SimConst.ST_MOVE else 10
	# Sommet approximatif du combattant le plus haut (pied − 110 px).
	_camera.set_top(minf(sim.f[0].y, sim.f[1].y) / 256.0 - 110.0)
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
			AudioManager.sfx(&"round")
		FxEvents.FIGHT:
			_announcer.say("BORROKA !", 0.7)
			AudioManager.sfx(&"fight")
			AudioManager.voice(&"borroka")
		FxEvents.HIT:
			var hit_pos: Vector2 = pos + Vector2(0, -56)
			if actor >= 0:
				hit_pos.x -= sim.f[actor].facing * -6
			_vfx.spark(hit_pos, ev[5])
			AudioManager.sfx([&"hit_light", &"hit_heavy", &"hit_uppercut", &"hit_super"][clampi(ev[5], 0, 3)])
			if Settings.vibrations and (OS.has_feature("mobile") or OS.has_feature("web_android")):
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
			AudioManager.sfx(&"ko")
			AudioManager.voice(&"plouf")
		FxEvents.TIME_OVER:
			_announcer.say("TEMPS !", 1.0)
		FxEvents.PERFECT:
			_announcer.say("PARFAIT !", 1.2, Color8(244, 198, 62))
			AudioManager.sfx(&"perfect")
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
			AudioManager.sfx(&"jump" if type == FxEvents.JUMP else &"land")
		FxEvents.WHIFF:
			AudioManager.sfx(&"whiff")
		FxEvents.SPECIAL_START:
			AudioManager.sfx(SPECIAL_SFX.get(sim.defs[actor].id, &"special"))
		FxEvents.PROJ_SPAWN:
			AudioManager.sfx(&"projectile")
		FxEvents.THROW:
			_vfx.word(pos + Vector2(0, -90), "HOP !")
			AudioManager.sfx(&"throw")
		FxEvents.TECH:
			_vfx.word(pos + Vector2(0, -90), "ESQUIVE !", Color8(84, 112, 168))
			AudioManager.sfx(&"tech")
		FxEvents.BUKATU:
			_announcer.say("BUKATU !", 2.0)
			AudioManager.voice(&"bukatu")
		FxEvents.FINISHER:
			_announcer.say("ZORIONAK !", 1.6, Color8(244, 198, 62))
			AudioManager.sfx(StringName(str({"bucket": "bucket", "wave": "wave", "fish": "splash"}.get(
				str(FighterDb.load_json(sim.defs[actor].id).get("finisher", {}).get("fx", "")), "crowd"))))
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
	AudioManager.play_music(&"victory")
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
	if _online:
		_report_online(res)
		return
	match_finished.emit(res)
	var on_end: Variant = params.get("on_end")
	if on_end is Callable and (on_end as Callable).is_valid():
		(on_end as Callable).call(res)
	else:
		_leave()


func _report_online(res: Dictionary, attempt: int = 0) -> void:
	var winner: int = int(res.get("winner", -1))
	if _forfeit >= 0:
		winner = 1 - _forfeit
	if session.desync:
		winner = -1
	Api.call_api(HTTPClient.METHOD_POST, "/match/report", {"match_id": int(OnlineMode.current.get("match_id", 0)),
		"winner": winner, "checksum": session.final_checksum if _forfeit < 0 else 0,
		"rounds": res.get("rounds", [0, 0])}, func(_ok: bool, _c: int, data: Variant) -> void:
			print("online_report winner=%d checksum=%d final_frame=%d attempt=%d reponse=%s" % [winner,
				session.final_checksum, session.final_frame, attempt, str(data)])
			# Premier rapporteur : le verdict arrive quand l'autre a rapporté à son tour.
			if data is Dictionary and str((data as Dictionary).get("state", "")) == "waiting" and attempt < 4:
				get_tree().create_timer(1.5).timeout.connect(_report_online.bind(res, attempt + 1))
				return
			var rated: bool = data is Dictionary and bool((data as Dictionary).get("rated", false))
			if winner >= 0 and not _recorded:
				_recorded = true
				var my_win: bool = winner == _local_slot
				Profiles.record_fight(sim.defs[_local_slot].id, my_win, str(params.get("stage", "")),
					my_win and int(res.get("finisher", 0)) != 0, my_win and bool(res.get("perfect", false)))
			SceneRouter.goto(&"results", {"mode": "online", "result": res, "fight": params,
				"rated": rated, "local_slot": _local_slot, "desync": session.desync, "rollbacks": session.rollbacks}))


func _leave() -> void:
	if _online:
		OnlineMode.leave()
		return
	SceneRouter.goto(StringName(str(params.get("return_to", "main_menu"))))
