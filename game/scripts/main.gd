extends Node3D
## The game: menus, rides, the link to the bike, sound and saving, wired
## together. Keyboard only.
##
## Options after "--" on the command line, for development and screenshots:
##   --demo=200             a made-up rider at 200 W instead of the bike
##   --demo-max=260         the most the made-up rider can push (FTP test)
##   --demo-rpm=90          the made-up rider's cadence, whatever it's asked for
##   --ride=kind:id         start riding at once (route:city-sprint,
##                          workout:pyramid, free:free-rolling)
##   --at=metres            start that far along
##   --elapsed=seconds      start a workout that far in
##   --screen=name          open a menu screen (routes, workouts, free,
##                          history, settings, riders, pause, summary, sleep)
##   --rider=name           ride as this rider (made if missing)
##   --screenshot=path --after=seconds    save a picture, then quit
##   --quit-after=seconds
##   --walk-away=seconds    stopped this long mid-ride saves and ends it (300)
##   --sleep-after=seconds  idle this long in the menus, the screen sleeps (180)
##   --time-scale=N         run the clock N times faster (testing finishes)
##   --view=0..3            camera: behind, side, eyes, close (close is for
##                          checking the model)
##   --keys=down,enter,...  press keys, one every 0.4 s from 1.5 s in
##                          (up down left right enter esc bksp space, or one
##                          letter or digit to type it; "wait" skips a turn)

enum State { MENU, RIDE, SUMMARY }

const SLEEP_AFTER := 180.0  # no pedalling and no keys for this long: the screen sleeps
## Stopped mid-ride, no pedalling and no keys, for this long: the ride is
## finished and saved for whoever walked away, then the screen sleeps.
const WALK_AWAY := 300.0
const WALK_AWAY_WARN := 60.0  # the last this-many seconds are counted down on screen
## The Exit button's exit status in kiosk mode. The kiosk wrapper
## (kiosk-client.sh) tells it apart from a crash or Docker stopping the game,
## and may power the computer off (EXIT_ACTION=poweroff).
const EXIT_STATUS := 10
const AUTO_START_WATTS := 40.0
const AUTO_START_SECONDS := 4.0
const CHOOSING := 15.0  # a key pressed this recently means you're choosing
const ATTRACT_SPEED := 7.5
const PEDAL_FREE_RIDE := "free-rolling"  # what pedalling in the menu starts
const LANE := 1.2  # the rider keeps to the right of the centre line
const BIKE_COLOR := Color("00f0ff")
const GHOST_PALE := Color(0.8, 0.9, 1.0)  # your own ghost; another rider's wears their colour
const PASS_MARGIN := 3.0  # m past the ghost before "passed" counts, so it can't flicker

