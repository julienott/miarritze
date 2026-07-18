class_name Surf
extends ChallengeBase
## Côte des Basques — « Rame et glisse » (vrai surf).
##
## Boucle : la vague approche (télégraphiée) → RAME en tapant vite pour
## remplir la jauge de vitesse → take-off dans la fenêtre, sinon la vague
## ferme (-1 vie) → GLISSE sur la face : maintenir = descendre/accélérer,
## relâcher = remonter ; rester entre la lèvre et la mousse → la vague
## s'éteint, la suivante est plus grosse. FSM : Wait, Paddle, TakeOff,
## Ride, Closeout, WaveEnd.

const _PLAYER_X: float = 380.0
const _SEA_Y: float = 470.0          # ligne de flottaison au line-up

@export_group("Vagues")
@export var wave_interval: float = 2.2       # répit entre deux vagues (s)
@export var wave_approach_time: float = 3.0  # temps d'approche visible (s)
@export var ride_duration_base: float = 5.0  # durée de glisse (s), + taille
@export var wave_growth: float = 0.14        # la vague grossit à chaque set

@export_group("Rame")
@export var paddle_per_tap: float = 0.16     # vitesse gagnée par tap
@export var paddle_decay: float = 0.35       # vitesse perdue par seconde
@export var takeoff_threshold: float = 0.65  # vitesse requise pour partir
@export var takeoff_window: float = 0.9      # durée de la fenêtre (s)

@export_group("Glisse")
@export var face_top: float = 240.0          # haut de la face (lèvre)
@export var face_bottom: float = 560.0       # bas de la face (mousse)
@export var climb_speed: float = 260.0       # remontée (relâché)
@export var dive_speed: float = 330.0        # descente (maintenu)
@export var danger_margin: float = 46.0      # débattement au-delà des limites
@export var danger_grace: float = 0.55       # tolérance avant chute (s)
@export var ride_points_per_second: int = 12
@export var takeoff_points: int = 20
@export var perfect_bonus: int = 30
@export var wave_complete_points: int = 25

var _fsm: StateMachine
var _rider: Node2D
var _player: LouisSprite
var _board: Sprite2D
var _face: Polygon2D
var _lip: Line2D
var _foam: Line2D
var _speed_bar: ColorRect
var _speed_fill: ColorRect
var _speed_zone: ColorRect
var _status: Label
var _hint: Label

var _wave_count: int = 0
var _wave_size: float = 1.0
var _paddle_speed: float = 0.0
var _swell_x: float = 1600.0             # front de la vague qui approche
var _bob_time: float = 0.0


func _on_begin() -> void:
	_face = Polygon2D.new()
	_face.color = Color(0.13, 0.47, 0.60, 0.96)
	add_child(_face)

	_lip = Line2D.new()
	_lip.width = 22.0
	_lip.default_color = Color(0.87, 0.96, 0.94)
	add_child(_lip)
	_foam = Line2D.new()
	_foam.width = 30.0
	_foam.default_color = Color(0.80, 0.92, 0.90, 0.9)
	add_child(_foam)

	_rider = Node2D.new()
	_rider.z_index = 2
	add_child(_rider)
	_board = SpriteUtil.sprite("surfboard")
	_board.position = Vector2(-20.0, LouisSprite.FEET_Y - 4.0)
	_rider.add_child(_board)
	_player = LouisSprite.new()
	_rider.add_child(_player)

	# jauge de rame (verticale, à gauche de Louis)
	_speed_bar = _bar(Vector2(240.0, 300.0), Vector2(36.0, 260.0), Color(0.14, 0.08, 0.12, 0.9))
	_speed_fill = _bar(Vector2(246.0, 554.0), Vector2(24.0, 0.0), Color(0.3, 0.85, 0.3))
	_speed_zone = _bar(Vector2(240.0, 300.0), Vector2(36.0, 6.0), Color(0.95, 0.78, 0.24))
	_speed_zone.position.y = 300.0 + 260.0 * (1.0 - takeoff_threshold)

	_status = _make_label(30, Vector2(140.0, 130.0), Color(0.97, 0.95, 0.89))
	_hint = _make_label(18, Vector2(140.0, 180.0), Color(0.95, 0.78, 0.24))

	_fsm = StateMachine.new(self)
	_fsm.add_state(&"wait", WaitState.new())
	_fsm.add_state(&"paddle", PaddleState.new())
	_fsm.add_state(&"takeoff", TakeOffState.new())
	_fsm.add_state(&"ride", RideState.new())
	_fsm.add_state(&"closeout", CloseoutState.new())
	_fsm.add_state(&"wave_end", WaveEndState.new())
	_fsm.transition_to(&"wait")


func _bar(bar_position: Vector2, size: Vector2, color: Color) -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.position = bar_position
	bar.size = size
	bar.color = color
	bar.visible = false
	add_child(bar)
	return bar


