class_name Island
extends RefCounted
## The one world every ride happens in: a stretch of land whose roads meet
## at places. Routes, free rides and workouts are paths along these roads
## (path()). Where the places are and which roads join them is laid out by
## hand below; the bends, the rolling hills and the land between the roads
## are generated from that, the same every time.
##
## The land's height is worked out once for the whole island (bake()), which
## takes a while, so the game's image does it when it's built
## (tools/bake_island.gd) and saves it in BAKED. Without that file the game
## works it out when it starts.

const STEP := 5.0  # m between road points; Route.STEP
const ROAD_HALF := 3.0
const FLAT := 9.0  # the land is level with the road out to here...
const SHOULDER := 20.0  # ...then rises a little by here...
const BLEND := 110.0  # ...and has become the open land by here
const CELL := 8.0  # m between baked heights
const FAR_CELL := 128.0  # the rough shape of the land between the roads
const MARGIN := 1600.0  # land beyond the outermost roads, inside the baked area
const OUTSIDE := 40.0  # the land's height at the baked area's edge, and beyond it
const HILLS_FROM_EDGE := 500.0  # the hills die away over this far in from the edge
const HASH := 60.0  # m: cells of the lookup of road segments
const PLAZA_MIN := 12.0  # m: the radius of the round plaza at every place...
const PLAZA_MAX := 24.0  # ...bigger where roads leave close together
const BAKED := "res://world/island.bin"
const FILE_TAG := "BIKEISL1"

## What each part of the island looks like: its colours (Catalog.themes())
## and how high the land between the roads rises, m.
const AREAS := {
	"city": {"theme": "city", "hills": 4.0},
	"plains": {"theme": "cyan", "hills": 9.0},
	"valley": {"theme": "ice", "hills": 14.0},
	"hills": {"theme": "green", "hills": 30.0},
	"ridge": {"theme": "magenta", "hills": 34.0},
	"mountain": {"theme": "violet", "hills": 60.0},
	"quarry": {"theme": "amber", "hills": 24.0},
}

## x east, z south (north is -z), m; elevations in m.
const PLACES := {
	"city": {"name": "Neon City", "at": Vector2(0, 0), "elev": 12.0, "area": "city"},
	"west-gate": {"name": "West Gate", "at": Vector2(-2700, 700), "elev": 3.0, "area": "plains"},
	"valley-south": {"name": "Valley South", "at": Vector2(200, -2900), "elev": 22.0, "area": "valley"},
	"valley-north": {"name": "Valley North", "at": Vector2(500, -6100), "elev": 24.0, "area": "valley"},
	"hilltop": {"name": "Hilltop", "at": Vector2(3700, -1900), "elev": 58.0, "area": "hills"},
	"east-point": {"name": "East Point", "at": Vector2(6500, 300), "elev": 6.0, "area": "plains"},
	"foot": {"name": "Mountain Foot", "at": Vector2(2300, 2900), "elev": 42.0, "area": "mountain"},
	"summit": {"name": "Summit", "at": Vector2(4000, 5600), "elev": 330.0, "area": "mountain"},
	"quarry": {"name": "Quarry", "at": Vector2(-2100, 3900), "elev": 24.0, "area": "quarry"},
}

