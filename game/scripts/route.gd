class_name Route
extends RefCounted
## A way round the island (Island): the roads of a path one after another,
## as a centreline every STEP metres with its gradient. Built from a spec in
## Catalog, so the same spec always gives the same way.
##
## Specs: "path": legs ("road", or "-road" to ride it backwards), each
## starting where the one before ended; "laps": times round (a loop).
## Free rides ("endless"): "loop": legs ridden round and round (ending where
## they start), or "roam": a seed, from "from", taking a road at random at
## each place, never one in "avoid" or steeper anywhere than "max_grade".

const STEP := Island.STEP
const MAX_GRADE := 0.14
const MIN_GRADE := -0.12
const ROAD_HALF := Island.ROAD_HALF
const SURFACE := 0.04  # the road is drawn this far above the centreline (no flicker with the land)
const RUNOUT := 800.0  # road drawn past the finish line, so it doesn't end in the void
const ENDLESS := 150000.0  # m of road laid out ahead for a free ride
const THEME_BLEND := 300.0  # m over which the colours change between areas
const ROAM_AHEAD := 12000.0  # m of road laid out ahead of a roaming rider...
const ROAM_TOP_UP := 6000.0  # ...topped up when less than this is left
const TURN_CLOSES := 15.0  # m before the way round a roundabout: the turn there is taken

var id := ""
var title := ""
var length := 0.0  # m: the finish line
var endless := false  # free ride: no finish line
var theme := "cyan"  # the colours where it starts
var points := PackedVector3Array()
var grades := PackedFloat32Array()  # rise over run
var ascent := 0.0
var legs: Array = []  # [{"s", "leg", "road", "area"}], in order along the way
var segments: Array = []  # [{"id", "name", "start", "end"}], m along the way
var island: Island
## Roaming free rides lay out only the road ahead, a road at random at each
## place, and the rider may pick another before reaching it.
var roaming := false
var changes := 0  # counts re-layings of the road ahead (the world watches it)
var _way: Array = []  # every leg laid out, ridden or not
var _avoid: Array = []
var _rng: RandomNumberGenerator
var _turn_cache := {}
var _turn_key := ""


static func from_spec(spec: Dictionary) -> Route:
	var r := Route.new()
	r.island = Island.main()
	r.id = spec.get("id", "")
	r.title = spec.get("name", "Route")
	r.endless = spec.get("endless", false)
	var way: Array = []
	if spec.has("path"):
		for lap in int(spec.get("laps", 1)):
			way.append_array(spec["path"])
	var p: Dictionary
	if spec.has("loop"):
		var lap_len: float = (r.island.path(spec["loop"])["points"].size() - 1) * STEP
		for lap in int(ceil(ENDLESS / lap_len)):
			way.append_array(spec["loop"])
		p = r.island.path(way)
	elif spec.has("roam"):
		p = r._roam(spec)
	else:
		p = r.island.path(way)
	var pts: PackedVector3Array = p["points"]
	r.legs = p["legs"]
	r.length = ENDLESS
	if not r.endless:
		# Past the finish the road carries on, the straightest way, for a
		# while, joined round the roundabout like any other road. The finish
		# line is where the way passes closest to the last place.
		var at: String = p["end"]
		var came: String = r.legs.back()["leg"]
		var more := []
		var extra := 0.0
		while extra < RUNOUT:
			var d := pts[pts.size() - 1] - pts[pts.size() - 9]
			var next := r.island.next_leg(at, came, atan2(d.x, -d.z), [])
			more.append(next)
			extra += r.island.roads[Island.leg_road(next)].length()
			came = next
			at = r.island.leg_end(next)
		var reach := (pts.size() - 1) * STEP
		var full: Dictionary = r.island.path(way + more)
		pts = full["points"]
		r.legs = full["legs"]
		var centre: Vector2 = Island.PLACES[p["end"]]["at"]
		var best := INF
		var s := maxf(reach - 80.0, 0.0)
		while s < reach + 80.0:
			var q := pts[mini(int(s / STEP), pts.size() - 1)]
			var dist := Vector2(q.x, q.z).distance_to(centre)
			if dist < best:
				best = dist
				r.length = s
			s += 1.0
	r.points = pts
	r._lay_out()
	r.theme = Island.AREAS[r.legs[0]["area"]]["theme"]
	return r


