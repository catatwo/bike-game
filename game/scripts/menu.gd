class_name Menu
extends Control
## Every screen outside a ride, driven by the keyboard alone: arrows move,
## Enter picks, Left/Right change a setting, Esc goes back.

signal start_ride(kind: String, id: String)
signal resume_ride
signal end_ride(save: bool)
signal done  # the summary was closed: back to the main menu
signal settings_changed
signal exit_requested
signal rider_picked(id: String)  # chosen on "Who's riding?", or just added
signal rider_removed  # the rider riding now was deleted
signal play(sound_name: String)

var settings: Settings
var riders: Riders
var rider: Rider  # whoever is riding now
var history: History  # theirs
var accent := UiStyle.ACCENT
var _stack: Array[Control] = []
var _status := UiStyle.label("", 26, UiStyle.DIM)
var _toast := UiStyle.label("", 40, UiStyle.INK, true, 700)
var _sleep := ColorRect.new()
var _sleep_clock := UiStyle.label("", 120, UiStyle.FAINT, true, 300)
var _quiet := false  # focus moved because a screen opened: no blip
var _in_ride := false  # the pause menu: the HUD shows the bike's state
var _routes := {}  # id -> Route, built once
var _estimates := {}  # id -> seconds, for the pace below
var _estimate_pace := 0.0
var _ghost_pick := {}  # "<rider id>:<route id>" -> whose best to race, or "none"


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.theme()

	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.offset_left = 60
	_status.offset_top = -52
	add_child(_status)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.offset_top = -170
	_toast.add_theme_constant_override("outline_size", 12)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_toast)

	_sleep.color = Color.BLACK
	_sleep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sleep.visible = false
	var sv := VBoxContainer.new()
	sv.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sv.grow_vertical = Control.GROW_DIRECTION_BOTH
	_sleep_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_sleep_clock)
	var hint := UiStyle.label("Pedal, or press any key", 34, UiStyle.FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(hint)
	_sleep.add_child(sv)
	add_child(_sleep)


func is_open() -> bool:
	return not _stack.is_empty()


func set_status(text: String, color := UiStyle.DIM) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func append_status(text: String) -> void:
	_status.text += text


func toast(text: String) -> void:
	_toast.text = text


func show_sleep(on: bool) -> void:
	_sleep.visible = on


func _process(_delta: float) -> void:
	if _sleep.visible:
		var t := Time.get_time_dict_from_system()
		_sleep_clock.text = "%02d:%02d" % [t["hour"], t["minute"]]
	_status.visible = is_open() and not _in_ride


# --- the stack of screens ----------------------------------------------------

func open_main() -> void:
	_clear()
	_push(_main_screen())


## "Who's riding?", over the main menu.
func open_picker() -> void:
	_push(_picker_screen())


## On "Who's riding?", the id of the highlighted rider; otherwise "".
func picker_choice() -> String:
	if _stack.is_empty() or not _stack.back().has_meta("picker"):
		return ""
	var f := get_viewport().gui_get_focus_owner()
	return str(f.get_meta("rider_id", "")) if f else ""


## False while typing a name or confirming a delete: pedalling mustn't start
## a ride from there.
func pedal_starts() -> bool:
	return _stack.is_empty() or not _stack.back().has_meta("no_pedal")


func open_screen(name: String) -> void:
	match name:
		"riders":
			_push(_picker_screen())
		"routes":
			_push(_routes_screen())
		"workouts":
			_push(_workouts_screen())
		"free":
			_push(_free_screen())
		"history":
			_push(_history_screen())
		"settings":
			_push(_settings_screen())


func open_pause(ride: Ride) -> void:
	_in_ride = true
	_push(_pause_screen(ride))


## `xp_before`: the rider's XP before this ride, for the level bar to climb from.
func open_summary(summary: Dictionary, best_before: Dictionary, xp_before := 0) -> void:
	_clear()
	_push(_summary_screen(summary, best_before, xp_before))


func close_all() -> void:
	_clear()


func _clear() -> void:
	_in_ride = false
	for s in _stack:
		s.queue_free()
	_stack.clear()


func _push(screen: Control) -> void:
	if not _stack.is_empty():
		var top: Control = _stack.back()
		top.set_meta("focus", get_viewport().gui_get_focus_owner())
		top.visible = false
	_stack.append(screen)
	add_child(screen)
	for c in [_status, _toast, _sleep]:
		move_child(c, -1)
	_focus(screen.get_meta("initial", null) if screen.has_meta("initial") else _first_button(screen))


func _pop() -> bool:
	if _stack.size() <= 1:
		return false
	_stack.pop_back().queue_free()
	var prev: Control = _stack.back()
	prev.visible = true
	if prev.has_meta("refresh"):
		(prev.get_meta("refresh") as Callable).call()
	var f = prev.get_meta("focus", null)
	if f == null or not is_instance_valid(f):
		# It never had focus (a screen pushed straight over it): where it starts.
		f = prev.get_meta("initial") if prev.has_meta("initial") else _first_button(prev)
	_focus(f)
	return true


func _focus(c: Control) -> void:
	if c == null:
		return
	_quiet = true
	c.grab_focus.call_deferred()
	_unquiet.call_deferred()


func _unquiet() -> void:
	_quiet = false


func _first_button(node: Node) -> Control:
	for child in node.get_children():
		if child is Button:
			return child
		var found := _first_button(child)
		if found:
			return found
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _stack.is_empty() or _sleep.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		var screen: Control = _stack.back()
		if screen.has_meta("on_cancel"):
			(screen.get_meta("on_cancel") as Callable).call()
		elif _pop():
			play.emit("back")
		get_viewport().set_input_as_handled()


# --- building blocks ---------------------------------------------------------

func _screen() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(text: String, on_press: Callable, right := "") -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.custom_minimum_size = Vector2(0, 62)
	b.pressed.connect(func() -> void:
		play.emit("select")
		on_press.call())
	b.focus_entered.connect(func() -> void:
		if not _quiet:
			play.emit("move"))
	if right != "":
		var l := UiStyle.label(right, 26, UiStyle.DIM)
		l.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.offset_left = -360
		l.offset_right = -24
		b.add_child(l)
	return b


func _wrap(text: String, size: int, color := UiStyle.DIM, width := 640.0) -> Label:
	var l := UiStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _level_color(level: String) -> Color:
	match level:
		"Beginner":
			return UiStyle.GOOD
		"Intermediate":
			return UiStyle.WARN
		"Advanced":
			return UiStyle.BAD
	return UiStyle.DIM


func _route(spec: Dictionary) -> Route:
	if not _routes.has(spec["id"]):
		_routes[spec["id"]] = Route.from_spec(spec)
	return _routes[spec["id"]]


## The steady pace the estimates assume: 70% of FTP, a comfortable ride.
func _pace() -> float:
	return snappedf(rider.ftp * 0.7, 5.0)


func _estimate(spec: Dictionary) -> float:
	if _estimate_pace != _pace() + rider.weight * 1000.0:
		_estimates.clear()
		_estimate_pace = _pace() + rider.weight * 1000.0
	if not _estimates.has(spec["id"]):
		_estimates[spec["id"]] = RiderPhysics.time_for(_route(spec), _pace(), rider.weight)
	return _estimates[spec["id"]]


static func _short_date(date: String) -> String:
	# "2026-09-28 21:40:05" -> "28 Sep 21:40"
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
			"Oct", "Nov", "Dec"]
	var parts := date.split(" ")
	if parts.size() < 2:
		return date
	var ymd := parts[0].split("-")
	if ymd.size() < 3:
		return date
	return "%d %s %s" % [int(ymd[2]), months[clampi(int(ymd[1]) - 1, 0, 11)], parts[1].substr(0, 5)]