var settings := Settings.new()
var riders := Riders.new()
var rider: Rider  # whoever is riding now
var history := History.new()  # theirs
var link := BikeLink.new()
var world := World.new()
var bike := Bicycle.new()
var ghost := Bicycle.new(GHOST_PALE, GHOST_PALE, true)
var camera := CameraRig.new()
var sound := Sound.new()
var hud := Hud.new()
var menu := Menu.new()
var state := State.MENU
var ride: Ride
var paused := false
var sleeping := false
var args := {}
var _attract: Route
var _attract_d := 300.0
var _idle := 0.0
var _stopped := 0.0  # seconds without pedalling during a ride, real time
var _walk_away := WALK_AWAY
var _sleep_after := SLEEP_AFTER
var _since_key := 0.0
var _pedalling := 0.0
var _last_km := 0
var _told_last_km := false
var _last_step := 0
var _last_beep := -1
var _under := 0.0  # FTP test: how long the rider has been under the target
var _ghost_side := 0  # 1: the ghost is ahead, -1: behind, 0: not yet known
var _routes := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	settings.load_file()
	riders.load_all()
	if args.has("demo"):
		link.demo_watts = float(args["demo"])
	if args.has("demo-max"):
		link.demo_max = float(args["demo-max"])
	if args.has("demo-rpm"):
		link.demo_rpm = float(args["demo-rpm"])
	_walk_away = float(args.get("walk-away", WALK_AWAY))
	_sleep_after = float(args.get("sleep-after", SLEEP_AFTER))
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	for n in [link, world, bike, ghost, camera, sound]:
		add_child(n)
	camera.current = true
	ghost.visible = false
	var ui := CanvasLayer.new()
	ui.add_child(hud)
	ui.add_child(menu)
	add_child(ui)
	menu.settings = settings
	menu.riders = riders
	menu.history = history
	menu.start_ride.connect(_start)
	menu.resume_ride.connect(_resume)
	menu.end_ride.connect(_end)
	menu.done.connect(_to_menu)
	menu.settings_changed.connect(_apply_settings)
	menu.exit_requested.connect(func() -> void:
		quit(EXIT_STATUS if OS.get_environment("BIKE_GAME_MODE") == "kiosk" else 0))
	menu.play.connect(sound.play)
	menu.rider_picked.connect(func(id: String) -> void:
		_use_rider(riders.find(id))
		menu.open_main())
	menu.rider_removed.connect(func() -> void:
		_use_rider(riders.list[0])
		menu.open_main()
		if riders.list.size() > 1:
			menu.open_picker())
	link.connected_changed.connect(_on_connected)

	var first := riders.find(settings.last_rider)
	if args.has("rider"):
		first = null
		for r in riders.list:
			if r.name.to_lower() == args["rider"].to_lower():
				first = r
		if first == null:
			first = riders.add(args["rider"])
	_use_rider(first if first else riders.list[0])
	_attract = _route(Catalog.find(Catalog.free_rides(), PEDAL_FREE_RIDE))
	_to_menu(not args.has("ride") and not args.has("rider"))

	if args.has("ride"):
		var kv: PackedStringArray = args["ride"].split(":")
		if kv.size() == 2:
			_start(kv[0], kv[1])
			if ride:
				ride.physics.distance = float(args.get("at", "0"))
				ride.physics.speed = 8.0
				ride.elapsed = float(args.get("elapsed", "0"))
				_last_km = int(ride.distance() / 1000.0)
				_last_step = ride.workout.step_index(ride.elapsed) if ride.workout else 0
	if args.has("screen"):
		_open_screen.call_deferred(args["screen"])
	if args.has("screenshot"):
		_screenshot(args["screenshot"], float(args.get("after", "3")))
	if args.has("quit-after"):
		get_tree().create_timer(float(args["quit-after"]), true, false, true).timeout.connect(quit)
	if args.has("time-scale"):
		Engine.time_scale = float(args["time-scale"])
	if args.has("view"):
		camera.view = int(args["view"]) as CameraRig.View
		bike.set_first_person(camera.view == CameraRig.View.EYES)
	if args.has("keys"):
		_press_keys(args["keys"].split(","))


func _route(spec: Dictionary) -> Route:
	if not _routes.has(spec["id"]):
		_routes[spec["id"]] = Route.from_spec(spec)
	return _routes[spec["id"]]


## From now on, everything personal (settings, rides, bests) is this rider's.
func _use_rider(r: Rider) -> void:
	rider = r
	history.dir = r.rides_dir()
	menu.rider = r
	if settings.last_rider != r.id:
		settings.last_rider = r.id
		settings.save_file()
	_apply_settings()


func _apply_settings() -> void:
	sound.apply_volumes(settings.music, settings.effects)
	sound.set_muted(settings.muted)
	bike.set_colors(BIKE_COLOR, rider.rgb())
	camera.view = rider.camera as CameraRig.View
	bike.set_first_person(camera.view == CameraRig.View.EYES)
	var vp := get_viewport()
	vp.scaling_3d_scale = [0.7, 0.85, 1.0][settings.quality]
	vp.msaa_3d = Viewport.MSAA_2X if settings.quality == 2 else Viewport.MSAA_DISABLED
	if world.route and world.quality != settings.quality:
		world.setup(world.route, settings.quality)
	if ride:
		ride.physics.rider_kg = rider.weight
		ride.ftp = rider.ftp


