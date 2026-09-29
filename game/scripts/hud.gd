class_name Hud
extends Control
## Numbers on screen during a ride: power, cadence and speed top left; time,
## distance and gradient top right; a workout's target in the middle; the
## route or workout profile along the bottom; and banners for news.

var profile := ProfileView.new()
var _power := UiStyle.label("0", 120, UiStyle.INK, true, 800)
var _cadence := UiStyle.label("0", 52, UiStyle.INK, true, 700)
var _speed := UiStyle.label("0.0", 52, UiStyle.INK, true, 700)
var _time := UiStyle.label("0:00", 64, UiStyle.INK, true, 700)
var _distance := UiStyle.label("0.0 km", 40, UiStyle.INK, true, 600)
var _grade := UiStyle.label("0.0%", 64, UiStyle.GOOD, true, 800)
var _climb := UiStyle.label("", 28, UiStyle.DIM)
var _ghost_gap := UiStyle.label("", 28, UiStyle.DIM)
var _segment := UiStyle.label("", 28, UiStyle.WARN, false, 600)
var _turn := UiStyle.label("", 30, UiStyle.INK, false, 600)
var minimap := MiniMap.new()
var _map_frame: PanelContainer
var _map_box: StyleBoxFlat
const MAP_SIZE := 180.0  # the map's square, as tall as the height profile
var _workout_box := VBoxContainer.new()
var _workout_panel: PanelContainer
var _target := UiStyle.label("0", 100, UiStyle.INK, true, 800)
var _target_rpm := UiStyle.label("", 40, UiStyle.INK, true, 700)
var _block := UiStyle.label("", 32, UiStyle.INK)
var _next := UiStyle.label("", 28, UiStyle.DIM)
var _extra := UiStyle.label("", 28, UiStyle.WARN)
var _banner := UiStyle.label("", 72, UiStyle.INK, true, 800)
var _sub := UiStyle.label("", 36, UiStyle.DIM)
var _status := UiStyle.label("", 26, UiStyle.DIM)
var _hints := UiStyle.label("", 24, UiStyle.FAINT)
var _fps := UiStyle.label("", 22, UiStyle.FAINT)
var _profile_wait := 0.0
var _banner_left := 0.0
var _banner_color := UiStyle.INK
var _sticky := ""


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var left := VBoxContainer.new()
	var power_row := HBoxContainer.new()
	power_row.add_child(_power)
	var w := UiStyle.label("W", 44, UiStyle.DIM, true, 600)
	w.size_flags_vertical = Control.SIZE_SHRINK_END
	power_row.add_child(w)
	left.add_child(power_row)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_cadence)
	row.add_child(_unit("rpm"))
	row.add_child(_spacer(40))
	row.add_child(_speed)
	row.add_child(_unit("km/h"))
	left.add_child(row)
	var lp := UiStyle.panel(left)
	lp.position = Vector2(36, 32)
	add_child(lp)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	for l in [_time, _distance, _grade, _climb, _ghost_gap, _segment]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(l)
	var rp := UiStyle.panel(right)
	rp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rp.offset_right = -36
	rp.offset_top = 32
	add_child(rp)

	_workout_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var tl := UiStyle.label("TARGET", 24, UiStyle.DIM, true, 600)
	for l in [tl, _target, _target_rpm, _block, _next, _extra]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_workout_box.add_child(l)
	_workout_panel = UiStyle.panel(_workout_box)
	_workout_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_workout_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_workout_panel.offset_top = 32
	_workout_panel.custom_minimum_size = Vector2(520, 0)
	add_child(_workout_panel)

	# The height profile along the bottom, and the map in a square beside it,
	# the same height.
	profile.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	profile.offset_left = 36
	profile.offset_right = -36 - MAP_SIZE - 16
	profile.offset_top = -30 - MAP_SIZE
	profile.offset_bottom = -30
	add_child(profile)
	var frame := PanelContainer.new()
	var box := UiStyle.box(Color(UiStyle.ACCENT, 0.5), UiStyle.BG, 2, 12)
	box.set_content_margin_all(6)
	frame.add_theme_stylebox_override("panel", box)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	frame.offset_left = -36 - MAP_SIZE
	frame.offset_right = -36
	frame.offset_top = -30 - MAP_SIZE
	frame.offset_bottom = -30
	frame.add_child(minimap)
	add_child(frame)
	_map_frame = frame
	_map_box = box

	var centre := VBoxContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Above the rider, below the panels along the top.
	centre.offset_top = -110
	centre.offset_bottom = -110
	for l in [_banner, _sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 12)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		centre.add_child(l)
	add_child(centre)

	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.offset_left = 40
	_status.offset_top = -252
	add_child(_status)
	_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hints.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hints.offset_right = -40
	_hints.offset_top = -250
	add_child(_hints)
	# Roaming: the next place and the way on from it, above the profile.
	_turn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_turn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn.offset_top = -30 - MAP_SIZE - 92
	_turn.add_theme_constant_override("outline_size", 10)
	_turn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_turn)
	_fps.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_fps.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fps.offset_top = -26
	add_child(_fps)