## from/to: places; via: the points the road passes, [x, z]; roll: size of
## its rolling hills as a gradient, over roll_scale m; wiggle: how far its
## bends wander, m; walls: [where (0-1 along it), length m, gradient], a
## steep stretch, counted from `from` to `to`.
const ROADS := [
	{"id": "city-loop", "name": "City Loop", "from": "city", "to": "city", "area": "city",
		"via": [[600, -300], [1200, -200], [1300, 400], [600, 300]],
		"roll": 0.004, "roll_scale": 500.0, "wiggle": 6.0},
	{"id": "gate-road", "name": "Gate Road", "from": "city", "to": "west-gate", "area": "plains",
		"via": [[-900, 350], [-1800, 350]], "roll": 0.006, "roll_scale": 700.0, "wiggle": 25.0},
	{"id": "valley-road", "name": "Valley Road", "from": "city", "to": "valley-south", "area": "valley",
		"via": [[-200, -1000], [300, -1900]], "roll": 0.012, "roll_scale": 900.0, "wiggle": 30.0},
	{"id": "west-rim", "name": "West Rim", "from": "valley-south", "to": "valley-north", "area": "valley",
		"via": [[-700, -3700], [-900, -4800], [-500, -5700]], "roll": 0.012, "roll_scale": 800.0,
		"wiggle": 30.0},
	{"id": "east-rim", "name": "East Rim", "from": "valley-north", "to": "valley-south", "area": "valley",
		"via": [[1500, -5500], [1800, -4400], [1300, -3400]], "roll": 0.012, "roll_scale": 900.0,
		"wiggle": 30.0},
	{"id": "hill-road", "name": "Hill Road", "from": "city", "to": "hilltop", "area": "hills",
		"via": [[300, -900], [1500, -1300], [2600, -1500]], "roll": 0.025, "roll_scale": 700.0,
		"wiggle": 30.0},
	{"id": "ridge", "name": "The Ridge", "from": "hilltop", "to": "east-point", "area": "ridge",
		"via": [[4700, -1700], [5500, -900]], "roll": 0.035, "roll_scale": 550.0, "wiggle": 25.0,
		"walls": [[0.5, 700.0, -0.06]]},
	{"id": "east-road", "name": "East Road", "from": "east-point", "to": "foot", "area": "plains",
		"via": [[5600, 1900], [4000, 2700]], "roll": 0.02, "roll_scale": 900.0, "wiggle": 35.0},
	{"id": "south-road", "name": "South Road", "from": "city", "to": "foot", "area": "mountain",
		"via": [[-100, 1300], [1200, 2400]], "roll": 0.012, "roll_scale": 900.0, "wiggle": 30.0},
	{"id": "summit-road", "name": "Summit Road", "from": "foot", "to": "summit", "area": "mountain",
		"via": [[2000, 3700], [2900, 3900], [2500, 4500], [3500, 4700], [3200, 5300]],
		"roll": 0.006, "roll_scale": 600.0, "wiggle": 0.0},
	{"id": "summit-east", "name": "The Long Descent", "from": "summit", "to": "east-point",
		"area": "mountain", "via": [[5300, 5100], [6300, 4000], [6800, 2200]], "roll": 0.008,
		"roll_scale": 700.0, "wiggle": 20.0},
	{"id": "west-road", "name": "West Road", "from": "west-gate", "to": "quarry", "area": "plains",
		"via": [[-3300, 1700], [-3000, 3100]], "roll": 0.01, "roll_scale": 800.0, "wiggle": 30.0,
		"walls": [[0.55, 600.0, 0.07]]},
	{"id": "quarry-road", "name": "Quarry Road", "from": "quarry", "to": "foot", "area": "quarry",
		"via": [[-1200, 4400], [100, 4000], [1300, 3300]], "roll": 0.012, "roll_scale": 800.0,
		"wiggle": 25.0, "walls": [[0.3, 850.0, 0.075]]},
	{"id": "valley-hill", "name": "Valley Hill", "from": "hilltop", "to": "valley-south", "area": "hills",
		"via": [[2600, -2600], [1300, -2900]], "roll": 0.02, "roll_scale": 700.0, "wiggle": 30.0},
]

## Timed stretches, each on one road in its own direction, from `from` to
## `to` along it (0 is its start, 1 its end). Any ride along that road that
## way is timed over them.
const SEGMENTS := [
	{"id": "switchbacks", "name": "The Switchbacks", "road": "summit-road", "from": 0.06, "to": 1.0},
	{"id": "quarry-wall", "name": "Quarry Wall", "road": "quarry-road", "from": 0.28, "to": 0.5},
	{"id": "west-wall", "name": "West Wall", "road": "west-road", "from": 0.52, "to": 0.72},
	{"id": "hilltop-drag", "name": "Hilltop Drag", "road": "hill-road", "from": 0.35, "to": 1.0},
	{"id": "valley-sprint", "name": "Valley Sprint", "road": "west-rim", "from": 0.1, "to": 0.5},
]


class Road:
	var id := ""
	var name := ""
	var from := ""
	var to := ""
	var area := ""
	var points := PackedVector3Array()  # every STEP m (very nearly), from -> to

	## Along the road, in STEP units: (points - 1) * STEP.
	func length() -> float:
		return (points.size() - 1) * STEP


var roads := {}  # id -> Road
var road_ids: Array[String] = []
## The land: heights[z * width + x] at world (origin.x + x * CELL,
## origin.y + z * CELL); road_distance likewise, capped at BLEND.
var heights := PackedFloat32Array()
var road_distance := PackedFloat32Array()
var origin := Vector2.ZERO
var width := 0
var depth := 0
var _hash := {}  # Vector2i -> [[road id, segment index], ...]
var _plazas := {}  # place id -> radius, m

static var _main: Island


