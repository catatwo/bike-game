class_name Rider
extends RefCounted
## One person who rides the bike: their name and settings, in
## user://riders/<id>/rider.cfg, and their rides, in user://riders/<id>/rides.
## Settings everyone shares (sound, graphics) are in Settings.

const CAMERA_NAMES := ["Behind", "Side", "Rider's eyes"]
const COLORS := [["Magenta", Color("ff3bd4")], ["White", Color("e8f4ff")],
	["Cyan", Color("00e5ff")], ["Lime", Color("8aff3d")], ["Red", Color("ff3b4f")],
	["Orange", Color("ff8a2b")], ["Violet", Color("a06bff")]]

var id := ""
var dir := ""  # user://riders/<id>
var name := ""
var weight := 80.0  # kg
var ftp := 150.0  # W: the power you could hold for about an hour
var hill_feel := 1.0  # how much of each hill the bike makes you feel
var color := 0  # index into COLORS
var camera := 0
var last_choice := ""  # the menu entry picked last, offered first next time


func _cfg_path() -> String:
	return dir.path_join("rider.cfg")


func rides_dir() -> String:
	return dir.path_join("rides")


func rgb() -> Color:
	return COLORS[color][1]


func load_file() -> bool:
	var cf := ConfigFile.new()
	if cf.load(_cfg_path()) != OK:
		return false
	name = str(cf.get_value("rider", "name", name))
	apply({"weight": cf.get_value("rider", "weight", weight),
		"ftp": cf.get_value("rider", "ftp", ftp),
		"hill_feel": cf.get_value("rider", "hill_feel", hill_feel),
		"color": cf.get_value("rider", "color", color),
		"camera": cf.get_value("rider", "camera", camera),
		"last_choice": cf.get_value("rider", "last_choice", last_choice)})
	return true


## Takes values from anywhere (a file, the old settings file), within limits.
func apply(v: Dictionary) -> void:
	weight = clampf(float(v.get("weight", weight)), 40.0, 160.0)
	ftp = clampf(float(v.get("ftp", ftp)), 50.0, 500.0)
	hill_feel = clampf(float(v.get("hill_feel", hill_feel)), 0.25, 1.5)
	color = clampi(int(v.get("color", color)), 0, COLORS.size() - 1)
	camera = clampi(int(v.get("camera", camera)), 0, CAMERA_NAMES.size() - 1)
	last_choice = str(v.get("last_choice", last_choice))


func save_file() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var cf := ConfigFile.new()
	cf.set_value("rider", "name", name)
	cf.set_value("rider", "weight", weight)
	cf.set_value("rider", "ftp", ftp)
	cf.set_value("rider", "hill_feel", hill_feel)
	cf.set_value("rider", "color", color)
	cf.set_value("rider", "camera", camera)
	cf.set_value("rider", "last_choice", last_choice)
	var err := cf.save(_cfg_path())
	if err != OK:
		push_warning("couldn't save %s's settings: %s" % [name, error_string(err)])