static func _choice_name(choice: String) -> String:
	var kv := choice.split(":")
	if kv.size() != 2:
		return ""
	var list: Array
	match kv[0]:
		"route":
			list = Catalog.routes()
		"workout":
			list = Catalog.workouts()
		"free":
			list = Catalog.free_rides()
		_:
			return ""
	var spec := Catalog.find(list, kv[1])
	if spec.is_empty():
		return ""
	return ("Free ride: " if kv[0] == "free" else "") + spec["name"]


# --- screens -----------------------------------------------------------------

func _main_screen() -> Control:
	var root := _screen()
	var box := VBoxContainer.new()
	box.position = Vector2(110, 120)
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 10)
	var title := UiStyle.label("BIKE GAME", 96, accent, true, 900)
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_outline_color", Color(UiStyle.HOT, 0.35))
	box.add_child(title)
	box.add_child(_button("Riding: " + rider.name, func() -> void: _push(_picker_screen()),
			"change" if riders.list.size() > 1 else "add a rider"))
	box.add_child(_level_line(Levels.level_for(Levels.total(history.rides(), rider.ftp))))
	box.add_child(_gap(4))
	var again := _choice_name(rider.last_choice)
	if again != "":
		var kv := rider.last_choice.split(":")
		var b := _button("Ride again: " + again, func() -> void: start_ride.emit(kv[0], kv[1]))
		box.add_child(b)
		root.set_meta("initial", b)
	var free := _button("Free ride", func() -> void: _push(_free_screen()), "no finish line")
	box.add_child(free)
	if not root.has_meta("initial"):
		root.set_meta("initial", free)
	box.add_child(_button("Routes", func() -> void: _push(_routes_screen()),
			"%d to ride" % Catalog.routes().size()))
	box.add_child(_button("Workouts", func() -> void: _push(_workouts_screen()),
			"10 min to 1 hour"))
	box.add_child(_button("History", func() -> void: _push(_history_screen())))
	box.add_child(_button("Settings", func() -> void: _push(_settings_screen())))
	box.add_child(_button("Exit", func() -> void: exit_requested.emit()))
	box.add_child(_gap(8))
	if rider.weight == 80.0 and rider.ftp == 150.0:
		box.add_child(_wrap("First time, %s? Set your weight in Settings and take the FTP test in Workouts: speeds and workouts depend on them." % rider.name,
				26, UiStyle.WARN))
	if settings.pedal_start:
		box.add_child(_wrap("Or just start pedalling: a free ride starts by itself.", 26, UiStyle.FAINT))
	var p := UiStyle.panel(box, Color(accent, 0.6))
	p.position = Vector2(80, 56)
	root.add_child(p)
	return root


## A list on the left, details of the highlighted entry on the right.
func _list_screen(title: String, items: Array, kind: String, detail: Callable,
		hint := "Enter: ride    Esc: back") -> Control:
	var root := _screen()
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 80
	h.offset_right = -80
	h.offset_top = 70
	h.offset_bottom = -110
	h.add_theme_constant_override("separation", 36)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(760, 0)
	left.add_theme_constant_override("separation", 16)
	left.add_child(UiStyle.label(title, 56, accent, true, 800))
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	left.add_child(scroll)
	left.add_child(UiStyle.label(hint, 24, UiStyle.FAINT))
	h.add_child(left)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var dp := UiStyle.panel(box, Color(accent, 0.6))
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(dp)
	for it in items:
		var b := _button(it["name"], it["pick"], it.get("right", ""))
		var show := func() -> void:
			for c in box.get_children():
				box.remove_child(c)
				c.queue_free()
			detail.call(box, it)
		b.focus_entered.connect(show)
		if it.has("on_side"):  # Left/Right change something about this entry
			b.gui_input.connect(func(ev: InputEvent) -> void:
				var d := -1 if ev.is_action_pressed("ui_left", true) \
						else (1 if ev.is_action_pressed("ui_right", true) else 0)
				if d != 0:
					(it["on_side"] as Callable).call(d)
					show.call()
					play.emit("move")
					b.accept_event())
		list.add_child(b)
		if kind != "" and rider.last_choice == kind + ":" + it["id"]:
			root.set_meta("initial", b)
	if items.is_empty():
		list.add_child(UiStyle.label("Nothing here yet.", 32, UiStyle.DIM))
	root.add_child(h)
	return root


