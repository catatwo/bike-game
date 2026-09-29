class_name History
extends RefCounted
## Finished rides, kept in user://rides: an index of summaries, plus each
## ride's once-a-second samples (for ghosts).

var dir := "user://rides"


func _index_path() -> String:
	return dir.path_join("index.json")


func rides() -> Array:
	if not FileAccess.file_exists(_index_path()):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(_index_path()))
	return data if data is Array else []


## Saves a ride and returns its summary with the file name added, its XP
## (Levels.for_ride) when given, and anything in `extra` (an FTP test's
## result, whose ghost was raced). Rides shorter than a minute aren't worth
## keeping.
func save(ride: Ride, xp := {}, extra := {}) -> Dictionary:
	var summary := ride.summary()
	summary.merge(extra)
	if ride.elapsed < 60.0:
		return summary
	if not xp.is_empty():
		summary["xp"] = xp["total"]
		summary["xp_parts"] = xp["parts"]
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = summary["date"].replace(":", "").replace(" ", "_").replace("-", "")
	var name := "%s_%s" % [stamp, summary["id"]]
	summary["file"] = name
	var f := FileAccess.open(dir.path_join(name + ".json"), FileAccess.WRITE)
	if f == null:
		push_warning("couldn't save the ride: %s" % error_string(FileAccess.get_open_error()))
		return summary
	f.store_string(JSON.stringify({"summary": summary, "samples": ride.samples}))
	f.close()
	var all := rides()
	all.append(summary)
	var idx := FileAccess.open(_index_path(), FileAccess.WRITE)
	if idx:
		idx.store_string(JSON.stringify(all, " "))
		idx.close()
	return summary


## The fastest finished ride of a route, or {}.
func best(route_id: String) -> Dictionary:
	var found := {}
	for s in rides():
		if s.get("kind") == "route" and s.get("id") == route_id and s.get("completed"):
			if found.is_empty() or s["time"] < found["time"]:
				found = s
	return found


## The fastest time on a segment in any saved ride, or INF.
func segment_best(id: String) -> float:
	var best := INF
	for s in rides():
		for seg in s.get("segments", []):
			if seg.get("id") == id:
				best = minf(best, float(seg["time"]))
	return best


## The best average power over each span in any saved ride: span -> W.
func records() -> Dictionary:
	var out := {}
	for s in rides():
		var powers: Dictionary = s.get("powers", {})
		for k in powers:
			out[int(k)] = maxf(out.get(int(k), 0.0), float(powers[k]))
	return out


## Distance at each second of the best ride of a route, for its ghost.
func ghost(route_id: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var b := best(route_id)
	if b.is_empty() or not b.has("file"):
		return out
	var path := dir.path_join(b["file"] + ".json")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		for s in data.get("samples", []):
			out.append(float(s[1]))
	return out