# --- moving between menus and rides -----------------------------------------

## Back to the main menu. With `ask` and more than one rider, "Who's riding?"
## comes first: when the game starts, and when it wakes up.
func _to_menu(ask := false) -> void:
	state = State.MENU
	paused = false
	ride = null
	hud.visible = false
	ghost.visible = false
	world.setup(_attract, settings.quality)
	menu.accent = world.palette["edge"]
	menu.open_main()
	if ask and riders.list.size() > 1:
		menu.open_picker()
	sound.music("menu")


func _start(kind: String, id: String) -> void:
	var route: Route
	var workout: Workout = null
	var k := Ride.Kind.ROUTE
	var sub := ""
	match kind:
		"route":
			var spec := Catalog.find(Catalog.routes(), id)
			if spec.is_empty():
				return
			route = _route(spec)
			sub = "%s    %d m of climbing" % [UiStyle.km(route.length), roundi(route.ascent)]
		"workout":
			if id == Workout.TEST_ID:
				workout = Workout.ftp_test(rider.ftp)
				sub = "Five easy minutes, then %d W more every minute, until you can't." % Workout.TEST_STEP
			else:
				var spec := Catalog.find(Catalog.workouts(), id)
				if spec.is_empty():
					return
				workout = Workout.from_spec(spec)
				sub = "%d minutes. The bike holds the target for you." % roundi(workout.duration / 60.0)
			route = _route(Catalog.workout_road())
			k = Ride.Kind.WORKOUT
			if link.bike_connected and not link.erg:
				sub = "This bike can't hold a wattage: match the target yourself."
		"free":
			var spec := Catalog.find(Catalog.free_rides(), id)
			if spec.is_empty():
				return
			if spec.has("roam"):
				# A different way round each time: the spec's own seed only
				# for the menu's backdrop and the tests.
				spec = spec.duplicate()
				spec["roam"] = randi()
				route = Route.from_spec(spec)
			else:
				route = _route(spec)
			k = Ride.Kind.FREE
			sub = "Up and Down change the effort. Esc to finish."
		_:
			return
	ride = Ride.create(k, route, workout, rider.weight, rider.ftp)
	_stopped = 0.0
	link.demo_cadence = 0.0
	ride.records_before = history.records()
	_segment_records()
	ghost.set_colors(GHOST_PALE, GHOST_PALE)
	hud.profile.ghost_color = Color(1, 1, 1, 0.6)
	hud.minimap.ghost_color = GHOST_PALE
	hud.minimap.rider_color = rider.rgb()
	if k == Ride.Kind.ROUTE:
		# Whose best to race, as picked on the Routes screen (yours by default).
		var g := menu.ghost_for(id)
		var owner := riders.find(str(g.get("rider_id", "")))
		if owner:
			var h := History.new()
			h.dir = owner.rides_dir()
			ride.ghost = h.ghost(id)
			ride.rival = {"name": owner.name, "time": g["time"], "self": owner == rider}
			if owner != rider:
				ghost.set_colors(GHOST_PALE, owner.rgb())
				hud.profile.ghost_color = owner.rgb()
				hud.minimap.ghost_color = owner.rgb()
	rider.last_choice = kind + ":" + id
	rider.save_file()
	world.setup(route, settings.quality)
	hud.setup(ride, world.palette["edge"], rider.ftp)
	hud.reset_power_color()
	hud.visible = true
	menu.close_all()
	menu.toast("")
	state = State.RIDE
	paused = false
	_last_km = 0
	_told_last_km = false
	_last_step = 0
	_last_beep = -1
	_pedalling = 0.0
	_under = 0.0
	_ghost_side = 0
	sound.music("ride")
	sound.play("go")
	hud.banner(ride.title(), sub, world.palette["edge"], 5.0)


