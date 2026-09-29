class_name Settings
extends RefCounted
## Settings everyone on this bike shares, kept in user://settings.cfg: sound,
## graphics, and who rode last. Each rider's own settings are in Rider.

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High"]

var music := 0.5
var effects := 0.8
var quality := 1  # 0 low, 1 medium, 2 high
var show_fps := false
var muted := false  # M, anywhere
var pedal_start := true  # pedalling in the menu starts a free ride
var last_rider := ""  # the id of whoever rode last: offered first


func load_file(path := PATH) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	music = clampf(cf.get_value("sound", "music", music), 0.0, 1.0)
	effects = clampf(cf.get_value("sound", "effects", effects), 0.0, 1.0)
	muted = cf.get_value("sound", "muted", muted)
	pedal_start = cf.get_value("menu", "pedal_start", pedal_start)
	quality = clampi(cf.get_value("screen", "quality", quality), 0, 2)
	show_fps = cf.get_value("screen", "show_fps", show_fps)
	last_rider = str(cf.get_value("riders", "last", last_rider))


func save_file(path := PATH) -> void:
	var cf := ConfigFile.new()
	cf.set_value("sound", "music", music)
	cf.set_value("sound", "effects", effects)
	cf.set_value("sound", "muted", muted)
	cf.set_value("menu", "pedal_start", pedal_start)
	cf.set_value("screen", "quality", quality)
	cf.set_value("screen", "show_fps", show_fps)
	cf.set_value("riders", "last", last_rider)
	var err := cf.save(path)
	if err != OK:
		push_warning("couldn't save settings: %s" % error_string(err))