## The roads a free ride's spec keeps off.
static func avoided(spec: Dictionary) -> Array:
	var out: Array = spec.get("avoid", []).duplicate()
	if spec.has("max_grade"):
		var isl := Island.main()
		for id in isl.road_ids:
			if isl.steepest(id) > float(spec["max_grade"]) and not id in out:
				out.append(id)
	return out


## The road ahead from spec "from", a road at random at each place with the
## spec's seed; more is laid on as it's ridden (keep_ahead()).
func _roam(spec: Dictionary) -> Dictionary:
	roaming = true
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(spec["roam"])
	_avoid = avoided(spec)
	_way = []
	_lay_on(spec.get("from", "city"), ROAM_AHEAD)
	return island.path(_way)


## Adds legs at random until about `total` m are laid out.
func _lay_on(start: String, total: float) -> void:
	var laid := 0.0
	for leg in _way:
		laid += island.roads[Island.leg_road(leg)].length()
	while laid < total:
		var came: String = _way.back() if not _way.is_empty() else ""
		var at: String = start if _way.is_empty() else island.leg_end(came)
		var leg := island.next_leg(at, came, 0.0, _avoid, _rng)
		_way.append(leg)
		laid += island.roads[Island.leg_road(leg)].length()


func _relay() -> void:
	var p := island.path(_way)
	points = p["points"]
	legs = p["legs"]
	_lay_out()
	changes += 1


## Roaming: lays more road on when less than ROAM_TOP_UP is left past `s`.
## True when it did.
func keep_ahead(s: float) -> bool:
	if not roaming or (points.size() - 1) * STEP - s > ROAM_TOP_UP:
		return false
	_lay_on("", s + ROAM_AHEAD)
	_relay()
	return true


## Roaming: the next place whose way on can still be picked, from `s`:
## {"place", "s" (where the curve across it starts: everything before that
## stays put whatever's picked), "options": [{"leg", "turn"}, leftmost
## first], "index" (the one taken), "j" (its leg)}, or {}.
func next_turn(s: float) -> Dictionary:
	if not roaming:
		return {}
	var j := _leg_index(s) + 1
	while j < legs.size() and float(legs[j]["turn_s"]) - TURN_CLOSES <= s:
		j += 1
	if j >= legs.size():
		return {}
	var key := "%d:%d" % [changes, j]
	if key != _turn_key:
		var came: String = _way[j - 1]
		var place := island.leg_end(came)
		var options := island.turn_options(place, came, _avoid)
		var index := -1
		for k in options.size():
			if options[k]["leg"] == _way[j]:
				index = k
		_turn_cache = {"place": place, "s": float(legs[j]["turn_s"]), "options": options,
			"index": index, "j": j}
		_turn_key = key
	return _turn_cache


## Roaming: take the way `step` to the left (-1) or right (+1) of the one
## taken at the next place, and lay the road beyond it afresh. Returns
## next_turn() after it.
func choose_turn(s: float, step: int) -> Dictionary:
	var t := next_turn(s)
	if t.is_empty():
		return t
	var k := clampi(int(t["index"]) + step, 0, t["options"].size() - 1)
	if k == t["index"]:
		return t
	_way.resize(t["j"])
	_way.append(t["options"][k]["leg"])
	_lay_on("", s + ROAM_AHEAD)
	_relay()
	return next_turn(s)


## Gradients, the climbing and the segments, from the points.
func _lay_out() -> void:
	var n := points.size()
	grades.resize(n)
	for i in n:
		var a := points[mini(i, n - 2)]
		var b := points[mini(i + 1, n - 1)]
		grades[i] = (b.y - a.y) / STEP
	_find_segments()
	ascent = 0.0
	for i in mini(int(length / STEP), n - 1):
		ascent += maxf(points[i + 1].y - points[i].y, 0.0)


func _index(s: float) -> int:
	return clampi(int(s / STEP), 0, points.size() - 2)


func _frac(s: float, i: int) -> float:
	return clampf(s / STEP - i, 0.0, 1.0)


## Where the way rides a segment: each leg along a segment's road, the
## right way, and (for a route) finished before the finish line.
func _find_segments() -> void:
	segments = []
	for k in legs.size():
		var leg: Dictionary = legs[k]
		if str(leg["leg"]).begins_with("-"):
			continue
		var from: float = leg["s"]
		var to: float = legs[k + 1]["s"] if k + 1 < legs.size() else (points.size() - 1) * STEP
		for seg in Island.SEGMENTS:
			if seg["road"] != leg["road"]:
				continue
			var ends := island.segment_ends(seg)
			var a := _nearest(ends[0], from, to)
			var b := _nearest(ends[1], from, to)
			if b > a and (endless or b <= length):
				segments.append({"id": seg["id"], "name": seg["name"], "start": a, "end": b})