## Each segment's best time for this rider, and the fastest of anyone's.
func _segment_records() -> void:
	var histories := []
	for r in riders.list:
		var h := History.new()
		h.dir = r.rides_dir()
		histories.append([r, h])
	for seg in Island.SEGMENTS:
		var id: String = seg["id"]
		for rh in histories:
			var t: float = rh[1].segment_best(id)
			if rh[0] == rider and t < INF:
				ride.segment_best[id] = t
			if t < float(ride.segment_kom.get(id, {}).get("time", INF)):
				ride.segment_kom[id] = {"name": rh[0].name, "time": t, "self": rh[0] == rider}
	ride.segment_best_now = ride.segment_best.duplicate()
	ride.segment_kom_now = ride.segment_kom.duplicate(true)


func _pause() -> void:
	paused = true
	hud.clear_banner()
	menu.open_pause(ride)
	sound.play("back")


func _resume() -> void:
	paused = false
	menu.close_all()


func _end(save: bool) -> void:
	if save and ride.elapsed >= 60.0:
		_finish()
	else:
		_to_menu()


func _finish() -> void:
	var best_before := history.best(ride.route.id) if ride.kind == Ride.Kind.ROUTE else {}
	var before := history.rides()
	var xp := Levels.for_ride(ride, before, best_before) if ride.elapsed >= 60.0 else {}
	var extra := {}
	if ride.workout and ride.workout.id == Workout.TEST_ID:
		extra["ftp_test"] = Workout.test_result(ride.samples)
		extra["ftp_before"] = ride.ftp
	if not ride.rival.is_empty() and not ride.rival["self"]:
		extra["rival"] = {"name": ride.rival["name"], "time": ride.rival["time"]}
	if not ride.new_records().is_empty():
		extra["records"] = ride.new_records()
	var summary := history.save(ride, xp, extra)
	_idle = 0.0
	_stopped = 0.0
	state = State.SUMMARY
	paused = false
	hud.visible = false
	ghost.visible = false
	menu.open_summary(summary, best_before, Levels.total(before, rider.ftp))
	sound.music("menu")
	var pb: bool = ride.kind == Ride.Kind.ROUTE and ride.finished and summary.has("file") \
			and not best_before.is_empty() and summary["time"] < best_before["time"]
	sound.play("pb" if pb else "finish")


func _open_screen(name: String) -> void:
	match name:
		"pause":
			if ride:
				_pause()
		"summary":
			var r := ride if ride else Ride.create(Ride.Kind.ROUTE, _route(Catalog.routes()[5]), null, 80.0, 200.0)
			if r.elapsed < 1.0:
				r.elapsed = 2412.0
				r.physics.distance = 9000.0
				r.energy = 180.0 * 2412.0
				r.max_power = 412.0
				r.ascent = 262.0
				r.finished = true
			var s := r.summary()
			s["file"] = "example"
			s["xp_parts"] = [["40 min riding, hard for you", 520], ["route finished", Levels.FINISHED],
				["new best time", Levels.NEW_BEST], ["3 days in a row", 2 * Levels.STREAK_DAY]]
			s["xp"] = 520 + Levels.FINISHED + Levels.NEW_BEST + 2 * Levels.STREAK_DAY
			ride = r
			# Just short of a new level, so the screen shows one.
			menu.open_summary(s, {"time": 2500.0}, 8300)
			state = State.SUMMARY
			hud.visible = false
		"sleep":
			_sleep()
		_:
			menu.open_screen(name)


# --- every frame -------------------------------------------------------------

