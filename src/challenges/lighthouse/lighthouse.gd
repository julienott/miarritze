class_name Lighthouse
extends ChallengeBase
## Phare — ascension-plateforme verticale (cf. DESIGN.md §4.6).
## Débloqué par le score cumulé. Louis marche automatiquement sur chaque
## palier ; tap = saut vers le palier suivant. Au sommet : la salle des
## trophées (classement des copains) et un bonus.
## FSM : Climb, Jump, Fall, Reach.

const _PLAYER_SIZE: Vector2 = Vector2(44, 60)
const _PLATFORM_SIZE: Vector2 = Vector2(220, 26)
const _LEFT_X: float = 380.0
const _RIGHT_X: float = 830.0
const _BASE_Y: float = 640.0
const _STEP_Y: float = 150.0

@export var platform_count: int = 25
@export var walk_speed: float = 240.0
@export var jump_velocity: float = -880.0
@export var jump_horizontal_speed: float = 320.0
@export var gravity: float = 2100.0
@export var platform_points: int = 15
@export var summit_points: int = 200
@export var time_bonus_per_second: int = 2

var _fsm: StateMachine
var _player: ColorRect
var _camera: Camera2D
var _platforms: Array[ColorRect] = []
var _current_level: int = 0
var _walk_direction: float = 1.0
var _velocity: Vector2 = Vector2.ZERO
var _trophy_layer: CanvasLayer = null
var _trophy_rows: VBoxContainer = null
var _trophy_status: Label = null


func _on_begin() -> void:
	for i: int in platform_count:
		var platform: ColorRect = ColorRect.new()
		platform.position = Vector2(_platform_x(i) - _PLATFORM_SIZE.x * 0.5, _level_y(i))
		platform.size = _PLATFORM_SIZE
		platform.color = Color(0.75, 0.72, 0.68) if i % 2 == 0 else Color(0.65, 0.35, 0.3)
		add_child(platform)
		_platforms.append(platform)

	_player = ColorRect.new()
	_player.size = _PLAYER_SIZE
	_player.color = Color(0.85, 0.25, 0.2)
	add_child(_player)
	_place_on_level(0)

	_camera = Camera2D.new()
	_camera.position = Vector2(640.0, 400.0)
	add_child(_camera)
	_camera.make_current()

	_fsm = StateMachine.new(self)
	_fsm.add_state(&"climb", ClimbState.new())
	_fsm.add_state(&"jump", JumpState.new())
	_fsm.add_state(&"fall", FallState.new())
	_fsm.add_state(&"reach", ReachState.new())
	_fsm.transition_to(&"climb")


func _on_tapped(position: Vector2) -> void:
	_fsm.handle_tap(position)


func _physics_process(delta: float) -> void:
	if not is_running():
		return
	_fsm.update(delta)
	# La caméra suit Louis vers le haut, jamais sous le rez-de-chaussée.
	var target_y: float = minf(_player.position.y - 160.0, 400.0)
	_camera.position.y = lerpf(_camera.position.y, target_y, 6.0 * delta)


func _platform_x(level: int) -> float:
	return _LEFT_X if level % 2 == 0 else _RIGHT_X


func _level_y(level: int) -> float:
	return _BASE_Y - level * _STEP_Y


func _place_on_level(level: int) -> void:
	_current_level = level
	_player.position = Vector2(_platform_x(level) - _PLAYER_SIZE.x * 0.5,
		_level_y(level) - _PLAYER_SIZE.y)


## Palier atteint pendant une chute : le plus haut dont le dessus est sous les
## pieds ET dont Louis chevauche l'étendue horizontale. -1 si aucun.
func landing_level() -> int:
	var feet: float = _player.position.y + _PLAYER_SIZE.y
	var center_x: float = _player.position.x + _PLAYER_SIZE.x * 0.5
	for level: int in range(platform_count - 1, -1, -1):
		var top: float = _level_y(level)
		if feet >= top and feet <= top + 40.0:
			if absf(center_x - _platform_x(level)) <= _PLATFORM_SIZE.x * 0.5 + 8.0:
				return level
	return -1


