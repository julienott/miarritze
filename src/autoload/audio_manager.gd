extends Node
## AudioManager — musique par épreuve, SFX, volumes.
##
## Cherche assets/audio/music/<challenge>.ogg et assets/audio/sfx/<name>.ogg ;
## silencieux si l'asset n'existe pas encore (les assets arrivent en Phase 4).

const _MUSIC_DIR: String = "res://assets/audio/music/"
const _SFX_DIR: String = "res://assets/audio/sfx/"
const _SFX_PLAYER_COUNT: int = 4

## Volume musique (0..1), réglable au playtest.
@export_range(0.0, 1.0) var music_volume: float = 0.8

## Volume SFX (0..1), réglable au playtest.
@export_range(0.0, 1.0) var sfx_volume: float = 1.0

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _current_music: StringName = &""


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Master"
	add_child(_music_player)
	for i: int in _SFX_PLAYER_COUNT:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		_sfx_players.append(player)


## Lance (ou relance) le thème musical associé à une épreuve.
func play_music(challenge: StringName) -> void:
	if challenge == _current_music and _music_player.playing:
		return
	var stream: AudioStream = _load_stream(_MUSIC_DIR + String(challenge))
	_current_music = challenge
	if stream == null:
		_music_player.stop()
		return
	_music_player.stream = stream
	_music_player.volume_db = linear_to_db(music_volume)
	_music_player.play()


func stop_music() -> void:
	_current_music = &""
	_music_player.stop()


## Joue un bruitage par nom (ex. &"jump", &"coin", &"splash").
func sfx(sfx_name: StringName) -> void:
	var stream: AudioStream = _load_stream(_SFX_DIR + String(sfx_name))
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _SFX_PLAYER_COUNT
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume)
	player.play()


func _load_stream(base_path: String) -> AudioStream:
	for extension: String in ["ogg", "wav", "mp3"]:
		var path: String = "%s.%s" % [base_path, extension]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null