## The island, built once. Loads the baked land, or works it out.
static func main() -> Island:
	if _main == null:
		_main = Island.new()
		_main.build_roads()
		if not _main.load_baked(BAKED):
			push_warning("no baked island land at %s: working it out now (slow)" % BAKED)
			_main.bake()
	return _main


# --- the roads -----------------------------------------------------------

func build_roads() -> void:
	roads.clear()
	road_ids.clear()
	_hash.clear()
	for spec in ROADS:
		var r := _make_road(spec)
		roads[r.id] = r
		road_ids.append(r.id)
		for i in r.points.size() - 1:
			var key := _cell(Vector2(r.points[i].x, r.points[i].z))
			if not _hash.has(key):
				_hash[key] = []
			_hash[key].append([r.id, i])


func _make_road(spec: Dictionary) -> Road:
	var r := Road.new()
	r.id = spec["id"]
	r.name = spec.get("name", r.id)
	r.from = spec["from"]
	r.to = spec["to"]
	r.area = spec["area"]
	var ctrl: Array[Vector2] = [PLACES[r.from]["at"]]
	for v in spec.get("via", []):
		ctrl.append(Vector2(v[0], v[1]))
	ctrl.append(PLACES[r.to]["at"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(r.id)
	var line := _spline(ctrl, r.from == r.to)
	line = _wiggle(line, float(spec.get("wiggle", 20.0)), rng)
	line = _resample(line)
	var elev := _elevations(line.size(), spec, PLACES[r.from]["elev"], PLACES[r.to]["elev"], rng)
	r.points.resize(line.size())
	for i in line.size():
		r.points[i] = Vector3(line[i].x, elev[i], line[i].y)
	return r


## A smooth line through the points (centripetal Catmull-Rom), about a
## metre between samples. A loop comes back to where it started.
static func _spline(ctrl: Array[Vector2], closed: bool) -> PackedVector2Array:
	var pts := ctrl.duplicate()
	if closed:
		pts.pop_back()
	var n := pts.size()
	var out := PackedVector2Array()
	for i in (n if closed else n - 1):
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p0: Vector2
		var p3: Vector2
		if closed:
			p0 = pts[(i - 1 + n) % n]
			p3 = pts[(i + 2) % n]
		else:
			p0 = pts[i - 1] if i > 0 else 2.0 * p1 - p2
			p3 = pts[i + 2] if i + 2 < n else 2.0 * p2 - p1
		var steps := maxi(4, int(p1.distance_to(p2)))
		for k in steps:
			out.append(_catmull(p0, p1, p2, p3, float(k) / steps))
	out.append(pts[0] if closed else pts[n - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var t1 := sqrt(maxf(p0.distance_to(p1), 0.01))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 0.01))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 0.01))
	var t := lerpf(t1, t2, u)
	var a1 := p0 * (t1 - t) / t1 + p1 * t / t1
	var a2 := p1 * (t2 - t) / (t2 - t1) + p2 * (t - t1) / (t2 - t1)
	var a3 := p2 * (t3 - t) / (t3 - t2) + p3 * (t - t2) / (t3 - t2)
	var b1 := a1 * (t2 - t) / t2 + a2 * t / t2
	var b2 := a2 * (t3 - t) / (t3 - t1) + a3 * (t - t1) / (t3 - t1)
	return b1 * (t2 - t) / (t2 - t1) + b2 * (t - t1) / (t2 - t1)