## The distance along the way, between from and to, nearest a point.
func _nearest(p: Vector3, from: float, to: float) -> float:
	var best := from
	var bd := INF
	var i := int(from / STEP)
	while i * STEP <= to and i < points.size():
		var d := Vector2(points[i].x - p.x, points[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i * STEP
		i += 1
	return best


## Along a smooth curve by the points, not straight from one to the next:
## straight pieces jolt the rider sideways at every point on a bend, which
## reads as a wobble.
func position_at(s: float) -> Vector3:
	var i := _index(s)
	return _curve(i, _frac(s, i))


## A cubic B-spline: its bend changes smoothly everywhere (a curve through
## the points exactly would change it in a step at every point, a jolt), and
## it strays from the points by at most a few centimetres. Mirrored points
## past the ends pin it to the first and the last.
func _curve(i: int, t: float) -> Vector3:
	var n := points.size()
	var p1 := points[i]
	var p2 := points[i + 1]
	var p0 := points[i - 1] if i > 0 else 2.0 * p1 - p2
	var p3 := points[i + 2] if i + 2 < n else 2.0 * p2 - p1
	var u := 1.0 - t
	return (p0 * (u * u * u) + p1 * (3.0 * t * t * t - 6.0 * t * t + 4.0)
			+ p2 * (-3.0 * t * t * t + 3.0 * t * t + 3.0 * t + 1.0) + p3 * (t * t * t)) / 6.0


## The way the curve is heading at s: 0 is towards -Z.
func heading_at(s: float) -> float:
	var i := _index(s)
	var t := _frac(s, i)
	var d := _curve(i, minf(t + 0.02, 1.0)) - _curve(i, maxf(t - 0.02, 0.0))
	return atan2(d.x, -d.z)


func grade_at(s: float) -> float:
	var i := _index(s)
	return lerpf(grades[i], grades[i + 1], _frac(s, i))


## Average gradient over the next `span` metres: what the bike should feel.
func grade_ahead(s: float, span: float) -> float:
	var total := 0.0
	var n := 5
	for k in n:
		total += grade_at(s + span * k / (n - 1))
	return total / n


func elevation_at(s: float) -> float:
	return position_at(s).y


## Unit vector along the road, tilted with the gradient.
func forward_at(s: float) -> Vector3:
	var h := heading_at(s)
	return Vector3(sin(h), grade_at(s), -cos(h)).normalized()


## Unit vector to the right of the road, level.
func right_at(s: float) -> Vector3:
	var h := heading_at(s)
	return Vector3(cos(h), 0.0, sin(h))


## A point on the land `d` metres to the side of the road (negative is left).
func land_point(s: float, d: float) -> Vector3:
	var p := position_at(s) + right_at(s) * d
	return Vector3(p.x, island.height_at(p.x, p.z), p.z)


## The leg of the way at `s`: {"s", "leg", "road", "area"}.
func leg_at(s: float) -> Dictionary:
	return legs[_leg_index(s)]


func _leg_index(s: float) -> int:
	var lo := 0
	var hi := legs.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if legs[mid]["s"] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


## The colours at `s`: the area's theme, and the one before it with how far
## the change has got (0-1), for blending.
func theme_at(s: float) -> Array:
	var i := _leg_index(s)
	var leg: Dictionary = legs[i]
	var here: String = Island.AREAS[leg["area"]]["theme"]
	if i <= 0:
		return [here, here, 1.0]
	var before: String = Island.AREAS[legs[i - 1]["area"]]["theme"]
	return [before, here, clampf((s - float(leg["s"])) / THEME_BLEND, 0.0, 1.0)]


## Where the drawn road ends.
func visual_end() -> float:
	return (points.size() - 2) * STEP


## Lowest and highest points, for drawing the profile.
func elevation_range(from_s: float, to_s: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var i0 := _index(from_s)
	var i1 := _index(to_s) + 1
	for i in range(i0, i1 + 1):
		lo = minf(lo, points[i].y)
		hi = maxf(hi, points[i].y)
	return Vector2(lo, hi)