func _unit(text: String) -> Label:
	var l := UiStyle.label(text, 26, UiStyle.DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_END
	return l


func _spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	return c


func setup(ride: Ride, accent: Color, ftp: float) -> void:
	profile.route = ride.route
	profile.workout = ride.workout
	profile.ftp = ftp
	profile.window = 5000.0 if ride.route.endless and ride.workout == null else 0.0
	# The FTP test's ramp runs on as long as you can: show the next few minutes.
	profile.time_window = 900.0 if ride.workout and ride.workout.id == Workout.TEST_ID else 0.0
	profile.accent = accent
	minimap.route = ride.route
	minimap.accent = accent
	_map_box.border_color = Color(accent, 0.5)
	_map_box.shadow_color = Color(accent, 0.22)
	_workout_panel.visible = ride.kind == Ride.Kind.WORKOUT
	_cadence.add_theme_color_override("font_color", UiStyle.INK)
	_banner_left = 0.0
	_banner.text = ""
	_sub.text = ""
	_sticky = ""
	_profile_wait = 0.0
	match ride.kind:
		Ride.Kind.FREE when ride.route.roaming:
			_hints.text = "Left/Right: turn    Up/Down: effort    C: camera    M: mute    Esc: pause"
		Ride.Kind.FREE:
			_hints.text = "Up/Down: effort    C: camera    F: fps    M: mute    Esc: pause"
		Ride.Kind.WORKOUT when ride.workout.id == Workout.TEST_ID:
			_hints.text = "C: camera    F: fps    M: mute    Esc: pause"
		Ride.Kind.WORKOUT:
			_hints.text = "Up/Down: intensity    C: camera    F: fps    M: mute    Esc: pause"
		_:
			_hints.text = "C: camera    F: fps    M: mute    Esc: pause"


func update_ride(ride: Ride, link: BikeLink, delta: float, show_fps: bool) -> void:
	var power := link.power
	_power.text = str(roundi(power))
	_cadence.text = str(roundi(link.cadence))
	_speed.text = "%.1f" % ride.speed_kmh()
	_time.text = UiStyle.clock(ride.elapsed)
	var g := ride.physics_grade()
	_grade.text = "%s%.1f%%" % ["+" if g > 0.0005 else "", g * 100.0]
	_grade.add_theme_color_override("font_color", UiStyle.grade_color(g))
	match ride.kind:
		Ride.Kind.ROUTE:
			_distance.text = "%.1f / %s" % [ride.distance() / 1000.0, UiStyle.km(ride.route.length)]
			_climb.text = "%d m climbed of %d" % [roundi(ride.ascent), roundi(ride.route.ascent)]
		Ride.Kind.FREE:
			_distance.text = UiStyle.km(ride.distance(), 2)
			var e := roundi(ride.effort * 100.0)
			_climb.text = "%d m climbed   effort %s%d%%" % [roundi(ride.ascent), "+" if e > 0 else "", e]
		Ride.Kind.WORKOUT:
			_distance.text = UiStyle.km(ride.distance(), 2)
			if ride.workout.id != Workout.TEST_ID:
				_climb.text = "%s left" % UiStyle.clock(ride.workout.duration - ride.elapsed)
			elif ride.elapsed < Workout.TEST_WARMUP:
				_climb.text = "warm-up: %s left" % UiStyle.clock(Workout.TEST_WARMUP - ride.elapsed)
			else:
				_climb.text = "ramp: minute %d" % (int((ride.elapsed - Workout.TEST_WARMUP) / 60.0) + 1)
			_update_workout(ride, power)
	_ghost_gap.text = _gap_text(ride)
	_ghost_gap.visible = _ghost_gap.text != ""
	_segment.text = _segment_text(ride)
	_segment.visible = _segment.text != ""
	_turn.text = _turn_text(ride)

	profile.position_m = ride.distance()
	profile.ghost_m = ride.ghost_distance()
	profile.elapsed = ride.elapsed
	profile.intensity = ride.intensity
	# The marker moves slowly; redrawing a few times a second saves the GPU
	# rebuilding the whole profile every frame.
	_profile_wait -= delta
	minimap.position_m = ride.distance()
	minimap.ghost_m = ride.ghost_distance()
	if _profile_wait <= 0.0:
		_profile_wait = 0.25
		profile.queue_redraw()

	if _banner_left > 0.0:
		_banner_left -= delta
		_banner.add_theme_color_override("font_color", _banner_color)
		var a := clampf(_banner_left / 0.5, 0.0, 1.0)
		_banner.modulate.a = a
		_sub.modulate.a = a
	elif _sticky != "":
		_banner.text = _sticky
		_sub.text = ""
		_banner.add_theme_color_override("font_color", UiStyle.WARN)
		_banner.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 300.0)
	else:
		_banner.text = ""
		_sub.text = ""
	_fps.text = "%d fps" % Engine.get_frames_per_second() if show_fps else ""