static func _cumulative(pts: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	return cum


## Bends that wander up to `amp` metres either side, but not near the ends,
## so roads still meet exactly at their places.
static func _wiggle(pts: PackedVector2Array, amp: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	if amp <= 0.0:
		return pts
	var cum := _cumulative(pts)
	var total: float = cum[cum.size() - 1]
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var s: float = cum[i]
		var x := s / 650.0 * TAU
		var w := smoothstep(0.0, 150.0, s) * smoothstep(0.0, 150.0, total - s)
		var off := amp * w * (0.6 * sin(x + ph[0]) + 0.3 * sin(2.3 * x + ph[1]) + 0.1 * sin(5.1 * x + ph[2]))
		out[i] = pts[i] + Vector2(-t.y, t.x) * off
	return out


## Evenly spaced points, as near STEP apart as a whole number of them allows.
static func _resample(pts: PackedVector2Array) -> PackedVector2Array:
	var cum := _cumulative(pts)
	var total: float = cum[cum.size() - 1]
	var n := maxi(1, roundi(total / STEP))
	var out := PackedVector2Array()
	var j := 0
	for i in n + 1:
		var s := total * i / n
		while j < pts.size() - 2 and cum[j + 1] < s:
			j += 1
		var k := (s - cum[j]) / maxf(cum[j + 1] - cum[j], 1e-6)
		out.append(pts[j].lerp(pts[j + 1], clampf(k, 0.0, 1.0)))
	return out


## Heights along a road: a steady climb or descent between its places, its
## walls, and rolling hills that leave the ends where they are; smoothed.
static func _elevations(n: int, spec: Dictionary, e0: float, e1: float,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var total := (n - 1) * STEP
	var walls: Array = spec.get("walls", [])
	var wall_rise := 0.0
	for w in walls:
		wall_rise += float(w[1]) * float(w[2])
	var roll := float(spec.get("roll", 0.01))
	var lam := float(spec.get("roll_scale", 800.0))
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var rolled := PackedFloat32Array()
	rolled.resize(n)
	var acc := 0.0
	for i in n:
		rolled[i] = acc
		var s := i * STEP
		var x := s / lam * TAU
		var g := roll * (0.6 * sin(x + ph[0]) + 0.3 * sin(2.31 * x + ph[1]) + 0.1 * sin(5.17 * x + ph[2]))
		acc += g * smoothstep(0.0, 200.0, s) * smoothstep(0.0, 200.0, total - s) * STEP
	var drift: float = rolled[n - 1]
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := i * STEP
		var t := s / total
		var wall := 0.0
		for w in walls:
			wall += float(w[2]) * clampf(s - float(w[0]) * total, 0.0, float(w[1]))
		out[i] = e0 + (e1 - e0 - wall_rise) * clampf((t - 0.03) / 0.94, 0.0, 1.0) \
				+ wall + rolled[i] - drift * t
	return _smooth(out, 6)


static func _smooth(v: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n := v.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var sum := 0.0
		for k in range(i - r, i + r + 1):
			sum += v[clampi(k, 0, n - 1)]
		out[i] = sum / (2 * r + 1)
	out[0] = v[0]
	out[n - 1] = v[n - 1]
	return out


# --- paths -----------------------------------------------------------------

## The steepest gradient anywhere on a road, up or down (0.07 is 7%).
func steepest(id: String) -> float:
	var pts: PackedVector3Array = roads[id].points
	var worst := 0.0
	for i in pts.size() - 1:
		worst = maxf(worst, absf(pts[i + 1].y - pts[i].y) / STEP)
	return worst


## The roads touching a place, as legs leaving it: "road" or "-road".
func legs_from(place: String) -> Array[String]:
	var out: Array[String] = []
	for id in road_ids:
		var r: Road = roads[id]
		if r.from == place:
			out.append(id)
		if r.to == place and r.from != place:
			out.append("-" + id)
	return out


static func leg_road(leg: String) -> String:
	return leg.trim_prefix("-")


func leg_start(leg: String) -> String:
	var r: Road = roads[leg_road(leg)]
	return r.to if leg.begins_with("-") else r.from


func leg_end(leg: String) -> String:
	var r: Road = roads[leg_road(leg)]
	return r.from if leg.begins_with("-") else r.to


## The roads of `legs` end to end: {"points", "legs": [{"s", "turn_s", "leg",
## "road", "area"}], "end"}; "s" is where the leg's own road begins, "turn_s"
## where the curve across the plaza before it does. Each leg must start where the one before ended. Where
## one road hands over to the next, the way curves across the place's plaza
## rather than turning on a point.
func path(legs: Array) -> Dictionary:
	var pts := PackedVector3Array()
	var starts := []  # the index where each leg's own road begins
	var curves := []  # ...and where the curve across the plaza before it begins
	var out := []
	var at := ""
	for n in legs.size():
		var leg: String = legs[n]
		assert(roads.has(leg_road(leg)), "no road %s" % leg)
		assert(at == "" or leg_start(leg) == at, "%s doesn't start at %s" % [leg, at])
		var r: Road = roads[leg_road(leg)]
		var rp := r.points
		if leg.begins_with("-"):
			rp = rp.duplicate()
			rp.reverse()
		var first := 0
		curves.append(0)
		if n > 0:
			# Leave the last road at the plaza's rim, curve across, and join
			# this one at the rim on its side.
			var centre: Vector2 = PLACES[at]["at"]
			var rim := plaza_radius(at) * 0.8
			while pts.size() > 2 and Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z).distance_to(centre) < rim:
				pts.remove_at(pts.size() - 1)
			while first < rp.size() - 2 and Vector2(rp[first].x, rp[first].z).distance_to(centre) < rim:
				first += 1
			curves[n] = pts.size() - 1
			pts.append_array(_across(pts[pts.size() - 1], pts[pts.size() - 2], rp[first], rp[first + 1]))
		starts.append(pts.size())
		out.append({"leg": leg, "road": r.id, "area": r.area})
		for i in range(first, rp.size()):
			pts.append(rp[i])
		at = leg_end(leg)
	# Evenly spaced again, exactly STEP apart from the start (a route's
	# distance is its index), so laying more road onto the end never moves
	# the points before it.
	var cum := PackedFloat64Array()
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + Vector2(pts[i].x, pts[i].z).distance_to(Vector2(pts[i - 1].x, pts[i - 1].z))
	for n in out.size():
		out[n]["s"] = 0.0 if n == 0 else cum[starts[n]]
		out[n]["turn_s"] = 0.0 if n == 0 else cum[curves[n]]
	var even := PackedVector3Array()
	var total: float = cum[cum.size() - 1]
	var count := int(total / STEP)
	var j := 0
	for k in count + 1:
		var d := k * STEP
		while j < pts.size() - 2 and cum[j + 1] < d:
			j += 1
		even.append(pts[j].lerp(pts[j + 1], clampf((d - cum[j]) / maxf(cum[j + 1] - cum[j], 1e-9), 0.0, 1.0)))
	return {"points": even, "legs": out, "end": at}


## The way across a plaza, from leaving one road at `a` (having come from
## `a_before`) to joining the next at `b` (going on to `b_after`), about a
## metre apart, not including a or b. A curve that leaves along the way in
## and arrives along the way out, shaped like a circle's arc; a turn right
## back swings wide round the plaza.
static func _across(a: Vector3, a_before: Vector3, b: Vector3, b_after: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var din := (a2 - Vector2(a_before.x, a_before.z)).normalized()
	var dout := (Vector2(b_after.x, b_after.z) - b2).normalized()
	var turn := absf(din.angle_to(dout))
	var chord := a2.distance_to(b2)
	var reach := chord / 3.0
	if turn > deg_to_rad(120.0):
		reach = chord * 0.9
	elif turn > 0.05:
		reach = chord * (4.0 / 3.0) * tan(turn / 4.0) / (2.0 * sin(turn / 2.0))
	var c1 := a2 + din * reach
	var c2 := b2 - dout * reach
	var n := maxi(2, ceili(chord * 1.5))
	for k in range(1, n):
		var t := float(k) / n
		var q := a2.bezier_interpolate(c1, c2, b2, t)
		out.append(Vector3(q.x, lerpf(a.y, b.y, t), q.y))
	return out


## The radius of a place's round plaza: big enough that the roads leaving it
## have come apart by its rim.
func plaza_radius(place: String) -> float:
	if _plazas.has(place):
		return _plazas[place]
	var centre: Vector2 = PLACES[place]["at"]
	var dirs: Array[Vector2] = []
	for id in road_ids:
		var pts: PackedVector3Array = roads[id].points
		var ends := []
		if roads[id].from == place:
			ends.append(pts[mini(6, pts.size() - 1)])
		if roads[id].to == place:
			ends.append(pts[maxi(pts.size() - 7, 0)])
		for e in ends:
			dirs.append((Vector2(e.x, e.z) - centre).normalized())
	var closest := PI
	for i in dirs.size():
		for j in range(i + 1, dirs.size()):
			closest = minf(closest, absf(dirs[i].angle_to(dirs[j])))
	var r := clampf((ROAD_HALF + 0.5) / sin(maxf(closest, 0.05) * 0.5) + 3.0, PLAZA_MIN, PLAZA_MAX)
	_plazas[place] = r
	return r


## A segment's start and end on the island.
func segment_ends(seg: Dictionary) -> Array[Vector3]:
	var pts: PackedVector3Array = roads[seg["road"]].points
	var n := pts.size() - 1
	return [pts[roundi(float(seg["from"]) * n)], pts[roundi(float(seg["to"]) * n)]]


## "The Ridge to East Point", or just "City Loop" for a road that comes back.
func leg_name(leg: String) -> String:
	var r: Road = roads[leg_road(leg)]
	if r.from == r.to:
		return r.name
	return "%s to %s" % [r.name, PLACES[leg_end(leg)]["name"]]


## A leg's own points, in the direction it's ridden.
func leg_points(leg: String) -> PackedVector3Array:
	var pts: PackedVector3Array = roads[leg_road(leg)].points
	if leg.begins_with("-"):
		pts = pts.duplicate()
		pts.reverse()
	return pts


## The ways on from `place` for someone who came along `came`, leftmost
## first: never one in `avoid`, and never straight back unless it's a dead
## end. Each is {"leg", "turn"} (the turn in degrees, negative to the left).
func turn_options(place: String, came: String, avoid: Array) -> Array:
	var arrive := leg_points(came)
	var a := arrive[arrive.size() - 1] - arrive[maxi(arrive.size() - 7, 0)]
	var heading := atan2(a.x, -a.z)
	var out := []
	for back in [false, true]:
		for leg in legs_from(place):
			var road := leg_road(leg)
			if road in avoid:
				continue
			var u_turn: bool = road == leg_road(came) and roads[road].from != roads[road].to
			if u_turn != back:
				continue
			var p := leg_points(leg)
			var d := p[mini(6, p.size() - 1)] - p[0]
			out.append({"leg": leg, "turn": rad_to_deg(angle_difference(heading, atan2(d.x, -d.z)))})
		if not out.is_empty():
			break
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["turn"] < y["turn"])
	return out


## The next leg from `place` for someone who came along `came` (or ""):
## never straight back if there's anything else, never one of `avoid`, and
## the straightest on unless `rng` is given, when it's a fair choice.
func next_leg(place: String, came: String, heading: float, avoid: Array,
		rng: RandomNumberGenerator = null) -> String:
	var options := []
	for leg in legs_from(place):
		if leg_road(leg) in avoid:
			continue
		if came != "" and leg_road(leg) == leg_road(came) and roads[leg_road(leg)].from != roads[leg_road(leg)].to:
			continue
		options.append(leg)
	if options.is_empty():  # a dead end: back the way we came
		for leg in legs_from(place):
			if not leg_road(leg) in avoid:
				options.append(leg)
	if options.is_empty():
		options = legs_from(place)
	if rng:
		return options[rng.randi_range(0, options.size() - 1)]
	var best: String = options[0]
	var best_turn := INF
	for leg in options:
		var p := path([leg])["points"] as PackedVector3Array
		var d := p[mini(8, p.size() - 1)] - p[0]
		var turn := absf(angle_difference(heading, atan2(d.x, -d.z)))
		if turn < best_turn:
			best_turn = turn
			best = leg
	return best


# --- the land ----------------------------------------------------------------

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / HASH), floori(p.y / HASH))


## The nearest road within `radius` of a point (x, z):
## {"dist", "y", "road", "index"}, or {}.
func nearest_road(p: Vector2, radius: float) -> Dictionary:
	var best := {}
	var bd := radius
	var c := _cell(p)
	var r := int(ceil(radius / HASH)) + 1
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := c + Vector2i(dx, dz)
			if not _hash.has(key):
				continue
			for seg in _hash[key]:
				var pts: PackedVector3Array = roads[seg[0]].points
				var a := pts[seg[1]]
				var b := pts[seg[1] + 1]
				var a2 := Vector2(a.x, a.z)
				var ab := Vector2(b.x, b.z) - a2
				var k := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var d := p.distance_to(a2 + ab * k)
				if d < bd:
					bd = d
					best = {"dist": d, "y": lerpf(a.y, b.y, k), "road": seg[0], "index": seg[1] + k}
	return best


## The area a point is in: the nearest place's.
func area_at(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for id in PLACES:
		var d: float = p.distance_squared_to(PLACES[id]["at"])
		if d < bd:
			bd = d
			best = PLACES[id]["area"]
	return best


func height_at(x: float, z: float) -> float:
	return _sample(heights, x, z, OUTSIDE)


func road_distance_at(x: float, z: float) -> float:
	return _sample(road_distance, x, z, BLEND)


func _sample(grid: PackedFloat32Array, x: float, z: float, outside: float) -> float:
	var fx := (x - origin.x) / CELL
	var fz := (z - origin.y) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= width - 1 or fz >= depth - 1:
		return outside
	var ix := int(fx)
	var iz := int(fz)
	var kx := fx - ix
	var kz := fz - iz
	var i := iz * width + ix
	return lerpf(lerpf(grid[i], grid[i + 1], kx), lerpf(grid[i + width], grid[i + width + 1], kx), kz)


## Works out the whole island's land: level with the roads beside them,
## rising into hills between them, and settling to OUTSIDE far beyond them.
func bake() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id in road_ids:
		for p in roads[id].points:
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
	lo -= Vector2.ONE * MARGIN
	hi += Vector2.ONE * MARGIN
	origin = (lo / CELL).floor() * CELL
	width = int(ceil((hi.x - origin.x) / CELL)) + 1
	depth = int(ceil((hi.y - origin.y) / CELL)) + 1
	var far := _far_field()
	var n := width * depth
	var near_d := PackedFloat32Array()
	near_d.resize(n)
	near_d.fill(BLEND)
	var exact_d := PackedFloat32Array()  # near a road: the exact distance to it
	exact_d.resize(n)
	exact_d.fill(INF)
	var near_y := PackedFloat32Array()
	near_y.resize(n)
	var wsum := PackedFloat32Array()
	wsum.resize(n)
	var ysum := PackedFloat32Array()
	ysum.resize(n)
	# Every road point within BLEND of a spot pulls it towards its height,
	# the nearer the more; every 2nd point is plenty for that.
	var rad := int(ceil(BLEND / CELL))
	for id in road_ids:
		var pts: PackedVector3Array = roads[id].points
		for i in range(0, pts.size(), 2):
			var p := pts[i]
			var cx := roundi((p.x - origin.x) / CELL)
			var cz := roundi((p.z - origin.y) / CELL)
			for gz in range(maxi(cz - rad, 0), mini(cz + rad, depth - 1) + 1):
				var dz := origin.y + gz * CELL - p.z
				var row := gz * width
				for gx in range(maxi(cx - rad, 0), mini(cx + rad, width - 1) + 1):
					var dx := origin.x + gx * CELL - p.x
					var d2 := dx * dx + dz * dz
					if d2 >= BLEND * BLEND:
						continue
					var w := 1.0 / (d2 + 100.0)
					wsum[row + gx] += w
					ysum[row + gx] += w * p.y
					near_d[row + gx] = minf(near_d[row + gx], sqrt(d2))
	# Near the roads, the exact distance to the nearest one, and its height
	# (further out, the distance to the nearest point is near enough).
	var fine := int(ceil((SHOULDER + CELL) / CELL))
	for id in road_ids:
		var pts: PackedVector3Array = roads[id].points
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var ab := b - a
			var cx := roundi((a.x - origin.x) / CELL)
			var cz := roundi((a.y - origin.y) / CELL)
			for gz in range(maxi(cz - fine, 0), mini(cz + fine, depth - 1) + 1):
				for gx in range(maxi(cx - fine, 0), mini(cx + fine, width - 1) + 1):
					var q := Vector2(origin.x + gx * CELL, origin.y + gz * CELL)
					var k := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					var d := q.distance_to(a + ab * k)
					var at := gz * width + gx
					if d < exact_d[at]:
						exact_d[at] = d
						near_y[at] = lerpf(pts[i].y, pts[i + 1].y, k)
	heights.resize(n)
	road_distance.resize(n)
	for gz in depth:
		var z := origin.y + gz * CELL
		for gx in width:
			var x := origin.x + gx * CELL
			var at := gz * width + gx
			var open: float = far.call(x, z)
			var d := exact_d[at] if exact_d[at] < INF else near_d[at]
			var h := open
			if d <= FLAT:
				h = near_y[at] - 0.05
			elif d < BLEND:
				# From the nearest road's height to the average of the roads
				# around (so two roads at different heights meet smoothly),
				# a small rise, then the open land.
				var k := smoothstep(FLAT, SHOULDER, d)
				var level := lerpf(near_y[at], ysum[at] / wsum[at], k)
				h = lerpf(level + k * 1.2, open, smoothstep(SHOULDER, BLEND, d))
			heights[at] = h
			road_distance[at] = minf(d, BLEND)
	# Every place's plaza: level with the place, easing out into the land.
	for id in PLACES:
		var c: Vector2 = PLACES[id]["at"]
		var elev: float = PLACES[id]["elev"]
		var r := plaza_radius(id)
		var reach := r + 14.0
		for gz in range(maxi(floori((c.y - reach - origin.y) / CELL), 0), mini(ceili((c.y + reach - origin.y) / CELL), depth - 1) + 1):
			for gx in range(maxi(floori((c.x - reach - origin.x) / CELL), 0), mini(ceili((c.x + reach - origin.x) / CELL), width - 1) + 1):
				var q := origin + Vector2(gx, gz) * CELL
				var dq := q.distance_to(c)
				var at := gz * width + gx
				heights[at] = lerpf(elev - 0.05, heights[at], smoothstep(r + 3.0, reach, dq))
				road_distance[at] = minf(road_distance[at], maxf(dq - r, 0.0))


## The open land's height at any point, as a Callable(x, z): a smooth
## surface through the roads' heights and OUTSIDE at the baked area's edge
## (relaxed on a coarse grid), plus hills that rise away from the roads, as
## high as each area's, dying away towards the edge.
func _far_field() -> Callable:
	var fw := int(ceil(width * CELL / FAR_CELL)) + 1
	var fd := int(ceil(depth * CELL / FAR_CELL)) + 1
	var val := PackedFloat32Array()
	val.resize(fw * fd)
	var fixed := PackedByteArray()
	fixed.resize(fw * fd)
	var sums := PackedFloat32Array()
	sums.resize(fw * fd)
	var counts := PackedFloat32Array()
	counts.resize(fw * fd)
	for id in road_ids:
		for p in roads[id].points:
			var i := roundi((p.z - origin.y) / FAR_CELL) * fw + roundi((p.x - origin.x) / FAR_CELL)
			sums[i] += p.y
			counts[i] += 1.0
	for fz in fd:
		for fx in fw:
			var i := fz * fw + fx
			if counts[i] > 0.0:
				val[i] = sums[i] / counts[i]
				fixed[i] = 1
			elif fx == 0 or fz == 0 or fx == fw - 1 or fz == fd - 1:
				val[i] = OUTSIDE
				fixed[i] = 1
			else:
				val[i] = 20.0
	# Over-relaxed Gauss-Seidel: each free cell becomes the average of its
	# neighbours, a little beyond, until it settles.
	for it in 400:
		for fz in range(1, fd - 1):
			for fx in range(1, fw - 1):
				var i := fz * fw + fx
				if fixed[i] == 1:
					continue
				var avg := (val[i - 1] + val[i + 1] + val[i - fw] + val[i + fw]) * 0.25
				val[i] += 1.85 * (avg - val[i])
	# How high the hills rise, by area, blended between places.
	var amp := PackedFloat32Array()
	amp.resize(fw * fd)
	for fz in fd:
		for fx in fw:
			var q := origin + Vector2(fx, fz) * FAR_CELL
			var w := 0.0
			var sum := 0.0
			for id in PLACES:
				var d2: float = q.distance_squared_to(PLACES[id]["at"])
				var k := 1.0 / (d2 * d2 + 1.0)
				w += k
				sum += k * float(AREAS[PLACES[id]["area"]]["hills"])
			amp[fz * fw + fx] = sum / w
	var o := origin
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 1729
	noise.frequency = 1.0 / 420.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	return func(x: float, z: float) -> float:
		var fx := clampf((x - o.x) / FAR_CELL, 0.0, fw - 1.001)
		var fz := clampf((z - o.y) / FAR_CELL, 0.0, fd - 1.001)
		var ix := int(fx)
		var iz := int(fz)
		var kx := fx - ix
		var kz := fz - iz
		var i := iz * fw + ix
		var base := lerpf(lerpf(val[i], val[i + 1], kx), lerpf(val[i + fw], val[i + fw + 1], kx), kz)
		var a := lerpf(lerpf(amp[i], amp[i + 1], kx), lerpf(amp[i + fw], amp[i + fw + 1], kx), kz)
		# The hills die away towards the edge, to meet the land beyond it.
		var edge := minf(minf(x - o.x, o.x + (fw - 1) * FAR_CELL - x),
				minf(z - o.y, o.y + (fd - 1) * FAR_CELL - z))
		a *= smoothstep(0.0, HILLS_FROM_EDGE, edge)
		return base + a * (0.5 + 0.7 * noise.get_noise_2d(x, z))


# --- the baked file ----------------------------------------------------------

## A fingerprint of everything the land is made from, so a stale file is
## noticed.
static func fingerprint() -> int:
	return hash(str([PLACES, ROADS, AREAS, STEP, FLAT, SHOULDER, BLEND, CELL, FAR_CELL, OUTSIDE,
		MARGIN, HILLS_FROM_EDGE, PLAZA_MIN, PLAZA_MAX, 5]))


func save_baked(file: String) -> Error:
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(FILE_TAG)
	f.store_64(fingerprint())
	f.store_float(origin.x)
	f.store_float(origin.y)
	f.store_32(width)
	f.store_32(depth)
	f.store_buffer(heights.to_byte_array())
	f.store_buffer(road_distance.to_byte_array())
	f.close()
	return OK


func load_baked(file: String) -> bool:
	if not FileAccess.file_exists(file):
		return false
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null or f.get_buffer(FILE_TAG.length()).get_string_from_ascii() != FILE_TAG:
		return false
	if f.get_64() != fingerprint():
		push_warning("the baked island land is out of date")
		return false
	origin = Vector2(f.get_float(), f.get_float())
	width = f.get_32()
	depth = f.get_32()
	heights = f.get_buffer(width * depth * 4).to_float32_array()
	road_distance = f.get_buffer(width * depth * 4).to_float32_array()
	return heights.size() == width * depth and road_distance.size() == width * depth