func _routes_screen() -> Control:
	var items := []
	for spec in Catalog.routes():
		var r := _route(spec)
		var id: String = spec["id"]
		var it := {"id": id, "name": spec["name"], "spec": spec,
			"right": "%s   %s" % [UiStyle.km(r.length), UiStyle.clock(_estimate(spec))],
			"pick": func() -> void: start_ride.emit("route", id)}
		if not _bests(id).is_empty():
			it["on_side"] = func(d: int) -> void: _next_ghost(id, d)
		items.append(it)
	return _list_screen("ROUTES", items, "route", _route_detail,
			"Enter: ride    Left/Right: whose ghost    Esc: back")


## The fastest time on a segment of any rider: {"name", "time"}, or {}.
func _fastest_on(id: String) -> Dictionary:
	var out := {}
	for r in riders.list:
		var h := History.new()
		h.dir = r.rides_dir()
		var t := h.segment_best(id)
		if t < float(out.get("time", INF)):
			out = {"name": r.name, "time": t}
	return out


## Everyone's best time on a route, fastest first: [{"rider_id", "name", "time"}].
func _bests(route_id: String) -> Array:
	var out := []
	for r in riders.list:
		var h := History.new()
		h.dir = r.rides_dir()
		var b := h.best(route_id)
		if not b.is_empty():
			out.append({"rider_id": r.id, "name": r.name, "time": float(b["time"])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"])
	return out


## Whose best to race on a route: as picked on the Routes screen, otherwise
## your own, otherwise the fastest rider's. {} for no ghost.
func ghost_for(route_id: String) -> Dictionary:
	var bests := _bests(route_id)
	var pick: String = _ghost_pick.get(rider.id + ":" + route_id, rider.id)
	if pick == "none" or bests.is_empty():
		return {}
	for b in bests:
		if b["rider_id"] == pick:
			return b
	return bests[0]


func _next_ghost(route_id: String, d: int) -> void:
	var choices: Array = _bests(route_id).map(func(b: Dictionary) -> String: return b["rider_id"])
	choices.append("none")
	var now: String = ghost_for(route_id).get("rider_id", "none")
	var i := posmod(choices.find(now) + d, choices.size())
	_ghost_pick[rider.id + ":" + route_id] = choices[i]


func _route_detail(box: VBoxContainer, it: Dictionary) -> void:
	var spec: Dictionary = it["spec"]
	var r := _route(spec)
	box.add_child(UiStyle.label(spec["name"], 50, UiStyle.INK, true, 800))
	box.add_child(UiStyle.label(spec["level"].to_upper(), 24, _level_color(spec["level"]), true, 700))
	box.add_child(_wrap(spec["about"], 30))
	box.add_child(UiStyle.label("%s    %d m of climbing" % [UiStyle.km(r.length), roundi(r.ascent)], 30))
	box.add_child(UiStyle.label("About %s at %d W" % [UiStyle.clock(_estimate(spec)), roundi(_pace())],
			30, accent))
	var bests := _bests(spec["id"])
	if not bests.is_empty():
		var g := ghost_for(spec["id"])
		var race := "no ghost"
		if not g.is_empty():
			race = ("your best, %s" if g["rider_id"] == rider.id else g["name"] + "'s best, %s") \
					% UiStyle.clock(g["time"])
		box.add_child(UiStyle.label("Race: %s    ◀ ▶" % race, 30, UiStyle.WARN))
		if riders.list.size() > 1:
			var times := bests.slice(0, 4).map(func(b: Dictionary) -> String:
				return "%s %s" % ["you" if b["rider_id"] == rider.id else b["name"], UiStyle.clock(b["time"])])
			box.add_child(_wrap("Best times: " + ", ".join(times), 26, UiStyle.FAINT))
	var segs := r.segments
	if not segs.is_empty():
		var lines := PackedStringArray()
		for seg in segs:
			var mine := history.segment_best(seg["id"])
			var fastest := _fastest_on(seg["id"])
			var line: String = seg["name"]
			if mine < INF:
				line += ": you %s" % UiStyle.clock(mine)
			if not fastest.is_empty() and fastest["name"] != rider.name:
				line += "%s fastest %s %s" % [", " if mine < INF else ": ", fastest["name"], UiStyle.clock(fastest["time"])]
			lines.append(line)
		box.add_child(_wrap("Segments  " + "    ".join(lines), 24, UiStyle.WARN))
	var pv := ProfileView.new()
	pv.show_marker = false
	pv.route = r
	pv.accent = accent
	pv.custom_minimum_size = Vector2(0, 230)
	box.add_child(pv)


func _workouts_screen() -> Control:
	var items := []
	var minutes := Workout.test_minutes(rider.ftp)
	items.append({"id": Workout.TEST_ID, "name": "FTP test", "test": true,
		"workout": Workout.ftp_test(rider.ftp, maxi(minutes - 2, 4)),
		"right": "Test   about %d min" % minutes,
		"pick": func() -> void: start_ride.emit("workout", Workout.TEST_ID)})
	for spec in Catalog.workouts():
		var w := Workout.from_spec(spec)
		var id: String = spec["id"]
		items.append({"id": id, "name": spec["name"], "spec": spec, "workout": w,
			"right": "%s   %d min" % [spec["level"], roundi(w.duration / 60.0)],
			"pick": func() -> void: start_ride.emit("workout", id)})
	return _list_screen("WORKOUTS", items, "workout", _workout_detail)


func _workout_detail(box: VBoxContainer, it: Dictionary) -> void:
	if it.has("test"):
		_test_detail(box, it)
		return
	var spec: Dictionary = it["spec"]
	var w: Workout = it["workout"]
	var hardest := 0.0
	for st in w.steps:
		hardest = maxf(hardest, maxf(st[1], st[2]))
	box.add_child(UiStyle.label(spec["name"], 50, UiStyle.INK, true, 800))
	box.add_child(UiStyle.label("%s    %d MIN" % [spec["level"].to_upper(), roundi(w.duration / 60.0)],
			24, _level_color(spec["level"]), true, 700))
	box.add_child(_wrap(spec["about"], 30))
	box.add_child(UiStyle.label("Average %d W, hardest %d W" % [roundi(w.average_target() * rider.ftp),
			roundi(hardest * rider.ftp)], 30, accent))
	if w.has_cadence():
		var rpms: Array = []
		for st in w.steps:
			if st[3] > 0.0 and not rpms.has(roundi(st[3])):
				rpms.append(roundi(st[3]))
		rpms.sort()
		box.add_child(UiStyle.label("Cadence: %s rpm" % ", ".join(rpms.map(func(x: int) -> String: return str(x))),
				30, UiStyle.WARN))
	box.add_child(_wrap("Targets are set from your FTP (%d W, in Settings). The bike holds each one for you; Up and Down make the whole workout easier or harder." % roundi(rider.ftp),
			26, UiStyle.FAINT))
	var pv := ProfileView.new()
	pv.show_marker = false
	pv.workout = w
	pv.ftp = rider.ftp
	pv.accent = accent
	pv.custom_minimum_size = Vector2(0, 230)
	box.add_child(pv)


func _test_detail(box: VBoxContainer, it: Dictionary) -> void:
	var w: Workout = it["workout"]
	box.add_child(UiStyle.label("FTP test", 50, UiStyle.INK, true, 800))
	box.add_child(UiStyle.label("TEST    ABOUT %d MIN" % Workout.test_minutes(rider.ftp), 24, accent, true, 700))
	box.add_child(_wrap(w.about, 30))
	box.add_child(UiStyle.label("Starts at %d W, then %d W more each minute" % [Workout.test_start(rider.ftp),
			Workout.TEST_STEP], 30, accent))
	box.add_child(_wrap("Your FTP now: %d W. At the end you choose whether to use the new one. Best done rested, not after a hard day." % roundi(rider.ftp),
			26, UiStyle.FAINT))
	var pv := ProfileView.new()
	pv.show_marker = false
	pv.workout = w
	pv.ftp = rider.ftp
	pv.accent = accent
	pv.custom_minimum_size = Vector2(0, 230)
	box.add_child(pv)


func _free_screen() -> Control:
	var items := []
	for spec in Catalog.free_rides():
		var id: String = spec["id"]
		var what := "roaming"
		if spec.has("loop"):
			what = "%s laps" % UiStyle.km((Island.main().path(spec["loop"])["points"].size() - 1) * Route.STEP)
		items.append({"id": id, "name": spec["name"], "spec": spec,
			"right": "%s   %s" % [spec["level"], what],
			"pick": func() -> void: start_ride.emit("free", id)})
	return _list_screen("FREE RIDE", items, "free", _free_detail)


func _free_detail(box: VBoxContainer, it: Dictionary) -> void:
	var spec: Dictionary = it["spec"]
	box.add_child(UiStyle.label(spec["name"], 50, UiStyle.INK, true, 800))
	box.add_child(UiStyle.label(spec["level"].to_upper(), 24, _level_color(spec["level"]), true, 700))
	box.add_child(_wrap(spec["about"], 30))
	if spec.has("loop"):
		var lap: PackedVector3Array = Island.main().path(spec["loop"])["points"]
		var climb := 0.0
		for i in lap.size() - 1:
			climb += maxf(lap[i + 1].y - lap[i].y, 0.0)
		box.add_child(UiStyle.label("One lap: %s    %d m of climbing" % [UiStyle.km((lap.size() - 1) * Route.STEP),
				roundi(climb)], 30, accent))
	else:
		box.add_child(UiStyle.label("A different way round every time", 30, accent))
	box.add_child(_wrap("No finish line: ride as long as you like, then Esc to finish and save. The bar at the bottom shows the road ahead.",
			26, UiStyle.FAINT))


func _history_screen() -> Control:
	var rides := history.rides()
	rides.reverse()
	var total_t := 0.0
	var total_d := 0.0
	for r in rides:
		total_t += r.get("time", 0.0)
		total_d += r.get("distance", 0.0)
	var items := []
	for r in rides.slice(0, 60):
		items.append({"id": r.get("file", ""), "name": "%s    %s" % [_short_date(r.get("date", "")), r.get("title", "")],
			"summary": r, "right": "%s   %s" % [UiStyle.clock(r.get("time", 0.0)), UiStyle.km(r.get("distance", 0.0))],
			"pick": func() -> void: pass})
	var hint := "%s's rides" % rider.name
	var recs := history.records()
	if not recs.is_empty():
		var parts := PackedStringArray()
		for span in Ride.RECORD_SPANS:
			if recs.has(span):
				parts.append("%s %d W" % [Ride.SPAN_NAMES[span], roundi(recs[span])])
		hint += "    Power records: " + "   ".join(parts)
	var screen := _list_screen("HISTORY", items, "", _history_detail, hint + "    Esc: back")
	if not rides.is_empty():
		var totals := UiStyle.label("%d %s    %s    %s" % [rides.size(),
				"ride" if rides.size() == 1 else "rides", UiStyle.clock(total_t),
				UiStyle.km(total_d, 0)], 30, UiStyle.DIM)
		totals.position = Vector2(420, 92)
		screen.add_child(totals)
	return screen


func _history_detail(box: VBoxContainer, it: Dictionary) -> void:
	var s: Dictionary = it["summary"]
	box.add_child(UiStyle.label(s.get("title", ""), 44, UiStyle.INK, true, 800))
	box.add_child(UiStyle.label(_short_date(s.get("date", "")), 26, UiStyle.DIM))
	box.add_child(_stats_grid(s, true))
	var segs: Array = s.get("segments", [])
	if not segs.is_empty():
		box.add_child(_wrap("Segments: " + ", ".join(segs.map(func(g: Dictionary) -> String:
			return "%s %s" % [g["name"], UiStyle.clock(g["time"])])), 26, UiStyle.WARN))
	var held: Dictionary = s.get("on_target", {})
	if not held.is_empty():
		var bits := PackedStringArray()
		for what in ["power", "cadence"]:
			if held.has(what):
				bits.append("%s %d%%" % [what, held[what]])
		box.add_child(_wrap("On target: " + ", ".join(bits), 26, UiStyle.GOOD))


func _stats_grid(s: Dictionary, with_xp := false) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 40)
	g.add_theme_constant_override("v_separation", 8)
	var rows := [
		["Time", UiStyle.clock(s.get("time", 0.0))],
		["Distance", UiStyle.km(s.get("distance", 0.0), 2)],
		["Average power", "%d W" % s.get("avg_power", 0)],
		["Hardest", "%d W" % s.get("max_power", 0)],
		["Average cadence", "%d rpm" % s.get("avg_cadence", 0)],
		["Climbing", "%d m" % s.get("ascent", 0)],
		["Work", "%d kJ  (about %d kcal burned)" % [s.get("energy_kj", 0), s.get("energy_kj", 0)]],
	]
	if with_xp and s.has("xp"):
		rows.append(["XP", "+%d" % s["xp"]])
	for r in rows:
		g.add_child(UiStyle.label(r[0], 30, UiStyle.DIM))
		g.add_child(UiStyle.label(r[1], 30, UiStyle.INK, true, 600))
	return g


func _settings_screen() -> Control:
	var root := _screen()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(900, 0)
	box.add_child(UiStyle.label("SETTINGS", 56, accent, true, 800))
	var help := _wrap("", 26, UiStyle.DIM, 900)
	help.custom_minimum_size.y = 80
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(900, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	box.add_child(scroll)
	var refreshers: Array[Callable] = []
	var r := rider
	var s := settings

	var mine := UiStyle.label("", 26, accent, true, 700)
	refreshers.append(func() -> void: mine.text = "JUST FOR %s" % r.name.to_upper())
	rows.add_child(mine)
	var name_row := _button("Name", func() -> void: _push(_name_screen(r)))
	var name_value := _row_value(name_row)
	refreshers.append(func() -> void: name_value.text = r.name)
	name_row.focus_entered.connect(func() -> void: help.text = "Enter to change it.")
	rows.add_child(name_row)
	for row in [
		["Weight", func() -> String: return "%d kg" % r.weight,
			func(d: int) -> void: r.weight = clampf(r.weight + d, 40.0, 160.0),
			"Your weight: it decides how fast you climb."],
		["FTP", func() -> String: return "%d W" % r.ftp,
			func(d: int) -> void: r.ftp = clampf(r.ftp + d * 5.0, 50.0, 500.0),
			"The power you could hold for about an hour. Workouts are set from it. Not sure? Take the FTP test, at the top of Workouts."],
		["Hill feel", func() -> String: return "%d%%" % roundi(r.hill_feel * 100.0),
			func(d: int) -> void: r.hill_feel = clampf(snappedf(r.hill_feel + d * 0.05, 0.05), 0.25, 1.5),
			"How much of each hill the bike makes you feel. 100% is real; less makes climbs gentler. Your speed on screen stays real."],
		["Rider colour", func() -> String: return Rider.COLORS[r.color][0],
			func(d: int) -> void: r.color = posmod(r.color + d, Rider.COLORS.size()),
			"The colour of your suit's lines and glow. The bike stays cyan."],
		["Camera", func() -> String: return Rider.CAMERA_NAMES[r.camera],
			func(d: int) -> void: r.camera = posmod(r.camera + d, Rider.CAMERA_NAMES.size()),
			"Where you watch from. C changes it during a ride too."],
	]:
		rows.add_child(_setting_row(row, help, refreshers))

	rows.add_child(_gap(6))
	rows.add_child(UiStyle.label("FOR EVERYONE ON THIS BIKE", 26, accent, true, 700))
	for row in [
		["Music", func() -> String: return "%d%%" % roundi(s.music * 100.0),
			func(d: int) -> void: s.music = clampf(snappedf(s.music + d * 0.1, 0.1), 0.0, 1.0),
			"Music volume."],
		["Sound effects", func() -> String: return "%d%%" % roundi(s.effects * 100.0),
			func(d: int) -> void: s.effects = clampf(snappedf(s.effects + d * 0.1, 0.1), 0.0, 1.0),
			"Wind, beeps and chimes."],
		["Graphics", func() -> String: return Settings.QUALITY_NAMES[s.quality],
			func(d: int) -> void: s.quality = clampi(s.quality + d, 0, 2),
			"Lower runs smoother on a slow computer; higher looks better."],
		["Pedal to start", func() -> String: return "On" if s.pedal_start else "Off",
			func(_d: int) -> void: s.pedal_start = not s.pedal_start,
			"In the menu, pedalling for a few seconds, with no key pressed for 15 seconds, starts a free ride."],
		["Show FPS", func() -> String: return "On" if s.show_fps else "Off",
			func(_d: int) -> void: s.show_fps = not s.show_fps,
			"Frames per second, at the bottom of the screen during a ride."],
	]:
		rows.add_child(_setting_row(row, help, refreshers))

	if riders.list.size() > 1:
		rows.add_child(_gap(6))
		var del := _button("", func() -> void: _push(_delete_screen(r)))
		refreshers.append(func() -> void: del.text = "Delete %s" % r.name)
		del.focus_entered.connect(func() -> void:
			help.text = "Takes %s and all their rides off this bike. It asks first." % r.name)
		rows.add_child(del)

	for f in refreshers:
		f.call()
	box.add_child(_gap(10))
	box.add_child(help)
	box.add_child(UiStyle.label("Left/Right: change    Esc: done", 24, UiStyle.FAINT))
	var p := UiStyle.panel(box, Color(accent, 0.6))
	p.position = Vector2(80, 60)
	root.add_child(p)
	root.set_meta("refresh", func() -> void:
		for f in refreshers:
			f.call())
	root.set_meta("on_cancel", func() -> void:
		settings.save_file()
		r.save_file()
		_pop()
		play.emit("back"))
	return root


## A value shown at the right of a settings row.
func _row_value(b: Button) -> Label:
	var value := UiStyle.label("", 32, UiStyle.INK, true, 600)
	value.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	value.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.offset_left = -520
	value.offset_right = -24
	b.add_child(value)
	return value


## [name, shows the value, changes it by a step, help]: Left/Right change it.
func _setting_row(row: Array, help: Label, refreshers: Array[Callable]) -> Button:
	var b := _button(row[0], func() -> void: pass)
	var value := _row_value(b)
	var show: Callable = row[1]
	var change: Callable = row[2]
	var refresh := func() -> void: value.text = "◀  %s  ▶" % show.call()
	refreshers.append(refresh)
	var apply := func(d: int) -> void:
		change.call(d)
		refresh.call()
		play.emit("move")
		settings_changed.emit()
	b.pressed.connect(func() -> void: apply.call(1))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev.is_action_pressed("ui_left", true):
			apply.call(-1)
			b.accept_event()
		elif ev.is_action_pressed("ui_right", true):
			apply.call(1)
			b.accept_event())
	var text: String = row[3]
	b.focus_entered.connect(func() -> void: help.text = text)
	return b


## "Who's riding?": everyone on this bike, whoever rode last highlighted.
func _picker_screen() -> Control:
	var root := _screen()
	root.set_meta("picker", true)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(820, 0)
	box.add_theme_constant_override("separation", 10)
	box.add_child(UiStyle.label("WHO'S RIDING?", 72, accent, true, 900))
	box.add_child(_gap(8))
	var hint := _wrap("", 26, UiStyle.FAINT, 820)
	hint.custom_minimum_size.y = 76
	for r in riders.list:
		var b := _button(r.name, func() -> void: rider_picked.emit(r.id), _rider_note(r))
		b.set_meta("rider_id", r.id)
		b.focus_entered.connect(func() -> void:
			var pedal := "\nOr just pedal: a free ride for %s starts by itself." % r.name \
					if settings.pedal_start else ""
			hint.text = "Enter: that's me    Esc: back" + pedal)
		box.add_child(b)
		if r == rider:
			root.set_meta("initial", b)
	if riders.list.size() < Riders.MAX:
		var add := _button("+ Add a rider", func() -> void: _push(_name_screen(null)))
		add.focus_entered.connect(func() -> void: hint.text = "Enter: type their name    Esc: back")
		box.add_child(add)
	box.add_child(_gap(8))
	box.add_child(hint)
	var content: Control = box
	if riders.list.size() > 1:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 48)
		h.add_child(box)
		h.add_child(_week_board())
		content = h
	var p := UiStyle.panel(content, Color(accent, 0.8))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(p)
	return root


