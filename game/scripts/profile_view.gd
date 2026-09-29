class_name ProfileView
extends Control
## A route's height profile coloured by gradient, or a workout's blocks
## coloured by zone, with where you are (and your ghost) marked on it.

var route: Route
var workout: Workout
var position_m := 0.0
var ghost_m := -1.0
var ghost_color := Color(1, 1, 1, 0.6)  # another rider's ghost: their colour
var elapsed := 0.0
var intensity := 1.0
var ftp := 150.0
var window := 0.0  # metres shown around you; 0 shows the whole route
var time_window := 0.0  # seconds of a workout shown around now; 0 shows it all
var accent := UiStyle.ACCENT
var show_labels := true
var show_marker := true  # off for previews in the menus


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_style_box(UiStyle.box(Color(accent, 0.5), UiStyle.BG, 2, 12), Rect2(Vector2.ZERO, size))
	var pad := Vector2(24, 18)
	var inner := Rect2(pad, size - pad * 2 - Vector2(0, 18 if show_labels else 0))
	if workout:
		_draw_workout(inner)
	elif route:
		_draw_route(inner)


func _range() -> Vector2:
	if window <= 0.0:
		return Vector2(0.0, route.length)
	var from := maxf(0.0, position_m - window * 0.15)
	return Vector2(from, from + window)


func _draw_route(rect: Rect2) -> void:
	var r := _range()
	var er := route.elevation_range(r.x, r.y)
	var lo := er.x
	var hi := maxf(er.y, lo + 40.0)  # flat should look flat
	# The lowest point sits a little above the bottom, so a flat road still
	# shows as a band of colour.
	lo -= (hi - lo) * 0.12
	var n := 180
	var pts := PackedVector2Array()
	for i in n + 1:
		var s := lerpf(r.x, r.y, float(i) / n)
		var y := rect.end.y - (route.elevation_at(s) - lo) / (hi - lo) * rect.size.y
		pts.append(Vector2(rect.position.x + rect.size.x * i / n, y))
	for i in n:
		var mid := lerpf(r.x, r.y, (i + 0.5) / n)
		var c := UiStyle.grade_color(route.grade_at(mid))
		c.a = 0.28 if mid < position_m else 0.75
		draw_colored_polygon(PackedVector2Array([pts[i], pts[i + 1],
				Vector2(pts[i + 1].x, rect.end.y), Vector2(pts[i].x, rect.end.y)]), c)
	draw_polyline(pts, Color(1, 1, 1, 0.85), 2.0, true)
	if ghost_m >= 0.0:
		_marker(rect, r, ghost_m, lo, hi, ghost_color, 7.0)
	if show_marker:
		_marker(rect, r, position_m, lo, hi, accent, 10.0)
	if show_labels:
		var f := UiStyle.font(false, 500)
		var y := rect.end.y + 26
		draw_string(f, Vector2(rect.position.x, y), UiStyle.km(r.x, 0 if r.x == 0 else 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiStyle.DIM)
		draw_string(f, Vector2(rect.end.x - 200, y), UiStyle.km(r.y),
				HORIZONTAL_ALIGNMENT_RIGHT, 200, 20, UiStyle.DIM)
		draw_string(f, Vector2(rect.position.x + rect.size.x * 0.5 - 150, y),
				"%d m of height difference" % roundi(er.y - er.x),
				HORIZONTAL_ALIGNMENT_CENTER, 300, 20, UiStyle.FAINT)


func _marker(rect: Rect2, r: Vector2, at: float, lo: float, hi: float,
		color: Color, radius: float) -> void:
	if at < r.x or at > r.y:
		return
	var x := rect.position.x + rect.size.x * (at - r.x) / (r.y - r.x)
	var y := rect.end.y - (route.elevation_at(at) - lo) / (hi - lo) * rect.size.y
	draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(color, 0.6), 2.0)
	draw_circle(Vector2(x, y), radius, color)


func _draw_workout(rect: Rect2) -> void:
	var t0 := 0.0
	var t1 := workout.duration
	if time_window > 0.0:
		t0 = maxf(0.0, elapsed - time_window * 0.3)
		t1 = t0 + time_window
	var span := t1 - t0
	var top := 1.6
	var t := 0.0
	for st in workout.steps:
		var dur: float = st[0]
		# The part of this block that's on show.
		var a := maxf(t, t0)
		var b := minf(t + dur, t1)
		if b > a:
			var from: float = lerpf(st[1], st[2], (a - t) / dur)
			var to: float = lerpf(st[1], st[2], (b - t) / dur)
			var x0 := rect.position.x + rect.size.x * (a - t0) / span
			var x1 := rect.position.x + rect.size.x * (b - t0) / span
			var y0 := rect.end.y - rect.size.y * minf(from * intensity, top) / top
			var y1 := rect.end.y - rect.size.y * minf(to * intensity, top) / top
			var c := Workout.zone_color((st[1] + st[2]) * 0.5 * intensity)
			c.a = 0.3 if t + dur <= elapsed else 0.85
			draw_colored_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x1, y1),
					Vector2(x1, rect.end.y), Vector2(x0, rect.end.y)]), c)
			if st[3] > 0.0 and x1 - x0 >= 26.0:
				draw_string(UiStyle.font(true, 700), Vector2(x0, minf(y0, y1) - 5.0), str(roundi(st[3])),
						HORIZONTAL_ALIGNMENT_CENTER, x1 - x0, 15, Color(1, 1, 1, 0.75))
		t += dur
	var ftp_y := rect.end.y - rect.size.y / top
	var x := rect.position.x
	while x < rect.end.x:
		draw_line(Vector2(x, ftp_y), Vector2(minf(x + 10, rect.end.x), ftp_y), Color(1, 1, 1, 0.35), 1.0)
		x += 20
	if show_marker:
		var px := rect.position.x + rect.size.x * clampf((elapsed - t0) / span, 0.0, 1.0)
		draw_line(Vector2(px, rect.position.y - 4), Vector2(px, rect.end.y), accent, 3.0)
	if show_labels:
		var f := UiStyle.font(false, 500)
		var y := rect.end.y + 26
		draw_string(f, Vector2(rect.position.x, y), UiStyle.clock(t0), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiStyle.DIM)
		draw_string(f, Vector2(rect.end.x - 200, y), UiStyle.clock(t1),
				HORIZONTAL_ALIGNMENT_RIGHT, 200, 20, UiStyle.DIM)
		draw_string(f, Vector2(rect.position.x + 8, ftp_y - 6), "FTP %d W" % roundi(ftp * intensity),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiStyle.FAINT)
