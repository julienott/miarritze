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
var _paddle_sprite: AnimatedSprite2D
var _wave: WaveVisual
var _speed_bar: ColorRect
var _speed_fill: ColorRect
var _speed_zone: ColorRect
var _status: Label
var _hint: Label

var _wave_count: int = 0
var _wave_size: float = 1.0
var _paddle_speed: float = 0.0
var _ride_s: float = 0.55                # position sur la face (0 pied, 1 crête)
var _bob_time: float = 0.0


func _on_begin() -> void:
	_wave = WaveVisual.new()
	add_child(_wave)

	_rider = Node2D.new()
	_rider.z_index = 2
	add_child(_rider)
	_board = SpriteUtil.sprite("surfboard")
	_board.position = Vector2(-20.0, LouisSprite.FEET_Y - 4.0)
	_rider.add_child(_board)
	_player = LouisSprite.new()
	_rider.add_child(_player)
	# Louis allongé qui rame (profil), sprite dédié 2 frames
	_paddle_sprite = AnimatedSprite2D.new()
	var paddle_frames: SpriteFrames = SpriteFrames.new()
	paddle_frames.set_animation_speed(&"default", 5.0)
	paddle_frames.set_animation_loop(&"default", true)
	var paddle_sheet: Texture2D = load("res://assets/sprites/louis_paddle.png")
	for i: int in 2:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = paddle_sheet
		atlas.region = Rect2(i * 32, 0, 32, 16)
		paddle_frames.add_frame(&"default", atlas)
	_paddle_sprite.sprite_frames = paddle_frames
	_paddle_sprite.centered = false
	_paddle_sprite.scale = Vector2(4.0, 4.0)
	_paddle_sprite.position = Vector2(-64.0, LouisSprite.FEET_Y - 56.0)
	_paddle_sprite.play(&"default")
	_rider.add_child(_paddle_sprite)

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


## Ligne d'eau sous Louis (la houle de la vague comprise).
func water_y() -> float:
	return _wave.surface_y(_PLAYER_X)


func rider_flat(flat: bool) -> void:
	# allongé sur la planche (sprite profil dédié) ou debout pour surfer
	_paddle_sprite.visible = flat
	_player.visible = not flat
	_board.visible = not flat


## Place Louis (allongé ou debout) sur l'eau à x = _PLAYER_X.
func float_rider() -> void:
	_rider.position = Vector2(_PLAYER_X, water_y() - LouisSprite.FEET_Y)


# ================================================================= États

class WaitState extends State:
	var _rest: float = 0.0

	func enter(_previous: StringName) -> void:
		var surf: Surf = machine.owner_node as Surf
		_rest = surf.wave_interval
		surf.rider_flat(true)
		surf._paddle_sprite.speed_scale = 1.0
		# la houle se reforme au large
		surf._wave.center_x = 1650.0
		surf._wave.height = 60.0
		surf._wave.breaking = 0.1
		surf._wave.collapse = 0.0
		surf.set_status("La vague arrive…", "prépare-toi à ramer")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		surf.float_rider()
		surf._rider.rotation = 0.05 * sin(surf._bob_time * 1.6)
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
		var t: float = clampf(_elapsed / total, 0.0, 1.0)
		# la vague approche et grossit ; elle soulève Louis toute seule
		surf._wave.center_x = lerpf(1650.0, Surf._PLAYER_X + 180.0, t)
		surf._wave.height = lerpf(60.0, 260.0 * surf._wave_size, t)
		surf._wave.breaking = lerpf(0.1, 0.6, t)
		surf.float_rider()
		surf._rider.rotation = -0.22 * t
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
		surf._paddle_sprite.speed_scale = 2.5
		AudioManager.sfx(&"step")


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
		# la vague se cale sous Louis, il se lève au milieu de la face
		var target: Vector2 = surf._wave.face_point(0.55)
		surf._wave.center_x = lerpf(surf._wave.center_x, Surf._PLAYER_X + surf._wave.sigma * 1.5 * 0.45, 6.0 * delta)
		surf._rider.position = surf._rider.position.lerp(target - Vector2(0.0, LouisSprite.FEET_Y), minf(_t * 3.0, 1.0))
		surf._rider.rotation = 0.18
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
		surf._ride_s = 0.55
		surf._rider.rotation = 0.0
		surf.set_status("Surfe la face !", "MAINTIENS = descendre, relâche = remonter")

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		_time += delta
		var progress: float = _time / _duration
		# la vague meurt doucement, l'écume monte
		surf._wave.height = 260.0 * surf._wave_size * (1.0 - progress * 0.55)
		surf._wave.breaking = 0.6 + 0.4 * progress
		# pilotage LE LONG de la face : maintenir = descendre, relâcher = monter
		if surf._is_touch_pressed():
			surf._ride_s = maxf(surf._ride_s - delta / 0.9, 0.0)
			surf._rider.rotation = lerpf(surf._rider.rotation, 0.3, 8.0 * delta)
		else:
			surf._ride_s = minf(surf._ride_s + delta / 1.1, 1.0)
			surf._rider.rotation = lerpf(surf._rider.rotation, -0.15, 8.0 * delta)
		var p: Vector2 = surf._wave.face_point(surf._ride_s)
		surf._rider.position = p - Vector2(32.0, LouisSprite.FEET_Y)
		var in_danger: bool = surf._ride_s > 0.86 or surf._ride_s < 0.10
		if in_danger:
			_danger_time += delta
			if _danger_time >= surf.danger_grace:
				machine.transition_to(&"closeout")
				return
			var hint: String = "trop haut, la lèvre déferle !" if surf._ride_s > 0.5 else "trop bas, la mousse te rattrape !"
			surf.set_status("Attention !", hint)
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
		surf.rider_flat(false)
		surf._board.visible = false
		surf._player.play(&"hit")
		surf._player.modulate = Color(1, 1, 1, 0.6)
		AudioManager.sfx(&"splash")
		surf.lose_life()

	func update(delta: float) -> void:
		var surf: Surf = machine.owner_node as Surf
		_t += delta
		# l'écume dévale la face et emporte Louis
		surf._wave.collapse = minf(surf._wave.collapse + delta * 2.0, 1.0)
		surf._wave.breaking = 1.0
		surf._wave.height = maxf(surf._wave.height - 140.0 * delta, 30.0)
		surf._rider.position.y = lerpf(surf._rider.position.y,
			surf.water_y() - LouisSprite.FEET_Y, 3.0 * delta)
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
		surf._wave.height = maxf(surf._wave.height - 200.0 * delta, 8.0)
		surf._wave.breaking = maxf(surf._wave.breaking - delta, 0.2)
		surf._rider.position.y = lerpf(surf._rider.position.y,
			surf.water_y() - LouisSprite.FEET_Y, 2.0 * delta)
		if _t >= 1.0:
			machine.transition_to(&"wait")