## This week, from Monday: each rider's time on the bike and XP, most XP first.
func _week_board() -> VBoxContainer:
	var board := VBoxContainer.new()
	board.custom_minimum_size = Vector2(440, 0)
	board.add_theme_constant_override("separation", 12)
	board.add_child(UiStyle.label("THIS WEEK", 40, accent, true, 800))
	var today := Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system())
	var weekday: int = Time.get_datetime_dict_from_system()["weekday"]  # 0 is Sunday
	var monday := Time.get_date_string_from_unix_time(today - 86400 * ((weekday + 6) % 7))
	var rows := []
	for r in riders.list:
		var h := History.new()
		h.dir = r.rides_dir()
		var week := h.rides().filter(func(x: Dictionary) -> bool:
			return str(x.get("date", "")).substr(0, 10) >= monday)
		var t := 0.0
		for x in week:
			t += float(x.get("time", 0.0))
		rows.append({"name": r.name, "time": t, "xp": Levels.total(week, r.ftp)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["xp"] > b["xp"])
	if rows[0]["xp"] == 0:
		board.add_child(_wrap("Nobody has ridden yet this week.", 28, UiStyle.DIM, 440))
		return board
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 10)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var lead: bool = i == 0
		grid.add_child(UiStyle.label(row["name"], 30, UiStyle.GOOD if lead else UiStyle.INK, false, 600))
		grid.add_child(UiStyle.label(UiStyle.clock(row["time"]) if row["time"] > 0.0 else "-", 28, UiStyle.DIM))
		grid.add_child(UiStyle.label("%d XP" % row["xp"], 28, UiStyle.GOOD if lead else UiStyle.INK, true, 600))
	board.add_child(grid)
	return board


