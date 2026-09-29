class_name MiniMap
extends Control
## A racing-game map: zoomed in round you, turning with you so the way you
## ride is always up. Every road, the way being ridden in cyan (faint where
## it's been ridden), the plazas, the finish, the ghost (held at the edge
## when it's off the map), place names kept upright, and which way is north.

const SPAN := 700.0  # m of the island from the map's top edge to its bottom
const YOU_AT := 0.72  # how far down the map you are: most of it is ahead
const EVERY := 20.0  # m between the points drawn
const AHEAD := 4000.0  # m of the way ahead drawn (all of a route's is)
const TURN_RATE := 6.0  # how quickly the map turns after you (per second)
const LABELS := ["city", "summit", "west-gate", "hilltop", "valley-south", "valley-north",
	"east-point", "foot", "quarry"]
const WAY := Color("00f0ff")
const ROAD := Color(0.62, 0.72, 0.88)

var route: Route:
	set(r):
		route = r
		_prepare()
		_heading_set = false
		_route_pts = PackedVector2Array()
		if r and not r.endless:
			var s := 0.0
			while s < r.length:
				_route_pts.append(_flat(s))
				s += EVERY
			_route_pts.append(_flat(r.length))
var position_m := 0.0
var ghost_m := -1.0
var accent := UiStyle.ACCENT
var rider_color := Color("ff3bd4")
var ghost_color := Color(0.8, 0.9, 1.0)
var _route_pts := PackedVector2Array()
var _heading := 0.0
var _heading_set := false

static var _roads: Array[PackedVector2Array] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(100, 100)


## A point of the way being ridden, from above: x east, z south (down).
func _flat(s: float) -> Vector2:
	var p := route.position_at(s)
	return Vector2(p.x, p.z)


static func _prepare() -> void:
	if not _roads.is_empty():
		return
	var isl := Island.main()
	for id in isl.road_ids:
		var pts: PackedVector3Array = isl.roads[id].points
		var line := PackedVector2Array()
		var step := int(EVERY / Island.STEP)
		for i in range(0, pts.size(), step):
			line.append(Vector2(pts[i].x, pts[i].z))
		line.append(Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z))
		_roads.append(line)


func _process(delta: float) -> void:
	if route == null or not is_visible_in_tree():
		return
	var want := route.heading_at(position_m + 15.0)
	if not _heading_set:
		_heading = want
		_heading_set = true
	_heading = lerp_angle(_heading, want, 1.0 - exp(-TURN_RATE * delta))
	queue_redraw()


func _draw() -> void:
	if route == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var scale := size.y / SPAN
	var rot := -_heading  # heading 0 is north, and north is up on screen
	var you := Vector2(size.x * 0.5, size.y * YOU_AT)
	var me := _flat(position_m)
	var to_screen := func(p: Vector2) -> Vector2: return you + ((p - me) * scale).rotated(rot)
	# Everything below is drawn in the island's own metres, placed by this.
	draw_set_transform(you - (me * scale).rotated(rot), rot, Vector2(scale, scale))
	var px := 1.0 / scale  # one pixel, in metres
	var view := (SPAN * 0.9) * (SPAN * 0.9)
	for line in _roads:
		if line[0].distance_squared_to(me) > view * 16.0 and line[line.size() - 1].distance_squared_to(me) > view * 16.0 \
				and line[line.size() / 2].distance_squared_to(me) > view * 16.0:
			continue
		draw_polyline(line, Color(ROAD, 0.35), 7.0 * px)
		draw_polyline(line, Color(ROAD, 0.55), 4.0 * px)
	var isl := Island.main()
	for id in Island.PLACES:
		var c: Vector2 = Island.PLACES[id]["at"]
		if c.distance_squared_to(me) < view * 4.0:
			draw_circle(c, maxf(isl.plaza_radius(id), 5.0 * px), Color(ROAD, 0.55))
	var n := int(position_m / EVERY)
	if not route.endless:
		var done := _route_pts.slice(0, clampi(n + 1, 1, _route_pts.size()))
		done.append(me)
		var ahead := PackedVector2Array([me])
		ahead.append_array(_route_pts.slice(clampi(n + 1, 0, _route_pts.size())))
		if done.size() >= 2:
			draw_polyline(done, Color(WAY, 0.3), 5.0 * px)
		if ahead.size() >= 2:
			draw_polyline(ahead, Color(WAY, 0.35), 11.0 * px)
			draw_polyline(ahead, WAY, 5.5 * px)
	else:
		var ahead := PackedVector2Array([me])
		var s := position_m + EVERY
		while s < position_m + AHEAD:
			ahead.append(_flat(s))
			s += EVERY
		draw_polyline(ahead, Color(WAY, 0.35), 11.0 * px)
		draw_polyline(ahead, WAY, 5.5 * px)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Upright, on top: place names, the finish, the ghost, north and you.
	var font := UiStyle.font(false, 600)
	for id in LABELS:
		var p: Vector2 = to_screen.call(Island.PLACES[id]["at"])
		if rect.grow(40.0).has_point(p):
			draw_string(font, p + Vector2(8.0, -6.0), Island.PLACES[id]["name"], HORIZONTAL_ALIGNMENT_LEFT,
					-1, 13, Color(1, 1, 1, 0.6))
	if not route.endless:
		var f: Vector2 = to_screen.call(_route_pts[_route_pts.size() - 1])
		if rect.has_point(f):
			_finish_flag(f)
	if ghost_m >= 0.0:
		var g: Vector2 = to_screen.call(_flat(ghost_m))
		var inside := rect.grow(-8.0)
		if inside.has_point(g):
			draw_circle(g, 8.0, Color(0, 0, 0, 0.6))
			draw_circle(g, 6.0, ghost_color)
		else:
			# At the edge, on the side it's on.
			var d := (g - you).normalized()
			var k := INF
			if absf(d.x) > 1e-4:
				k = minf(k, ((inside.end.x if d.x > 0.0 else inside.position.x) - you.x) / d.x)
			if absf(d.y) > 1e-4:
				k = minf(k, ((inside.end.y if d.y > 0.0 else inside.position.y) - you.y) / d.y)
			var e := you + d * k
			draw_arc(e, 7.0, 0.0, TAU, 20, ghost_color, 3.0, true)
	var north := Vector2(0.0, -1.0).rotated(rot)
	var nk := minf((size.x * 0.5 - 12.0) / maxf(absf(north.x), 1e-4), (size.y * 0.5 - 12.0) / maxf(absf(north.y), 1e-4))
	var np := rect.get_center() + north * nk
	draw_circle(np, 9.0, Color(0, 0, 0, 0.7))
	draw_string(font, np + Vector2(-4.5, 4.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
	var tip := you + Vector2(0.0, -12.0)
	var arrow := PackedVector2Array([tip, you + Vector2(8.0, 8.0), you + Vector2(0.0, 4.0),
			you + Vector2(-8.0, 8.0)])
	draw_colored_polygon(arrow, rider_color)
	arrow.append(tip)
	draw_polyline(arrow, Color.WHITE, 2.0, true)


func _finish_flag(p: Vector2) -> void:
	var c := 4.0
	for i in 3:
		for j in 3:
			draw_rect(Rect2(p + Vector2(i - 1.5, j - 1.5) * c, Vector2(c, c)),
					Color.WHITE if (i + j) % 2 == 0 else Color.BLACK)