func _process(delta: float) -> void:
	# Timers about the person (keys, idling, pedalling to start) run on real
	# time, whatever speed the ride clock runs at in tests.
	var real := delta / Engine.time_scale
	_since_key += real
	_status()
	# Pedalling wakes the screen, like a key does.
	if sleeping and link.power >= AUTO_START_WATTS:
		_wake()
	match state:
		State.RIDE:
			_ride_frame(delta)
			if state == State.RIDE:
				_walk_away_check(real)
		State.SUMMARY:
			link.send_grade(0.0)
			_show_bike(ride.route, ride.distance(), 0.0, 0.0, delta)
			world.update(ride.distance(), camera)
			sound.set_speed(0.0)
			_sleep_check(real)
		_:
			_attract_frame(delta, real)


func _attract_frame(delta: float, real: float) -> void:
	_attract_d += ATTRACT_SPEED * delta
	_attract.keep_ahead(_attract_d)
	if _attract_d > _attract.length - 5000.0:
		_attract_d = 300.0
	link.send_grade(0.0)
	_show_bike(_attract, _attract_d, ATTRACT_SPEED, 80.0, delta)
	world.update(_attract_d, camera)
	sound.set_speed(0.0)
	_auto_start(real)
	_sleep_check(real)


func _ride_frame(delta: float) -> void:
	ride.route.keep_ahead(ride.distance())
	if not paused:
		ride.update(link.power, link.cadence, delta)
		_drive_bike()
		_events()
		_test_check(delta)
		if ride.finished:
			_finish()
			return
	var d := ride.distance()
	_show_bike(ride.route, d, ride.physics.speed, 0.0 if ride.paused() else link.cadence, delta)
	var gd := ride.ghost_distance()
	ghost.visible = gd >= 0.0 and absf(gd - d) < 400.0
	if ghost.visible:
		var gp := ride.route.position_at(gd) + ride.route.right_at(gd) * (LANE - 1.3) \
				+ Vector3(0.0, Route.SURFACE, 0.0)
		ghost.global_transform = Transform3D(Basis.looking_at(ride.route.forward_at(gd), Vector3.UP), gp)
		ghost.animate(ride.physics.speed, 85.0, delta)
	world.update(d, camera)
	hud.update_ride(ride, link, delta, settings.show_fps)
	sound.set_speed(ride.physics.speed)
	if not link.bike_connected:
		hud.sticky("Waiting for the bike...")
	elif ride.elapsed == 0.0 and link.power <= 0.0:
		hud.sticky("Pedal to start")
	elif ride.paused():
		var left := minf(_walk_away - _stopped, _walk_away - _since_key)
		if left <= WALK_AWAY_WARN and ride.elapsed >= 60.0:
			hud.sticky("Pedal to carry on: saving the ride in %d" % ceili(maxf(left, 0.0)))
		else:
			hud.sticky("Pedal to carry on")
	else:
		hud.sticky("")


func _show_bike(route: Route, d: float, speed: float, cadence: float, delta: float) -> void:
	var pos := route.position_at(d) + route.right_at(d) * LANE + Vector3(0.0, Route.SURFACE, 0.0)
	var fwd := route.forward_at(d)
	bike.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
	bike.animate(speed, cadence, delta)
	camera.follow(pos, fwd, route.right_at(d), delta)


func _drive_bike() -> void:
	if ride.kind == Ride.Kind.WORKOUT:
		# The made-up rider keeps to the cadence it's asked for.
		link.demo_cadence = ride.workout.cadence_at(ride.elapsed)
		if link.erg:
			link.send_power(ride.target_power())
		else:
			link.send_grade(0.0)
	else:
		link.send_grade(ride.bike_grade(rider.hill_feel))


## The FTP test ends when the rider can't keep up in the ramp: under
## TEST_GIVE_UP of the target for TEST_GIVE_UP_AFTER seconds.
func _segment_entered(seg: Dictionary) -> void:
	var best: float = ride.segment_best_now.get(seg["id"], INF)
	var kom: Dictionary = ride.segment_kom_now.get(seg["id"], {})
	var sub := "First time: set the time to beat"
	if not kom.is_empty():
		sub = "Fastest: %s %s" % ["you" if kom.get("self", false) else kom["name"], UiStyle.clock(kom["time"])]
		if best < INF and not kom.get("self", false):
			sub = "Your best %s    %s" % [UiStyle.clock(best), sub]
	hud.banner("SEGMENT: " + str(seg["name"]).to_upper(), sub, UiStyle.WARN, 3.5)
	sound.play("go")