func show_trophy_room() -> void:
	_trophy_layer = CanvasLayer.new()
	add_child(_trophy_layer)

	var panel: ColorRect = ColorRect.new()
	panel.position = Vector2(240.0, 80.0)
	panel.size = Vector2(800.0, 560.0)
	panel.color = Color(0.08, 0.15, 0.25, 0.95)
	_trophy_layer.add_child(panel)

	var title: Label = Label.new()
	title.text = "🏆 Salle des trophées"
	title.add_theme_font_size_override(&"font_size", 44)
	title.position = Vector2(60.0, 30.0)
	panel.add_child(title)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.position = Vector2(60.0, 110.0)
	rows.add_theme_constant_override(&"separation", 10)
	panel.add_child(rows)

	var status: Label = Label.new()
	status.text = "Chargement du classement…"
	status.add_theme_font_size_override(&"font_size", 26)
	rows.add_child(status)

	var done_button: Button = Button.new()
	done_button.text = "Terminer"
	done_button.custom_minimum_size = Vector2(280, 70)
	done_button.add_theme_font_size_override(&"font_size", 28)
	done_button.position = Vector2(260.0, 460.0)
	done_button.pressed.connect(end)
	panel.add_child(done_button)

	_trophy_rows = rows
	_trophy_status = status
	LeaderboardClient.leaderboard_fetched.connect(
		_on_trophy_leaderboard_fetched, CONNECT_ONE_SHOT)
	LeaderboardClient.fetch_leaderboard()


func _on_trophy_leaderboard_fetched(entries: Array[Dictionary]) -> void:
	if _trophy_status != null:
		_trophy_status.queue_free()
		_trophy_status = null
	if entries.is_empty():
		var empty: Label = Label.new()
		empty.text = "Sois le premier au sommet !"
		empty.add_theme_font_size_override(&"font_size", 26)
		_trophy_rows.add_child(empty)
		return
	var rank: int = 1
	for entry: Dictionary in entries.slice(0, 8):
		var row: Label = Label.new()
		row.add_theme_font_size_override(&"font_size", 26)
		row.text = "%d.  %s — %d" % [rank, str(entry.get("pseudo", "?")),
			int(entry.get("total", entry.get("best_score", 0)))]
		_trophy_rows.add_child(row)
		rank += 1


# --- États ---

class ClimbState extends State:
	func enter(_previous: StringName) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		lighthouse._velocity = Vector2.ZERO

	func update(delta: float) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		# Va-et-vient automatique sur le palier courant.
		var platform_center: float = lighthouse._platform_x(lighthouse._current_level)
		var half: float = Lighthouse._PLATFORM_SIZE.x * 0.5 - Lighthouse._PLAYER_SIZE.x * 0.5
		var center_x: float = lighthouse._player.position.x + Lighthouse._PLAYER_SIZE.x * 0.5
		center_x += lighthouse.walk_speed * lighthouse._walk_direction * delta
		if center_x > platform_center + half:
			center_x = platform_center + half
			lighthouse._walk_direction = -1.0
		elif center_x < platform_center - half:
			center_x = platform_center - half
			lighthouse._walk_direction = 1.0
		lighthouse._player.position.x = center_x - Lighthouse._PLAYER_SIZE.x * 0.5

	func handle_tap(_position: Vector2) -> void:
		machine.transition_to(&"jump")


class JumpState extends State:
	func enter(_previous: StringName) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		# Le saut part vers le palier suivant : la direction horizontale est
		# donnée par la position du prochain palier, le timing par le joueur
		# (sauter du mauvais bord = rater le palier).
		var next_x: float = lighthouse._platform_x(lighthouse._current_level + 1)
		var center_x: float = lighthouse._player.position.x + Lighthouse._PLAYER_SIZE.x * 0.5
		var direction: float = signf(next_x - center_x)
		lighthouse._velocity = Vector2(lighthouse.jump_horizontal_speed * direction,
			lighthouse.jump_velocity)
		AudioManager.sfx(&"jump")

	func update(delta: float) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		lighthouse._velocity.y += lighthouse.gravity * delta
		lighthouse._player.position += lighthouse._velocity * delta
		if lighthouse._velocity.y >= 0.0:
			machine.transition_to(&"fall")


class FallState extends State:
	func update(delta: float) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		lighthouse._velocity.y += lighthouse.gravity * delta
		lighthouse._player.position += lighthouse._velocity * delta
		var level: int = lighthouse.landing_level()
		if level >= 0:
			var reached_higher: bool = level > lighthouse._current_level
			lighthouse._place_on_level(level)
			if reached_higher:
				lighthouse.add_score(lighthouse.platform_points)
				AudioManager.sfx(&"step")
			if level >= lighthouse.platform_count - 1:
				machine.transition_to(&"reach")
			else:
				machine.transition_to(&"climb")
		elif lighthouse._player.position.y > Lighthouse._BASE_Y + 200.0:
			# Filet de sécurité : jamais plus bas que le rez-de-chaussée.
			lighthouse._place_on_level(0)
			machine.transition_to(&"climb")


class ReachState extends State:
	func enter(_previous: StringName) -> void:
		var lighthouse: Lighthouse = machine.owner_node as Lighthouse
		lighthouse.add_score(lighthouse.summit_points)
		AudioManager.sfx(&"victory")
		lighthouse.show_trophy_room()