## "Level 7, last today", or "no rides yet".
func _rider_note(r: Rider) -> String:
	var h := History.new()
	h.dir = r.rides_dir()
	var rides := h.rides()
	if rides.is_empty():
		return "no rides yet"
	return "Level %d, last %s" % [Levels.level_for(Levels.total(rides, r.ftp))["level"],
			_when(rides.back().get("date", ""))]


## LEVEL 7  Road Captain  [=======     ]
func _level_line(lv: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.add_child(UiStyle.label("LEVEL %d" % lv["level"], 24, accent, true, 800))
	line.add_child(UiStyle.label(lv["title"], 24, UiStyle.DIM))
	var bar := LevelBar.new()
	bar.color = accent
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(0, 10)
	bar.ratio = float(lv["into"]) / lv["needed"]
	line.add_child(bar)
	return line


## "2026-09-28 21:40:05" -> "today", "yesterday", "3 days ago" or "28 Sep".
static func _when(date: String) -> String:
	var day := date.substr(0, 10)
	var today := Time.get_date_string_from_system()
	var days := roundi((Time.get_unix_time_from_datetime_string(today)
			- Time.get_unix_time_from_datetime_string(day)) / 86400.0)
	if days <= 0:
		return "today"
	if days == 1:
		return "yesterday"
	if days < 7:
		return "%d days ago" % days
	return _short_date(date).substr(0, _short_date(date).rfind(" "))


## Typing a name: for a new rider (r null), or to rename r.
func _name_screen(r: Rider) -> Control:
	var root := _screen()
	root.set_meta("no_pedal", true)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(820, 0)
	box.add_theme_constant_override("separation", 14)
	box.add_child(UiStyle.label("NEW RIDER" if r == null else "NEW NAME", 72, accent, true, 900))
	box.add_child(UiStyle.label("Type a name, then press Enter.", 30, UiStyle.DIM))
	var line := LineEdit.new()
	line.max_length = Riders.NAME_MAX
	line.text = r.name if r else ""
	line.placeholder_text = "Name"
	line.select_all_on_focus = true
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size = Vector2(0, 76)
	line.add_theme_font_override("font", UiStyle.font(false, 600))
	line.add_theme_font_size_override("font_size", 40)
	line.add_theme_color_override("font_color", UiStyle.INK)
	line.add_theme_color_override("font_placeholder_color", UiStyle.FAINT)
	line.add_theme_color_override("caret_color", accent)
	line.add_theme_stylebox_override("normal", UiStyle.box(accent, Color(0.0, 0.45, 0.55, 0.3), 3, 10))
	line.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	box.add_child(line)
	var problem := UiStyle.label("", 28, UiStyle.WARN)
	box.add_child(problem)
	box.add_child(UiStyle.label("Esc: cancel", 24, UiStyle.FAINT))
	# Focused means typing: no Enter needed first.
	line.focus_entered.connect(func() -> void: line.edit.call_deferred())
	line.text_submitted.connect(func(text: String) -> void:
		var why := riders.name_problem(text, r)
		if why != "":
			problem.text = why
			play.emit("back")
			line.edit.call_deferred()
			return
		play.emit("select")
		if r == null:
			rider_picked.emit(riders.add(text).id)
		else:
			riders.rename(r, text)
			_pop())
	# Esc cancels at once, rather than first leaving the text box.
	line.gui_input.connect(func(ev: InputEvent) -> void:
		if ev.is_action_pressed("ui_cancel"):
			line.accept_event()
			_pop()
			play.emit("back"))
	var p := UiStyle.panel(box, Color(accent, 0.8))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(p)
	root.set_meta("initial", line)
	return root


func _delete_screen(r: Rider) -> Control:
	var root := _screen()
	root.set_meta("no_pedal", true)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(820, 0)
	box.add_theme_constant_override("separation", 14)
	box.add_child(_wrap("DELETE %s?" % r.name.to_upper(), 56, UiStyle.BAD, 820))
	var h := History.new()
	h.dir = r.rides_dir()
	var n := h.rides().size()
	var rides := "their %d %s and best times" % [n, "ride" if n == 1 else "rides"] \
			if n > 0 else "their settings"
	box.add_child(_wrap("%s and %s go from this bike. This can't be undone." % [r.name, rides],
			30, UiStyle.DIM, 820))
	box.add_child(_gap(8))
	var keep := _button("Keep %s" % r.name, func() -> void: _pop())
	box.add_child(keep)
	box.add_child(_button("Delete %s" % r.name, func() -> void:
		if riders.remove(r):
			rider_removed.emit()))
	var p := UiStyle.panel(box, Color(UiStyle.BAD, 0.8))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(p)
	root.set_meta("initial", keep)
	return root


func _pause_screen(ride: Ride) -> Control:
	var root := _screen()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(760, 0)
	var t := UiStyle.label("PAUSED", 72, accent, true, 900)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var sofar := UiStyle.label("%s    %s    %d W average" % [UiStyle.clock(ride.elapsed),
			UiStyle.km(ride.distance(), 2), roundi(ride.average_power())], 30, UiStyle.DIM)
	sofar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sofar)
	box.add_child(_gap(10))
	box.add_child(_button("Keep riding", func() -> void: resume_ride.emit()))
	var finish := "Finish and save" if ride.elapsed >= 60.0 else "Finish (too short to save)"
	box.add_child(_button(finish, func() -> void: end_ride.emit(true)))
	box.add_child(_button("Quit without saving", func() -> void: end_ride.emit(false)))
	var p := UiStyle.panel(box, Color(accent, 0.8))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(p)
	root.set_meta("on_cancel", func() -> void: resume_ride.emit())
	return root