func _segment_done(result: Dictionary) -> void:
	var id: String = result["id"]
	var t: float = result["time"]
	var best: float = ride.segment_best_now.get(id, INF)
	var kom: Dictionary = ride.segment_kom_now.get(id, {})
	var head := "%s  %s" % [str(result["name"]).to_upper(), UiStyle.clock(t)]
	if not kom.is_empty() and not kom.get("self", false) and t < float(kom["time"]):
		hud.banner(head, "KING OF THE MOUNTAIN! %s faster than %s" % [UiStyle.clock(float(kom["time"]) - t), kom["name"]],
				UiStyle.GOOD, 4.0)
		sound.play("pb")
	elif t < best:
		hud.banner(head, "NEW BEST! %s faster" % UiStyle.clock(best - t), UiStyle.GOOD, 4.0)
		sound.play("pb")
	elif best < INF:
		hud.banner(head, "Your best is %s" % UiStyle.clock(best), UiStyle.INK, 3.0)
		sound.play("km")
	else:
		hud.banner(head, "Your first time: now there's a time to beat", UiStyle.INK, 3.0)
		sound.play("km")
	# Later laps compare with this one.
	ride.segment_best_now[id] = minf(best, t)
	if kom.is_empty() or t < float(kom["time"]):
		ride.segment_kom_now[id] = {"name": rider.name, "time": t, "self": true}


func _test_check(delta: float) -> void:
	if ride.workout == null or ride.workout.id != Workout.TEST_ID \
			or ride.elapsed < Workout.TEST_WARMUP + 20.0:
		return
	_under = _under + delta if link.power < ride.target_power() * Workout.TEST_GIVE_UP else 0.0
	if _under >= Workout.TEST_GIVE_UP_AFTER:
		ride.finished = true


func _events() -> void:
	var edge: Color = world.palette["edge"]
	while not ride.events.is_empty():
		var e: Array = ride.events.pop_front()
		match e[0]:
			"segment":
				_segment_entered(e[1])
			"segment_done":
				_segment_done(e[1])
			"record":
				hud.banner("NEW %s RECORD" % Ride.SPAN_NAMES[e[1]].to_upper(), "%d W" % roundi(e[2]),
						UiStyle.GOOD, 3.0)
				sound.play("pb")
	var gd := ride.ghost_distance()
	if gd >= 0.0 and ride.elapsed > 5.0:
		var gap := gd - ride.distance()
		var side := 1 if gap > PASS_MARGIN else (-1 if gap < -PASS_MARGIN else _ghost_side)
		if _ghost_side != 0 and side != _ghost_side:
			var who := "YOUR BEST" if ride.rival.get("self", true) else "%s'S GHOST" % ride.rival["name"].to_upper()
			if side < 0:
				hud.banner("YOU PASSED " + who, "", UiStyle.GOOD, 2.5)
				sound.play("km")
			else:
				hud.banner(who + " PASSED YOU", "", UiStyle.WARN, 2.5)
		_ghost_side = side
	var km := int(ride.distance() / 1000.0)
	if km > _last_km:
		_last_km = km
		sound.play("km")
		if ride.kind != Ride.Kind.WORKOUT:
			hud.banner("%d KM" % km, "", edge, 2.0)
	if ride.kind == Ride.Kind.ROUTE and not _told_last_km \
			and ride.route.length - ride.distance() <= 1000.0 and ride.route.length > 2000.0:
		_told_last_km = true
		hud.banner("1 KM TO GO", "", UiStyle.WARN, 3.0)
	if ride.kind == Ride.Kind.WORKOUT:
		var w := ride.workout
		var i := w.step_index(ride.elapsed)
		if i != _last_step:
			_last_step = i
			sound.play("go")
			var st: Array = w.steps[i]
			hud.banner(Workout.describe(st, ride.ftp, ride.intensity), "for %s" % UiStyle.clock(st[0]),
					Workout.zone_color((st[1] + st[2]) * 0.5), 3.0)
		var left := int(ceil(w.remaining_in_step(ride.elapsed)))
		if left <= 3 and left >= 1 and left != _last_beep:
			_last_beep = left
			sound.play("beep")
		elif left > 3:
			_last_beep = -1


