extends Node
## AudioManager — musique par écran/stage, SFX, voix (SPEC §12).
##
## Bus Music / SFX / Voice créés au démarrage, volumes depuis Settings,
## ducking de la musique (−8 dB) pendant les annonces et le super.
## Web : l'autoplay est bloqué jusqu'au premier geste ; la piste en cours
## est relancée à ce moment-là. Silencieux si un asset n'existe pas encore.

const _MUSIC_DIR: String = "res://assets/audio/music/"
const _SFX_DIR: String = "res://assets/audio/sfx/"
const _VOICE_DIR: String = "res://assets/audio/voice/"
const _SFX_PLAYER_COUNT: int = 6
const DUCK_DB: float = -8.0

var _music_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _current_music: StringName = &""
var _web_unlocked: bool = false
var _duck_t: float = 0.0
var _cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus: String in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, &"Master")
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = &"Voice"
	add_child(_voice_player)
	for i: int in _SFX_PLAYER_COUNT:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)
	_web_unlocked = not OS.has_feature("web")
	apply_volumes()


func apply_volumes() -> void:
	_set_bus("Music", Settings.music_volume)
	_set_bus("SFX", Settings.sfx_volume)
	_set_bus("Voice", Settings.voice_volume)


func _set_bus(bus: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func _input(event: InputEvent) -> void:
	if _web_unlocked:
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton \
			or event is InputEventKey or event is InputEventJoypadButton:
		_web_unlocked = true
		# Safari (macOS et iOS) : le contexte WebAudio reste suspendu même après
		# un geste utilisateur tant qu'on n'appelle pas resume() explicitement.
		# Le driver Godot n'y pense pas, on force côté JS.
		if OS.has_feature("web"):
			JavaScriptBridge.eval("""(function(){
				try {
					var AC = window.AudioContext || window.webkitAudioContext;
					if (!AC) return;
					if (!window.__godotAudioCtxs) window.__godotAudioCtxs = [];
					// Capture tous les contextes créés depuis le début.
					if (!AC.__patched) {
						var orig = AC.prototype.constructor;
						AC.__patched = true;
					}
					// On parcourt l'objet Module de l'export Godot si présent.
					var ctxs = [];
					if (window.Godot && window.Godot.AudioContext) ctxs.push(window.Godot.AudioContext);
					if (window.AudioDriverWeb && window.AudioDriverWeb.context) ctxs.push(window.AudioDriverWeb.context);
					if (window.audio_driver_js && window.audio_driver_js.context) ctxs.push(window.audio_driver_js.context);
					ctxs.forEach(function(c){ try { if (c && c.resume) c.resume(); } catch(e){} });
					// Secours : un AudioContext muet, dont la création relance tout.
					try { var tmp = new AC(); tmp.resume && tmp.resume(); setTimeout(function(){ tmp.close && tmp.close(); }, 100); } catch(e){}
				} catch(e){}
			})();""", true)
		if _current_music != &"":
			var track: StringName = _current_music
			_current_music = &""
			play_music(track)


func _process(delta: float) -> void:
	var target: float = DUCK_DB if _duck_t > 0.0 else 0.0
	_duck_t = maxf(_duck_t - delta, 0.0)
	_music_player.volume_db = move_toward(_music_player.volume_db, target, delta * 40.0)


## Baisse la musique pendant `seconds` (annonces, super).
func duck(seconds: float = 1.0) -> void:
	_duck_t = maxf(_duck_t, seconds)


func play_music(track: StringName) -> void:
	if track == _current_music and _music_player.playing:
		return
	var stream: AudioStream = _load_stream(_MUSIC_DIR + String(track))
	_current_music = track
	if stream == null:
		_music_player.stop()
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_current_music = &""
	_music_player.stop()


func sfx(sfx_name: StringName, pitch: float = 1.0) -> void:
	var stream: AudioStream = _load_stream(_SFX_DIR + String(sfx_name))
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _SFX_PLAYER_COUNT
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


## Annonce vocale (« Borroka ! »…) ; repli silencieux si absente.
func voice(voice_name: StringName) -> void:
	var stream: AudioStream = _load_stream(_VOICE_DIR + String(voice_name))
	if stream == null:
		return
	duck(1.2)
	_voice_player.stream = stream
	_voice_player.play()


func _load_stream(base_path: String) -> AudioStream:
	if _cache.has(base_path):
		return _cache[base_path]
	var found: AudioStream = null
	for extension: String in ["ogg", "wav", "mp3"]:
		var path: String = "%s.%s" % [base_path, extension]
		if ResourceLoader.exists(path):
			found = load(path) as AudioStream
			break
	_cache[base_path] = found
	return found