## "The Switchbacks  2:31   best 5:10" while riding a segment, or "".
func _segment_text(ride: Ride) -> String:
	if ride.segment_now.is_empty():
		return ""
	var id: String = ride.segment_now["id"]
	var text := "%s  %s" % [ride.segment_now["name"], UiStyle.clock(ride.elapsed - float(ride.segment_now["t0"]))]
	if ride.segment_best_now.has(id):
		text += "   best %s" % UiStyle.clock(ride.segment_best_now[id])
	return text


## Roaming: "Hilltop in 400 m:  ◀  The Ridge to East Point  ▶", the arrows
## only where there's another way to pick; "" otherwise.
func _turn_text(ride: Ride) -> String:
	var t := ride.route.next_turn(ride.distance())
	if t.is_empty() or int(t["index"]) < 0:
		return ""
	var d: float = float(t["s"]) - ride.distance()
	var place: String = Island.PLACES[t["place"]]["name"]
	var dist := "%d m" % (roundi(d / 10.0) * 10) if d < 1000.0 else UiStyle.km(d)
	var way := Island.main().leg_name(t["options"][t["index"]]["leg"])
	var n: int = t["options"].size()
	var left := "◀  " if int(t["index"]) > 0 else ""
	var right := "  ▶" if int(t["index"]) < n - 1 else ""
	return "%s in %s:   %s%s%s" % [place, dist, left, way, right]


## "Sam's ghost: 40 m ahead", "Your best: 12 m behind", or "".
func _gap_text(ride: Ride) -> String:
	var gd := ride.ghost_distance()
	if gd < 0.0 or ride.rival.is_empty():
		return ""
	var who := "Your best" if ride.rival.get("self", true) else "%s's ghost" % ride.rival["name"]
	var gap := roundi(gd - ride.distance())
	if gap == 0:
		return "%s: level with you" % who
	return "%s: %d m %s" % [who, absi(gap), "ahead" if gap > 0 else "behind"]


func _update_workout(ride: Ride, power: float) -> void:
	var target := ride.target_power()
	var w := ride.workout
	var rpm := w.cadence_at(ride.elapsed)
	_target.text = "%d W" % roundi(target)
	_target.add_theme_color_override("font_color", Workout.zone_color(target / ride.ftp))
	_target_rpm.text = "at %d rpm" % roundi(rpm) if rpm > 0.0 else ""
	_target_rpm.visible = rpm > 0.0
	var i := w.step_index(ride.elapsed)
	_block.text = "%s left in this block" % UiStyle.clock(w.remaining_in_step(ride.elapsed))
	if i + 1 < w.steps.size():
		var nx: Array = w.steps[i + 1]
		_next.text = "Next: %s at %s" % [UiStyle.clock(nx[0]), Workout.describe(nx, ride.ftp, ride.intensity)]
	else:
		_next.text = "Last block"
	var settling := w.settling(ride.elapsed)
	var hint := ""
	if rpm > 0.0 and not settling and _cadence_off(ride, rpm) != 0:
		hint = "Pedal faster: %d rpm" % roundi(rpm) if _cadence_off(ride, rpm) < 0 \
				else "Pedal slower: %d rpm" % roundi(rpm)
	elif not is_equal_approx(ride.intensity, 1.0):
		hint = "Intensity %d%%" % roundi(ride.intensity * 100.0)
	_extra.text = hint
	# How close you are, averaged over a couple of seconds: green on target,
	# yellow near it, red off it; left alone while a new block settles.
	if settling:
		reset_power_color()
		_cadence.add_theme_color_override("font_color", UiStyle.INK)
		return
	var off := absf(ride.smooth_power - target) / maxf(target, 1.0)
	_power.add_theme_color_override("font_color", _band_color(off, Workout.POWER_BAND, Workout.POWER_BAND * 2.0))
	if rpm > 0.0:
		_cadence.add_theme_color_override("font_color", _band_color(absf(ride.smooth_cadence - rpm),
				Workout.CADENCE_BAND, Workout.CADENCE_BAND * 2.0))
	else:
		_cadence.add_theme_color_override("font_color", UiStyle.INK)


static func _band_color(off: float, good: float, near: float) -> Color:
	return UiStyle.GOOD if off <= good else (UiStyle.WARN if off <= near else UiStyle.BAD)


## -1 too slow, 1 too fast, 0 on the cadence target (averaged).
static func _cadence_off(ride: Ride, rpm: float) -> int:
	var d := ride.smooth_cadence - rpm
	if absf(d) <= Workout.CADENCE_BAND:
		return 0
	return -1 if d < 0.0 else 1


func clear_banner() -> void:
	_banner_left = 0.0
	_banner.text = ""
	_sub.text = ""


func reset_power_color() -> void:
	_power.add_theme_color_override("font_color", UiStyle.INK)


## A message in the middle of the screen for a few seconds.
func banner(text: String, sub := "", color := UiStyle.INK, seconds := 3.0) -> void:
	_banner.text = text
	_sub.text = sub
	_banner_color = color
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	_sub.modulate.a = 1.0
	_banner_left = seconds


## A message that stays until cleared, like "Bike disconnected".
func sticky(text: String) -> void:
	_sticky = text


func set_status(text: String) -> void:
	_status.text = text