func _status() -> void:
	_bike_status()
	if settings.muted:
		menu.append_status("    Sound off (M)")


func _bike_status() -> void:
	if link.demo_watts > 0.0:
		menu.set_status("Demo rider at %d W" % roundi(link.demo_watts), UiStyle.DIM)
	elif not link.bridge_running():
		menu.set_status("The bike helper isn't running", UiStyle.WARN)
	elif link.bridge_state == "no_adapter":
		menu.set_status("No Bluetooth adapter found on this computer", UiStyle.WARN)
	elif not link.bike_connected:
		menu.set_status("Switch on the bike", UiStyle.DIM)
	else:
		var extra := "  -  holds wattages for workouts" if link.erg else ""
		menu.set_status("Bike connected: %s%s" % [link.bike_name, extra], UiStyle.GOOD)
	hud.set_status("Bike disconnected" if state == State.RIDE and not link.bike_connected else "")


func _on_connected(is_connected: bool) -> void:
	if is_connected:
		sound.play("connect")
		_idle = 0.0
		if sleeping:
			_wake()


## In the menu, pedalling for a few seconds starts a free ride, unless
## you're busy choosing something with the keyboard, typing, or it's switched
## off in Settings. The demo rider never stops pedalling, so it doesn't count.
## On "Who's riding?" it rides as the highlighted rider.
func _auto_start(delta: float) -> void:
	if sleeping or not settings.pedal_start or link.demo_watts > 0.0 \
			or not link.bike_connected or _since_key < CHOOSING or not menu.pedal_starts():
		_pedalling = 0.0
		menu.toast("")
		return
	var who := riders.find(menu.picker_choice())
	if who == null:
		who = rider
	_pedalling = _pedalling + delta if link.power >= AUTO_START_WATTS else 0.0
	if _pedalling > 0.8:
		var whose := " for %s" % who.name if riders.list.size() > 1 else ""
		menu.toast("Pedalling... a free ride%s starts in %d" % [whose, ceili(AUTO_START_SECONDS - _pedalling)])
	else:
		menu.toast("")
	if _pedalling >= AUTO_START_SECONDS:
		if who != rider:
			_use_rider(who)
		_start("free", PEDAL_FREE_RIDE)


## Nobody pedalling and no keys for a while: the screen sleeps. It used to
## wait for the bike to switch off, but a bike on mains power stays on.
func _sleep_check(delta: float) -> void:
	_idle = 0.0 if link.power > 0.0 else _idle + delta
	if not sleeping and _idle > _sleep_after and _since_key > _sleep_after:
		_sleep()


## Mid-ride, nobody pedalling and no keys (paused or not) for `_walk_away`
## seconds: somebody walked away. A ride worth keeping is finished and saved
## for them (the summary shows, then the screen sleeps); anything shorter
## goes back to the menu.
func _walk_away_check(real: float) -> void:
	_stopped = _stopped + real if link.power <= 0.0 else 0.0
	if _stopped < _walk_away or _since_key < _walk_away:
		return
	_stopped = 0.0
	if ride.elapsed >= 60.0:
		_finish()
	else:
		_to_menu()


## Nothing to do: a black screen at a few frames a second, no music.
func _sleep() -> void:
	sleeping = true
	menu.show_sleep(true)
	sound.music("")
	world.visible = false
	bike.visible = false
	Engine.max_fps = 4


