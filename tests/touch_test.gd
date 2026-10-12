extends Node
## Tests de la manette virtuelle avec des index de toucher ALÉATOIRES
## (régression iOS, SPEC §7.3, §14.2). Lancé comme scène (autoloads chargés) :
## godot --headless --path . res://tests/touch_test.tscn

var _fail: int = 0


func _ready() -> void:
	var tc: TouchControls = TouchControls.new()
	add_child(tc)
	# iPhone 13 en paysage : 844×390 pt, vue logique ≈ 468×216.
	tc.forced_view = Vector2(468, 216)
	tc.forced_height_pt = 390.0
	tc._layout()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1234
	for trial: int in 50:
		var i_stick: int = rng.randi_range(0, 1 << 20)
		var i_btn: int = rng.randi_range(0, 1 << 20)
		var i_btn2: int = rng.randi_range(0, 1 << 20)
		# Joystick : appui moitié gauche puis glisser vers la droite.
		_touch(tc, i_stick, Vector2(90, 150), true)
		_drag(tc, i_stick, Vector2(110, 150))
		# Deux boutons en même temps (POING + SPÉCIAL), index arbitraires.
		_touch(tc, i_btn, tc._buttons["punch"]["center"], true)
		_touch(tc, i_btn2, tc._buttons["special"]["center"], true)
		var m: int = tc.read_mask()
		_check(m & InputSource.RIGHT != 0, "joystick → droite (essai %d)" % trial)
		_check(m & InputSource.PUNCH != 0 and m & InputSource.SPECIAL != 0, "POING + SPÉCIAL simultanés")
		# Glisser de POING vers PIED sans lever le doigt.
		_drag(tc, i_btn, tc._buttons["kick"]["center"])
		m = tc.read_mask()
		_check(m & InputSource.KICK != 0 and m & InputSource.PUNCH == 0, "glisser POING → PIED")
		# Relâcher dans le désordre.
		_touch(tc, i_btn2, tc._buttons["special"]["center"], false)
		_touch(tc, i_stick, Vector2(110, 150), false)
		_touch(tc, i_btn, tc._buttons["kick"]["center"], false)
		m = tc.read_mask()
		_check(m == 0, "tout relâché → masque vide (%d)" % m)
	# Tap très bref (appui + relâcher dans le même tick) : jamais perdu.
	_touch(tc, 77, tc._buttons["punch"]["center"], true)
	_touch(tc, 77, tc._buttons["punch"]["center"], false)
	_check(tc.read_mask() & InputSource.PUNCH != 0, "tap bref verrouillé")
	# Hystérésis : près de la frontière droite/diagonale, la direction ne tremble pas.
	_touch(tc, 5, Vector2(80, 150), true)
	_drag(tc, 5, Vector2(120, 150))
	_drag(tc, 5, Vector2(120, 136))   # ≈ 19° : reste « droite » grâce à l'hystérésis
	_check(tc._dir == 6, "hystérésis 10° (dir %d)" % tc._dir)
	_touch(tc, 5, Vector2(120, 136), false)
	# --- Mode Gestes (§7.4)
	tc.mode = "gestures"
	var supers: Array[int] = [0]
	tc.super_requested.connect(func() -> void: supers[0] += 1)
	# Pouce gauche qui se déplace + tap droit au même moment : PAS de super.
	_touch(tc, 900, Vector2(80, 150), true)
	_touch(tc, 901, Vector2(380, 120), true)
	_drag(tc, 900, Vector2(130, 150))
	_touch(tc, 901, Vector2(380, 120), false)
	_touch(tc, 900, Vector2(130, 150), false)
	_check(supers[0] == 0, "geste : pas de super sur pouce + tap")
	tc.read_mask()
	# Deux taps courts simultanés : super.
	_touch(tc, 910, Vector2(300, 120), true)
	_touch(tc, 911, Vector2(400, 120), true)
	_touch(tc, 910, Vector2(300, 120), false)
	_touch(tc, 911, Vector2(400, 120), false)
	_check(supers[0] == 1, "geste : tap à deux doigts → super (%d)" % supers[0])
	_check(tc.read_mask() & (InputSource.SPECIAL | InputSource.GUARD) == (InputSource.SPECIAL | InputSource.GUARD), "geste : super = SPÉCIAL+GARDE")
	# Garde tenue par un doigt, un autre doigt droit qui tape ne la retire pas.
	_touch(tc, 920, Vector2(400, 150), true)
	tc._touches[920]["t0"] = Time.get_ticks_msec() - 400
	tc._process(0.016)
	_touch(tc, 921, Vector2(330, 100), true)
	tc._touches[921]["t0"] = Time.get_ticks_msec() - 400
	_touch(tc, 921, Vector2(330, 100), false)
	_check(tc.read_mask() & InputSource.GUARD != 0, "geste : la garde reste tenue")
	_touch(tc, 920, Vector2(400, 150), false)
	_check(tc.read_mask() & InputSource.GUARD == 0, "geste : garde relâchée")
	# Swipe vers l'adversaire (à droite) : PIED avant.
	_touch(tc, 930, Vector2(300, 120), true)
	tc._touches[930]["t0"] = Time.get_ticks_msec() - 100
	_touch(tc, 930, Vector2(345, 122), false)
	var sm: int = tc.read_mask()
	_check(sm & InputSource.KICK != 0 and sm & InputSource.RIGHT != 0, "geste : swipe vers l'adversaire → avant + PIED")
	print("touch_test : %s" % ("OK" if _fail == 0 else "%d échecs" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


func _touch(tc: TouchControls, index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	tc._input(e)


func _drag(tc: TouchControls, index: int, pos: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	tc._input(e)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		printerr("  ✗ " + msg)
