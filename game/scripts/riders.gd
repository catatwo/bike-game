class_name Riders
extends RefCounted
## Everyone who rides this bike, in the order they were added. Each has a
## folder, user://riders/<id>, named by a number so a rename moves nothing.
## There is always at least one rider: "Rider 1" to begin with.

const MAX := 8
const NAME_MAX := 20

var root := "user://riders"
var list: Array[Rider] = []


## Reads every rider. The first time, the settings and rides kept from before
## there were riders become Rider 1's, so nothing is lost.
func load_all(old_settings := Settings.PATH, old_rides := "user://rides") -> void:
	if not DirAccess.dir_exists_absolute(root):
		_adopt_old_data(old_settings, old_rides)
	list.clear()
	for d in DirAccess.get_directories_at(root):
		if d.is_valid_int():
			var r := _rider(d)
			if r.load_file():
				list.append(r)
	list.sort_custom(func(a: Rider, b: Rider) -> bool: return int(a.id) < int(b.id))
	if list.is_empty():
		list.append(_create("Rider 1"))


func _adopt_old_data(old_settings: String, old_rides: String) -> void:
	var r := _create("Rider 1")
	var cf := ConfigFile.new()
	if cf.load(old_settings) == OK:
		r.apply({"weight": cf.get_value("rider", "weight", r.weight),
			"ftp": cf.get_value("rider", "ftp", r.ftp),
			"hill_feel": cf.get_value("rider", "hill_feel", r.hill_feel),
			"color": cf.get_value("rider", "color", r.color),
			"camera": cf.get_value("screen", "camera", r.camera),
			"last_choice": cf.get_value("menu", "last_choice", r.last_choice)})
		r.save_file()
	if DirAccess.dir_exists_absolute(old_rides):
		var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(old_rides),
				ProjectSettings.globalize_path(r.rides_dir()))
		if err != OK:
			push_warning("couldn't move the old rides to Rider 1: %s" % error_string(err))


func _rider(id: String) -> Rider:
	var r := Rider.new()
	r.id = id
	r.dir = root.path_join(id)
	return r


func _create(name: String) -> Rider:
	var next := 1
	if DirAccess.dir_exists_absolute(root):
		for d in DirAccess.get_directories_at(root):
			if d.is_valid_int():
				next = maxi(next, int(d) + 1)
	var r := _rider(str(next))
	r.name = name
	r.save_file()
	return r


func find(id: String) -> Rider:
	for r in list:
		if r.id == id:
			return r
	return null


## "  Big   Ben " -> "Big Ben", at most NAME_MAX letters.
static func clean_name(text: String) -> String:
	var words := PackedStringArray()
	for w in text.strip_edges().split(" ", false):
		words.append(w.strip_edges())
	return " ".join(words).substr(0, NAME_MAX).strip_edges()


## Why a name can't be used, or "" when it can. `except` is the rider being
## renamed, who may keep their own name.
func name_problem(text: String, except: Rider = null) -> String:
	var n := clean_name(text)
	if n == "":
		return "Type a name first."
	for r in list:
		if r != except and r.name.to_lower() == n.to_lower():
			return "%s is already here. Pick another name." % r.name
	return ""


func add(text: String) -> Rider:
	var r := _create(clean_name(text))
	list.append(r)
	return r


func rename(r: Rider, text: String) -> void:
	r.name = clean_name(text)
	r.save_file()


## Deletes a rider with all their rides. The last rider stays.
func remove(r: Rider) -> bool:
	if list.size() <= 1 or not list.has(r):
		return false
	_remove_tree(ProjectSettings.globalize_path(r.dir))
	list.erase(r)
	return true


static func _remove_tree(path: String) -> void:
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)