func _summary_screen(s: Dictionary, best_before: Dictionary, xp_before: int) -> Control:
	var root := _screen()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(820, 0)
	var head := "RIDE COMPLETE" if s.get("completed", false) else "RIDE OVER"
	var t := UiStyle.label(head, 72, accent, true, 900)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var name := UiStyle.label(s.get("title", ""), 36, UiStyle.INK, true, 600)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	if riders.list.size() > 1:
		var who := UiStyle.label(rider.name, 28, UiStyle.DIM)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(who)
	box.add_child(_gap(6))
	var grid := _stats_grid(s)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if s.has("xp"):
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 56)
		h.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(grid)
		h.add_child(_xp_box(s, xp_before))
		box.add_child(h)
	else:
		box.add_child(grid)
	box.add_child(_gap(6))
	var note := ""
	var color := UiStyle.DIM
	if s.get("kind") == "route" and s.get("completed", false):
		if best_before.is_empty():
			note = "Your first time on this route: next time you'll race its ghost."
			color = UiStyle.WARN
		elif s["time"] < best_before["time"]:
			note = "NEW BEST! %s faster than before." % UiStyle.clock(best_before["time"] - s["time"])
			color = UiStyle.GOOD
		else:
			note = "Your best is still %s." % UiStyle.clock(best_before["time"])
	var rival: Dictionary = s.get("rival", {})
	if not rival.is_empty() and s.get("completed", false) and s.has("file"):
		var gap := float(rival["time"]) - float(s["time"])
		var rl := _wrap("You beat %s's best by %s!" % [rival["name"], UiStyle.clock(gap)] if gap > 0.0
				else "%s's best is still %s faster." % [rival["name"], UiStyle.clock(-gap)],
				32, UiStyle.GOOD if gap > 0.0 else UiStyle.DIM, 820)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(rl)
	var extras := []
	var segs: Array = s.get("segments", [])
	if not segs.is_empty():
		extras.append("Segments: " + ", ".join(segs.map(func(g: Dictionary) -> String:
			return "%s %s" % [g["name"], UiStyle.clock(g["time"])])))
	var held: Dictionary = s.get("on_target", {})
	if not held.is_empty():
		var bits := PackedStringArray()
		if held.has("power"):
			bits.append("power %d%% of the time" % held["power"])
		if held.has("cadence"):
			bits.append("cadence %d%%" % held["cadence"])
		extras.append("On target: " + ", ".join(bits))
	var recs: Array = s.get("records", [])
	if not recs.is_empty():
		extras.append("New records: " + ", ".join(recs.map(func(r: Array) -> String:
			return "%s %d W (was %d)" % [Ride.SPAN_NAMES[int(r[0])], r[1], r[2]])))
	for line in extras:
		var el := _wrap(line, 28, UiStyle.GOOD if line.begins_with("New") else UiStyle.DIM, 820)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(el)
	var test: Dictionary = s.get("ftp_test", {})
	var before := roundi(float(s.get("ftp_before", rider.ftp)))
	if s.has("ftp_test"):
		color = UiStyle.GOOD
		note = "Your best minute: %d W, so your FTP is about %d W. It was %d W." \
				% [test["best_minute"], test["ftp"], before] if not test.is_empty() \
				else "The test ended before a full minute of the ramp, so there's no new FTP from it."
		if test.is_empty():
			color = UiStyle.WARN
	if not s.has("file"):
		note = "Rides under a minute aren't saved."
	if note != "":
		var nl := _wrap(note, 32, color, 820)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(nl)
	box.add_child(_gap(8))
	if not test.is_empty():
		var use := _button("Use %d W as my FTP" % test["ftp"], func() -> void:
			rider.apply({"ftp": test["ftp"]})
			rider.save_file()
			settings_changed.emit()
			done.emit())
		box.add_child(use)
		box.add_child(_button("Keep %d W" % before, func() -> void: done.emit()))
		root.set_meta("initial", use)
	else:
		box.add_child(_button("Back to the menu", func() -> void: done.emit()))
	var p := UiStyle.panel(box, Color(accent, 0.8))
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(p)
	root.set_meta("on_cancel", func() -> void: done.emit())
	return root


