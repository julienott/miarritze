class_name BkFrisson
extends Node
## Ressenti du chassé local (`idee_frisson`, SPEC-GORDEKA §3.4) : battement de cœur, vignettage et
## vibration qui montent quand le chasseur approche, « Il fouille à côté ! » quand il fouille une
## cachette voisine. Seulement pour le joueur local chassé (jamais le chasseur ni un fantôme) ; ne
## dépend que de la distance au chasseur, sans direction : ça ne révèle rien que le chassé ne voie
## déjà (il voit toute la carte). Aucun effet sur les règles.

## Battements par minute : calme (au bord de frisson_portee) → chasseur tout près.
const BPM_MIN: float = 70.0
const BPM_MAX: float = 160.0
## Volume du battement (dB) : à peine audible → fort.
const DB_MIN: float = -22.0
const DB_MAX: float = -3.0
## Intensité à partir de laquelle on vibre à chaque battement (manette, téléphone).
const VIBRE_DES: float = 0.6
const VIBRE_MS: int = 45
## Intensité minimale quand sa propre jauge de repérage monte (il se sait vu).
const VU_MIN: float = 0.7

var game: BkGame
## Intensité 0 → 1 (vignettage, battement) et enveloppe du dernier battement (1 → 0, pulsation).
var level: float = 0.0
var beat: float = 0.0
## « Il fouille à côté ! » : secondes restantes d'affichage.
var search_near: float = 0.0
var _player: AudioStreamPlayer
var _chase_player: AudioStreamPlayer
var _next_beat: float = 0.0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.stream = heartbeat_stream()
	add_child(_player)
	_chase_player = AudioStreamPlayer.new()
	_chase_player.stream = chase_stream()
	_chase_player.volume_db = -6.0
	add_child(_chase_player)


## Intensité pour un chassé à `d` px du chasseur, `gauge` = sa jauge de repérage : 0 au-delà de
## frisson_portee cases, 1 au contact (petit cercle de vue), au moins VU_MIN s'il est en train d'être vu.
static func intensity(d: float, gauge: float) -> float:
	var near: float = BkRules.px("near_radius")
	var far: float = maxf(BkRules.px("frisson_portee"), near + 1.0)
	var k: float = clampf(1.0 - (d - near) / (far - near), 0.0, 1.0)
	if gauge > 0.0:
		k = maxf(k, VU_MIN + (1.0 - VU_MIN) * clampf(gauge, 0.0, 1.0))
	return k * k * (3.0 - 2.0 * k)          # montée douce (smoothstep)


func _process(dt: float) -> void:
	var me: BkActor = game.local if game else null
	var on: bool = me != null and BkRules.on("idee_frisson") and game.visite == "" \
		and game.phase == BkGame.Phase.HUNT and me != game.hunter and me.role == BkActor.Role.HIDER
	var want: float = intensity(me.position.distance_to(game.hunter.position), me.gauge) if on else 0.0
	level = move_toward(level, want, dt * 2.5)
	beat = maxf(0.0, beat - dt * 4.0)
	var h: BkActor = game.hunter if game else null
	if on and h.search_left > 0.0 and h.position.distance_to(me.position) < BkRules.px("frisson_fouille_portee"):
		search_near = 1.2
	search_near = maxf(0.0, search_near - dt) if on else 0.0
	if level < 0.03:
		_next_beat = 0.0
		return
	_next_beat -= dt
	if _next_beat <= 0.0:
		_next_beat = 60.0 / lerpf(BPM_MIN, BPM_MAX, level)
		_beat()


func _beat() -> void:
	beat = 1.0
	_player.volume_db = lerpf(DB_MIN, DB_MAX, level)
	_player.play()
	if level < VIBRE_DES or game.local.is_bot:
		return
	var reglages: Node = get_node_or_null("/root/Settings")
	if reglages != null and not reglages.vibrations:
		return                          # vibration coupée dans les Réglages
	var strength: float = clampf((level - VIBRE_DES) / (1.0 - VIBRE_DES), 0.2, 1.0)
	for pad: int in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, strength * 0.6, strength, VIBRE_MS / 1000.0)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.vibrate && navigator.vibrate(%d)" % VIBRE_MS, true)
	elif OS.has_feature("mobile"):
		Input.vibrate_handheld(VIBRE_MS, strength)


## Départ d'une poursuite (idee_poursuite) : « fiouu ! » entendu de tous.
func play_chase() -> void:
	_chase_player.play()


## « Fiouu » de départ de poursuite : glissando montant avec un petit vibrato, 0,35 s.
static func chase_stream() -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(rate * 0.35)
	var data: PackedByteArray = PackedByteArray()
	data.resize(n * 2)
	var ph: float = 0.0
	for i: int in n:
		var t: float = float(i) / rate
		var f: float = 300.0 + 900.0 * t / 0.35 + 30.0 * sin(TAU * 18.0 * t)
		ph += TAU * f / rate
		var env: float = minf(t / 0.02, 1.0) * clampf((0.35 - t) / 0.1, 0.0, 1.0)
		data.encode_s16(i * 2, int(0.5 * env * (sin(ph) + 0.3 * sin(ph * 2.0)) * 30000.0 / 1.3))
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s


## « Poum-poum » de cœur (deux coups sourds), généré une fois : PCM 16 bits mono à 22 050 Hz.
static func heartbeat_stream() -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(rate * 0.42)
	var data: PackedByteArray = PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		var t: float = float(i) / rate
		var v: float = _thump(t, 0.0, 1.0) + _thump(t, 0.17, 0.7)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s


## Un coup sourd qui commence à `t0` s : sinus grave qui descend, attaque brève, extinction rapide.
static func _thump(t: float, t0: float, amp: float) -> float:
	var u: float = t - t0
	if u < 0.0:
		return 0.0
	var env: float = minf(u / 0.008, 1.0) * exp(-u * 22.0)
	return amp * env * sin(TAU * (62.0 - 20.0 * minf(u / 0.12, 1.0)) * u)
