class_name Sound
extends Node
## Music, the rush of wind and tyres that follows your speed, and blips and
## chimes for the menus, intervals and finishing. The sounds are made by
## tools/make_sounds.py into res://sounds; any that are missing are skipped,
## so the game still runs without them.

const EFFECTS := ["move", "select", "back", "beep", "go", "km", "finish", "connect", "pb",
	"levelup"]

var _fx := {}
var _music := AudioStreamPlayer.new()
var _wind := AudioStreamPlayer.new()
var _tyres := AudioStreamPlayer.new()
var _track := ""
var _music_volume := 0.5
var _effects_volume := 0.8
var _speed := 0.0  # m/s, smoothed


func _ready() -> void:
	for n in EFFECTS:
		var stream := _load(n, false)
		if stream:
			var p := AudioStreamPlayer.new()
			p.stream = stream
			p.max_polyphony = 3
			add_child(p)
			_fx[n] = p
	add_child(_music)
	for p in [_wind, _tyres]:
		p.volume_db = -80.0
		add_child(p)
	_wind.stream = _load("wind", true)
	_tyres.stream = _load("tyres", true)
	if _wind.stream:
		_wind.play()
	if _tyres.stream:
		_tyres.play()


func _load(name: String, loop: bool) -> AudioStream:
	var path := "res://sounds/%s.wav" % name
	if not ResourceLoader.exists(path):
		return null
	var stream = load(path)
	if loop and stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


## Everything off or on (the M key), without touching the volume settings.
func set_muted(on: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), on)


func apply_volumes(music: float, effects: float) -> void:
	_music_volume = music
	_effects_volume = effects
	_music.volume_db = linear_to_db(maxf(music * 0.7, 0.0001))


func play(name: String) -> void:
	if _fx.has(name) and _effects_volume > 0.0:
		var p: AudioStreamPlayer = _fx[name]
		p.volume_db = linear_to_db(_effects_volume)
		p.play()


## "menu", "ride", or "" for silence.
func music(track: String) -> void:
	if track == _track:
		return
	_track = track
	_music.stop()
	if track == "":
		return
	_music.stream = _load("music_" + track, true)
	if _music.stream:
		_music.play()


func set_speed(speed_mps: float) -> void:
	_speed = speed_mps


func _process(delta: float) -> void:
	# Wind grows with the square of speed, like the real thing; the tyres hum
	# along more evenly.
	var v := clampf(_speed / 15.0, 0.0, 1.2)
	var wind := v * v * 0.55 * _effects_volume
	var tyres := clampf(_speed / 6.0, 0.0, 1.0) * 0.3 * _effects_volume
	_wind.volume_db = lerpf(_wind.volume_db, linear_to_db(maxf(wind, 0.0001)), 1.0 - exp(-4.0 * delta))
	_tyres.volume_db = lerpf(_tyres.volume_db, linear_to_db(maxf(tyres, 0.0001)), 1.0 - exp(-4.0 * delta))
	_wind.pitch_scale = 0.8 + 0.5 * minf(v, 1.0)
	_tyres.pitch_scale = 0.7 + 0.6 * minf(v, 1.0)


## Before quitting: sounds still playing when the engine shuts down are
## reported as leaks, and stopping one only takes effect a frame later.
func stop_all() -> void:
	for p in [_music, _wind, _tyres] + _fx.values():
		p.stop()
		p.stream = null