func _wake() -> void:
	sleeping = false
	_idle = 0.0
	menu.show_sleep(false)
	world.visible = true
	bike.visible = true
	Engine.max_fps = 0
	if state == State.SUMMARY:
		_to_menu(true)  # the summary of a ride somebody walked away from
	elif state == State.MENU:
		menu.open_main()
		if riders.list.size() > 1:
			menu.open_picker()  # someone else may be on the bike now
	sound.music("ride" if state == State.RIDE else "menu")


# --- keys --------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_since_key = 0.0
		_idle = 0.0
		if sleeping:
			_wake()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_Q and (event as InputEventKey).ctrl_pressed:
		quit()
		return
	if key == KEY_M and not event.is_echo():
		settings.muted = not settings.muted
		settings.save_file()
		sound.set_muted(settings.muted)
		if state == State.RIDE and not paused:
			hud.banner("Sound off" if settings.muted else "Sound on", "", UiStyle.INK, 1.2)
		get_viewport().set_input_as_handled()
		return
	if state != State.RIDE or paused:
		return
	match key:
		KEY_ESCAPE:
			if not event.is_echo():
				_pause()
		KEY_LEFT, KEY_RIGHT:
			if ride.route.roaming:
				var before: Dictionary = ride.route.next_turn(ride.distance())
				var after := ride.route.choose_turn(ride.distance(), -1 if key == KEY_LEFT else 1)
				if not after.is_empty() and after.get("index") != before.get("index", -1):
					sound.play("move")
		KEY_UP, KEY_DOWN:
			var step := 1 if key == KEY_UP else -1
			if ride.kind == Ride.Kind.FREE:
				ride.change_effort(step)
				var e := roundi(ride.effort * 100.0)
				hud.banner("Effort %s%d%%" % ["+" if e > 0 else "", e], "", UiStyle.INK, 1.2)
				sound.play("move")
			elif ride.kind == Ride.Kind.WORKOUT and ride.workout.id != Workout.TEST_ID:
				ride.change_intensity(step)
				hud.banner("Intensity %d%%" % roundi(ride.intensity * 100.0), "", UiStyle.INK, 1.2)
				sound.play("move")
		KEY_F:
			if not event.is_echo():
				settings.show_fps = not settings.show_fps
				settings.save_file()
		KEY_C:
			if not event.is_echo():
				camera.cycle_view()
				rider.camera = camera.view
				bike.set_first_person(camera.view == CameraRig.View.EYES)
				rider.save_file()
				hud.banner(Rider.CAMERA_NAMES[rider.camera], "", UiStyle.INK, 1.2)
	get_viewport().set_input_as_handled()


func _press_keys(keys: PackedStringArray) -> void:
	var codes := {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"enter": KEY_ENTER, "esc": KEY_ESCAPE, "bksp": KEY_BACKSPACE, "space": KEY_SPACE}
	await get_tree().create_timer(1.5, true, false, true).timeout
	for k in keys:
		var code: int = codes.get(k, KEY_NONE)
		var typed := 0
		if code == KEY_NONE and k.length() == 1:
			code = OS.find_keycode_from_string(k.to_upper())
			typed = k.unicode_at(0)
		elif k == "space":
			typed = 32
		if code != KEY_NONE:
			for down in [true, false]:
				var ev := InputEventKey.new()
				ev.keycode = code
				ev.physical_keycode = code
				ev.unicode = typed
				ev.pressed = down
				Input.parse_input_event(ev)
				await get_tree().process_frame
		await get_tree().create_timer(0.4, true, false, true).timeout


func _screenshot(path: String, after: float) -> void:
	# Real seconds, whatever --time-scale says.
	await get_tree().create_timer(after, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	quit()


## Stop the sounds, give the audio thread two frames to let go, then quit.
func quit(status := 0) -> void:
	sound.stop_all()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(status)