## What the ride earned, line by line, then the level bar climbing from where
## the rider was, with a fanfare if it crosses into a new level.
func _xp_box(s: Dictionary, xp_before: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 6)
	for part in s.get("xp_parts", []):
		var row := HBoxContainer.new()
		var what := UiStyle.label(str(part[0]), 28, UiStyle.DIM)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(what)
		row.add_child(UiStyle.label("+%d" % part[1], 28, UiStyle.INK, true, 600))
		box.add_child(row)
	var total := UiStyle.label("+%d XP" % s["xp"], 40, accent, true, 800)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(total)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var level := UiStyle.label("", 34, UiStyle.INK, true, 800)
	var title := UiStyle.label("", 28, UiStyle.DIM)
	title.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(level)
	head.add_child(title)
	box.add_child(head)
	var bar := LevelBar.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(0, 14)
	box.add_child(bar)
	var to_go := UiStyle.label("", 24, UiStyle.FAINT)
	box.add_child(to_go)
	var up := UiStyle.label("", 32, UiStyle.GOOD, true, 800)
	box.add_child(up)
	var from: Dictionary = Levels.level_for(xp_before)
	var show := func(xp: float) -> void:
		var lv := Levels.level_for(roundi(xp))
		level.text = "LEVEL %d" % lv["level"]
		title.text = lv["title"]
		bar.ratio = float(lv["into"]) / lv["needed"]
		to_go.text = "%d XP to level %d" % [lv["needed"] - lv["into"], lv["level"] + 1]
		if lv["level"] > from["level"] and up.text == "":
			up.text = "LEVEL UP!" if lv["title"] == from["title"] else "LEVEL UP!  New title: %s" % lv["title"]
			play.emit("levelup")
	show.call(float(xp_before))
	# Bound to the box, so it stops if the screen closes before it's done.
	var tw := box.create_tween()
	tw.tween_interval(0.8)
	tw.tween_method(show, float(xp_before), float(xp_before + int(s["xp"])), 2.2) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return box