func _make_label(size: int, label_position: Vector2, color: Color) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.position = label_position
	label.custom_minimum_size = Vector2(1000.0, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	return label


func set_status(text: String, hint: String = "") -> void:
	_status.text = text
	_hint.text = hint


func _on_tapped(position: Vector2) -> void:
	_fsm.handle_tap(position)


func _physics_process(delta: float) -> void:
	if not is_running():
		return
	_bob_time += delta
	_fsm.update(delta)
	_update_speed_bar()


func _update_speed_bar() -> void:
	var show_bar: bool = _fsm.current_name == &"paddle"
	_speed_bar.visible = show_bar
	_speed_fill.visible = show_bar
	_speed_zone.visible = show_bar
	if show_bar:
		var h: float = 248.0 * clampf(_paddle_speed, 0.0, 1.0)
		_speed_fill.size.y = h
		_speed_fill.position.y = 554.0 - h
		_speed_fill.color = Color(0.3, 0.85, 0.3) if _paddle_speed >= takeoff_threshold else Color(0.95, 0.65, 0.15)


## Ligne d'eau au line-up (houle légère).
func lineup_y() -> float:
	return _SEA_Y + 6.0 * sin(_bob_time * 1.6)


func rider_flat(flat: bool) -> void:
	# à plat SUR la planche pour ramer, debout pour surfer
	_player.rotation = -PI / 2.0 if flat else 0.0
	_player.position = Vector2(12.0, 76.0) if flat else Vector2.ZERO
	_board.position = Vector2(-16.0, 82.0) if flat else Vector2(-20.0, LouisSprite.FEET_Y - 4.0)


## Dessine la vague qui approche pendant Wait/Paddle (front à _swell_x).
func draw_approaching_wave() -> void:
	var height: float = 130.0 * _wave_size
	var points: PackedVector2Array = PackedVector2Array()
	points.append(Vector2(1400.0, 730.0))
	points.append(Vector2(_swell_x - 220.0, 730.0))
	for i: int in 13:
		var x: float = _swell_x - 220.0 + i * 40.0
		var t: float = i / 12.0
		points.append(Vector2(x, lineup_y() + 40.0 - height * sin(t * PI * 0.5)))
	_face.polygon = points
	_face.visible = true
	_lip.visible = false
	_foam.visible = false


## Dessine la face pendant la glisse : pente, lèvre en haut, mousse en bas.
func draw_ride_wave(progress: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	points.append(Vector2(-40.0, 730.0))
	points.append(Vector2(1320.0, 730.0))
	points.append(Vector2(1320.0, face_top - 40.0))
	for i: int in 17:
		var x: float = 1320.0 - i * 85.0
		var t: float = i / 16.0
		points.append(Vector2(x, face_top - 40.0 + (face_bottom + 90.0 - face_top) * t
			+ 12.0 * sin(_bob_time * 3.0 + i)))
	_face.polygon = points
	_face.visible = true
	var lip_points: PackedVector2Array = PackedVector2Array()
	var foam_points: PackedVector2Array = PackedVector2Array()
	for i: int in 9:
		lip_points.append(Vector2(1320.0 - i * 90.0,
			face_top - 20.0 + 10.0 * sin(_bob_time * 5.0 + i * 1.3)))
	for i: int in 9:
		foam_points.append(Vector2(-40.0 + i * 90.0,
			face_bottom + 66.0 + 10.0 * sin(_bob_time * 4.0 + i)))
	_lip.points = lip_points
	_foam.points = foam_points
	_lip.visible = true
	_foam.visible = true
	# l'étau se resserre visuellement en fin de vague
	_lip.position.y = progress * 30.0
	_foam.position.y = -progress * 30.0


# ================================================================= États

class WaitState extends State:
	var _rest: float = 0.0

	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		_rest = surf.wave_interval
		surf._swell_x = 1600.0
		surf.rider_flat(true)
		surf._player.play(&"idle")
		surf._board.visible = true
		surf.set_status("La vague arrive…", "prépare-toi à ramer")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._rider.position = Vector2(Surf._PLAYER_X, surf.lineup_y() - LouisSprite.FEET_Y)
		surf._rider.rotation = 0.05 * sin(surf._bob_time * 1.6)
		surf.draw_approaching_wave()
		_rest -= delta
		if _rest <= 0.0:
			machine.transition_to(&"paddle")


class PaddleState extends State:
	var _elapsed: float = 0.0

	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		_elapsed = 0.0
		surf._paddle_speed = 0.0
		surf.set_status("RAME !", "tape, tape, tape ! remplis la jauge jusqu'au trait jaune")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		_elapsed += delta
		surf._paddle_speed = maxf(surf._paddle_speed - surf.paddle_decay * delta, 0.0)
		var total: float = surf.wave_approach_time
		surf._swell_x = lerpf(1600.0, Surf._PLAYER_X - 120.0, clampf(_elapsed / total, 0.0, 1.0))
		surf.draw_approaching_wave()
		# la houle soulève Louis quand le front est proche
		var lift: float = clampf(1.0 - absf(surf._swell_x - Surf._PLAYER_X) / 300.0, 0.0, 1.0)
		surf._rider.position = Vector2(Surf._PLAYER_X,
			surf.lineup_y() - LouisSprite.FEET_Y - lift * 110.0 * surf._wave_size)
		surf._rider.rotation = -0.18 * lift
		# verdict dans la fenêtre de take-off
		var window_start: float = total - surf.takeoff_window * 0.5
		var window_end: float = total + surf.takeoff_window * 0.5
		if _elapsed >= window_start and _elapsed <= window_end:
			if surf._paddle_speed >= surf.takeoff_threshold:
				var centered: bool = absf(_elapsed - total) < surf.takeoff_window * 0.2
				surf.add_score(surf.takeoff_points)
				if centered:
					surf.add_score(surf.perfect_bonus)
					surf.set_status("TAKE-OFF PARFAIT !", "+%d" % (surf.takeoff_points + surf.perfect_bonus))
				else:
					surf.set_status("Take-off !", "+%d" % surf.takeoff_points)
				machine.transition_to(&"takeoff")
		elif _elapsed > window_end:
			machine.transition_to(&"closeout")

	func handle_tap(_position: Vector2) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf._paddle_speed = minf(surf._paddle_speed + surf.paddle_per_tap, 1.0)
		surf._player.play(&"climb")   # bras qui rament


class TakeOffState extends State:
	var _t: float = 0.0

	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		_t = 0.0
		surf.rider_flat(false)
		surf._player.play(&"surf")
		AudioManager.sfx(&"jump")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		_t += delta
		var from: Vector2 = surf._rider.position
		var to: Vector2 = Vector2(Surf._PLAYER_X,
			(surf.face_top + surf.face_bottom) * 0.5 - LouisSprite.FEET_Y)
		surf._rider.position = from.lerp(to, minf(_t * 3.0, 1.0))
		surf._rider.rotation = 0.22
		surf.draw_ride_wave(0.0)
		if _t >= 0.45:
			machine.transition_to(&"ride")


class RideState extends State:
	var _time: float = 0.0
	var _duration: float = 5.0
	var _danger_time: float = 0.0
	var _score_tick: float = 0.0

	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		_time = 0.0
		_danger_time = 0.0
		_duration = surf.ride_duration_base * (0.8 + 0.4 * surf._wave_size)
		surf._rider.rotation = 0.0
		surf.set_status("Surfe la face !", "MAINTIENS = descendre, relâche = remonter")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		_time += delta
		var progress: float = _time / _duration
		surf.draw_ride_wave(progress)
		var y: float = surf._rider.position.y + LouisSprite.FEET_Y
		if surf._is_touch_pressed():
			y += surf.dive_speed * delta
			surf._rider.rotation = lerpf(surf._rider.rotation, 0.25, 8.0 * delta)
		else:
			y -= surf.climb_speed * delta
			surf._rider.rotation = lerpf(surf._rider.rotation, -0.18, 8.0 * delta)
		var top_limit: float = surf.face_top + progress * 30.0
		var bottom_limit: float = surf.face_bottom - progress * 30.0
		y = clampf(y, top_limit - surf.danger_margin, bottom_limit + surf.danger_margin)
		surf._rider.position.y = y - LouisSprite.FEET_Y
		var in_danger: bool = y < top_limit or y > bottom_limit
		if in_danger:
			_danger_time += delta
			if _danger_time >= surf.danger_grace:
				machine.transition_to(&"closeout")
				return
			surf.set_status("Attention !", "reviens au milieu de la vague !")
		else:
			_danger_time = maxf(_danger_time - delta * 2.0, 0.0)
		_score_tick += delta
		if _score_tick >= 1.0 / float(maxi(surf.ride_points_per_second, 1)):
			_score_tick = 0.0
			surf.add_score(1)
		if _time >= _duration:
			machine.transition_to(&"wave_end")


class CloseoutState extends State:
	var _t: float = 0.0

	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		_t = 0.0
		surf.set_status("La vague a fermé !", "")
		surf._board.visible = false
		surf._player.play(&"hit")
		surf._player.modulate = Color(1, 1, 1, 0.6)
		AudioManager.sfx(&"splash")
		surf.lose_life()

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		_t += delta
		surf._rider.position.y = lerpf(surf._rider.position.y,
			surf.lineup_y() - LouisSprite.FEET_Y, 3.0 * delta)
		surf._rider.rotation += 6.0 * delta
		if _t >= 1.1:
			surf._player.modulate = Color.WHITE
			surf._rider.rotation = 0.0
			machine.transition_to(&"wait")


class WaveEndState extends State:
	var _t: float = 0.0

	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		_t = 0.0
		surf._wave_count += 1
		surf._wave_size += surf.wave_growth
		var bonus: int = int(surf.wave_complete_points * surf._wave_size)
		surf.add_score(bonus)
		surf.set_status("Vague surfée !", "+%d — la prochaine est plus grosse…" % bonus)
		AudioManager.sfx(&"landed")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		_t += delta
		surf._rider.position.y = lerpf(surf._rider.position.y,
			surf.lineup_y() - LouisSprite.FEET_Y, 2.0 * delta)
		surf.draw_ride_wave(1.0)
		if _t >= 1.0:
			machine.transition_to(&"wait")
